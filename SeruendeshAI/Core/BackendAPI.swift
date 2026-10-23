import Foundation

/// Public application endpoints; provider credentials stay on the server.
protocol SeruBackend: Sendable {
    func metadata() async throws -> APIMetadata
    func recommend(_ request: APIRecommendRequest, photo: Data?) async throws -> APIRecommendationResponse
    func events(query: String?, price: String?, limit: Int, offset: Int) async throws -> APIEventPage
    func route(poiID: String, origin: APIOrigin) async throws -> APIRouteToPlace
    func routeIdeas(origin: APIOrigin) async throws -> [APIRouteIdea]
    func geocode(query: String) async throws -> [APIGeocodeResult]
}

enum APIOrigin: Hashable, Sendable {
    case landmark(String)
    case location(lat: Double, lon: Double, label: String?)

    fileprivate func encode<K: CodingKey>(into container: inout KeyedEncodingContainer<K>, location: K, landmark: K, label: K? = nil) throws {
        switch self {
        case .landmark(let value): try container.encode(String(value.prefix(80)), forKey: landmark)
        case .location(let lat, let lon, let name):
            guard lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { throw APIError.invalidLocation }
            try container.encode(APICoordinate(lat: (lat * 1000).rounded() / 1000, lon: (lon * 1000).rounded() / 1000), forKey: location)
            if let label, let name { try container.encode(String(name.prefix(120)), forKey: label) }
        }
    }
}

struct APIRecommendRequest: Encodable, Sendable {
    let query: String
    let origin: APIOrigin
    let duration: Int?
    let withKids: Bool
    let onlyFree: Bool
    let lang: String

    init(query: String, origin: APIOrigin, duration: Int? = nil, withKids: Bool, onlyFree: Bool, lang: String = "ru") {
        self.query = query; self.origin = origin; self.duration = duration
        self.withKids = withKids; self.onlyFree = onlyFree; self.lang = lang
    }

    fileprivate var effectiveQuery: String {
        let suffix = onlyFree ? ". Только бесплатные места" : ""
        return String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000 - suffix.count)) + suffix
    }

    enum CodingKeys: String, CodingKey { case query, lang, location, landmark, locationLabel = "location_label", duration = "time_budget_min", profile, refine }
    private struct Profile: Encodable { let with_kids: Bool; let tourist = false; let accessibility = false; let group_size = 1 }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(effectiveQuery, forKey: .query)
        try c.encode(lang, forKey: .lang)
        try origin.encode(into: &c, location: .location, landmark: .landmark, label: .locationLabel)
        if let duration { try c.encode(min(480, max(10, duration)), forKey: .duration) }
        try c.encode(Profile(with_kids: withKids), forKey: .profile)
        try c.encode([String](), forKey: .refine)
    }
}

enum APIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case invalidLocation
    case invalidPhoto
    case photoTooLarge
    case http(status: Int, code: String?)
    case network(URLError.Code)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Сервер прислал непонятный ответ. Попробуй ещё раз."
        case .invalidLocation: return "Не удалось определить начало прогулки. Выбери ориентир или адрес."
        case .invalidPhoto: return "Выбери фотографию в формате JPEG или PNG."
        case .photoTooLarge: return "Фото слишком большое. Выбери изображение до 8 МБ."
        case .network(let code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost: return "Нет соединения с интернетом. Проверь сеть и попробуй ещё раз."
            case .timedOut: return "Ответ занял слишком много времени. Попробуй ещё раз."
            default: return "Не удалось связаться с сервером. Попробуй ещё раз."
            }
        case .http(let status, let code):
            if status == 429 { return "Слишком много запросов. Подожди минуту и попробуй ещё раз." }
            switch code {
            case "invalid_credentials": return "Неверный email или пароль."
            case "email_taken": return "Этот email уже зарегистрирован. Попробуй войти."
            case "email_unavailable": return "Восстановление по почте сейчас недоступно. Попробуй позже."
            case "invalid_or_expired_token": return "Ссылка устарела или уже использована. Запроси новую."
            case "too_many_saved": return "В избранном уже 300 мест. Удали одно, чтобы добавить новое."
            case "invalid_saved_snapshot": return "Не удалось сохранить данные места. Обнови рекомендации и попробуй ещё раз."
            case "account_validation": return "Проверь имя, email и пароль. Пароль должен содержать от 8 до 128 символов."
            case "not_authenticated", "session_expired": return "Сессия закончилась. Войди в аккаунт ещё раз."
            case "route_unavailable": return "Не удалось построить маршрут по улицам. Попробуй другой ориентир."
            case "location_required": return "Выбери начало маршрута: ориентир или адрес."
            case "unknown_poi": return "Это место больше не доступно. Обнови рекомендации."
            case "photo_unavailable": return "Поиск по фото сейчас недоступен. Напиши, где ты находишься."
            case "photo_too_large": return APIError.photoTooLarge.errorDescription
            case "unsupported_media_type", "unsupported_format", "invalid_image", "image_required": return APIError.invalidPhoto.errorDescription
            default:
                if status >= 500 { return "Сервер временно недоступен. Попробуй чуть позже." }
                if status == 401 { return "Войди в аккаунт ещё раз." }
                if status == 422 { return "Не удалось обработать запрос. Проверь место начала и попробуй ещё раз." }
                return "Не удалось выполнить запрос (\(status)). Попробуй ещё раз."
            }
        }
    }
}

