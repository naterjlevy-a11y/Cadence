import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

/// Identifies a push-to-talk activation key. We support a small set of
/// well-known modifier-style keys that work reliably as global hold-to-record
/// keys, plus a custom keycode option captured from the user.
enum PushToTalkKey: String, Codable, CaseIterable, Identifiable {
    case rightControl
    case rightOption
    case capsLock
    case fnGlobe
    case f5
    case f6
    case f13
    case f14
    case f15
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightControl: return "Right Control"
        case .rightOption: return "Right Option"
        case .capsLock: return "Caps Lock"
        case .fnGlobe: return "Fn / Globe"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .custom: return "Custom"
        }
    }

    /// Whether this key is robust enough to be recommended for new users.
    var isRecommended: Bool {
        switch self {
        case .rightControl, .rightOption, .f5, .f13: return true
        default: return false
        }
    }
}

/// How the user starts and stops a recording.
enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    /// Hold the key down to record. Release to stop. (Wispr Flow default.)
    case holdToTalk
    /// Double-tap the key quickly to start recording. Tap once or
    /// double-tap again to stop. Useful when a chat agent already owns
    /// hold-to-talk on the same key.
    case doubleTapToggle
    /// Both at once. Hold the key for walkie-talkie mode (release to send).
    /// Or double-tap to start hands-free, double-tap (or single tap) to stop.
    /// Whichever you do first wins.
    case hybrid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .holdToTalk: return "Hold to talk"
        case .doubleTapToggle: return "Double-tap to toggle"
        case .hybrid: return "Hybrid (both)"
        }
    }

    var description: String {
        switch self {
        case .holdToTalk: return "Press and hold the key while you speak. Release to send."
        case .doubleTapToggle: return "Tap the key twice quickly to start. Tap again to stop and send."
        case .hybrid: return "Hold for walkie-talkie. Double-tap to lock in, then a single tap to send."
        }
    }
}

enum CleanupLevel: String, Codable, CaseIterable, Identifiable {
    case raw
    case light
    case standard
    case professional

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: return "Raw transcript"
        case .light: return "Light cleanup"
        case .standard: return "Standard cleanup"
        case .professional: return "Professional rewrite"
        }
    }

    var description: String {
        switch self {
        case .raw: return "No edits — paste exactly what was transcribed."
        case .light: return "Remove obvious filler words. Light punctuation."
        case .standard: return "Remove fillers, punctuate, capitalize, format."
        case .professional: return "Tighten phrasing while preserving meaning."
        }
    }
}

enum BrowserPreference: String, Codable, CaseIterable, Identifiable {
    case auto
    case safari
    case chrome
    case arc
    case edge
    case firefox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (default browser)"
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .edge: return "Microsoft Edge"
        case .firefox: return "Firefox"
        }
    }

    var bundleId: String? {
        switch self {
        case .auto: return nil
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .arc: return "company.thebrowser.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .firefox: return "org.mozilla.firefox"
        }
    }
}

enum NoRoutePolicy: String, Codable, Identifiable {
    case currentApp
    case lastDestination
    /// Legacy — still decodes from older installs; treated like `currentApp`.
    case scratchpad
    case ask

    var id: String { rawValue }

    static var allCases: [NoRoutePolicy] { [.currentApp, .lastDestination] }

    var displayName: String {
        switch self {
        case .currentApp: return "Paste into the current app"
        case .lastDestination: return "Use last destination"
        case .scratchpad, .ask: return "Paste into the current app"
        }
    }
}

