import Foundation
import os
import Sentry

/// Centralized crash + error reporting via Sentry. Disabled when no DSN is
/// configured in `CloudConfig.plist` — falls back to local `os.Logger`.
enum CrashReporter {
    private(set) static var isEnabled = false

    static func start() {
        let dsn = CloudConfig.shared.sentryDSN
        guard !dsn.isEmpty, !dsn.contains("YOUR_") else {
            Log.app.debug("CrashReporter: no Sentry DSN configured")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.enableCrashHandler = true
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true
            options.tracesSampleRate = 0.2

            #if DEBUG
            options.environment = "debug"
            options.debug = false
            #else
            options.environment = "production"
            #endif

            let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
            let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
            options.releaseName = "mellotron@\(short)+\(build)"
        }

        isEnabled = true
        Log.app.info("CrashReporter: Sentry active")
    }

    static func capture(_ error: Error, context: [String: String] = [:]) {
        Log.app.error("Captured error: \(error.localizedDescription, privacy: .public)")
        for (k, v) in context {
            Log.app.error("  \(k, privacy: .public): \(v, privacy: .public)")
        }
        guard isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            for (k, v) in context { scope.setExtra(value: v, key: k) }
        }
    }

    static func captureMessage(_ message: String) {
        Log.app.error("Report: \(message, privacy: .public)")
        guard isEnabled else { return }
        SentrySDK.capture(message: message)
    }
}
