import Foundation

/// Bundled cloud service endpoints. Copy `CloudConfig.example.plist` →
/// `CloudConfig.plist` in this folder and fill in your Supabase + API URLs.
/// `CloudConfig.plist` is gitignored so secrets never ship in the repo.
struct CloudConfig {
    static let shared = CloudConfig()

    let supabaseURL: URL?
    let supabaseAnonKey: String
    let apiBaseURL: URL?
    let sentryDSN: String
    /// Where Supabase sends the user after they click a magic link or OAuth.
    /// Must be listed under Supabase → Authentication → URL Configuration → Redirect URLs.
    /// Local dev: run `npm run dev` in /web and use http://localhost:3000/auth/callback
    /// (or :3001 if 3000 is busy). Production: https://your-domain/auth/callback
    let authRedirectURL: String
    /// Stripe publishable key (pk_test_… / pk_live_…). Safe to ship in the app bundle.
    let stripePublishableKey: String

    /// True when Supabase + API base are configured (enables Cadence Cloud).
    var isCloudEnabled: Bool {
        guard supabaseURL != nil, apiBaseURL != nil, !supabaseAnonKey.isEmpty else { return false }
        return !supabaseAnonKey.contains("YOUR_") && !supabaseAnonKey.contains("REPLACE")
    }

    var transcribeURL: URL? {
        apiBaseURL?.appendingPathComponent("v1/transcribe")
    }

    var polishURL: URL? {
        apiBaseURL?.appendingPathComponent("v1/polish")
    }

    var quotaURL: URL? {
        apiBaseURL?.appendingPathComponent("v1/quota")
    }

    var embeddedCheckoutBaseURL: URL? {
        apiBaseURL?.appendingPathComponent("embedded-checkout")
    }

    private init() {
        var url: URL?
        var anonKey = ""
        var api: URL?
        var dsn = ""
        var authRedirect = "cadence://auth/callback"
        var stripePK = ""

        if let plist = Self.loadPlist(named: "CloudConfig") ?? Self.loadPlist(named: "CloudConfig.example") {
            url = (plist["SupabaseURL"] as? String).flatMap(URL.init(string:))
            anonKey = (plist["SupabaseAnonKey"] as? String) ?? ""
            api = (plist["APIBaseURL"] as? String).flatMap(URL.init(string:))
            dsn = (plist["SentryDSN"] as? String) ?? ""
            if let configured = plist["AuthRedirectURL"] as? String, !configured.isEmpty {
                authRedirect = configured
            }
            stripePK = (plist["StripePublishableKey"] as? String) ?? ""
        }

        if let envURL = ProcessInfo.processInfo.environment["CADENCE_SUPABASE_URL"],
           let parsed = URL(string: envURL) {
            url = parsed
        }
        if let key = ProcessInfo.processInfo.environment["CADENCE_SUPABASE_ANON_KEY"], !key.isEmpty {
            anonKey = key
        }
        if let envAPI = ProcessInfo.processInfo.environment["CADENCE_API_BASE_URL"],
           let parsed = URL(string: envAPI) {
            api = parsed
        }
        if let envDSN = ProcessInfo.processInfo.environment["CADENCE_SENTRY_DSN"], !envDSN.isEmpty {
            dsn = envDSN
        }
        if let envRedirect = ProcessInfo.processInfo.environment["CADENCE_AUTH_REDIRECT_URL"], !envRedirect.isEmpty {
            authRedirect = envRedirect
        }
        if let envPK = ProcessInfo.processInfo.environment["CADENCE_STRIPE_PUBLISHABLE_KEY"], !envPK.isEmpty {
            stripePK = envPK
        }

        supabaseURL = url
        supabaseAnonKey = anonKey
        apiBaseURL = api
        sentryDSN = dsn
        authRedirectURL = authRedirect
        stripePublishableKey = stripePK
    }

    private static func loadPlist(named: String) -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: named, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict
    }
}
