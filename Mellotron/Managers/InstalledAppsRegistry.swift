import Foundation
import AppKit

/// Scans the user's installed apps and turns each one into a routable
/// destination. This is what makes "Hey Photos", "Hey Freeform",
/// "Hey Final Cut Pro" Just Work without the user having to configure
/// anything.
final class InstalledAppsRegistry {
    static let shared = InstalledAppsRegistry()

    private(set) var destinations: [Destination] = []
    private var fingerprint: String = ""

    private let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        ("~/Applications" as NSString).expandingTildeInPath,
    ]

    private init() {
        refresh()
    }

    /// Re-scan disk and rebuild the destination list. Cheap (~tens of ms).
    @discardableResult
    func refresh() -> [Destination] {
        let fm = FileManager.default
        var apps: [Destination] = []
        var seenBundles: Set<String> = []

        for root in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: root).appendingPathComponent(entry)
                guard let dest = destination(forApp: appURL),
                      let bundleId = dest.bundleId,
                      !seenBundles.contains(bundleId) else { continue }
                seenBundles.insert(bundleId)
                apps.append(dest)
            }
        }
        // Sort by name so the list is stable when surfaced in UI.
        apps.sort { $0.displayName.lowercased() < $1.displayName.lowercased() }
        self.destinations = apps
        self.fingerprint = apps.map { $0.id }.joined(separator: ",")
        Log.app.info("InstalledAppsRegistry: indexed \(apps.count, privacy: .public) apps")
        return apps
    }

    private func destination(forApp url: URL) -> Destination? {
        guard let bundle = Bundle(url: url) else { return nil }
        guard let bundleId = bundle.bundleIdentifier else { return nil }
        // Skip helpers, daemons, and our own bundle.
        if bundleId == "com.mellotron.Mellotron" { return nil }
        if bundleId.contains(".helper") || bundleId.contains(".Helper") { return nil }

        let displayName = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return Destination(
            id: "installed:\(bundleId)",
            displayName: displayName,
            aliases: aliases(forName: displayName, bundleId: bundleId),
            bundleId: bundleId,
            url: nil,
            preferredMode: .nativeAppOnly,
            fallbackMode: nil,
            autoSubmitEnabled: false,
            pasteDelaySeconds: 0.5,
            enabled: true,
            inputFieldHints: [],
            customUserAliases: []
        )
    }

    /// Build a list of likely-spoken aliases for an app. Includes the
    /// display name (lowercased), name without spaces, and well-known
    /// nicknames for common apps.
    private func aliases(forName name: String, bundleId: String) -> [String] {
        var aliases: Set<String> = []
        let lower = name.lowercased()
        aliases.insert(lower)
        // Strip trailing words like "(beta)" / "pro" only when long enough.
        let stripped = lower
            .replacingOccurrences(of: " (beta)", with: "")
            .replacingOccurrences(of: " (lite)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        aliases.insert(stripped)

        // Hand-crafted nicknames for common apps.
        if let extras = Self.commonAppNicknames[bundleId] {
            for ex in extras { aliases.insert(ex) }
        }
        return Array(aliases)
    }

    /// Bundle-id -> alternate names that real humans actually say.
    private static let commonAppNicknames: [String: [String]] = [
        "com.apple.Photos": ["photos", "photo library", "my photos"],
        "com.apple.mail": ["mail", "apple mail", "email", "inbox", "gmail"],
        "com.apple.Music": ["music", "apple music", "itunes", "songs"],
        "com.apple.TV": ["tv", "apple tv", "television"],
        "com.apple.podcasts": ["podcasts", "podcast"],
        "com.apple.iCal": ["calendar", "cal", "schedule"],
        "com.apple.iPhoto": ["photos", "iphoto"],
        "com.apple.Notes": ["notes", "apple notes", "note"],
        "com.apple.reminders": ["reminders", "to do", "todo"],
        "com.apple.freeform": ["freeform", "free form", "whiteboard"],
        "com.apple.iWork.Pages": ["pages", "apple pages"],
        "com.apple.iWork.Numbers": ["numbers", "apple numbers"],
        "com.apple.iWork.Keynote": ["keynote"],
        "com.apple.Safari": ["safari", "browser"],
        "com.google.Chrome": ["chrome", "google chrome"],
        "com.brave.Browser": ["brave", "brave browser"],
        "company.thebrowser.Browser": ["arc", "arc browser"],
        "com.microsoft.VSCode": ["vs code", "vscode", "code"],
        "com.todesktop.230313mzl4w4u92": ["cursor", "code editor"],
        "com.tinyspeck.slackmacgap": ["slack"],
        "com.figma.Desktop": ["figma"],
        "com.linear": ["linear"],
        "com.spotify.client": ["spotify"],
        "com.openai.chat": ["chat gpt", "chatgpt", "gpt", "open ai"],
        "com.anthropic.claudefordesktop": ["claude", "anthropic", "cloud"],
        "ai.perplexity.mac": ["perplexity", "search ai"],
        "com.discord": ["discord"],
        "com.hnc.Discord": ["discord"],
        "com.tdesktop.Telegram": ["telegram"],
        "com.WhatsApp.WhatsAppMac": ["whatsapp", "whats app"],
        "com.apple.iChat": ["messages", "imessage", "texts", "text messages"],
        "com.apple.MobileSMS": ["messages", "imessage", "texts", "text messages"],
        "com.apple.FaceTime": ["facetime", "face time", "video call"],
        "com.apple.Maps": ["maps", "apple maps", "directions"],
        "com.apple.weather": ["weather"],
        "com.apple.stocks": ["stocks"],
        "com.apple.iBooksX": ["books", "apple books", "ibooks"],
        "com.apple.dt.Xcode": ["xcode"],
        "com.apple.Terminal": ["terminal"],
        "com.googlecode.iterm2": ["iterm", "iterm2"],
        "com.apple.systempreferences": ["system settings", "system preferences", "settings", "preferences"],
        "com.apple.SystemPreferences": ["system settings", "system preferences", "settings", "preferences"],
        "com.apple.finder": ["finder", "files", "my files"],
        "com.apple.ActivityMonitor": ["activity monitor"],
    ]
}

