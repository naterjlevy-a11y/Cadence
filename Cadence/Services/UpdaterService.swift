import Foundation
import AppKit
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController`. Schedules background checks
/// every 24 hours, exposes a manual "Check for Updates" action, and
/// surfaces a delegate hook for logging.
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,  // off until we ship a signed appcast
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = true
        controller.updater.updateCheckInterval = 60 * 60 * 24
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    var canCheckNow: Bool {
        controller.updater.canCheckForUpdates
    }
}

extension UpdaterService: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            Log.app.error("Sparkle update cycle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
