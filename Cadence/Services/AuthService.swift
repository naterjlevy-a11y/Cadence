import Foundation
import Combine
import AuthenticationServices
import AppKit

/// Supabase session management. Tokens live in Keychain via `SecretStore`.
///
/// Auth methods, in order of how the app uses them:
///   1. `bootstrapIfNeeded`          — silent anonymous session on first launch
///   2. `signInWithEmail` / `verifyEmailOTP`   — passwordless email code
///   3. `signInWithApple`            — native Apple sheet (needs paid Dev team)
///   4. `signInWithProvider(.google / .github / …)` — browser OAuth via Supabase
///   5. `handleCallbackURL`          — receives `cadence://auth/...` from OAuth
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userId: String?
    @Published private(set) var plan: String = "free"
    @Published private(set) var quotaUsedSeconds: Double = 0
    @Published private(set) var quotaLimitSeconds: Double = 0
    @Published private(set) var isAnonymous: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var pendingOTPEmail: String?
    @Published private(set) var otpResendAvailableAt: Date?

    /// Seconds until another OTP can be requested (0 = ready).
    var otpResendSecondsRemaining: Int {
        guard let at = otpResendAvailableAt else { return 0 }
        return max(0, Int(at.timeIntervalSinceNow.rounded(.up)))
    }

    var canResendOTP: Bool { otpResendSecondsRemaining == 0 }

    /// Supabase's default security cooldown for the same email is 60 seconds.
    /// We match it so the client doesn't let the user hit the server's 429.
    private let otpResendCooldownSeconds: TimeInterval = 60

    enum OAuthProvider: String, CaseIterable, Identifiable {
        case google
        case github
        case apple // for symmetry; we use the native sheet for Apple

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .google: return "Google"
            case .github: return "GitHub"
            case .apple:  return "Apple"
            }
        }
    }

    private var refreshTimer: Timer?
    private var didRestoreSession = false
    private var cloudBootstrapInFlight = false
    private var pendingCloudBootstrap: [(Bool) -> Void] = []
    private var refreshInFlight = false
    private var pendingRefreshWaiters: [(Bool) -> Void] = []

    private override init() {
        super.init()
    }

    /// Bearer token for Cadence Cloud API calls.
    var accessToken: String? {
        ensureSessionRestored()
        let token = SecretStore.shared.supabaseAccessToken
        return token.isEmpty ? nil : token
    }

    /// Touch Keychain only when cloud auth is actually needed — not at launch.
    private func ensureSessionRestored() {
        guard !didRestoreSession else { return }
        didRestoreSession = true
        restoreSession()
    }

    /// Ensures a Cadence Cloud bearer token exists before Groq-via-proxy calls.
    /// Creates an anonymous Supabase session if needed (async, coalesced).
    func ensureCloudSessionReady(completion: @escaping (Bool) -> Void) {
        guard CloudConfig.shared.isCloudEnabled else {
            completion(false)
            return
        }
        ensureSessionRestored()
        let token = SecretStore.shared.supabaseAccessToken
        if !token.isEmpty {
            completion(true)
            return
        }

        pendingCloudBootstrap.append(completion)
        guard !cloudBootstrapInFlight else { return }
        cloudBootstrapInFlight = true
        signInAnonymously { [weak self] ok in
            guard let self else { return }
            self.cloudBootstrapInFlight = false
            let waiters = self.pendingCloudBootstrap
            self.pendingCloudBootstrap.removeAll()
            waiters.forEach { $0(ok) }
        }
    }

    // MARK: - Bootstrap

    /// Call once at launch. Restores session or creates anonymous user when cloud is enabled.
    func bootstrapIfNeeded() {
        guard CloudConfig.shared.isCloudEnabled else { return }
        // Session restore and anonymous bootstrap run on first `accessToken` read.
    }

    func restoreSession() {
        let token = SecretStore.shared.supabaseAccessToken
        isSignedIn = !token.isEmpty
        userId = UserPreferences.shared.cloudUserId.nilIfEmpty
        userEmail = UserPreferences.shared.cloudUserEmail.nilIfEmpty
        isAnonymous = UserPreferences.shared.cloudIsAnonymous
        if isSignedIn {
            scheduleRefresh()
            withFreshToken { [weak self] _ in
                DispatchQueue.main.async { self?.fetchQuota() }
            }
        }
    }

    // MARK: - Anonymous

    func signInAnonymously(completion: @escaping (Bool) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(false); return
        }
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/signup"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = Data("{}".utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                self?.applyAuthResponse(data: data, response: response, source: .anonymous, completion: completion)
            }
        }.resume()
    }

    // MARK: - Email OTP (passwordless)

    /// Sends a 6-digit verification code email. User enters the code in-app.
    func signInWithEmail(_ email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(.failure(AuthError.notConfigured)); return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            completion(.failure(AuthError.invalidEmail)); return
        }

        if !canResendOTP {
            completion(.failure(AuthError.message("Wait \(otpResendSecondsRemaining)s before requesting another code.")))
            return
        }

        var req = URLRequest(url: base.appendingPathComponent("auth/v1/otp"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let redirect = CloudConfig.shared.authRedirectURL
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": trimmed,
            "create_user": true,
            "options": ["email_redirect_to": redirect]
        ])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 400 {
                    let msg = Self.parseSupabaseError(data: data, status: status,
                        fallback: "Could not send the verification code.")
                    // On a rate-limit, start a countdown from the server's wait
                    // time (when provided) so the Resend button reflects reality.
                    if status == 429 {
                        let wait = Self.retryAfterSeconds(from: msg) ?? Int(self?.otpResendCooldownSeconds ?? 60)
                        self?.otpResendAvailableAt = Date().addingTimeInterval(TimeInterval(wait))
                    }
                    self?.lastError = msg
                    completion(.failure(AuthError.message(msg)))
                    return
                }
                self?.pendingOTPEmail = trimmed
                self?.lastError = nil
                self?.otpResendAvailableAt = Date().addingTimeInterval(self?.otpResendCooldownSeconds ?? 60)
                completion(.success(()))
            }
        }.resume()
    }

    /// Verifies the 6-digit code from the sign-up email. Establishes a session
    /// so the user can set a password next — does not finish sign-in yet.
    func verifyEmailOTP(email: String, code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            completion(.failure(AuthError.message("Enter the code from your email."))); return
        }

        // Try email (existing users), signup (new users), magiclink (fallback).
        let verifyTypes = ["email", "signup", "magiclink"]
        tryVerifyTypes(verifyTypes, index: 0, email: trimmedEmail, code: trimmedCode, completion: completion)
    }

    private func tryVerifyTypes(
        _ types: [String],
        index: Int,
        email: String,
        code: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard index < types.count else {
            lastError = "That code didn't work. Check it or tap Resend code."
            completion(.failure(AuthError.message(lastError!)))
            return
        }
        attemptEmailVerify(type: types[index], email: email, code: code) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure:
                self?.tryVerifyTypes(types, index: index + 1, email: email, code: code, completion: completion)
            }
        }
    }

    /// Sets the account password after email verification. Supabase stores it hashed.
    func setPassword(_ password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(.failure(AuthError.notConfigured)); return
        }
        guard password.count >= 8 else {
            completion(.failure(AuthError.message("Password must be at least 8 characters."))); return
        }
        guard let token = accessToken, !token.isEmpty else {
            completion(.failure(AuthError.message("Verify your email first."))); return
        }

        var req = URLRequest(url: base.appendingPathComponent("auth/v1/user"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 400 {
                    let msg = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["msg"] as? String
                        ?? "Could not set password (HTTP \(status))."
                    self?.lastError = msg
                    completion(.failure(AuthError.message(msg)))
                    return
                }
                self?.pendingOTPEmail = nil
                self?.otpResendAvailableAt = nil
                self?.lastError = nil
                self?.fetchUser()
                self?.fetchQuota()
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .cadenceAuthCompleted, object: nil)
                completion(.success(()))
            }
        }.resume()
    }

    /// Email + password sign-in for returning users.
    func signInWithPassword(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(.failure(AuthError.notConfigured)); return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            completion(.failure(AuthError.message("Enter your email and password."))); return
        }

        var req = URLRequest(url: base.appendingPathComponent("auth/v1/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.url = req.url?.appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": trimmedEmail,
            "password": password,
        ])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 400 {
                    let msg = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["error_description"] as? String
                        ?? (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["msg"] as? String
                        ?? "Invalid email or password."
                    self?.lastError = msg
                    completion(.failure(AuthError.message(msg)))
                    return
                }
                self?.applyAuthResponse(data: data, response: response, source: .email) { ok in
                    if ok {
                        self?.pendingOTPEmail = nil
                        NSApp.activate(ignoringOtherApps: true)
                        NotificationCenter.default.post(name: .cadenceAuthCompleted, object: nil)
                        completion(.success(()))
                    } else {
                        completion(.failure(AuthError.message(self?.lastError ?? "Sign-in failed.")))
                    }
                }
            }
        }.resume()
    }

    private func attemptEmailVerify(
        type: String,
        email: String,
        code: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(.failure(AuthError.notConfigured)); return
        }

        var req = URLRequest(url: base.appendingPathComponent("auth/v1/verify"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": type,
            "email": email,
            "token": code,
        ])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 400 {
                    let msg = Self.parseSupabaseError(data: data, status: status,
                        fallback: "That code didn't work. Check it or request a new one.")
                    completion(.failure(AuthError.message(msg)))
                    return
                }
                self?.applyAuthResponse(data: data, response: response, source: .email) { ok in
                    if ok {
                        self?.lastError = nil
                        completion(.success(()))
                    } else {
                        completion(.failure(AuthError.message(self?.lastError ?? "Verification failed.")))
                    }
                }
            }
        }.resume()
    }

    private static func parseSupabaseError(data: Data?, status: Int, fallback: String) -> String {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }
        let code = (obj["error_code"] as? String) ?? (obj["code"] as? String) ?? ""
        let msg = (obj["msg"] as? String)
            ?? (obj["error_description"] as? String)
            ?? (obj["message"] as? String)
            ?? fallback

        if status == 429 || code == "over_email_send_rate_limit" {
            // Supabase's own message usually says exactly how long to wait
            // ("you can only request this after 54 seconds"). Surface it.
            if let seconds = retryAfterSeconds(from: msg) {
                return "Please wait \(seconds)s before requesting another code."
            }
            if msg.localizedCaseInsensitiveContains("security")
                || msg.localizedCaseInsensitiveContains("second") {
                return msg
            }
            return "You're requesting codes too quickly. Wait about a minute, then try again."
        }
        if code == "otp_expired" || msg.localizedCaseInsensitiveContains("expired") {
            return "That code expired. Tap Resend code for a new one."
        }
        if code == "otp_disabled" {
            return "Email codes aren't enabled. Check Supabase email settings."
        }
        if msg.localizedCaseInsensitiveContains("invalid") {
            return "That code isn't valid. Double-check the 6 digits from your email."
        }
        return msg
    }

    /// Extracts the wait time from messages like
    /// "For security purposes, you can only request this after 54 seconds".
    private static func retryAfterSeconds(from message: String) -> Int? {
        guard let range = message.range(
            of: "[0-9]+\\s*second",
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let digits = message[range].prefix { $0.isNumber }
        return Int(digits)
    }

    // MARK: - Apple

    func signInWithApple() {
        lastError = nil
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - OAuth (Google, GitHub, …)

    /// Opens the default browser to Supabase's OAuth endpoint. Supabase will
    /// hand off to Google/GitHub/etc., then redirect to `cadence://auth/callback`.
    func signInWithProvider(_ provider: OAuthProvider) {
        guard let base = CloudConfig.shared.supabaseURL else {
            lastError = "Cadence Cloud is not configured."; return
        }
        let redirect = CloudConfig.shared.authRedirectURL
        var components = URLComponents(url: base.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: redirect),
        ]
        guard let url = components.url else { return }
        Log.app.info("Opening OAuth for \(provider.rawValue, privacy: .public)")
        NSWorkspace.shared.open(url)
    }

    /// Called when macOS opens `cadence://auth/callback…` (from the web bridge
    /// page or OAuth). Tokens may be in the URL fragment or as a `code` query param.
    func handleCallbackURL(_ url: URL) {
        // Never log the full callback — the URL fragment carries the access token.
        Log.app.info("Auth callback received (scheme=\(url.scheme ?? "?", privacy: .public))")
        var tokens = parseAuthParameters(from: url)

        if let error = tokens["error_description"] ?? tokens["error"] {
            lastError = error
            Log.app.error("Auth callback error: \(error, privacy: .public)")
            return
        }

        if let access = tokens["access_token"], let refresh = tokens["refresh_token"] {
            applySessionTokens(access: access, refresh: refresh)
            return
        }

        if let code = tokens["code"] ?? tokens["auth_code"] {
            exchangeAuthorizationCode(code) { [weak self] ok in
                if !ok {
                    self?.lastError = self?.lastError ?? "Could not complete sign-in from the link."
                }
            }
            return
        }

        lastError = "Sign-in link did not include session tokens. Try sending a new link."
        Log.app.error("Auth callback missing tokens and code")
    }

    private func applySessionTokens(access: String, refresh: String) {
        SecretStore.shared.setSupabaseSession(accessToken: access, refreshToken: refresh)
        UserPreferences.shared.cloudIsAnonymous = false
        isAnonymous = false
        isSignedIn = true
        lastError = nil
        scheduleRefresh()
        fetchUser()
        fetchQuota()
        NSApp.activate(ignoringOtherApps: true)
        Log.app.info("Cadence Cloud session active (callback)")
        NotificationCenter.default.post(name: .cadenceAuthCompleted, object: nil)
    }

    /// Supabase PKCE / magic-link redirect sometimes returns `?code=` instead of hash tokens.
    private func exchangeAuthorizationCode(_ code: String, completion: @escaping (Bool) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(false); return
        }
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.url = req.url?.appending(queryItems: [URLQueryItem(name: "grant_type", value: "pkce")])
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["auth_code": code])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    self?.applyAuthResponse(data: data, response: response, source: .email) { ok in
                        if ok {
                            NSApp.activate(ignoringOtherApps: true)
                            NotificationCenter.default.post(name: .cadenceAuthCompleted, object: nil)
                        }
                        completion(ok)
                    }
                    return
                }
                // Fallback: authorization_code grant (older Supabase projects).
                self?.exchangeAuthorizationCodeLegacy(code, completion: completion)
            }
        }.resume()
    }

    private func exchangeAuthorizationCodeLegacy(_ code: String, completion: @escaping (Bool) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else {
            completion(false); return
        }
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.url = req.url?.appending(queryItems: [URLQueryItem(name: "grant_type", value: "authorization_code")])
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["auth_code": code])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                self?.applyAuthResponse(data: data, response: response, source: .email) { ok in
                    if ok {
                        NSApp.activate(ignoringOtherApps: true)
                        NotificationCenter.default.post(name: .cadenceAuthCompleted, object: nil)
                    }
                    completion(ok)
                }
            }
        }.resume()
    }

    private func parseAuthParameters(from url: URL) -> [String: String] {
        var tokens: [String: String] = [:]
        let raw = url.absoluteString
        if let fragmentStart = raw.firstIndex(of: "#") {
            let fragment = raw[raw.index(after: fragmentStart)...]
            tokens.merge(parseURLEncoded(String(fragment))) { _, new in new }
        }
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = comps.queryItems {
            for item in queryItems {
                if let v = item.value { tokens[item.name] = v }
            }
        }
        return tokens
    }

    // MARK: - Sign out

    func signOut() {
        SecretStore.shared.clearSupabaseSession()
        UserPreferences.shared.cloudUserId = ""
        UserPreferences.shared.cloudUserEmail = ""
        UserPreferences.shared.cloudIsAnonymous = false
        isSignedIn = false
        isAnonymous = false
        userId = nil
        userEmail = nil
        plan = "free"
        // These were left untouched, so the Account pane kept rendering the
        // previous user's "N min left" bar after signing out.
        quotaUsedSeconds = 0
        quotaLimitSeconds = 0
        pendingOTPEmail = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        // Drop any in-flight coalesced work so it can't resurrect the session.
        cloudBootstrapInFlight = false
        pendingCloudBootstrap.removeAll()
        refreshInFlight = false
        pendingRefreshWaiters.removeAll()
        Log.app.info("Signed out of Cadence Cloud")
    }

    // MARK: - Token refresh + quota

    /// Decodes a JWT's `exp` claim → expiry Date (nil if unparseable).
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// True if there is no token, or it expires within the next 5 minutes.
    var accessTokenNeedsRefresh: Bool {
        guard let token = accessToken, !token.isEmpty else { return true }
        guard let exp = Self.jwtExpiry(token) else { return true }
        return Date().addingTimeInterval(300) >= exp
    }

    /// Guarantees a fresh access token before running cloud work: refreshes
    /// first if the current one is expired/near-expiry, then hands back the
    /// (possibly new) token. This is what fixes "signed in but everything 401s
    /// after an hour" — including the plan showing Free and cloud transcription
    /// failing. Completion runs on an arbitrary queue.
    func withFreshToken(_ completion: @escaping (String?) -> Void) {
        if !accessTokenNeedsRefresh {
            completion(accessToken); return
        }
        // This used to ignore the Bool and hand back `accessToken` regardless —
        // i.e. the SAME expired token it had just failed to refresh. Callers
        // then sent a dead JWT and got a 401 they couldn't distinguish from any
        // other failure. Nil means "no usable token", and callers treat it so.
        refreshSessionIfNeeded { [weak self] ok in
            completion(ok ? self?.accessToken : nil)
        }
    }

    func refreshSessionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let refresh = SecretStore.shared.supabaseRefreshToken
        guard !refresh.isEmpty, let base = CloudConfig.shared.supabaseURL else {
            completion?(false); return
        }

        // Coalesce concurrent refreshes, the same way `ensureCloudSessionReady`
        // already does for anonymous bootstrap. Supabase GoTrue ROTATES refresh
        // tokens, so two simultaneous POSTs with the same token meant the second
        // came back "Invalid Refresh Token: Already Used" — and reuse-detection
        // can revoke the whole token family, silently signing the user out with
        // no UI to recover. Opening Settings → Account during a dictation was
        // enough to trigger it.
        if let completion { pendingRefreshWaiters.append(completion) }
        guard !refreshInFlight else { return }
        refreshInFlight = true
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.url = req.url?.appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refresh])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyAuthResponse(data: data, response: response, source: .refresh) { ok in
                    self.refreshInFlight = false
                    let waiters = self.pendingRefreshWaiters
                    self.pendingRefreshWaiters.removeAll()

                    // A refresh token that won't refresh is dead — it's been
                    // rotated, reused, revoked, or simply aged out. Previously
                    // `isSignedIn` stayed true and the 40-minute timer just kept
                    // retrying the same dead token forever, so the UI claimed
                    // "Signed in" while every cloud call 401'd. Surface it.
                    if !ok, let status = (response as? HTTPURLResponse)?.statusCode,
                       status == 400 || status == 401 {
                        Log.app.warning("Refresh token rejected (\(status, privacy: .public)) — signing out")
                        self.signOut()
                    }

                    waiters.forEach { $0(ok) }
                }
            }
        }.resume()
    }

    func fetchQuota() {
        guard let url = CloudConfig.shared.quotaURL else { return }
        withFreshToken { [weak self] token in
            guard let token, !token.isEmpty else { return }
            self?.performQuotaFetch(url: url, token: token)
        }
    }

    private func performQuotaFetch(url: URL, token: String) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plan = obj["plan"] as? String else { return }
            let used = (obj["used_seconds"] as? Double) ?? 0
            let limit = (obj["limit_seconds"] as? Double) ?? 0
            DispatchQueue.main.async {
                self?.plan = plan
                self?.quotaUsedSeconds = used
                self?.quotaLimitSeconds = limit
            }
        }.resume()
    }

    private func fetchUser() {
        guard let base = CloudConfig.shared.supabaseURL, let token = accessToken else { return }
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/user"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                self?.userId = obj["id"] as? String
                self?.userEmail = obj["email"] as? String
                let isAnon = (obj["is_anonymous"] as? Bool) ?? ((obj["email"] as? String)?.isEmpty ?? true)
                self?.isAnonymous = isAnon
                UserPreferences.shared.cloudUserId = (obj["id"] as? String) ?? ""
                UserPreferences.shared.cloudUserEmail = (obj["email"] as? String) ?? ""
                UserPreferences.shared.cloudIsAnonymous = isAnon
            }
        }.resume()
    }

    // MARK: - Private

    private enum AuthSource {
        case anonymous, email, apple, oauth, refresh
    }

    private func applyAuthResponse(data: Data?, response: URLResponse?, source: AuthSource, completion: @escaping (Bool) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastError = "Auth failed (HTTP \(status))"
            completion(false); return
        }
        if let err = json["error_description"] as? String ?? json["msg"] as? String {
            lastError = err
            completion(false); return
        }
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            lastError = "Missing tokens in auth response"
            completion(false); return
        }

        SecretStore.shared.setSupabaseSession(accessToken: access, refreshToken: refresh)

        var anonGuess = (source == .anonymous)
        if let user = json["user"] as? [String: Any] {
            userId = user["id"] as? String
            userEmail = user["email"] as? String
            if let isAnon = user["is_anonymous"] as? Bool { anonGuess = isAnon }
            else if (user["email"] as? String)?.isEmpty == false { anonGuess = false }
            UserPreferences.shared.cloudUserId = userId ?? ""
            UserPreferences.shared.cloudUserEmail = userEmail ?? ""
        }
        UserPreferences.shared.cloudIsAnonymous = anonGuess
        isAnonymous = anonGuess

        isSignedIn = true
        lastError = nil
        scheduleRefresh()
        fetchQuota()
        Log.app.info("Cadence Cloud session active (source=\(String(describing: source), privacy: .public))")
        completion(true)
    }

    private func exchangeAppleToken(idToken: String, completion: @escaping (Bool) -> Void) {
        guard let base = CloudConfig.shared.supabaseURL else { completion(false); return }
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.url = req.url?.appending(queryItems: [URLQueryItem(name: "grant_type", value: "id_token")])
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": idToken
        ])
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                self?.applyAuthResponse(data: data, response: response, source: .apple, completion: completion)
            }
        }.resume()
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 40 * 60, repeats: true) { [weak self] _ in
            self?.refreshSessionIfNeeded()
        }
    }

    private func parseURLEncoded(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let key = kv[0].removingPercentEncoding ?? kv[0]
            let val = kv[1].removingPercentEncoding ?? kv[1]
            out[key] = val
        }
        return out
    }
}

enum AuthError: LocalizedError {
    case notConfigured
    case invalidEmail
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cadence Cloud isn’t configured."
        case .invalidEmail:  return "Enter a valid email address."
        case .message(let m): return m
        }
    }
}

extension Notification.Name {
    static let cadenceAuthCompleted = Notification.Name("cadenceAuthCompleted")
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            lastError = "Apple Sign In returned no identity token"
            return
        }
        exchangeAppleToken(idToken: idToken) { [weak self] ok in
            if !ok { self?.lastError = self?.lastError ?? "Apple Sign In failed" }
            if ok { NotificationCenter.default.post(name: .cadenceAuthCompleted, object: nil) }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        lastError = error.localizedDescription
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
