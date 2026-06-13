import Foundation
import AppKit

/// Plan describing how to reach a destination right now, given installed apps.
struct LaunchPlan {
    enum Action {
        case focusRunningApp(NSRunningApplication)
        case openApp(URL)
        case openWebsite(URL, browserBundleId: String?)
        case openPopup(URL)
        case stayInCurrentApp
    }

    let destination: Destination
    let action: Action
}

/// Decides how to reach a destination and executes the plan.
final class LaunchManager {
    static let shared = LaunchManager()
    private let workspace = NSWorkspace.shared

    /// Decide what to do: focus existing app, launch native app, open website,
    /// or stay in the current app.
    /// `subdestination` overrides the destination's URL when present.
    func makePlan(for destination: Destination, subdestination: Subdestination? = nil) -> LaunchPlan {
        // Current-app destination: never switch.
        if destination.preferredMode == .currentApp {
            return LaunchPlan(destination: destination, action: .stayInCurrentApp)
        }

        // Popup wins over native / browser launch when a URL exists.
        if destination.openInPopup {
            if let url = subdestination?.url ?? destination.url {
                return LaunchPlan(destination: destination, action: .openPopup(url))
            }
        }

        let prefs = UserPreferences.shared
        let urlOverride = subdestination?.url

        // If we have a sub-URL, force a website-style open. Subdestinations
        // are URLs, and we always want to honor that even if the destination
        // would normally focus a running app first.
        if let urlOverride {
            return LaunchPlan(
                destination: destination,
                action: .openWebsite(urlOverride, browserBundleId: prefs.browserPreference.bundleId)
            )
        }

        // Try to focus a running native app first when allowed.
        if prefs.preferExistingWindows,
           let bundleId = destination.bundleId,
           let running = runningApp(withBundleId: bundleId) {
            return LaunchPlan(destination: destination, action: .focusRunningApp(running))
        }

        switch destination.preferredMode {
        case .nativeAppPreferred, .nativeAppOnly:
            if let bundleId = destination.bundleId, let appURL = applicationURL(forBundleId: bundleId) {
                return LaunchPlan(destination: destination, action: .openApp(appURL))
            }
            // Native preferred but app not installed -> fall through to website if allowed.
            if destination.preferredMode == .nativeAppPreferred,
               let url = destination.url {
                return LaunchPlan(
                    destination: destination,
                    action: .openWebsite(url, browserBundleId: prefs.browserPreference.bundleId)
                )
            }
            // Native-only but app not installed.
            return LaunchPlan(
                destination: destination,
                action: .stayInCurrentApp
            )

        case .websitePreferred, .websiteOnly:
            if let url = destination.url {
                return LaunchPlan(
                    destination: destination,
                    action: .openWebsite(url, browserBundleId: prefs.browserPreference.bundleId)
                )
            }
            return LaunchPlan(destination: destination, action: .stayInCurrentApp)

        case .currentApp:
            return LaunchPlan(destination: destination, action: .stayInCurrentApp)
        }
    }

    /// Execute a plan and call back when the destination should be ready for paste.
    func execute(_ plan: LaunchPlan, completion: @escaping (Result<Void, Error>) -> Void) {
        switch plan.action {
        case .stayInCurrentApp:
            completion(.success(()))

        case .focusRunningApp(let app):
            let activated = app.activate(options: [])
            Log.launch.info("Focused \(app.localizedName ?? "?", privacy: .public) -> \(activated)")
            // Allow a short moment for the window to come forward.
            DispatchQueue.main.asyncAfter(deadline: .now() + plan.destination.pasteDelaySeconds) {
                completion(.success(()))
            }

        case .openApp(let url):
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.addsToRecentItems = false
            workspace.openApplication(at: url, configuration: cfg) { app, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                if let app, app.isFinishedLaunching == false {
                    // Wait briefly for first launch.
                    self.waitForAppReady(app: app, deadline: 4.0) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + plan.destination.pasteDelaySeconds) {
                            completion(.success(()))
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + plan.destination.pasteDelaySeconds) {
                        completion(.success(()))
                    }
                }
            }

        case .openWebsite(let url, let browserBundleId):
            do {
                try openURL(url, in: browserBundleId)
                let webExtra: TimeInterval = plan.destination.preferredMode == .websiteOnly ? 0.45 : 0
                let totalDelay = plan.destination.pasteDelaySeconds + webExtra
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay * 0.55) {
                    self.activateBrowser(bundleId: browserBundleId)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                    self.activateBrowser(bundleId: browserBundleId)
                    completion(.success(()))
                }
            } catch {
                completion(.failure(error))
            }

