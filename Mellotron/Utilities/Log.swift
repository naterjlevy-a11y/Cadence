import Foundation
import os

/// Lightweight wrapper around `os.Logger` that suppresses sensitive payloads
/// unless developer debug mode is explicitly enabled.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mellotron.Mellotron"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    static let router = Logger(subsystem: subsystem, category: "router")
    static let launch = Logger(subsystem: subsystem, category: "launch")
    static let paste = Logger(subsystem: subsystem, category: "paste")
    static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let cookies = Logger(subsystem: subsystem, category: "cookies")

    /// Returns `text` if developer debug mode is on, otherwise `"<redacted>"`.
    static func redact(_ text: String) -> String {
        UserPreferences.shared.developerDebugMode ? text : "<redacted>"
    }
}