/// Centralized, observable user preferences backed by `UserDefaults`.
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var observer: NSObjectProtocol?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Property-wrapper writes post `.preferencesDidChange`; rebroadcast as
        // SwiftUI changes so views observing this object refresh.
        observer = NotificationCenter.default.addObserver(
            forName: .preferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
        runMigrations()
    }

    /// One-time data migrations. Keyed on small flags so each runs once.
    private func runMigrations() {
        // v2: hands-free "hybrid" latching confused users — move everyone to
        // plain hold-to-talk unless they had explicitly chosen double-tap.
        if !defaults.bool(forKey: "migration.pttHoldToTalk.v2") {
            if activationMode == .hybrid { activationMode = .holdToTalk }
            defaults.set(true, forKey: "migration.pttHoldToTalk.v2")
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Onboarding

    @PublishedDefault("hasCompletedOnboarding", default: false)
    var hasCompletedOnboarding: Bool

    // MARK: - General

    @PublishedDefault("launchAtLogin", default: false)
    var launchAtLogin: Bool

    @PublishedDefault("showMenuBarIcon", default: true)
    var showMenuBarIcon: Bool

    @PublishedDefault("showFloatingIndicator", default: true)
    var showFloatingIndicator: Bool

    @PublishedDefault("playSounds", default: true)
    var playSounds: Bool

    @PublishedDefault("soundVolume", default: 0.3)
    var soundVolume: Double

    @PublishedDefault("paused", default: false)
    var paused: Bool

    @PublishedDefault("developerDebugMode", default: false)
    var developerDebugMode: Bool

    // MARK: - Push-to-talk

    @PublishedDefault("pushToTalkKey", default: PushToTalkKey.rightControl)
    var pushToTalkKey: PushToTalkKey

    @PublishedDefault("customKeyCode", default: -1)
    var customKeyCode: Int

    @PublishedDefault("minimumHoldMilliseconds", default: 150)
    var minimumHoldMilliseconds: Int

    @PublishedDefault("maximumRecordingSeconds", default: 300)
    var maximumRecordingSeconds: Int

    @PublishedDefault("preferOnDeviceTranscription", default: false)
    var preferOnDeviceTranscription: Bool

    @PublishedDefault("activationMode", default: ActivationMode.holdToTalk)
    var activationMode: ActivationMode

    @PublishedDefault("doubleTapMaxIntervalMs", default: 450)
    var doubleTapMaxIntervalMs: Int

    @PublishedDefault("brandDictionaryEnabled", default: true)
    var brandDictionaryEnabled: Bool

    @PublishedDefault("smartFormattingEnabled", default: true)
    var smartFormattingEnabled: Bool

    @PublishedDefault("onboardingStep", default: 0)
    var onboardingStep: Int

    @PublishedDefault("aiPolishEnabled", default: true)
    var aiPolishEnabled: Bool

    @PublishedDefault("aiPolishProvider", default: "openrouter")
    var aiPolishProvider: String

    @PublishedDefault("aiPolishApiKey", default: "")
    var aiPolishApiKey: String

    @PublishedDefault("aiPolishModel", default: "openai/gpt-4o-mini")
    var aiPolishModel: String

    @PublishedDefault("aiPolishEndpoint", default: "https://openrouter.ai/api/v1/chat/completions")
    var aiPolishEndpoint: String

    // MARK: - Transcription (speech-to-text)

    /// `"apple"` (Apple Speech, on-device + free) or `"groq"` (Groq Whisper,
    /// far better recognition of brand names / proper nouns, ~free tier).
    @PublishedDefault("transcriptionProvider", default: "groq")
    var transcriptionProvider: String

    /// Groq Cloud API key. Free signup at https://console.groq.com/keys.
    @PublishedDefault("groqApiKey", default: "")
    var groqApiKey: String

    /// Groq Whisper model. `whisper-large-v3-turbo` is the recommended
    /// fast-and-accurate default; `whisper-large-v3` is slightly more
    /// accurate but ~2x slower.
    @PublishedDefault("groqWhisperModel", default: "whisper-large-v3-turbo")
    var groqWhisperModel: String

    /// Fall back to Apple Speech if Groq fails / network is down / no key.
    @PublishedDefault("transcriptionFallbackToApple", default: true)
    var transcriptionFallbackToApple: Bool

    /// How Groq auth works when `transcriptionProvider == "groq"`:
    /// `auto` = Cadence Cloud if signed in, else BYOK, else Apple;
    /// `cloud` = proxy only; `byok` = your own Groq key only.
    @PublishedDefault("transcriptionAuthMode", default: "auto")
    var transcriptionAuthMode: String

    @PublishedDefault("cloudUserId", default: "")
    var cloudUserId: String

    @PublishedDefault("cloudUserEmail", default: "")
    var cloudUserEmail: String

    @PublishedDefault("cloudIsAnonymous", default: true)
    var cloudIsAnonymous: Bool

    /// Set to true once the user has dismissed the "permissions need a refresh"
    /// banner. Stays dismissed across launches as long as the same set of
    /// permissions remains in the "silently denied" state. Re-arms automatically
    /// when a new permission goes missing.
    @PublishedDefault("permissionBannerDismissedSignature", default: "")
    var permissionBannerDismissedSignature: String

    /// Default `false`: Cadence's built-in WKWebView popup (small,
    /// top-right, always-on-top). When `importChromeCookies` is on, session
    /// cookies are copied from Chrome before each load. Set `true` to open a
    /// chromeless Chrome `--app=` window instead (inherits Chrome session
    /// natively, but can't stay always-on-top).
    @PublishedDefault("popupUsesBrowserAppWindow", default: false)
    var popupUsesBrowserAppWindow: Bool

    /// Copy session cookies from the local Chrome profile into the embedded
    /// popup before loading. Requires one-time Keychain approval.
    @PublishedDefault("importChromeCookies", default: true)
    var importChromeCookies: Bool

    /// Chrome profile directory name under ~/Library/Application Support/Google/Chrome/.
    @PublishedDefault("chromeCookieProfile", default: "Default")
    var chromeCookieProfile: String

    // MARK: - Dictation / Cleanup

    @PublishedDefault("cleanupLevel", default: CleanupLevel.standard)
    var cleanupLevel: CleanupLevel

    @PublishedDefault("removeFillerWords", default: true)
    var removeFillerWords: Bool

    @PublishedDefault("addPunctuation", default: true)
    var addPunctuation: Bool

    @PublishedDefault("autoFormatLists", default: true)
    var autoFormatLists: Bool

    @PublishedDefault("personalDictionary", default: [String]())
    var personalDictionary: [String]

    // MARK: - Routing

    @PublishedDefault("enableSpokenRouting", default: true)
    var enableSpokenRouting: Bool

    @PublishedDefault("noRoutePolicy", default: NoRoutePolicy.currentApp)
    var noRoutePolicy: NoRoutePolicy

    @PublishedDefault("preferExistingWindows", default: true)
    var preferExistingWindows: Bool

    @PublishedDefault("browserPreference", default: BrowserPreference.auto)
    var browserPreference: BrowserPreference

    @PublishedDefault("autoSubmit", default: false)
    var autoSubmit: Bool

    @PublishedDefault("lastDestinationId", default: "")
    var lastDestinationId: String

    // MARK: - Privacy

    @PublishedDefault("saveDictationHistory", default: false)
    var saveDictationHistory: Bool

    @PublishedDefault("preserveClipboard", default: true)
    var preserveClipboard: Bool

    // MARK: - Per-destination overrides (id -> serialized DestinationOverride)

    @PublishedDefault("destinationOverrides", default: [String: Data]())
    var destinationOverrides: [String: Data]

    /// User-created destinations (paste-a-URL quick adds in Settings).
    @PublishedDefault("userDestinations", default: [Data]())
    var userDestinations: [Data]

    // MARK: - History

    @PublishedDefault("dictationHistory", default: [Data]())
    var dictationHistory: [Data]

    /// Restores every preference to its factory default (does not clear Keychain secrets).
    func resetAllToDefaults() {
        hasCompletedOnboarding = false
        launchAtLogin = false
        LaunchAtLogin.setEnabled(false)
        showMenuBarIcon = true
        showFloatingIndicator = true
        playSounds = true
        soundVolume = 0.3
        paused = false
        developerDebugMode = false
        pushToTalkKey = .rightControl
        customKeyCode = -1
        minimumHoldMilliseconds = 150
        maximumRecordingSeconds = 300
        preferOnDeviceTranscription = false
        activationMode = .holdToTalk
        doubleTapMaxIntervalMs = 450
        brandDictionaryEnabled = true
        smartFormattingEnabled = true
        onboardingStep = 0
        aiPolishEnabled = true
        aiPolishProvider = "openrouter"
        aiPolishApiKey = ""
        aiPolishModel = "openai/gpt-4o-mini"
        aiPolishEndpoint = "https://openrouter.ai/api/v1/chat/completions"
        transcriptionProvider = "groq"
        groqApiKey = ""
        groqWhisperModel = "whisper-large-v3-turbo"
        transcriptionFallbackToApple = true
        transcriptionAuthMode = "auto"
        popupUsesBrowserAppWindow = false
        importChromeCookies = true
        chromeCookieProfile = "Default"
        cleanupLevel = .standard
        removeFillerWords = true
        addPunctuation = true
        autoFormatLists = true
        personalDictionary = []
        enableSpokenRouting = true
        noRoutePolicy = .currentApp
        preferExistingWindows = true
        browserPreference = .auto
        autoSubmit = false
        lastDestinationId = ""
        saveDictationHistory = false
        preserveClipboard = true
        destinationOverrides = [:]
        dictationHistory = []
    }
}

/// Codable-aware UserDefaults backed property wrapper that publishes changes.
@propertyWrapper
struct PublishedDefault<Value: Codable> {
    let key: String
    let defaultValue: Value
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value {
        get {
            // Primitives stored directly for forward-compat with Settings.app inspectors.
            if Value.self == Bool.self,
               let value = defaults.object(forKey: key) as? Bool {
                return value as! Value
            }
            if Value.self == Int.self,
               let value = defaults.object(forKey: key) as? Int {
                return value as! Value
            }
            if Value.self == String.self,
               let value = defaults.object(forKey: key) as? String {
                return value as! Value
            }
            if Value.self == [String].self,
               let value = defaults.object(forKey: key) as? [String] {
                return value as! Value
            }
            guard let data = defaults.data(forKey: key) else { return defaultValue }
            return (try? decoder.decode(Value.self, from: data)) ?? defaultValue
        }
        set {
            if let bool = newValue as? Bool {
                defaults.set(bool, forKey: key)
            } else if let int = newValue as? Int {
                defaults.set(int, forKey: key)
            } else if let string = newValue as? String {
                defaults.set(string, forKey: key)
            } else if let strings = newValue as? [String] {
                defaults.set(strings, forKey: key)
            } else if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: key)
            }
            // Post asynchronously so we exit the property-wrapper exclusive
            // write before any observer reads back through the same wrapper.
            // Without this, observers that read another @PublishedDefault on
            // the same instance can hit Swift's exclusivity checker.
            let postedKey = key
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .preferencesDidChange,
                    object: nil,
                    userInfo: ["key": postedKey]
                )
            }
        }
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("CadencePreferencesDidChange")
    static let cadenceOpenPermissionRepair = Notification.Name("CadenceOpenPermissionRepair")
}
