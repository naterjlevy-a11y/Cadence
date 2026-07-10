import Foundation
import ServiceManagement

/// Wraps the `SMAppService` API so the rest of the app can toggle launch-at-login
/// without thinking about availability.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.app.error("Failed to toggle launch-at-login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension LaunchAtLogin {
    /// Alias used by newer call sites.
    static func apply(_ enabled: Bool) { setEnabled(enabled) }

    /// Reconcile system state with the stored preference at startup.
    static func sync() {
        let wanted = UserPreferences.shared.launchAtLogin
        if wanted != isEnabled { setEnabled(wanted) }
    }
}
