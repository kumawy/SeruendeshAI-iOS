import Foundation

enum PasswordResetLink {
    static func token(from url: URL) -> String? {
        let web = url.scheme?.lowercased() == "https" && url.host?.lowercased() == "seruendesh.site" && url.path == "/reset-password"
        let native = url.scheme?.lowercased() == "seruendesh" && url.host == "reset-password" && (url.path.isEmpty || url.path == "/")
        guard web || native, url.user == nil, url.password == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let tokens = (parts.queryItems ?? []).filter { $0.name == "token" }
        guard tokens.count == 1, let token = tokens.first?.value,
              (20...200).contains(token.count),
              !token.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return nil }
        return token
    }
}
