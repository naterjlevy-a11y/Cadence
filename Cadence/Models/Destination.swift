import Foundation

/// How Cadence should reach a destination.
enum LaunchMode: String, Codable {
    /// Try the native app first. If absent, fall back to the website.
    case nativeAppPreferred
    /// Try the website first. If absent, fall back to the native app.
    case websitePreferred
    /// Only use the website (e.g., Gemini, Google Docs).
    case websiteOnly
    /// Only use the native app (e.g., Apple Notes).
    case nativeAppOnly
    /// Stay in the current app — paste into whatever has focus.
    case currentApp
}

/// A user-defined target inside a destination — e.g. a specific Google Doc
/// they care about. The user can say "Hey Google Docs, Nate Levy, …" and
/// Cadence will open the matching URL instead of the destination's default.
struct Subdestination: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Lowercased aliases. The display name is implicitly an alias too.
    var aliases: [String]
    var url: URL

    init(id: UUID = UUID(), name: String, aliases: [String] = [], url: URL) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.url = url
    }

    var allMatchableNames: [String] {
        ([name] + aliases)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}

/// Describes a single destination Cadence knows how to route to.
struct Destination: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    /// Lowercased, regex-friendly aliases recognized at the start of speech.
    var aliases: [String]
    var bundleId: String?
    var url: URL?
    var preferredMode: LaunchMode
    var fallbackMode: LaunchMode?
    var autoSubmitEnabled: Bool
    var pasteDelaySeconds: Double
    var enabled: Bool
    /// Selector hints for the input field on a webpage. Used for future
    /// Accessibility-driven input insertion. Optional for MVP.
    var inputFieldHints: [String]
    var customUserAliases: [String]
    /// User-defined named shortcuts (e.g. specific Google Docs).
    var subdestinations: [Subdestination] = []
    /// Optional keyboard shortcut to focus the chat / message input field
    /// inside the destination app (e.g. "cmd+l" for Cursor's chat panel).
    /// Sent right after activation but before paste, so the dictation lands
    /// in the right place even if the user was on a different page.
    /// Format: lowercase `cmd|shift|option|ctrl|alt` joined by `+`, then a
    /// single key char or special name. Examples: "cmd+l", "cmd+shift+i".
    var focusInputShortcut: String? = nil

    /// When true, opening this destination shows it in Cadence's floating
    /// web-popup window (pinned to a corner of the screen) instead of
    /// launching the native app or full browser tab. Requires a URL.
    var openInPopup: Bool = false

    /// When non-empty, this destination is a *quick paste* (keyword) snippet:
    /// saying "Hey [alias]" pastes this exact text into the current app and
    /// ignores anything else you say. Stored locally on this Mac only.
    var pasteSnippet: String? = nil

    /// True when this destination just pastes a saved snippet instead of
    /// opening an app or website.
    var isSnippet: Bool {
        guard let pasteSnippet else { return false }
        return !pasteSnippet.isEmpty
    }

    var allAliases: [String] {
        (aliases + customUserAliases).map { $0.lowercased() }
    }
}

/// Per-destination user override for things like aliases / submit / mode.
struct DestinationOverride: Codable {
    var enabled: Bool? = nil
    var customUserAliases: [String]? = nil
    var preferredMode: LaunchMode? = nil
    var autoSubmitEnabled: Bool? = nil
    var pasteDelaySeconds: Double? = nil
    var subdestinations: [Subdestination]? = nil
    var openInPopup: Bool? = nil
    var pasteSnippet: String? = nil
}

/// Registry of all known destinations. Built-ins are merged with user overrides.
final class DestinationRegistry {
    static let shared = DestinationRegistry()

    private(set) var destinations: [Destination]

    private init() {
        self.destinations = DestinationRegistry.builtIns()
        applyStoredOverrides()
        NotificationCenter.default.addObserver(
            forName: .preferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let key = note.userInfo?["key"] as? String else { return }
            if key == "destinationOverrides" || key == "userDestinations" {
                self?.applyStoredOverrides()
            }
        }
    }

    func destination(withId id: String) -> Destination? {
        destinations.first { $0.id == id }
    }

    func updateOverride(_ override: DestinationOverride, for id: String) {
        var current = UserPreferences.shared.destinationOverrides
        if let data = try? JSONEncoder().encode(override) {
            current[id] = data
        }
        UserPreferences.shared.destinationOverrides = current
    }

    func clearOverride(for id: String) {
        var current = UserPreferences.shared.destinationOverrides
        current.removeValue(forKey: id)
        UserPreferences.shared.destinationOverrides = current
    }

