import Foundation
import AppKit

/// Helps the user move the running app to /Applications. Required for
/// stable Accessibility / Input Monitoring permissions on ad-hoc signed
/// dev builds, because TCC keys those permissions to the signed binary
/// and a build's signature changes every time you rebuild from Xcode.
enum AppRelocator {
    /// True when the app currently lives somewhere in /Applications.
    static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// Where the running app currently lives.
    static var runningPath: String {
        Bundle.main.bundlePath
    }

    /// Other copies of Mellotron.app on disk that might confuse TCC.
    /// We look in /Applications and ~/Library/Developer/Xcode/DerivedData
    /// — the two places dev builds typically end up.
    static func duplicateInstallations() -> [URL] {
        let me = Bundle.main.bundleURL.standardizedFileURL
        var found: [URL] = []
        let fm = FileManager.default

        // Likely sibling in /Applications.
        let inApps = URL(fileURLWithPath: "/Applications/Mellotron.app")
        if fm.fileExists(atPath: inApps.path), inApps.standardizedFileURL != me {
            found.append(inApps)
        }

        // Anywhere under DerivedData.
        let derived = ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath
        if let enumerator = fm.enumerator(atPath: derived) {
            for case let path as String in enumerator {
                if path.hasSuffix("/Mellotron.app") || path == "Mellotron.app" {
                    let url = URL(fileURLWithPath: derived).appendingPathComponent(path)
                    if url.standardizedFileURL != me, !found.contains(url) {
                        found.append(url)
                    }
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }

    /// Move duplicate copies of the app to the trash. Best-effort, and
    /// will skip the running app if it appears in the list.
    @discardableResult
    static func trashDuplicates(_ urls: [URL]) -> Int {
        let me = Bundle.main.bundleURL.standardizedFileURL
        let fm = FileManager.default
        var moved = 0
        for url in urls where url.standardizedFileURL != me {
            do {
                var resulting: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resulting)
                moved += 1
            } catch {
                Log.app.error("Trash failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return moved
    }

    /// Best-effort copy of the running app to /Applications and relaunch.
    /// Returns true once the relaunch was scheduled.
    @MainActor
    static func moveToApplicationsAndRelaunch() -> Bool {
        let src = Bundle.main.bundleURL
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(src.lastPathComponent)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: src, to: dest)
        } catch {
            Log.app.error("Move to /Applications failed: \(error.localizedDescription, privacy: .public)")
            // Fall back to revealing the app in Finder so the user can drag it.
            NSWorkspace.shared.activateFileViewerSelecting([src])
            return false
        }

        // Relaunch the copied app, then quit ourselves.
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [dest.path]
        do {
            try task.run()
        } catch {
            Log.app.error("Failed to relaunch from /Applications: \(error.localizedDescription, privacy: .public)")
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
        return true
    }

    /// Quit and reopen the current app from its current location.
    /// Used after the user grants Accessibility / Input Monitoring and
    /// needs a fresh process for TCC to apply.
    @MainActor
    static func relaunchSelf() {
        let src = Bundle.main.bundleURL
        // Use a small detached shell so we can `open` after we've quit.
        let script = """
        sleep 0.6
        open "\(src.path)"
        """
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            Log.app.error("Failed to schedule self-relaunch: \(error.localizedDescription, privacy: .public)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }
}