/// A small set of friendly named web destinations + Easter eggs. Folded
/// into the main registry alongside installed apps.
enum WebShortcuts {
    static let destinations: [Destination] = [
        web(id: "encyclopedia",
            name: "Wikipedia",
            aliases: ["encyclopedia", "wikipedia", "wiki"],
            url: "https://en.wikipedia.org/wiki/Special:Random"),
        web(id: "dictionary",
            name: "Dictionary",
            aliases: ["dictionary", "define"],
            url: "https://www.dictionary.com/"),
        web(id: "thesaurus",
            name: "Thesaurus",
            aliases: ["thesaurus", "synonym"],
            url: "https://www.thesaurus.com/"),
        web(id: "translate",
            name: "Google Translate",
            aliases: ["translate", "translation"],
            url: "https://translate.google.com/"),
        web(id: "google",
            name: "Google",
            aliases: ["google", "search the web", "google search"],
            url: "https://www.google.com/"),
        web(id: "youtube",
            name: "YouTube",
            aliases: ["youtube", "you tube"],
            url: "https://www.youtube.com/"),
        web(id: "github",
            name: "GitHub",
            aliases: ["github", "git hub"],
            url: "https://github.com/"),
        web(id: "stackoverflow",
            name: "Stack Overflow",
            aliases: ["stack overflow", "stackoverflow"],
            url: "https://stackoverflow.com/"),
        web(id: "calendar_web",
            name: "Google Calendar",
            aliases: ["google calendar", "g cal", "gcal"],
            url: "https://calendar.google.com/"),
        web(id: "drive",
            name: "Google Drive",
            aliases: ["drive", "google drive"],
            url: "https://drive.google.com/"),
        // Easter eggs ✨
        web(id: "easter_potato",
            name: "Potato",
            aliases: ["potato"],
            url: "https://en.wikipedia.org/wiki/Potato"),
        web(id: "easter_random",
            name: "Random Wikipedia",
            aliases: ["random", "surprise me", "show me something"],
            url: "https://en.wikipedia.org/wiki/Special:Random"),
        web(id: "easter_zen",
            name: "Hacker News",
            aliases: ["hacker news", "yc", "hn", "news"],
            url: "https://news.ycombinator.com/"),
    ]

    private static func web(id: String, name: String, aliases: [String], url: String) -> Destination {
        Destination(
            id: "web:\(id)",
            displayName: name,
            aliases: aliases,
            bundleId: nil,
            url: URL(string: url)!,
            preferredMode: .websiteOnly,
            fallbackMode: nil,
            autoSubmitEnabled: false,
            pasteDelaySeconds: 0.6,
            enabled: true,
            inputFieldHints: [],
            customUserAliases: []
        )
    }
}