final class BackendAPI: SeruBackend, Sendable {
    static let productionURL = URL(string: "https://seruendesh.site")!
    let baseURL: URL
    let session: URLSession
    let sessionVault: (any SessionCookieVault)?

    init(baseURL: URL = BackendAPI.productionURL, session: URLSession? = nil, sessionVault: (any SessionCookieVault)? = nil) {
        self.baseURL = baseURL
        self.sessionVault = sessionVault ?? (session == nil ? KeychainSessionCookieVault() : nil)
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 120
            configuration.httpShouldSetCookies = true
            configuration.httpCookieStorage = .shared
            self.session = URLSession(configuration: configuration)
        }
        restoreSessionCookie()
    }

    func metadata() async throws -> APIMetadata { try await call("api/meta") }

    func recommend(_ request: APIRecommendRequest, photo: Data? = nil) async throws -> APIRecommendationResponse {
        guard let photo else { return try await call("api/recommend", method: "POST", body: JSONEncoder().encode(request)) }
        guard photo.count <= 8 * 1024 * 1024 else { throw APIError.photoTooLarge }
        let png = photo.starts(with: [137,80,78,71,13,10,26,10])
        let jpeg = photo.starts(with: [255,216,255])
        guard png || jpeg else { throw APIError.invalidPhoto }
        let boundary = "Seru-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        var query = request.effectiveQuery
        if let duration = request.duration { query += ". На \(min(480, max(10, duration))) минут" }
        if request.withKids { query += ". С ребёнком" }
        field("query", String(query.prefix(1000)))
        field("lang", request.lang)
        if case .landmark(let landmark) = request.origin { field("landmark", String(landmark.prefix(80))) }
        let ext = png ? "png" : "jpg"
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"photo.\(ext)\"\r\nContent-Type: image/\(png ? "png" : "jpeg")\r\n\r\n".utf8))
        body.append(photo)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try await call("api/recommend/photo", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    func events(query: String? = nil, price: String? = nil, limit: Int = 20, offset: Int = 0) async throws -> APIEventPage {
        var items = [URLQueryItem(name: "view", value: "upcoming"), URLQueryItem(name: "limit", value: String(min(100, max(1, limit)))), URLQueryItem(name: "offset", value: String(max(0, offset)))]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(URLQueryItem(name: "q", value: String(query.prefix(500)))) }
        if let price, ["free", "paid"].contains(price) { items.append(URLQueryItem(name: "price", value: price)) }
        return try await call("api/events", queryItems: items)
    }

    func route(poiID: String, origin: APIOrigin) async throws -> APIRouteToPlace {
        try await call("api/route", method: "POST", body: JSONEncoder().encode(RouteBody(poiID: poiID, origin: origin)))
    }

    func routeIdeas(origin: APIOrigin) async throws -> [APIRouteIdea] {
        let page: IdeasPage = try await call("api/routes/ideas", method: "POST", body: JSONEncoder().encode(OriginBody(origin: origin)))
        return page.ideas
    }

    func geocode(query: String) async throws -> [APIGeocodeResult] {
        let page: GeocodePage = try await call("api/geocode", queryItems: [URLQueryItem(name: "q", value: String(query.prefix(120)))])
        return page.results
    }

    private struct OriginBody: Encodable {
        let origin: APIOrigin
        enum CodingKeys: String, CodingKey { case location, landmark, lang }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("ru", forKey: .lang)
            try origin.encode(into: &c, location: .location, landmark: .landmark)
        }
    }
    private struct RouteBody: Encodable {
        let poiID: String
        let origin: APIOrigin
        enum CodingKeys: String, CodingKey { case poiID = "poi_id", location, landmark, mode }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(poiID, forKey: .poiID)
            try c.encode("walk", forKey: .mode)
            try origin.encode(into: &c, location: .location, landmark: .landmark)
        }
    }
    private struct IdeasPage: Decodable { let ideas: [APIRouteIdea] }
    private struct GeocodePage: Decodable { let results: [APIGeocodeResult] }

    private func call<T: Decodable & Sendable>(_ path: String, method: String = "GET", queryItems: [URLQueryItem] = [], body: Data? = nil, contentType: String = "application/json") async throws -> T {
        try Task.checkCancellation()
        guard ["https", "http"].contains(baseURL.scheme?.lowercased() ?? ""), baseURL.host != nil,
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw APIError.http(status: response.statusCode, code: Self.errorCode(data)) }
            let decoder = JSONDecoder()
            decoder.userInfo[.apiBaseURL] = baseURL
            do { return try decoder.decode(T.self, from: data) }
            catch { throw APIError.invalidResponse }
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            throw APIError.network(error.code)
        } catch let error as APIError { throw error }
        catch { throw APIError.invalidResponse }
    }

    private static func errorCode(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? String { return error }
        if let error = json["error"] as? [String: Any] { return error["code"] as? String }
        return json["detail"] as? String
    }
}

