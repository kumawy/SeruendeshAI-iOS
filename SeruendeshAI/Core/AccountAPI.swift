import Foundation

protocol SeruAccountBackend: Sendable {
    func currentUser() async throws -> AccountUser?
    func register(name: String, email: String, password: String) async throws -> AccountUser
    func signIn(email: String, password: String) async throws -> AccountUser
    func signOut() async throws
    func deleteAccount() async throws
    func requestPasswordReset(email: String) async throws
    func confirmPasswordReset(token: String, password: String) async throws -> AccountUser
    func savedPlaces() async throws -> [APISavedPlace]
    func savePlace(id: String, snapshot: SavedPlaceSnapshot) async throws -> APISavedPlace
    func removeSavedPlace(id: String) async throws
}

struct AccountUser: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let email: String
    let name: String
    let lang: String
    let createdAt: Date
    init(id: String, email: String, name: String, lang: String = "ru", createdAt: Date = Date()) {
        self.id = id; self.email = email; self.name = name; self.lang = lang; self.createdAt = createdAt
    }
    enum CodingKeys: String, CodingKey { case id, email, name, lang; case createdAt = "created_at" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); email = try c.decode(String.self, forKey: .email)
        name = try c.decode(String.self, forKey: .name); lang = try c.decode(String.self, forKey: .lang)
        createdAt = try accountDate(c.decode(String.self, forKey: .createdAt), decoder: decoder)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(email, forKey: .email); try c.encode(name, forKey: .name); try c.encode(lang, forKey: .lang)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
    }
}

struct APISavedPlace: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let snapshot: SavedPlaceSnapshot
    let createdAt: Date
    init(id: String, snapshot: SavedPlaceSnapshot, createdAt: Date = Date()) { self.id = id; self.snapshot = snapshot; self.createdAt = createdAt }
    enum CodingKeys: String, CodingKey { case id = "poi_id", snapshot = "data", createdAt = "created_at" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        snapshot = try c.decodeIfPresent(SavedPlaceSnapshot.self, forKey: .snapshot) ?? SavedPlaceSnapshot()
        createdAt = try accountDate(c.decode(String.self, forKey: .createdAt), decoder: decoder)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(snapshot, forKey: .snapshot)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
    }
}

/// Same camelCase JSON fields as the web app and backend SavedSnapshot allowlist.
struct SavedPlaceSnapshot: Codable, Hashable, Sendable {
    var name: String?, category: String?, categoryKey: String?, iconKey: String?
    var photo: SavedPlacePhoto?
    var description: String?, descriptionUrl: String?, website: String?, phone: String?, instagram: String?
    var cuisine: [String]?, openStatus: String?, openingKind: String?, openingRaw: String?, cover: String?
    var lat: Double?, lon: Double?, address: String?, why: String?, action: String?, url: String?, image: String?, status: String?, distance: String?
    var travel: Int?, visit: Int?, visitRange: [Int]?, mode: String?, features: [String]?, badges: [String]?, source: String?, generated: Bool?
    var dataSources: [String]?, descriptionSource: String?, openConfidence: String?, accessibility: String?

    init() {}
    init(place: Place) {
        name = clipped(place.name, 300); category = clipped(place.category, 300)
        let icon = Self.webIcon(place.symbol)
        categoryKey = icon.category; iconKey = icon.icon
        if let coordinate = place.coordinate, coordinate.isValid { lat = coordinate.latitude; lon = coordinate.longitude }
        address = clipped(place.address ?? place.subtitle, 1000)
        phone = clipped(place.phone, 300)
        accessibility = clipped(place.accessibility, 300)
        why = clipped(place.reason, 2000)
        status = place.hours == "Часы уточняй" ? nil : clipped(place.hours, 300)
        distance = clipped(place.distance, 300)
        travel = min(10080, max(0, place.travelMinutes)); visit = min(10080, max(0, place.visitMinutes))
        badges = (place.isFree ? ["free"] : []) + (place.isChildFriendly ? ["kids"] : [])
        if let value = snapshotURL(place.imageURL?.absoluteString) {
            let credit = place.imageCredit ?? ""
            let pieces = credit.components(separatedBy: " · ")
            photo = SavedPlacePhoto(url: value.absoluteString, page: snapshotURL(place.imageSourceURL?.absoluteString)?.absoluteString,
                author: clipped(pieces.count > 1 ? pieces.dropLast().joined(separator: " · ") : credit, 300) ?? "",
                license: clipped(pieces.count > 1 ? pieces.last : nil, 300) ?? "")
            image = value.absoluteString
        }
        url = snapshotURL(place.sourceURL?.absoluteString)?.absoluteString
        descriptionUrl = url
        website = snapshotURL(place.websiteURL?.absoluteString)?.absoluteString
        descriptionSource = clipped(place.descriptionCredit, 300)
    }