    private func applyStoredOverrides() {
        let overrides = UserPreferences.shared.destinationOverrides
        var updated = DestinationRegistry.builtIns()
        // Merge in installed apps + web shortcuts + user-defined destinations.
        // Built-ins win on id collision.
        let existingIds = Set(updated.map(\.id))
        let extras = InstalledAppsRegistry.shared.destinations
            + WebShortcuts.destinations
            + CustomDestinationsStore.shared.load()
        for extra in extras where !existingIds.contains(extra.id) {
            updated.append(extra)
        }
        for index in updated.indices {
            guard let data = overrides[updated[index].id],
                  let override = try? JSONDecoder().decode(DestinationOverride.self, from: data) else {
                continue
            }
            if let enabled = override.enabled { updated[index].enabled = enabled }
            if let aliases = override.customUserAliases { updated[index].customUserAliases = aliases }
            if let mode = override.preferredMode { updated[index].preferredMode = mode }
            if let auto = override.autoSubmitEnabled { updated[index].autoSubmitEnabled = auto }
            if let delay = override.pasteDelaySeconds { updated[index].pasteDelaySeconds = delay }
            if let subs = override.subdestinations { updated[index].subdestinations = subs }
            if let popup = override.openInPopup { updated[index].openInPopup = popup }
            if let snippet = override.pasteSnippet { updated[index].pasteSnippet = snippet }
        }
        self.destinations = updated
    }

    static func builtIns() -> [Destination] {
        [
            Destination(
                id: "claude",
                displayName: "Claude",
                aliases: ["claude", "claudia", "claudio", "claud", "clyde", "cloud", "clod", "anthropic"],
                bundleId: "com.anthropic.claudefordesktop",
                url: URL(string: "https://claude.ai/new"),
                preferredMode: .nativeAppPreferred,
                fallbackMode: .websitePreferred,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.6,
                enabled: true,
                inputFieldHints: ["ProseMirror", "main-input"],
                customUserAliases: [],
                focusInputShortcut: "cmd+/"
            ),
            Destination(
                id: "chatgpt",
                displayName: "ChatGPT",
                aliases: ["chatgpt", "chat gpt", "gpt", "open ai", "openai", "chachi pt", "chat gbt", "chad gpt", "chatty", "chatty gpt", "chat g p t"],
                bundleId: "com.openai.chat",
                url: URL(string: "https://chat.openai.com/"),
                preferredMode: .nativeAppPreferred,
                fallbackMode: .websitePreferred,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.6,
                enabled: true,
                inputFieldHints: ["prompt-textarea"],
                customUserAliases: []
            ),
            Destination(
                id: "gemini",
                displayName: "Gemini",
                aliases: ["gemini", "google gemini", "bard", "jiminy", "jimmy", "germany", "gemany"],
                bundleId: nil,
                url: URL(string: "https://gemini.google.com/app"),
                preferredMode: .websiteOnly,
                fallbackMode: nil,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 1.35,
                enabled: true,
                inputFieldHints: ["rich-textarea"],
                customUserAliases: []
            ),
            Destination(
                id: "google_docs",
                displayName: "Google Docs",
                aliases: ["google docs", "google doc", "docs", "document", "google dock", "google dox"],
                bundleId: nil,
                url: URL(string: "https://docs.google.com/document/u/0/"),
                preferredMode: .websiteOnly,
                fallbackMode: nil,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 1.2,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: []
            ),
            Destination(
                id: "cursor",
                displayName: "Cursor",
                aliases: ["cursor", "code editor", "my editor", "courser", "kurser", "kursor", "cursive"],
                bundleId: "com.todesktop.230313mzl4w4u92",
                url: nil,
                preferredMode: .nativeAppOnly,
                fallbackMode: nil,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.85,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: [],
                focusInputShortcut: "cmd+l"
            ),
            Destination(
                id: "notes",
                displayName: "Apple Notes",
                aliases: ["notes", "apple notes", "note", "new note", "to my notes"],
                bundleId: "com.apple.Notes",
                url: nil,
                preferredMode: .nativeAppOnly,
                fallbackMode: nil,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.4,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: []
            ),
            Destination(
                id: "perplexity",
                displayName: "Perplexity",
                aliases: ["perplexity", "search ai", "perplex", "perplexed"],
                bundleId: "ai.perplexity.mac",
                url: URL(string: "https://www.perplexity.ai/"),
                preferredMode: .nativeAppPreferred,
                fallbackMode: .websitePreferred,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.5,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: []
            ),
            Destination(
                id: "gmail",
                displayName: "Gmail",
                aliases: ["gmail", "google mail"],
                bundleId: nil,
                url: URL(string: "https://mail.google.com/"),
                preferredMode: .websiteOnly,
                fallbackMode: nil,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.7,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: []
            ),
            Destination(
                id: "slack",
                displayName: "Slack",
                aliases: ["slack"],
                bundleId: "com.tinyspeck.slackmacgap",
                url: URL(string: "https://app.slack.com/"),
                preferredMode: .nativeAppPreferred,
                fallbackMode: .websitePreferred,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.4,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: []
            ),
            Destination(
                id: "current_app",
                displayName: "Current App",
                aliases: ["here", "this", "current app", "right here", "this app"],
                bundleId: nil,
                url: nil,
                preferredMode: .currentApp,
                fallbackMode: nil,
                autoSubmitEnabled: false,
                pasteDelaySeconds: 0.05,
                enabled: true,
                inputFieldHints: [],
                customUserAliases: []
            ),
        ]
    }
}