// Explicit keys preserve acronym spelling and nested source dictionaries.
private extension CodingUserInfoKey {
    static let apiBaseURL = CodingUserInfoKey(rawValue: "seru.api.baseURL")!
}
private func validatedAPIURL(_ value: String, decoder: Decoder) -> URL? {
    guard !value.isEmpty, !value.contains("\\"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
          let url = URL(string: value, relativeTo: decoder.userInfo[.apiBaseURL] as? URL)?.absoluteURL,
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
          url.user == nil, url.password == nil else { return nil }
    return url
}
private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T { try decodeIfPresent(T.self, forKey: key) ?? fallback }
    func optional<T: Decodable>(_ key: Key) throws -> T? { try decodeIfPresent(T.self, forKey: key) }
    func webURL(_ key: Key, decoder: Decoder) throws -> URL? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return validatedAPIURL(value, decoder: decoder)
    }
    func webURLs(_ key: Key, decoder: Decoder) throws -> [String: URL] {
        try value(key, default: [String: String]()).compactMapValues { validatedAPIURL($0, decoder: decoder) }
    }
}

struct APICoordinate: Codable, Hashable, Sendable { let lat: Double; let lon: Double }

enum APIJSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: APIJSONValue]), array([APIJSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: APIJSONValue].self) { self = .object(value) }
        else { self = .array(try c.decode([APIJSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct APIRecommendationResponse: Decodable, Hashable, Sendable {
    let apiVersion: String
    let requestID: String
    let lang: String
    let summary: String
    let recommendations: [APIRecommendation]
    let ideas: [APIRecommendation]
    let route: APIRoute?
    let usedContext: APIUsedContext?
    let considered: [APIConsidered]
    let notes: [String]
    let disclaimer: String
    let offTopic: Bool
    let navigateTo: String?
    let photoGuess: APIPhotoGuess?
    let serviceResults: [[String: APIJSONValue]]
    let aiGenerated: Bool
    let llm: APILLMInfo?
    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case requestID = "request_id"
        case lang
        case summary
        case recommendations
        case ideas
        case route
        case usedContext = "used_context"
        case considered
        case notes
        case disclaimer
        case offTopic = "off_topic"
        case navigateTo = "navigate_to"
        case photoGuess = "photo_guess"
        case serviceResults = "service_results"
        case aiGenerated = "ai_generated"
        case llm
    }
}
extension APIRecommendationResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try c.value(.apiVersion, default: "1.0")
        requestID = try c.value(.requestID, default: "")
        lang = try c.value(.lang, default: "ru")
        summary = try c.value(.summary, default: "")
        recommendations = try c.value(.recommendations, default: [])
        ideas = try c.value(.ideas, default: [])
        route = try c.optional(.route)
        usedContext = try c.optional(.usedContext)
        considered = try c.value(.considered, default: [])
        notes = try c.value(.notes, default: [])
        disclaimer = try c.value(.disclaimer, default: "")
        offTopic = try c.value(.offTopic, default: false)
        navigateTo = try c.optional(.navigateTo)
        photoGuess = try c.optional(.photoGuess)
        serviceResults = try c.value(.serviceResults, default: [])
        aiGenerated = try c.value(.aiGenerated, default: true)
        llm = try c.optional(.llm)
    }
}

struct APIRecommendation: Decodable, Hashable, Sendable {
    let poiID: String
    let name: String
    let category: String
    let categoryDetail: String
    let categoryLabel: String
    let icon: String
    let lat: Double
    let lon: Double
    let distanceM: Int
    let walkDistanceM: Int?
    let travelMin: Int
    let travelMode: String
    let visitMin: [Int]
    let visitSuggestedMin: Int
    let why: String
    let whatToDo: String
    let openStatus: String
    let openConfidence: String
    let opening: APIOpening?
    let source: String
    let sourceLabel: String
    let sourceURL: URL?
    let rating: Double?
    let website: URL?
    let photo: APIPhoto?
    let address: String?
    let description: String?
    let descriptionSource: String?
    let descriptionURL: URL?
    let descriptionAttribution: [APIDescriptionAttribution]
    let phone: String?
    let instagram: String?
    let cuisine: [String]
    let features: [String]
    let badges: [String]
    let accessibility: String
    let dataSources: [String]
    let rank: Int
    let match: Double?
    let popularity: Double?
    let arrivalAt: String?
    let departureAt: String?
    let leaveBy: String?
    let returnMin: Int
    let event: APIRecommendationEvent?
    let structuredFacts: [[String: APIJSONValue]]
    let menuItems: [[String: APIJSONValue]]
    let prices: [[String: APIJSONValue]]
    enum CodingKeys: String, CodingKey {
        case poiID = "poi_id"
        case name
        case category
        case categoryDetail = "category_detail"
        case categoryLabel = "category_label"
        case icon
        case lat
        case lon
        case distanceM = "distance_m"
        case walkDistanceM = "walk_distance_m"
        case travelMin = "travel_min"
        case travelMode = "travel_mode"
        case visitMin = "visit_min"
        case visitSuggestedMin = "visit_suggested_min"
        case why
        case whatToDo = "what_to_do"
        case openStatus = "open_status"
        case openConfidence = "open_confidence"
        case opening
        case source
        case sourceLabel = "source_label"
        case sourceURL = "source_url"
        case rating
        case website
        case photo
        case address
        case description
        case descriptionSource = "description_source"
        case descriptionURL = "description_url"
        case descriptionAttribution = "description_attribution"
        case phone
        case instagram
        case cuisine
        case features
        case badges
        case accessibility
        case dataSources = "data_sources"
        case rank
        case match
        case popularity
        case arrivalAt = "arrival_at"
        case departureAt = "departure_at"
        case leaveBy = "leave_by"
        case returnMin = "return_min"
        case event
        case structuredFacts = "structured_facts"
        case menuItems = "menu_items"
        case prices
    }
}
extension APIRecommendation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poiID = try c.decode(String.self, forKey: .poiID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.value(.category, default: "other")
        categoryDetail = try c.value(.categoryDetail, default: "other")
        categoryLabel = try c.value(.categoryLabel, default: "Место")
        icon = try c.value(.icon, default: "landmark")
        lat = try c.value(.lat, default: 0)
        lon = try c.value(.lon, default: 0)
        distanceM = try c.value(.distanceM, default: 0)
        walkDistanceM = try c.optional(.walkDistanceM)
        travelMin = try c.value(.travelMin, default: 0)
        travelMode = try c.value(.travelMode, default: "walk")
        visitMin = try c.value(.visitMin, default: [])
        visitSuggestedMin = try c.value(.visitSuggestedMin, default: 0)
        why = try c.value(.why, default: "")
        whatToDo = try c.value(.whatToDo, default: "")
        openStatus = try c.value(.openStatus, default: "unknown")
        openConfidence = try c.value(.openConfidence, default: "none")
        opening = try c.optional(.opening)
        source = try c.value(.source, default: "poi_data")
        sourceLabel = try c.value(.sourceLabel, default: "")
        sourceURL = try c.webURL(.sourceURL, decoder: decoder)
        rating = try c.optional(.rating)
        website = try c.webURL(.website, decoder: decoder)
        photo = try c.optional(.photo)
        address = try c.optional(.address)
        description = try c.optional(.description)
        descriptionSource = try c.optional(.descriptionSource)
        descriptionURL = try c.webURL(.descriptionURL, decoder: decoder)
        descriptionAttribution = try c.value(.descriptionAttribution, default: [])
        phone = try c.optional(.phone)
        instagram = try c.optional(.instagram)
        cuisine = try c.value(.cuisine, default: [])
        features = try c.value(.features, default: [])
        badges = try c.value(.badges, default: [])
        accessibility = try c.value(.accessibility, default: "unknown")
        dataSources = try c.value(.dataSources, default: [])
        rank = try c.value(.rank, default: 0)
        match = try c.optional(.match)
        popularity = try c.optional(.popularity)
        arrivalAt = try c.optional(.arrivalAt)
        departureAt = try c.optional(.departureAt)
        leaveBy = try c.optional(.leaveBy)
        returnMin = try c.value(.returnMin, default: 0)
        event = try c.optional(.event)
        structuredFacts = try c.value(.structuredFacts, default: [])
        menuItems = try c.value(.menuItems, default: [])
        prices = try c.value(.prices, default: [])
    }
}