    func place(id: String) -> Place {
        let point: GeoPoint? = if let lat, let lon { GeoPoint(latitude: lat, longitude: lon) } else { nil }
        let parts = [why, action, description].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var unique: [String] = []; for text in parts where !unique.contains(text) { unique.append(text) }
        var result = Place(id: id, name: name?.isEmpty == false ? name! : "Сохранённое место", category: category ?? "Место",
            subtitle: address ?? category ?? "", imageAsset: "", travelMinutes: max(0, travel ?? 0), visitMinutes: max(0, visit ?? visitRange?.first ?? 0),
            distance: distance ?? "", hours: status?.isEmpty == false ? status! : "Часы уточняй", rating: "", reason: unique.joined(separator: "\n\n"),
            symbol: Self.nativeIcon(iconKey ?? categoryKey ?? ""), isFree: badges?.contains("free") == true, isChildFriendly: badges?.contains("kids") == true)
        result.isLive = true; result.coordinate = point?.isValid == true ? point : nil
        result.imageURL = snapshotURL(photo?.url) ?? snapshotURL(image, allowRelative: true)
        result.imageSourceURL = snapshotURL(photo?.page)
        if result.imageURL != nil, let photo { result.imageCredit = [photo.author, photo.license].filter { !$0.isEmpty }.joined(separator: " · ") }
        result.sourceURL = snapshotURL(descriptionUrl) ?? snapshotURL(url)
        result.websiteURL = snapshotURL(website); result.descriptionCredit = descriptionSource
        result.address = address; result.phone = phone; result.accessibility = accessibility
        return result
    }

    private static func webIcon(_ symbol: String) -> (category: String, icon: String) {
        switch symbol {
        case "tree.fill": ("park", "trees")
        case "cup.and.saucer.fill": ("cafe", "coffee")
        case "building.columns.fill": ("landmark", "landmark")
        case "figure.and.child.holdinghands": ("playground", "baby")
        case "ticket.fill": ("theatre", "ticket")
        case "music.note": ("event_venue", "music")
        case "fork.knife": ("restaurant", "utensils")
        case "bag.fill": ("mall", "shopping")
        case "water.waves": ("viewpoint", "waves")
        case "books.vertical.fill": ("library", "book")
        case "laptopcomputer": ("coworking", "laptop")
        case "figure.walk": ("active", "activity")
        default: ("landmark", "landmark")
        }
    }
    private static func nativeIcon(_ key: String) -> String {
        switch key {
        case "trees", "flower", "park", "garden": "tree.fill"
        case "coffee", "cake", "cafe", "sweets": "cup.and.saucer.fill"
        case "baby", "playground", "kids_indoor": "figure.and.child.holdinghands"
        case "ticket", "theatre", "cinema": "ticket.fill"
        case "music", "mic", "event_venue": "music.note"
        case "utensils", "burger", "restaurant", "fast_food": "fork.knife"
        case "shopping", "store", "gift", "mall": "bag.fill"
        case "waves", "fish", "water_park": "water.waves"
        case "book", "library": "books.vertical.fill"
        case "laptop", "coworking": "laptopcomputer"
        case "activity", "active": "figure.walk"
        case "museum", "landmark", "monument", "gallery": "building.columns.fill"
        default: "mappin.circle.fill"
        }
    }
}

struct SavedPlacePhoto: Codable, Hashable, Sendable {
    var url: String
    var page: String?
    var author: String
    var license: String
    var source: String
    var width: Int?
    var height: Int?
    init(url: String, page: String? = nil, author: String = "", license: String = "", source: String = "Wikimedia Commons", width: Int? = nil, height: Int? = nil) {
        self.url = url; self.page = page; self.author = author; self.license = license; self.source = source; self.width = width; self.height = height
    }
    enum CodingKeys: String, CodingKey { case url, page, author, license, source, width, height }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url); page = try c.decodeIfPresent(String.self, forKey: .page)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""; license = try c.decodeIfPresent(String.self, forKey: .license) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "Wikimedia Commons"
        width = try c.decodeIfPresent(Int.self, forKey: .width); height = try c.decodeIfPresent(Int.self, forKey: .height)
    }
}

