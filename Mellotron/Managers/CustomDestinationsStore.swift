import Foundation

/// User-created destinations (e.g. paste-a-URL quick adds in Settings).
/// Stored as encoded `Destination` values in UserPreferences so they
/// participate in the same alias / routing / override pipeline as built-ins.
final class CustomDestinationsStore {
    static let shared = CustomDestinationsStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> [Destination] {
        UserPreferences.shared.userDestinations.compactMap {
            try? decoder.decode(Destination.self, from: $0)
        }
    }

    func save(_ destinations: [Destination]) {
        let encoded = destinations.compactMap { try? encoder.encode($0) }
        UserPreferences.shared.userDestinations = encoded
    }

    func add(name: String, url: URL, openInPopup: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let id = "user:" + trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        var existing = load()
        existing.removeAll { $0.id == id }
        let alias = trimmed.lowercased()
        let destination = Destination(
            id: id,
            displayName: trimmed,
            aliases: [alias],
            bundleId: nil,
            url: url,
            preferredMode: .websiteOnly,
            fallbackMode: nil,
            autoSubmitEnabled: false,
            pasteDelaySeconds: 0.6,
            enabled: true,
            inputFieldHints: [],
            customUserAliases: [],
            subdestinations: [],
            focusInputShortcut: nil,
            openInPopup: openInPopup
        )
        existing.append(destination)
        save(existing)
    }

    /// Create (or replace) a quick-paste keyword. Saying "Hey [keyword]"
    /// pastes `snippet` into the current app. Stored locally only.
    func addSnippet(keyword: String, snippet: String) {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        let trimmedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty, !trimmedSnippet.isEmpty else { return }
        let id = "snippet:" + trimmedKeyword.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        var existing = load()
        existing.removeAll { $0.id == id }
        let destination = Destination(
            id: id,
            displayName: trimmedKeyword,
            aliases: [trimmedKeyword.lowercased()],
            bundleId: nil,
            url: nil,
            preferredMode: .currentApp,
            fallbackMode: nil,
            autoSubmitEnabled: false,
            pasteDelaySeconds: 0.1,
            enabled: true,
            inputFieldHints: [],
            customUserAliases: [],
            subdestinations: [],
            focusInputShortcut: nil,
            openInPopup: false,
            pasteSnippet: trimmedSnippet
        )
        existing.append(destination)
        save(existing)
    }

    func remove(id: String) {
        var existing = load()
        existing.removeAll { $0.id == id }
        save(existing)
    }
}