struct APIOpening: Decodable, Hashable, Sendable {
    let status: String
    let confidence: String
    let label: String
    let raw: String?
    let source: String?
    let sourceURL: URL?
    let checkDate: String?
    let nextChange: String?
    enum CodingKeys: String, CodingKey {
        case status
        case confidence
        case label
        case raw
        case source
        case sourceURL = "source_url"
        case checkDate = "check_date"
        case nextChange = "next_change"
    }
}
extension APIOpening {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.value(.status, default: "unknown")
        confidence = try c.value(.confidence, default: "low")
        label = try c.value(.label, default: "Часы работы неизвестны")
        raw = try c.optional(.raw)
        source = try c.optional(.source)
        sourceURL = try c.webURL(.sourceURL, decoder: decoder)
        checkDate = try c.optional(.checkDate)
        nextChange = try c.optional(.nextChange)
    }
}

struct APIPhoto: Decodable, Hashable, Sendable {
    let url: URL?
    let width: Int?
    let height: Int?
    let author: String
    let license: String
    let page: URL?
    let source: String
    enum CodingKeys: String, CodingKey {
        case url
        case width
        case height
        case author
        case license
        case page
        case source
    }
}
extension APIPhoto {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.webURL(.url, decoder: decoder)
        width = try c.optional(.width)
        height = try c.optional(.height)
        author = try c.value(.author, default: "")
        license = try c.value(.license, default: "")
        page = try c.webURL(.page, decoder: decoder)
        source = try c.value(.source, default: "Wikimedia Commons")
    }
}

