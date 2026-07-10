import Foundation
import Security
import CommonCrypto
import WebKit
import SQLite3

/// Reads encrypted session cookies from the user's local Chrome profile and
/// injects them into Cadence's WKWebView popup so sites open already signed in.
final class ChromeCookieImporter {
    static let shared = ChromeCookieImporter()

    enum ImportResult: Equatable {
        case disabled
        case success(count: Int)
        case failed(message: String)
    }

    private let queue = DispatchQueue(label: "com.natelevy.cadence.chrome-cookies", qos: .userInitiated)
    private var cache: [String: [HTTPCookie]] = [:]
    private var knownHosts: Set<String> = []
    private let lock = NSLock()

    private init() {}

    // MARK: - Public

    /// Import cookies for `host` (if enabled) and inject into `store`.
    /// Calls `completion` on the main queue.
    func importIfNeeded(
        for host: String?,
        into store: WKHTTPCookieStore,
        timeout: TimeInterval = 8,
        completion: @escaping (ImportResult) -> Void
    ) {
        guard let host, !host.isEmpty else {
            DispatchQueue.main.async { completion(.success(count: 0)) }
            return
        }

        let prefs = UserPreferences.shared
        guard prefs.importChromeCookies else {
            DispatchQueue.main.async { completion(.disabled) }
            return
        }

        let normalizedHost = host.lowercased()
        lock.lock()
        if let cached = cache[normalizedHost] {
            lock.unlock()
            inject(cookies: cached, into: store, completion: { count in
                DispatchQueue.main.async { completion(.success(count: count)) }
            })
            return
        }
        lock.unlock()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let result = self.loadCookies(forHost: normalizedHost)
            switch result {
            case .success(let cookies):
                self.lock.lock()
                self.cache[normalizedHost] = cookies
                self.knownHosts.insert(normalizedHost)
                self.lock.unlock()
                self.inject(cookies: cookies, into: store) { count in
                    DispatchQueue.main.async { completion(.success(count: count)) }
                }
            case .failure(let error):
                Log.cookies.warning("Chrome cookie import failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(.failed(message: error.localizedDescription)) }
            }
        }

        queue.async(execute: workItem)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !workItem.isCancelled {
                // Work still running — don't cancel import; completion will fire when done.
            }
        }
    }

    /// Clear cached cookies so the next popup re-reads Chrome.
    @discardableResult
    func refreshAll() -> String {
        lock.lock()
        cache.removeAll()
        let hosts = knownHosts
        lock.unlock()
        if hosts.isEmpty {
            return "Cache cleared. Open a popup to sync from Chrome."
        }
        return "Cache cleared (\(hosts.count) host\(hosts.count == 1 ? "" : "s")). Next popup will re-sync."
    }

    /// Profile folder names that contain a `Cookies` database.
    static func availableChromeProfiles() -> [String] {
        let chromeRoot = chromeSupportDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: chromeRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ["Default"] }

        var profiles: [String] = []
        for url in entries {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let cookies = url.appendingPathComponent("Cookies")
            if FileManager.default.fileExists(atPath: cookies.path) {
                profiles.append(url.lastPathComponent)
            }
        }
        if profiles.isEmpty { return ["Default"] }
        return profiles.sorted { lhs, rhs in
            if lhs == "Default" { return true }
            if rhs == "Default" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    // MARK: - Chrome paths

    private static func chromeSupportDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    private func cookiesDatabaseURL() -> URL {
        let profile = UserPreferences.shared.chromeCookieProfile
        return Self.chromeSupportDirectory()
            .appendingPathComponent(profile, isDirectory: true)
            .appendingPathComponent("Cookies", isDirectory: false)
    }

    // MARK: - Load & decrypt

    private enum LoaderError: LocalizedError {
        case chromeNotInstalled
        case keychainDenied
        case databaseOpenFailed
        case queryFailed

        var errorDescription: String? {
            switch self {
            case .chromeNotInstalled: return "Chrome cookie database not found."
            case .keychainDenied: return "Keychain access denied — allow Chrome Safe Storage."
            case .databaseOpenFailed: return "Could not open Chrome cookies database."
            case .queryFailed: return "Could not read cookies from Chrome."
            }
        }
    }

    private func loadCookies(forHost host: String) -> Result<[HTTPCookie], LoaderError> {
        let dbURL = cookiesDatabaseURL()
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return .failure(.chromeNotInstalled)
        }

        guard let encryptionKey = fetchChromeEncryptionKey() else {
            return .failure(.keychainDenied)
        }

        guard let rows = readCookieRows(from: dbURL, host: host) else {
            return .failure(.databaseOpenFailed)
        }

        var cookies: [HTTPCookie] = []
        cookies.reserveCapacity(rows.count)

        for row in rows {
            guard shouldImportCookie(row, forPageHost: host) else { continue }
            guard let value = decryptCookieValue(row.encryptedValue, key: encryptionKey) else { continue }
            guard isValidCookieValue(value), isValidCookieName(row.name) else { continue }
            guard let cookie = makeHTTPCookie(row: row, decryptedValue: value) else { continue }
            cookies.append(cookie)
        }

        Log.cookies.info("Imported \(cookies.count, privacy: .public) cookies for \(host, privacy: .public)")
        return .success(cookies)
    }

    private func fetchChromeEncryptionKey() -> [UInt8]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecAttrAccount as String: "Chrome",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return deriveAESKey(password: password)
    }

    private func deriveAESKey(password: String) -> [UInt8] {
        var derived = [UInt8](repeating: 0, count: 16)
        let passwordBytes = Array(password.utf8)
        let salt = Array("saltysalt".utf8)

        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, passwordBytes.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &derived,
            derived.count
        )
        return derived
    }

    /// Auth/session cookie names for Google properties. Importing analytics or
    /// UI-state cookies (AMP_, zero-chakra, etc.) can produce malformed requests.
    private static let googleAuthCookieNames: Set<String> = [
        "SID", "HSID", "SSID", "APISID", "SAPISID", "SIDCC", "LSID", "GAPS",
        "NID", "AEC", "OGPC", "OGP",
        "__Secure-1PSID", "__Secure-3PSID",
        "__Secure-1PAPISID", "__Secure-3PAPISID",
        "__Secure-1PSIDTS", "__Secure-3PSIDTS",
        "__Secure-1PSIDCC", "__Secure-3PSIDCC",
        "__Secure-ENID", "__Secure-STRP",
    ]

    private struct CookieRow {
        let name: String
        let hostKey: String
        let topFrameSiteKey: String
        let path: String
        let encryptedValue: Data
        let expiresUtc: Int64
        let hasExpires: Bool
        let isSecure: Bool
        let isHttpOnly: Bool
    }

    private func readCookieRows(from dbURL: URL, host: String) -> [CookieRow]? {
        let hostKeys = hostKeysToMatch(for: host)

        // Copy to temp so we can read while Chrome is running (WAL-safe).
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-chrome-cookies-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try FileManager.default.copyItem(at: dbURL, to: tempURL)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
                if FileManager.default.fileExists(atPath: sidecar.path) {
                    try? FileManager.default.copyItem(
                        at: sidecar,
                        to: URL(fileURLWithPath: tempURL.path + suffix)
                    )
                }
            }
        } catch {
            Log.cookies.warning("Cookie DB copy failed, trying read-only open: \(error.localizedDescription, privacy: .public)")
        }

        var db: OpaquePointer?
        let openPath = FileManager.default.fileExists(atPath: tempURL.path) ? tempURL.path : dbURL.path
        if sqlite3_open_v2(openPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        var rows: [CookieRow] = []
        let sql = """
            SELECT name, host_key, top_frame_site_key, path, encrypted_value,
                   expires_utc, has_expires, is_secure, is_httponly
            FROM cookies
            WHERE length(encrypted_value) > 0
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(stmt, 0),
                  let hostC = sqlite3_column_text(stmt, 1),
                  let pathC = sqlite3_column_text(stmt, 3) else { continue }

            let hostKey = String(cString: hostC)
            guard hostKeys.contains(hostKey.lowercased()) else { continue }

            let topFrame = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""

            let blobLen = sqlite3_column_bytes(stmt, 4)
            guard blobLen > 0,
                  let blob = sqlite3_column_blob(stmt, 4) else { continue }
            let encrypted = Data(bytes: blob, count: Int(blobLen))

            let expires = sqlite3_column_int64(stmt, 5)
            let hasExpires = sqlite3_column_int(stmt, 6) != 0
            let secure = sqlite3_column_int(stmt, 7) != 0
            let httpOnly = sqlite3_column_int(stmt, 8) != 0

            rows.append(CookieRow(
                name: String(cString: nameC),
                hostKey: hostKey,
                topFrameSiteKey: topFrame,
                path: String(cString: pathC),
                encryptedValue: encrypted,
                expiresUtc: expires,
                hasExpires: hasExpires,
                isSecure: secure,
                isHttpOnly: httpOnly
            ))
        }

        return rows
    }

    /// Host keys to read from Chrome — eTLD+1 and below only (never bare `com`).
    private func hostKeysToMatch(for host: String) -> Set<String> {
        var keys: Set<String> = [host, ".\(host)"]
        var parts = host.split(separator: ".")
        while parts.count > 2 {
            parts.removeFirst()
            let domain = parts.joined(separator: ".")
            keys.insert(domain)
            keys.insert(".\(domain)")
        }
        return keys
    }

    private func shouldImportCookie(_ row: CookieRow, forPageHost host: String) -> Bool {
        // __Host- cookies must not carry a Domain attribute; skip rather than mis-set.
        if row.name.hasPrefix("__Host-") { return false }

        // Partitioned / embedded-context cookies don't apply to a top-level WKWebView.
        if !row.topFrameSiteKey.isEmpty, row.topFrameSiteKey != row.hostKey {
            return false
        }

        if row.name.hasPrefix("__Secure-"), !row.isSecure { return false }

        if row.hasExpires, row.expiresUtc > 0 {
            let unixMicros = row.expiresUtc - 11_644_473_600_000_000
            let seconds = Double(unixMicros) / 1_000_000.0
            if seconds < Date().timeIntervalSince1970 { return false }
        }

        if isGoogleHost(host) {
            return Self.googleAuthCookieNames.contains(row.name)
                || row.name.hasPrefix("__Secure-1P")
                || row.name.hasPrefix("__Secure-3P")
        }
        return true
    }

    private func isGoogleHost(_ host: String) -> Bool {
        host == "google.com" || host.hasSuffix(".google.com")
            || host.hasSuffix(".google.ca") || host.hasSuffix(".youtube.com")
    }

    private func isValidCookieName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 256 else { return false }
        for scalar in name.unicodeScalars {
            if scalar.value < 0x21 || scalar.value > 0x7E { return false }
            if scalar == ";" || scalar == " " { return false }
        }
        return true
    }

    private func isValidCookieValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 4096 else { return false }
        if value.contains("\0") { return false }
        for scalar in value.unicodeScalars {
            if scalar == "\r" || scalar == "\n" || scalar == ";" { return false }
            if scalar.value < 0x20 && scalar != "\t" { return false }
        }
        return true
    }

    private func decryptCookieValue(_ encrypted: Data, key: [UInt8]) -> String? {
        guard encrypted.count > 3 else { return nil }
        let prefix = String(data: encrypted.prefix(3), encoding: .utf8)
        guard prefix == "v10" || prefix == "v11" else { return nil }

        let ciphertext = encrypted.suffix(from: 3)
        guard let plain = aes128CBCDecrypt(ciphertext: Data(ciphertext), key: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    private func aes128CBCDecrypt(ciphertext: Data, key: [UInt8]) -> Data? {
        let iv: [UInt8] = Array(repeating: 0x20, count: 16)
        var outLength = 0
        var out = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)

        let status = ciphertext.withUnsafeBytes { cipherBytes in
            CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                key, key.count,
                iv,
                cipherBytes.baseAddress, ciphertext.count,
                &out, out.count,
                &outLength
            )
        }

        guard status == kCCSuccess else { return nil }
        return Data(out.prefix(outLength))
    }

    private func makeHTTPCookie(row: CookieRow, decryptedValue: String) -> HTTPCookie? {
        let domain = row.hostKey.hasPrefix(".") ? row.hostKey : ".\(row.hostKey)"
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: row.name,
            .value: decryptedValue,
            .path: row.path.isEmpty ? "/" : row.path,
            .domain: domain,
        ]

        if row.isSecure {
            properties[.secure] = "TRUE"
        }

        if row.hasExpires, row.expiresUtc > 0 {
            let unixMicros = row.expiresUtc - 11_644_473_600_000_000
            let seconds = Double(unixMicros) / 1_000_000.0
            if seconds > 0 {
                properties[.expires] = Date(timeIntervalSince1970: seconds)
            }
        }

        return HTTPCookie(properties: properties)
    }

    // MARK: - Inject

    private func inject(
        cookies: [HTTPCookie],
        into store: WKHTTPCookieStore,
        completion: @escaping (Int) -> Void
    ) {
        guard !cookies.isEmpty else {
            DispatchQueue.main.async { completion(0) }
            return
        }

        let domains = Set(cookies.map { $0.domain.lowercased() })
        DispatchQueue.main.async {
            store.getAllCookies { existing in
                let group = DispatchGroup()
                for existingCookie in existing where domains.contains(existingCookie.domain.lowercased()) {
                    group.enter()
                    store.delete(existingCookie) { group.leave() }
                }
                group.notify(queue: .main) {
                    let setGroup = DispatchGroup()
                    for cookie in cookies {
                        setGroup.enter()
                        store.setCookie(cookie) { setGroup.leave() }
                    }
                    setGroup.notify(queue: .main) {
                        completion(cookies.count)
                    }
                }
            }
        }
    }
}
