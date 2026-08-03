import Foundation
import AppKit
import CoreText
import SwiftUI

@main
final class CadenceApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = CadenceApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let menuBar = MenuBarController()
    private let coordinator = DictationCoordinator.shared
    private let permissions = PermissionsManager.shared
    private let hotkeys = HotkeyManager()
    private let indicator = RecordingIndicatorController()
    private let popup = WebPopupController.shared
    private let updater = UpdaterService.shared

    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Cadence starting up at \(Bundle.main.bundlePath, privacy: .public)")

        // Install a hidden main menu so Cmd+V/C/X/A/Z/Q work in every text
        // field. Accessory apps have no menu bar UI, but macOS still routes
        // those key equivalents through NSApp.mainMenu — without it, paste
        // is silently broken in SecureField/TextField everywhere.
        installMainMenu()
        registerBundledFonts()
        LaunchAtLogin.sync()
        CrashReporter.start()
        _ = updater // bootstrap Sparkle background-check timer
        // Warm the Cadence Cloud session a beat after launch so the first
        // dictation doesn't pay the anonymous-signup round trip inline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AuthService.shared.ensureCloudSessionReady { _ in }
        }

        // Catch cadence://auth/callback redirects from OAuth providers.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Wire menu bar actions.
        menuBar.openSettings = { [weak self] in self?.openSettings() }
        menuBar.openHistory = { [weak self] in self?.openHistory() }
        menuBar.openPermissionRepair = { [weak self] in self?.openPermissionRepair() }
        menuBar.quitApp = { NSApp.terminate(nil) }
        menuBar.install()

        NotificationCenter.default.addObserver(
            forName: .cadenceOpenPermissionRepair,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openPermissionRepair()
        }

        // Hotkey wiring.
        hotkeys.delegate = self
        if permissions.accessibility == .granted {
            hotkeys.start()
        }

        indicator.install()

        if !UserPreferences.shared.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.openOnboarding(force: false)
            }
        } else {
            // Make sure required perms are reflected in UI even when we don't onboard.
            permissions.refreshAll()
        }

        // Watch for input-monitoring becoming granted so we can start the tap.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CadenceInputMonitoringGranted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeys.start()
        }

        // Warm up the audio engine so the FIRST recording captures every word.
        // Once mic permission is granted (or already was), we keep the engine
        // running with a pre-roll buffer that lets us prepend the last ~400ms
        // before the key press into the recording.
        if permissions.microphone == .granted {
            coordinator.warmUpMic()
        } else {
            permissions.requestMicrophone { [weak self] granted in
                if granted { self?.coordinator.warmUpMic() }
            }
        }

        // Poll permissions to flip the hotkey on once granted, even without explicit UI flow.
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.permissions.refreshAll()
            if self.permissions.accessibility == .granted && self.hotkeys.isListening == false {
                self.hotkeys.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
        menuBar.remove()
        // The audio engine was never torn down — `shutDown()` had no callers at
        // all, so the tap stayed installed for the life of the process.
        coordinator.shutDownMic()
    }

    // MARK: - Main menu (hidden, exists only for Cmd+V routing)

    private func installMainMenu() {
        let main = NSMenu()

        // App menu (required parent of Quit)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Cadence",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let checkUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(UpdaterService.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdates.target = UpdaterService.shared
        appMenu.addItem(checkUpdates)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Cadence",
                                   action: #selector(NSApplication.hide(_:)),
                                   keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Cadence",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        // Edit menu — the only reason any of this exists.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        let undo = NSMenuItem(title: "Undo",
                              action: Selector(("undo:")),
                              keyEquivalent: "z")
        editMenu.addItem(undo)
        let redo = NSMenuItem(title: "Redo",
                              action: Selector(("redo:")),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",
                                    action: #selector(NSText.cut(_:)),
                                    keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",
                                    action: #selector(NSText.copy(_:)),
                                    keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",
                                    action: #selector(NSText.paste(_:)),
                                    keyEquivalent: "v"))
        let pasteMatch = NSMenuItem(title: "Paste and Match Style",
                                    action: Selector(("pasteAsPlainText:")),
                                    keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteMatch)
        editMenu.addItem(NSMenuItem(title: "Delete",
                                    action: #selector(NSText.delete(_:)),
                                    keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Select All",
                                    action: #selector(NSText.selectAll(_:)),
                                    keyEquivalent: "a"))

        editMenuItem.submenu = editMenu
        main.addItem(editMenuItem)

        NSApp.mainMenu = main
    }

    // MARK: - Window helpers

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    private func openSettings(tabId: String? = nil) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        if let tabId {
            settingsWindow?.present(tabId: tabId)
        } else {
            settingsWindow?.present()
        }
    }

    private func openOnboarding(force: Bool) {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController()
        }
        onboardingWindow?.present()
    }

    private func openHistory() {
        // History now lives inside Settings so we don't spawn extra windows.
        openSettings(tabId: "history")
    }

    private func openPermissionRepair() {
        // Permission repair is folded into the General settings tab.
        openSettings(tabId: "general")
    }

    // MARK: - Custom fonts

    /// Register Instrument Serif (bundled in Resources/) with CoreText so
    /// SwiftUI `.custom("InstrumentSerif-…")` calls resolve to our display face
    /// instead of silently falling back to the system font.
    private func registerBundledFonts() {
        let names = [
            "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
            "InstrumentSerif-Regular", "InstrumentSerif-Italic",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                Log.app.warning("Bundled font missing: \(name, privacy: .public)")
                continue
            }
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) {
                let msg = (err?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String? ?? "unknown" } ?? "nil"
                Log.app.error("Font registration failed for \(name, privacy: .public): \(msg ?? "unknown", privacy: .public)")
            }
        }
    }

    // MARK: - URL scheme handler (OAuth callback)

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw) else { return }
        guard url.scheme?.lowercased() == "cadence" else { return }
        // Don't log the full URL — auth callbacks carry tokens in the fragment.
        Log.app.info("Handling URL (host=\(url.host ?? "?", privacy: .public))")
        AuthService.shared.handleCallbackURL(url)
    }
}

// MARK: - HotkeyManagerDelegate

extension CadenceApp: HotkeyManagerDelegate {
    func hotkeyDidPress() {
        coordinator.startRecording()
    }

    func hotkeyDidRelease() {
        coordinator.stopRecording()
    }

    func hotkeyDidCancel() {
        coordinator.cancel()
    }
}