struct APIDescriptionAttribution: Decodable, Hashable, Sendable {
    let source: String
    let title: String
    let url: URL?
    let license: String
    let licenseURL: URL?
    let attribution: String
    let notice: String
    enum CodingKeys: String, CodingKey {
        case source
        case title
        case url
        case license
        case licenseURL = "license_url"
        case attribution
        case notice
    }
}
extension APIDescriptionAttribution {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.value(.source, default: "wikipedia")
        title = try c.value(.title, default: "")
        url = try c.webURL(.url, decoder: decoder)
        license = try c.value(.license, default: "")
        licenseURL = try c.webURL(.licenseURL, decoder: decoder)
        attribution = try c.value(.attribution, default: "")
        notice = try c.value(.notice, default: "")
    }
}

struct APIRecommendationEvent: Decodable, Hashable, Sendable {
    let title: String
    let startsAt: String?
    let url: URL?
    let source: String
    let priceFrom: String?
    enum CodingKeys: String, CodingKey {
        case title
        case startsAt = "starts_at"
        case url
        case source
        case priceFrom = "price_from"
    }
}
extension APIRecommendationEvent {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.value(.title, default: "")
        startsAt = try c.optional(.startsAt)
        url = try c.webURL(.url, decoder: decoder)
        source = try c.value(.source, default: "")
        priceFrom = try c.optional(.priceFrom)
    }
}

struct APIRoute: Decodable, Hashable, Sendable {
    let order: [String]
    let legs: [APIRouteLeg]
    let totalMin: Int
    let backMin: Int
    let fitsBudget: Bool
    let returnsToStart: Bool
    let summary: String
    enum CodingKeys: String, CodingKey {
        case order
        case legs
        case totalMin = "total_min"
        case backMin = "back_min"
        case fitsBudget = "fits_budget"
        case returnsToStart = "returns_to_start"
        case summary
    }
}
extension APIRoute {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.value(.order, default: [])
        legs = try c.value(.legs, default: [])
        totalMin = try c.value(.totalMin, default: 0)
        backMin = try c.value(.backMin, default: 0)
        fitsBudget = try c.value(.fitsBudget, default: false)
        returnsToStart = try c.value(.returnsToStart, default: false)
        summary = try c.value(.summary, default: "")
    }
}

struct APIRouteLeg: Decodable, Hashable, Sendable {
    let fromID: String
    let toID: String
    let distanceM: Int
    let travelMin: Int
    let polyline: [[Double]]
    let geometry: String
    enum CodingKeys: String, CodingKey {
        case fromID = "from_id"
        case toID = "to_id"
        case distanceM = "distance_m"
        case travelMin = "travel_min"
        case polyline
        case geometry
    }
}
extension APIRouteLeg {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromID = try c.value(.fromID, default: "start")
        toID = try c.value(.toID, default: "")
        distanceM = try c.value(.distanceM, default: 0)
        travelMin = try c.value(.travelMin, default: 0)
        polyline = try c.value(.polyline, default: [])
        geometry = try c.value(.geometry, default: "straight")
    }
}