extension BackendAPI: SeruAccountBackend {
    func currentUser() async throws -> AccountUser? {
        let data = try await accountData("api/auth/me")
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["user"] is NSNull {
            return nil
        }
        return try accountDecode(AccountUser.self, from: data)
    }
    func register(name: String, email: String, password: String) async throws -> AccountUser {
        try accountDecode(AccountUser.self, from: await accountData("api/auth/register", method: "POST", body: JSONEncoder().encode(RegisterBody(name: name, email: email, password: password))))
    }
    func signIn(email: String, password: String) async throws -> AccountUser {
        try accountDecode(AccountUser.self, from: await accountData("api/auth/login", method: "POST", body: JSONEncoder().encode(LoginBody(email: email, password: password))))
    }
    func signOut() async throws { _ = try await accountData("api/auth/logout", method: "POST"); clearSessionCookie() }
    func deleteAccount() async throws { _ = try await accountData("api/me", method: "DELETE"); clearSessionCookie() }
    func requestPasswordReset(email: String) async throws {
        _ = try await accountData("api/auth/password-reset/request", method: "POST", body: JSONEncoder().encode(ResetRequestBody(email: email)))
    }
    func confirmPasswordReset(token: String, password: String) async throws -> AccountUser {
        try accountDecode(AccountUser.self, from: await accountData("api/auth/password-reset/confirm", method: "POST", body: JSONEncoder().encode(ResetConfirmBody(token: token, password: password))))
    }
    func savedPlaces() async throws -> [APISavedPlace] { try accountDecode([APISavedPlace].self, from: await accountData("api/me/saved")) }
    func savePlace(id: String, snapshot: SavedPlaceSnapshot) async throws -> APISavedPlace {
        try accountDecode(APISavedPlace.self, from: await accountData("api/me/saved", id: id, method: "PUT", body: JSONEncoder().encode(SavedBody(data: snapshot))))
    }
    func removeSavedPlace(id: String) async throws { _ = try await accountData("api/me/saved", id: id, method: "DELETE") }

    private struct RegisterBody: Encodable { let name: String; let email: String; let password: String; let lang = "ru" }
    private struct LoginBody: Encodable { let email: String; let password: String }
    private struct ResetRequestBody: Encodable { let email: String }
    private struct ResetConfirmBody: Encodable { let token: String; let password: String }
    private struct SavedBody: Encodable { let data: SavedPlaceSnapshot }

    private func accountDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.invalidResponse }
    }
    private func accountData(_ path: String, id: String? = nil, method: String = "GET", body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard ["https", "http"].contains(baseURL.scheme?.lowercased() ?? ""), baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil,
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        if let id {
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            guard let escaped = id.addingPercentEncoding(withAllowedCharacters: unreserved) else { throw APIError.invalidResponse }
            components.percentEncodedPath += "/" + escaped
        }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let cookies = session.configuration.httpCookieStorage?.cookies(for: url) ?? []
        let sentSession = cookies.first { $0.name == "seru_session" }?.value
        if !cookies.isEmpty {
            for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(value, forHTTPHeaderField: name) }
        }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let detail = object?["detail"] as? String
                let code: String?
                if response.statusCode == 422 && path == "api/me/saved" {
                    code = detail == "too_many_saved" ? "too_many_saved" : "invalid_saved_snapshot"
                } else {
                    code = detail ?? (response.statusCode == 422 ? "account_validation" : nil)
                }
                if response.statusCode == 401 && ["not_authenticated", "session_expired"].contains(code ?? "") { clearSessionCookie(ifMatching: sentSession) }
                throw APIError.http(status: response.statusCode, code: code)
            }
            receiveSessionCookie(response)
            if path == "api/auth/me", let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], object["user"] is NSNull {
                clearSessionCookie(ifMatching: sentSession)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            throw APIError.network(error.code)
        }
    }
}

private func clipped(_ value: String?, _ limit: Int) -> String? { value.map { String($0.prefix(limit)) } }
private func snapshotURL(_ value: String?, allowRelative: Bool = false) -> URL? {
    guard let value, !value.isEmpty, value.count <= 2048, !value.contains("\\"),
          !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
          let url = (allowRelative && value.hasPrefix("/") && !value.hasPrefix("//") ? URL(string: value, relativeTo: BackendAPI.productionURL)?.absoluteURL : URL(string: value)),
          ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
    return url
}
private func accountDate(_ value: String, decoder: Decoder) throws -> Date {
    // SQLite returns naive UTC datetimes; Postgres includes an offset.
    let normalized = value.contains("+") || value.hasSuffix("Z") || value.dropFirst(10).contains("-") ? value : value + "Z"
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: normalized) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: normalized) { return date }
    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid account creation date"))
}
