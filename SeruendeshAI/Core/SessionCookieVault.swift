import Foundation
#if canImport(Security)
import Security
#endif

/// Stores only the opaque session cookie. Passwords and public profile data never enter this vault.
protocol SessionCookieVault: Sendable {
    func load(for baseURL: URL) -> Data?
    func store(_ data: Data?, for baseURL: URL)
}

struct KeychainSessionCookieVault: SessionCookieVault {
    private func account(_ url: URL) -> String {
        "\(url.scheme?.lowercased() ?? "https")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme == "http" ? 80 : 443))"
    }

    func load(for baseURL: URL) -> Data? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "kz.seruendesh.session",
            kSecAttrAccount as String: account(baseURL),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
        #else
        return nil
        #endif
    }

    func store(_ data: Data?, for baseURL: URL) {
        #if canImport(Security)
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "kz.seruendesh.session", kSecAttrAccount as String: account(baseURL)]
        guard let data else { SecItemDelete(key as CFDictionary); return }
        let update: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(key as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            SecItemAdd(key.merging(update) { _, new in new } as CFDictionary, nil)
        }
        #endif
    }
}

private struct StoredSessionCookie: Codable {
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date
    let secure: Bool
}

extension BackendAPI {
    func restoreSessionCookie() {
        guard let data = sessionVault?.load(for: baseURL) else { return }
        guard let stored = try? JSONDecoder().decode(StoredSessionCookie.self, from: data),
              stored.expiresAt > Date(), stored.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == baseURL.host?.lowercased(),
              stored.path == "/", !stored.value.isEmpty,
              !stored.secure || baseURL.scheme == "https",
              let cookie = HTTPCookie(properties: [.name:"seru_session", .value:stored.value, .domain:stored.domain,
                  .path:stored.path, .expires:stored.expiresAt, .secure:stored.secure ? "TRUE" : "FALSE", HTTPCookiePropertyKey("HttpOnly"):"TRUE"]) else {
            clearSessionCookie(); return
        }
        session.configuration.httpCookieStorage?.setCookie(cookie)
    }

    func receiveSessionCookie(_ response: HTTPURLResponse) {
        guard let url = response.url, url.host?.lowercased() == baseURL.host?.lowercased() else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        // Explicit parsing also supports ephemeral sessions and test URLProtocol transports.
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) where cookie.name == "seru_session" {
            if cookie.value.isEmpty || (cookie.expiresDate ?? .distantPast) <= Date() { clearSessionCookie(); continue }
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard domain == baseURL.host?.lowercased(), cookie.path == "/", !cookie.isSecure || baseURL.scheme == "https" else { continue }
            session.configuration.httpCookieStorage?.setCookie(cookie)
            let stored = StoredSessionCookie(value: cookie.value, domain: cookie.domain, path: cookie.path,
                expiresAt: cookie.expiresDate!, secure: cookie.isSecure)
            sessionVault?.store(try? JSONEncoder().encode(stored), for: baseURL)
        }
    }

    func clearSessionCookie() {
        if let storage = session.configuration.httpCookieStorage {
            for cookie in storage.cookies(for: baseURL) ?? [] where cookie.name == "seru_session" { storage.deleteCookie(cookie) }
        }
        sessionVault?.store(nil, for: baseURL)
    }

    /// A delayed guest/401 reply only invalidates the session used by that request.
    func clearSessionCookie(ifMatching sentValue: String?) {
        let currentValue = session.configuration.httpCookieStorage?.cookies(for: baseURL)?.first { $0.name == "seru_session" }?.value
        guard currentValue == sentValue else { return }
        clearSessionCookie()
    }
}