struct APIRouteToPlace: Decodable, Hashable, Sendable {
    let poiID: String
    let name: String
    let mode: String
    let distanceM: Int
    let travelMin: Int
    let geometry: String
    let polyline: [[Double]]
    let origin: APICoordinate?
    let originSource: String
    let links: [String: URL]
    enum CodingKeys: String, CodingKey {
        case poiID = "poi_id"
        case name
        case mode
        case distanceM = "distance_m"
        case travelMin = "travel_min"
        case geometry
        case polyline
        case origin
        case originSource = "origin_source"
        case links
    }
}
extension APIRouteToPlace {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poiID = try c.decode(String.self, forKey: .poiID)
        name = try c.value(.name, default: "")
        mode = try c.value(.mode, default: "walk")
        distanceM = try c.value(.distanceM, default: 0)
        travelMin = try c.value(.travelMin, default: 0)
        geometry = try c.value(.geometry, default: "straight")
        polyline = try c.value(.polyline, default: [])
        origin = try c.optional(.origin)
        originSource = try c.value(.originSource, default: "landmark")
        links = try c.webURLs(.links, decoder: decoder)
    }
}

struct APIRouteIdea: Decodable, Hashable, Sendable {
    let key: String
    let emoji: String
    let title: String
    let totalMin: Int
    let stops: [String]
    let query: String
    let response: APIRecommendationResponse
    enum CodingKeys: String, CodingKey {
        case key
        case emoji
        case title
        case totalMin = "total_min"
        case stops
        case query
        case response
    }
}
extension APIRouteIdea {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        emoji = try c.value(.emoji, default: "")
        title = try c.value(.title, default: "")
        totalMin = try c.value(.totalMin, default: 0)
        stops = try c.value(.stops, default: [])
        query = try c.value(.query, default: "")
        response = try c.decode(APIRecommendationResponse.self, forKey: .response)
    }
}

struct APIUsedContext: Decodable, Hashable, Sendable {
    let locationSource: String
    let locationLabel: String?
    let radiusM: Int?
    let timeBudgetMin: Int
    let mode: String
    let filters: [String]
    let now: String
    let location: APIUsedLocation?
    let localTime: String
    let weekday: String
    let isHoliday: String?
    let isDark: Bool
    let weather: APIWeatherInfo?
    let speedKmh: Double
    let party: String
    let parsedFromQuery: [String: APIJSONValue]
    let relaxations: [String]
    let funnel: [String: Int]
    let dataSources: [String]
    let dataBuiltAt: String?
    let privacy: String
    let aiCheck: [String: APIJSONValue]?
    enum CodingKeys: String, CodingKey {
        case locationSource = "location_source"
        case locationLabel = "location_label"
        case radiusM = "radius_m"
        case timeBudgetMin = "time_budget_min"
        case mode
        case filters
        case now
        case location
        case localTime = "local_time"
        case weekday
        case isHoliday = "is_holiday"
        case isDark = "is_dark"
        case weather
        case speedKmh = "speed_kmh"
        case party
        case parsedFromQuery = "parsed_from_query"
        case relaxations
        case funnel
        case dataSources = "data_sources"
        case dataBuiltAt = "data_built_at"
        case privacy
        case aiCheck = "ai_check"
    }
}
extension APIUsedContext {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locationSource = try c.value(.locationSource, default: "none")
        locationLabel = try c.optional(.locationLabel)
        radiusM = try c.optional(.radiusM)
        timeBudgetMin = try c.value(.timeBudgetMin, default: 60)
        mode = try c.value(.mode, default: "walk")
        filters = try c.value(.filters, default: [])
        now = try c.value(.now, default: "")
        location = try c.optional(.location)
        localTime = try c.value(.localTime, default: "")
        weekday = try c.value(.weekday, default: "")
        isHoliday = try c.optional(.isHoliday)
        isDark = try c.value(.isDark, default: false)
        weather = try c.optional(.weather)
        speedKmh = try c.value(.speedKmh, default: 4.5)
        party = try c.value(.party, default: "")
        parsedFromQuery = try c.value(.parsedFromQuery, default: [:])
        relaxations = try c.value(.relaxations, default: [])
        funnel = try c.value(.funnel, default: [:])
        dataSources = try c.value(.dataSources, default: [])
        dataBuiltAt = try c.optional(.dataBuiltAt)
        privacy = try c.value(.privacy, default: "")
        aiCheck = try c.optional(.aiCheck)
    }
}

