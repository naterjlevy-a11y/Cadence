import Foundation
import Security

/// Resolves API keys (currently the Groq Whisper key) from one of four
/// sources, in priority order:
///
///   1. Environment variable      — `GROQ_API_KEY` in the process env
///   2. `.env` file               — `~/.config/mellotron/.env`
///   3. macOS Keychain            — `com.mellotron.Mellotron` / `groq`
///   4. UserDefaults              — legacy `groqApiKey` pref (back-compat)
///
/// The Settings UI lets the user pick where new keys are written; reads
/// always walk the priority chain so a `.env` or env var overrides anything
/// stored in prefs.
final class SecretStore {
    static let shared = SecretStore()

    private let keychainService = "com.mellotron.Mellotron"
    private let groqAccount = "groq"
    private let supabaseAccessAccount = "supabase_access"
    private let supabaseRefreshAccount = "supabase_refresh"
    private let envVarName = "GROQ_API_KEY"

    enum Source: String {
        case envVar       = "Environment variable ($GROQ_API_KEY)"
        case dotEnv       = "~/.config/mellotron/.env"
        case keychain     = "macOS Keychain"
        case userDefaults = "App preferences"
        case none         = "Not set"
    }

    enum Storage: String, CaseIterable, Identifiable {
        case keychain      // recommended
        case dotEnv        // ~/.config/mellotron/.env
        case userDefaults  // plaintext in ~/Library/Preferences

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .keychain:     return "macOS Keychain (recommended)"
            case .dotEnv:       return ".env file (~/.config/mellotron/.env)"
            case .userDefaults: return "App preferences (plaintext)"
            }
        }
    }

    // MARK: - Cached .env

    private var dotEnvCache: [String: String]?
    private var dotEnvCacheStamp: Date?

    /// The Groq API key, resolved from the highest-priority source.
    var groqApiKey: String {
        groqApiKeyAndSource().key
    }

    /// Returns both the resolved key and where it came from. Used by the
    /// Settings UI to display "Loaded from …" status.
    func groqApiKeyAndSource() -> (key: String, source: Source) {
        if let env = ProcessInfo.processInfo.environment[envVarName],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (env.trimmingCharacters(in: .whitespacesAndNewlines), .envVar)
        }
        if let fromDotEnv = readFromDotEnv(envVarName),
           !fromDotEnv.isEmpty {
            return (fromDotEnv, .dotEnv)
        }
        if let kc = readKeychain(account: groqAccount),
           !kc.isEmpty {
            return (kc, .keychain)
        }
        let legacy = UserPreferences.shared.groqApiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            return (legacy, .userDefaults)
        }
        return ("", .none)
    }

    /// Write a new Groq key into the selected storage. Removes the key
    /// from the OTHER persisted stores (keychain + userDefaults) so we
    /// don't accumulate stale copies in lower-priority locations.
    ///
    /// Note: we never touch the `.env` file unless the user explicitly
    /// picked `.dotEnv` — that file is a user-owned artifact and we
    /// should not surprise-edit it.
    @discardableResult
    func setGroqApiKey(_ key: String, storage: Storage) -> Result<Void, Error> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        switch storage {
        case .keychain:
            do {
                try writeKeychain(trimmed, account: groqAccount)
                UserPreferences.shared.groqApiKey = ""
            } catch {
                return .failure(error)
            }

        case .dotEnv:
            do {
                try writeToDotEnv(envVarName, value: trimmed)
                deleteKeychain(account: groqAccount)
                UserPreferences.shared.groqApiKey = ""
            } catch {
                return .failure(error)
            }

        case .userDefaults:
            UserPreferences.shared.groqApiKey = trimmed
            deleteKeychain(account: groqAccount)
        }

        Log.transcription.info("Groq key updated -> \(storage.rawValue, privacy: .public)")
        return .success(())
    }

    /// Wipe the key from every store. Used by the Settings "Forget key" button.
    func clearGroqApiKey() {
        UserPreferences.shared.groqApiKey = ""
        deleteKeychain(account: groqAccount)
        Log.transcription.info("Groq key cleared from app stores")
    }

    // MARK: - Supabase session (Mellotron Cloud)
    //
    // Stored in a 0600 file under Application Support — NOT the Keychain.
    // Reading Keychain items on every launch re-triggers the macOS
    // "Mellotron wants to use your confidential information" prompt whenever
    // the app's code signature isn't stable (ad-hoc / per-build signing).
    // These are low-risk, refreshable session tokens, so a user-only file is
    // an acceptable and prompt-free home for them.

    private var sessionCache: [String: String]?

    private var sessionFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mellotron/session.json")
    }

    private func loadSession() -> [String: String] {
        if let cache = sessionCache { return cache }
        guard let data = try? Data(contentsOf: sessionFileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            sessionCache = [:]
            return [:]
        }
        sessionCache = obj
        return obj
    }

    private func saveSession(_ dict: [String: String]) {
        sessionCache = dict
        let url = sessionFileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    var supabaseAccessToken: String {
        loadSession()["access"] ?? ""
    }

    var supabaseRefreshToken: String {
        loadSession()["refresh"] ?? ""
    }

    func setSupabaseSession(accessToken: String, refreshToken: String) {
        saveSession(["access": accessToken, "refresh": refreshToken])
    }

    func clearSupabaseSession() {
        sessionCache = [:]
        try? FileManager.default.removeItem(at: sessionFileURL)
        // Also clear any tokens left in the Keychain by older builds.
        deleteKeychain(account: supabaseAccessAccount)
        deleteKeychain(account: supabaseRefreshAccount)
    }

    /// Force a re-read of the .env on next access (call after editing).
    func invalidateDotEnvCache() {
        dotEnvCache = nil
        dotEnvCacheStamp = nil
    }

    /// Path the app reads/writes for .env-style secrets.
    var dotEnvPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/mellotron/.env")
    }

    var dotEnvExists: Bool {
        FileManager.default.fileExists(atPath: dotEnvPath.path)
    }

    // MARK: - .env (read / write / parse)

    /// Minimal `.env` parser: `KEY=value` per line, `#` comments, optional
    /// quotes. We deliberately do not support multi-line values or escapes
    /// because we own the writer and only emit single-line ASCII keys.
    private func readFromDotEnv(_ key: String) -> String? {
        if let cache = dotEnvCache,
           let stamp = dotEnvCacheStamp,
           Date().timeIntervalSince(stamp) < 5.0 {
            return cache[key]
        }
        let url = dotEnvPath
        guard FileManager.default.fileExists(atPath: url.path),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            dotEnvCache = [:]
            dotEnvCacheStamp = Date()
            return nil
        }
        var out: [String: String] = [:]
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = line[..<eq].trimmingCharacters(in: .whitespaces)
            var v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if (v.hasPrefix("\"") && v.hasSuffix("\"")) ||
               (v.hasPrefix("'")  && v.hasSuffix("'")) {
                v = String(v.dropFirst().dropLast())
            }
            out[k] = v
        }
        dotEnvCache = out
        dotEnvCacheStamp = Date()
        return out[key]
    }

    private func writeToDotEnv(_ key: String, value: String) throws {
        let url = dotEnvPath
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])

        var lines: [String] = []
        if FileManager.default.fileExists(atPath: url.path),
           let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
        } else {
            lines = [
                "# Mellotron secrets — owned by you. Format: KEY=value, one per line.",
                "# This file is preferred over the macOS Keychain when both are set.",
                ""
            ]
        }

        var replaced = false
        let newLine = value.isEmpty ? "" : "\(key)=\(value)"
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key)=") {
                lines[i] = newLine
                replaced = true
                break
            }
        }
        if !replaced && !value.isEmpty {
            if let last = lines.last, !last.isEmpty {
                lines.append("")
            }
            lines.append(newLine)
        }

        let body = lines
            .filter { !($0.isEmpty && $0 == lines.last) }
            .joined(separator: "\n") + "\n"

        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        invalidateDotEnvCache()
    }

    // MARK: - Keychain

    private func keychainQuery(account: String, extras: [String: Any] = [:]) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        for (k, v) in extras { q[k] = v }
        return q
    }

    private func readKeychain(account: String) -> String? {
        let query = keychainQuery(account: account, extras: [
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeKeychain(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw NSError(domain: "SecretStore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid key encoding."])
        }
        if value.isEmpty {
            deleteKeychain(account: account)
            return
        }
        let query = keychainQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus),
                              userInfo: [NSLocalizedDescriptionKey: "Keychain write failed (status \(addStatus))."])
            }
        } else if updateStatus != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain update failed (status \(updateStatus))."])
        }
    }

    private func deleteKeychain(account: String) {
        SecItemDelete(keychainQuery(account: account) as CFDictionary)
    }
}