        case .openPopup(let url):
            // Prefer the user's preferred browser in Chrome-style app-window
            // mode (chromeless, focused). Falls back to the embedded
            // WKWebView popup if the browser isn't Chromium-based.
            if UserPreferences.shared.popupUsesBrowserAppWindow,
               openInBrowserAppWindow(url: url) {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.45, plan.destination.pasteDelaySeconds)) {
                    completion(.success(()))
                }
            } else {
                WebPopupController.shared.open(url: url) {
                    completion(.success(()))
                }
            }
        }
    }

    /// Open `url` in a chromeless "app window" of the user's preferred
    /// Chromium-based browser via `open <browser> --args --app=<url>`, with
    /// `--window-size` and `--window-position` flags so the popup lands at
    /// the right size and place immediately. An AppleScript resize runs as
    /// a fallback in case the flags get ignored. Returns false if the
    /// preferred browser doesn't support this mode.
    private func openInBrowserAppWindow(url: URL) -> Bool {
        let prefs = UserPreferences.shared
        let candidateIds: [String]
        if let preferred = prefs.browserPreference.bundleId {
            candidateIds = [preferred] + Self.chromiumBundleIdsRanked.filter { $0 != preferred }
        } else {
            candidateIds = Self.chromiumBundleIdsRanked
        }

        let layout = computePopupLayout()

        for bundleId in candidateIds {
            guard Self.chromiumBundleIds.contains(bundleId) else { continue }
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            // Drop `-n`: passing -n forces a new app instance which lands
            // the window in Chrome's "home" Space, away from the user.
            // Without -n the running browser stays put and the --app window
            // opens on the active Space.
            task.arguments = [
                "-a", appURL.path,
                "--args",
                "--app=\(url.absoluteString)",
            ]
            do {
                try task.run()
                Log.launch.info("Popup -> browser-app-window via \(bundleId, privacy: .public)")
                resizeBrowserAppWindow(bundleId: bundleId, layout: layout)
                return true
            } catch {
                Log.launch.warning("Failed to launch \(bundleId, privacy: .public) in app mode: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        return false
    }

    /// Geometry for the popup window: size + both Cocoa-style (bottom-left)
    /// and Chromium-style (top-left, pixels from primary display) origins.
    private struct PopupLayout {
        let size: CGSize
        /// Chromium `--window-position` coordinates (top-left of primary display).
        let chromeX: Int
        let chromeY: Int
        /// AppleScript `set bounds` rectangle (top-left of primary display).
        let bounds: (left: Int, top: Int, right: Int, bottom: Int)
    }

    /// Compute popup geometry pinned to the top-right of the screen the
    /// mouse is currently on. Matches the embedded popup's footprint.
    private func computePopupLayout() -> PopupLayout {
        let popupWidth: CGFloat = 380
        let popupHeight: CGFloat = 540
        let margin: CGFloat = 16

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let primaryHeight = NSScreen.screens.first?.frame.height ?? targetScreen.frame.height

        let visible = targetScreen.visibleFrame
        let left = Int(visible.maxX - popupWidth - margin)
        let topFromTopLeft = Int(primaryHeight - (visible.maxY - margin))

        return PopupLayout(
            size: CGSize(width: popupWidth, height: popupHeight),
            chromeX: left,
            chromeY: topFromTopLeft,
            bounds: (
                left: left,
                top: topFromTopLeft,
                right: left + Int(popupWidth),
                bottom: topFromTopLeft + Int(popupHeight)
            )
        )
    }

    /// After Chrome / Arc / Edge spawns a new `--app=` window, run an
    /// AppleScript `set bounds` as a belt-and-suspenders fallback in case
    /// the `--window-size` / `--window-position` flags were ignored.
    private func resizeBrowserAppWindow(bundleId: String, layout: PopupLayout) {
        guard let appName = Self.appleScriptAppName(for: bundleId) else { return }

        let b = layout.bounds
        let script = """
        tell application "\(appName)"
            try
                set _w to front window
                set bounds of _w to {\(b.left), \(b.top), \(b.right), \(b.bottom)}
            on error
                try
                    set bounds of window 1 to {\(b.left), \(b.top), \(b.right), \(b.bottom)}
                end try
            end try
        end tell
        """

        let runScript: () -> Void = {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            let nullPipe = Pipe()
            task.standardError = nullPipe
            task.standardOutput = nullPipe
            do { try task.run() } catch {
                Log.launch.warning("Popup resize osascript failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.6, execute: runScript)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.4, execute: runScript)
    }

    /// Map a known Chromium-based browser bundle ID to its AppleScript app
    /// name (the name `tell application "<name>"` expects).
    private static func appleScriptAppName(for bundleId: String) -> String? {
        switch bundleId {
        case "com.google.Chrome", "com.google.Chrome.canary": return "Google Chrome"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac", "com.microsoft.edgemac.Dev": return "Microsoft Edge"
        case "company.thebrowser.Browser": return "Arc"
        case "com.vivaldi.Vivaldi": return "Vivaldi"
        case "com.operasoftware.Opera": return "Opera"
        default: return nil
        }
    }

    /// Known Chromium-based browsers that respect `--app=URL`.
    private static let chromiumBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Dev",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    /// Preferred fallback ordering when the user hasn't picked a browser.
    private static let chromiumBundleIdsRanked: [String] = [
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    // MARK: - Helpers

    private func runningApp(withBundleId bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private func applicationURL(forBundleId bundleId: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleId)
    }

    private func openURL(_ url: URL, in browserBundleId: String?) throws {
        if let browserBundleId, let appURL = applicationURL(forBundleId: browserBundleId) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            workspace.open([url], withApplicationAt: appURL, configuration: cfg) { _, error in
                if let error {
                    Log.launch.error("openURL failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            workspace.open(url)
        }
    }

    private func activateBrowser(bundleId: String?) {
        let resolved = bundleId ?? defaultBrowserBundleId()
        guard let resolved else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: resolved).first {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }
        if let appURL = applicationURL(forBundleId: resolved) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            workspace.openApplication(at: appURL, configuration: cfg, completionHandler: nil)
        }
    }

    private func defaultBrowserBundleId() -> String? {
        guard let url = URL(string: "http://example.com"),
              let appURL = workspace.urlForApplication(toOpen: url) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    private func waitForAppReady(app: NSRunningApplication, deadline: TimeInterval, completion: @escaping () -> Void) {
        let start = Date()
        let timer = Timer(timeInterval: 0.15, repeats: true) { t in
            if app.isFinishedLaunching || Date().timeIntervalSince(start) >= deadline {
                t.invalidate()
                completion()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