struct APIUsedLocation: Decodable, Hashable, Sendable {
    let source: String
    let label: String
    let lat: Double
    let lon: Double
    let precisionM: Int
    enum CodingKeys: String, CodingKey {
        case source
        case label
        case lat
        case lon
        case precisionM = "precision_m"
    }
}
extension APIUsedLocation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.value(.source, default: "none")
        label = try c.value(.label, default: "")
        lat = try c.value(.lat, default: 0)
        lon = try c.value(.lon, default: 0)
        precisionM = try c.value(.precisionM, default: 100)
    }
}

struct APIWeatherInfo: Decodable, Hashable, Sendable {
    let temperatureC: Double?
    let feelsLikeC: Double?
    let windMs: Double?
    let precipitation: Bool
    let description: String
    let maxOutdoorMin: Int
    let usAQI: Double?
    let pm25: Double?
    let source: String
    enum CodingKeys: String, CodingKey {
        case temperatureC = "temperature_c"
        case feelsLikeC = "feels_like_c"
        case windMs = "wind_ms"
        case precipitation
        case description
        case maxOutdoorMin = "max_outdoor_min"
        case usAQI = "us_aqi"
        case pm25 = "pm2_5"
        case source
    }
}
extension APIWeatherInfo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperatureC = try c.optional(.temperatureC)
        feelsLikeC = try c.optional(.feelsLikeC)
        windMs = try c.optional(.windMs)
        precipitation = try c.value(.precipitation, default: false)
        description = try c.value(.description, default: "")
        maxOutdoorMin = try c.value(.maxOutdoorMin, default: 0)
        usAQI = try c.optional(.usAQI)
        pm25 = try c.optional(.pm25)
        source = try c.value(.source, default: "")
    }
}

struct APIConsidered: Decodable, Hashable, Sendable {
    let name: String
    let reason: String
    enum CodingKeys: String, CodingKey {
        case name
        case reason
    }
}
extension APIConsidered {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.value(.name, default: "")
        reason = try c.value(.reason, default: "")
    }
}

struct APILLMInfo: Decodable, Hashable, Sendable {
    let mode: String
    let model: String?
    let latencyMs: Int
    let usage: APILLMUsage?
    enum CodingKeys: String, CodingKey {
        case mode
        case model
        case latencyMs = "latency_ms"
        case usage
    }
}
extension APILLMInfo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.value(.mode, default: "template")
        model = try c.optional(.model)
        latencyMs = try c.value(.latencyMs, default: 0)
        usage = try c.optional(.usage)
    }
}

struct APILLMUsage: Decodable, Hashable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double?
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUSD = "cost_usd"
    }
}
extension APILLMUsage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.value(.inputTokens, default: 0)
        outputTokens = try c.value(.outputTokens, default: 0)
        costUSD = try c.optional(.costUSD)
    }
}

struct APIPhotoGuess: Decodable, Hashable, Sendable {
    let recognized: Bool
    let placeID: String?
    let kind: String?
    let name: String?
    let confidence: String
    let description: String
    let probability: Double?
    enum CodingKeys: String, CodingKey {
        case recognized
        case placeID = "place_id"
        case kind
        case name
        case confidence
        case description
        case probability
    }
}
extension APIPhotoGuess {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recognized = try c.value(.recognized, default: false)
        placeID = try c.optional(.placeID)
        kind = try c.optional(.kind)
        name = try c.optional(.name)
        confidence = try c.value(.confidence, default: "low")
        description = try c.value(.description, default: "")
        probability = try c.optional(.probability)
    }
}

struct APIMetadata: Decodable, Hashable, Sendable {
    let apiVersion: String
    let landmarks: [APILandmark]
    let categories: [APICategory]
    let dataBuiltAt: String?
    let poiCount: Int
    let sources: [String: String]
    let features: APIFeatures
    let map: APIMapTiles?
    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case landmarks
        case categories
        case dataBuiltAt = "data_built_at"
        case poiCount = "poi_count"
        case sources
        case features
        case map
    }
}
extension APIMetadata {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try c.value(.apiVersion, default: "1.0")
        landmarks = try c.value(.landmarks, default: [])
        categories = try c.value(.categories, default: [])
        dataBuiltAt = try c.optional(.dataBuiltAt)
        poiCount = try c.value(.poiCount, default: 0)
        sources = try c.value(.sources, default: [:])
        features = try c.value(.features, default: APIFeatures(passwordResetEmail: false, photo: false, mcp: true))
        map = try c.optional(.map)
    }
}

struct APIFeatures: Decodable, Hashable, Sendable {
    let passwordResetEmail: Bool
    let photo: Bool
    let mcp: Bool
    enum CodingKeys: String, CodingKey {
        case passwordResetEmail = "password_reset_email"
        case photo
        case mcp
    }
}
extension APIFeatures {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passwordResetEmail = try c.value(.passwordResetEmail, default: false)
        photo = try c.value(.photo, default: false)
        mcp = try c.value(.mcp, default: true)
    }
}

struct APILandmark: Decodable, Hashable, Sendable {
    let key: String
    let name: String
    let lat: Double
    let lon: Double
    enum CodingKeys: String, CodingKey {
        case key
        case name
        case lat
        case lon
    }
}
extension APILandmark {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
    }
}

struct APICategory: Decodable, Hashable, Sendable {
    let key: String
    let group: String
    let labels: [String: String]
    let icon: String
    enum CodingKeys: String, CodingKey {
        case key
        case group
        case labels
        case icon
    }
}
extension APICategory {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        group = try c.value(.group, default: "")
        labels = try c.value(.labels, default: [:])
        icon = try c.value(.icon, default: "landmark")
    }
}

struct APIMapTiles: Decodable, Hashable, Sendable {
    let url: String
    let attribution: String
    let dataURL: String?
    enum CodingKeys: String, CodingKey {
        case url
        case attribution
        case dataURL = "data_url"
    }
}
extension APIMapTiles {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.value(.url, default: "")
        attribution = try c.value(.attribution, default: "")
        dataURL = try c.optional(.dataURL)
    }
}

struct APIEventPage: Decodable, Hashable, Sendable {
    let items: [APIEvent]
    let total: Int
    let offset: Int
    let limit: Int
    let today: String
    let categories: [APIEventCategory]
    let months: [String]
    let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case items
        case total
        case offset
        case limit
        case today
        case categories
        case months
        case updatedAt = "updated_at"
    }
}
extension APIEventPage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.value(.items, default: [])
        total = try c.value(.total, default: 0)
        offset = try c.value(.offset, default: 0)
        limit = try c.value(.limit, default: 20)
        today = try c.value(.today, default: "")
        categories = try c.value(.categories, default: [])
        months = try c.value(.months, default: [])
        updatedAt = try c.optional(.updatedAt)
    }
}

struct APIEvent: Decodable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String?
    let venue: String?
    let address: String?
    let start: String?
    let end: String?
    let sessions: [String]
    let scheduleKind: String
    let priceFrom: Double?
    let currency: String?
    let category: String
    let categoryLabel: String
    let imageURL: URL?
    let announcedAt: String?
    let firstSeenAt: String?
    let sources: [APIEventSource]
    let isArchived: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case venue
        case address
        case start
        case end
        case sessions
        case scheduleKind = "schedule_kind"
        case priceFrom = "price_from"
        case currency
        case category
        case categoryLabel = "category_label"
        case imageURL = "image_url"
        case announcedAt = "announced_at"
        case firstSeenAt = "first_seen_at"
        case sources
        case isArchived = "is_archived"
    }
}
extension APIEvent {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.optional(.description)
        venue = try c.optional(.venue)
        address = try c.optional(.address)
        start = try c.optional(.start)
        end = try c.optional(.end)
        sessions = try c.value(.sessions, default: [])
        scheduleKind = try c.value(.scheduleKind, default: "continuous")
        priceFrom = try c.optional(.priceFrom)
        currency = try c.optional(.currency)
        category = try c.value(.category, default: "other")
        categoryLabel = try c.value(.categoryLabel, default: "Событие")
        imageURL = try c.webURL(.imageURL, decoder: decoder)
        announcedAt = try c.optional(.announcedAt)
        firstSeenAt = try c.optional(.firstSeenAt)
        sources = try c.value(.sources, default: [])
        isArchived = try c.value(.isArchived, default: false)
    }
}

struct APIEventSource: Decodable, Hashable, Sendable {
    let name: String
    let url: URL?
    enum CodingKeys: String, CodingKey {
        case name
        case url
    }
}
extension APIEventSource {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.value(.name, default: "")
        url = try c.webURL(.url, decoder: decoder)
    }
}

struct APIEventCategory: Decodable, Hashable, Sendable {
    let value: String
    let label: String
    enum CodingKeys: String, CodingKey {
        case value
        case label
    }
}
extension APIEventCategory {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.value(.value, default: "")
        label = try c.value(.label, default: "")
    }
}

struct APIGeocodeResult: Decodable, Hashable, Sendable {
    let label: String
    let lat: Double
    let lon: Double
    let source: String
    enum CodingKeys: String, CodingKey {
        case label
        case lat
        case lon
        case source
    }
}
extension APIGeocodeResult {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        source = try c.value(.source, default: "")
    }
}
