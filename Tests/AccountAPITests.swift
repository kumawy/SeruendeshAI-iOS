import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@Suite(.serialized)
struct AccountAPITests {
    private func client(vault: (any SessionCookieVault)? = nil, _ handler: @escaping @Sendable (URLRequest) async throws -> AccountHTTPStub) -> BackendAPI {
        AccountURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountURLProtocol.self]
        return BackendAPI(baseURL: URL(string: "https://account.example")!, session: URLSession(configuration: configuration), sessionVault: vault)
    }

    @Test func savedSnapshotPreservesSuppliedContactAndAccessibilityFacts() throws {
        var place = DemoData.places[0]
        place.address = "Кунаева, 1"
        place.phone = "+77170000000"
        place.accessibility = "yes"
        let encoded = try JSONEncoder().encode(SavedPlaceSnapshot(place: place))
        let restored = try JSONDecoder().decode(SavedPlaceSnapshot.self, from: encoded).place(id: place.id)
        #expect(restored.address == place.address)
        #expect(restored.phone == place.phone)
        #expect(restored.accessibility == place.accessibility)
        #expect(restored.subtitle == place.address)
    }

    @Test func currentUserDistinguishesGuestFromUserWithoutCaching() async throws {
        let guest = client { request in
            #expect(request.url?.path == "/api/auth/me")
            #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
            #expect(request.timeoutInterval == 20)
            return .init(200, #"{"user":null}"#)
        }
        #expect(try await guest.currentUser() == nil)
        let signedIn = client { _ in .init(200, accountUserJSON) }
        #expect(try await signedIn.currentUser()?.name == "Аслан")
    }

    @Test func registrationSendsBackendFieldsAndNoBearerCredentials() async throws {
        let api = client { request in
            #expect(request.url?.path == "/api/auth/register")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try JSONSerialization.jsonObject(with: accountBody(request)) as! [String: String]
            #expect(body == ["name":"Аслан", "email":"aslan@example.com", "password":"plain secret", "lang":"ru"])
            return .init(201, accountUserJSON)
        }
        #expect(try await api.register(name: "Аслан", email: "aslan@example.com", password: "plain secret").id == "user-1")
    }

    @Test func loginAndPasswordResetUseRealContract() async throws {
        let api = client { request in
            let body = try JSONSerialization.jsonObject(with: accountBody(request)) as! [String: String]
            switch request.url?.path {
            case "/api/auth/login": #expect(body == ["email":"aslan@example.com", "password":"secret123"])
            case "/api/auth/password-reset/request":
                #expect(body == ["email":"aslan@example.com"])
                return .init(202, #"{"ok":true}"#)
            case "/api/auth/password-reset/confirm": #expect(body == ["token":"reset-token-twenty-characters", "password":"changed123"])
            default: Issue.record("Unexpected account endpoint")
            }
            return .init(200, accountUserJSON)
        }
        #expect(try await api.signIn(email: "aslan@example.com", password: "secret123").email == "aslan@example.com")
        try await api.requestPasswordReset(email: "aslan@example.com")
        #expect(try await api.confirmPasswordReset(token: "reset-token-twenty-characters", password: "changed123").id == "user-1")
    }

    @Test func emptySuccessBodiesAreAcceptedForLogoutDeleteAndUnsave() async throws {
        let api = client { request in
            #expect(["/api/auth/logout", "/api/me", "/api/me/saved/osm:w1"].contains(request.url!.path))
            return .init(204, "")
        }
        try await api.signOut()
        try await api.deleteAccount()
        try await api.removeSavedPlace(id: "osm:w1")
    }

    @Test func accountErrorsExplainTheFailedActionInRussian() async throws {
        let cases = [(401, "invalid_credentials", "пароль"), (409, "email_taken", "зарегистрирован"),
                     (503, "email_unavailable", "почт"), (400, "invalid_or_expired_token", "ссылк"),
                     (422, "too_many_saved", "300"), (422, "invalid_saved_snapshot", "мест"),
                     (429, "too_many_attempts", "Подожди")]
        for (status, code, text) in cases {
            let api = client { _ in .init(status, "{\"detail\":\"\(code)\"}") }
            do { _ = try await api.signIn(email: "x@example.com", password: "bad"); Issue.record("Expected account error") }
            catch let error as APIError {
                guard case .http(let actualStatus, let actualCode) = error else { Issue.record("Expected HTTP status"); continue }
                #expect(actualStatus == status && actualCode == code)
                #expect(error.localizedDescription.localizedCaseInsensitiveContains(text))
                #expect(!error.localizedDescription.contains("bad"))
            }
        }
        let invalid = client { _ in .init(422, #"{"detail":[{"loc":["body","password"],"msg":"too short","input":"private-password"}]}"#) }
        do { _ = try await invalid.register(name: "A", email: "bad", password: "private-password"); Issue.record("Expected validation error") }
        catch { #expect(error.localizedDescription.contains("Проверь")); #expect(!error.localizedDescription.contains("private-password")) }
    }

    @Test func savedValidationErrorsReferToPlacesWithoutEchoingPrivateInput() async throws {
        let cases = [
            (#"{"detail":[{"loc":["body","data","why"],"msg":"too long","input":"private-saved-text"}]}"#, "invalid_saved_snapshot", "мест"),
            (#"{"detail":"poi_id too long"}"#, "invalid_saved_snapshot", "мест"),
            (#"{"detail":"too_many_saved"}"#, "too_many_saved", "300")
        ]
        for (json, expectedCode, message) in cases {
            let api = client { _ in .init(422, json) }
            do {
                _ = try await api.savePlace(id: "osm:w123", snapshot: SavedPlaceSnapshot(place: DemoData.places[0]))
                Issue.record("Expected saved-place validation error")
            } catch let error as APIError {
                guard case .http(let status, let code) = error else { Issue.record("Expected HTTP status"); continue }
                #expect(status == 422 && code == expectedCode)
                #expect(error.localizedDescription.localizedCaseInsensitiveContains(message))
                #expect(!error.localizedDescription.contains("пароль"))
                #expect(!error.localizedDescription.contains("private-saved-text"))
            }
        }
    }

    @Test func sessionCookieRestoresIntoNewClientAndLogoutClearsVault() async throws {
        let vault = MemorySessionVault()
        let first = client(vault: vault) { _ in
            .init(200, accountUserJSON, headers: ["Set-Cookie":"seru_session=test-only-token; Path=/; Max-Age=2592000; Secure; HttpOnly; SameSite=Lax"])
        }
        _ = try await first.signIn(email: "aslan@example.com", password: "secret123")
        #expect(vault.load(for: first.baseURL) != nil)
        let restored = client(vault: vault) { request in
            if request.url?.path == "/api/auth/logout" { return .init(204, "") }
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("seru_session=test-only-token") == true)
            return .init(200, accountUserJSON)
        }
        #expect(try await restored.currentUser()?.id == "user-1")
        try await restored.signOut()
        #expect(vault.load(for: restored.baseURL) == nil)
        #expect(restored.session.configuration.httpCookieStorage?.cookies(for: restored.baseURL)?.contains { $0.name == "seru_session" } != true)
    }

    @Test func guestAndAccountDeletionClearExpiredSessionWithoutDeletingOtherCookies() async throws {
        let vault = MemorySessionVault()
        let first = client(vault: vault) { _ in .init(200, accountUserJSON, headers: ["Set-Cookie":"seru_session=test-only-token; Path=/; Max-Age=2592000; Secure; HttpOnly"]) }
        _ = try await first.signIn(email: "aslan@example.com", password: "secret123")
        let guest = client(vault: vault) { _ in .init(200, #"{"user":null}"#) }
        let otherCookie = try #require(HTTPCookie(properties: [.name:"other", .value:"keep", .domain:"account.example", .path:"/"]))
        guest.session.configuration.httpCookieStorage?.setCookie(otherCookie)
        #expect(try await guest.currentUser() == nil)
        #expect(vault.load(for: guest.baseURL) == nil)
        #expect(guest.session.configuration.httpCookieStorage?.cookies(for: guest.baseURL)?.contains { $0.name == "other" } == true)
        let signingIn = client(vault: vault) { _ in .init(200, accountUserJSON, headers: ["Set-Cookie":"seru_session=test-only-token; Path=/; Max-Age=2592000; Secure; HttpOnly"]) }
        _ = try await signingIn.signIn(email: "aslan@example.com", password: "secret123")
        let deleting = client(vault: vault) { _ in .init(204, "") }
        try await deleting.deleteAccount()
        #expect(vault.load(for: deleting.baseURL) == nil)
    }

    @Test func oldGuestAndExpiredResponsesCannotClearANewerSession() async throws {
        for status in [200, 401] {
            let gate = AccountReplyGate()
            let vault = MemorySessionVault()
            let api = client(vault: vault) { request in
                if request.url?.path != "/api/auth/login" { return await gate.wait() }
                let body = try JSONSerialization.jsonObject(with: accountBody(request)) as! [String:String]
                let token = body["email"] == "old@example.com" ? "old-session" : "new-session"
                return .init(200, accountUserJSON, headers: ["Set-Cookie":"seru_session=\(token); Path=/; Max-Age=2592000; Secure; HttpOnly"])
            }
            _ = try await api.signIn(email: "old@example.com", password: "secret123")
            let pending = Task { if status == 200 { _ = try? await api.currentUser() } else { _ = try? await api.savedPlaces() } }
            await gate.waitUntilHeld()
            _ = try await api.signIn(email: "new@example.com", password: "secret123")
            await gate.release(.init(status, status == 200 ? #"{"user":null}"# : #"{"detail":"session_expired"}"#))
            await pending.value
            #expect(api.session.configuration.httpCookieStorage?.cookies(for: api.baseURL)?.first { $0.name == "seru_session" }?.value == "new-session")
            #expect(vault.load(for: api.baseURL) != nil)
        }
    }

    @Test func savedPlaceIDsStayWithinPathEvenWithSlashesAndURLDelimiters() async throws {
        let id = "osm:node/a?x=1#part"
        let api = client { request in
            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            #expect(components.percentEncodedPath == "/api/me/saved/osm%3Anode%2Fa%3Fx%3D1%23part")
            #expect(components.query == nil && components.fragment == nil)
            return .init(204, "")
        }
        try await api.removeSavedPlace(id: id)
    }

    @Test func webSavedSnapshotDecodesCamelCaseAndUnknownFactsRemainUnknown() async throws {
        let api = client { _ in .init(200, "[\(savedJSON)]") }
        let saved = try #require(try await api.savedPlaces().first)
        let place = saved.snapshot.place(id: saved.id)
        #expect(saved.id == "osm:w123")
        #expect(place.name == "Кофейня")
        #expect(place.isLive && place.imageAsset.isEmpty)
        #expect(place.coordinate == GeoPoint(latitude: 51.128, longitude: 71.43))
        #expect(place.imageURL?.absoluteString == "https://images.example/cafe.jpg")
        #expect(place.imageCredit?.contains("Автор") == true)
        #expect(place.imageSourceURL?.absoluteString == "https://commons.wikimedia.org/wiki/File:Cafe.jpg")
        #expect(place.rating.isEmpty && !place.isFree && !place.isChildFriendly)
        #expect(place.hours == "Часы уточняй")
        #expect(place.travelMinutes == 0 && place.distance.isEmpty)
    }

    @Test func nativeSnapshotRoundTripsCoordinatePhotosAndCreditsThroughAllowedWebKeys() async throws {
        var place = DemoData.places[0]
        place.isLive = true
        place.coordinate = .init(latitude: 51.128, longitude: 71.43)
        place.imageURL = URL(string: "https://images.example/cafe.jpg")
        place.imageCredit = "Автор · CC BY-SA"
        place.imageSourceURL = URL(string: "https://commons.wikimedia.org/wiki/File:Cafe.jpg")
        place.sourceURL = URL(string: "https://example.com/research")
        place.descriptionCredit = "Текст: источник"
        let snapshot = SavedPlaceSnapshot(place: place)
        let data = try JSONEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["lat"] as? Double == 51.128)
        #expect(object["lon"] as? Double == 71.43)
        #expect(object["iconKey"] != nil && object["imageURL"] == nil)
        #expect(object["rating"] == nil)
        #expect((object["photo"] as? [String: Any])?["page"] as? String == place.imageSourceURL?.absoluteString)
        let decoded = try JSONDecoder().decode(SavedPlaceSnapshot.self, from: data).place(id: place.id)
        #expect(decoded.imageURL == place.imageURL && decoded.coordinate == place.coordinate)
        #expect(decoded.imageCredit == place.imageCredit)
        #expect(decoded.descriptionCredit == place.descriptionCredit)
        let expectedName = place.name
        let api = client { request in
            #expect(request.httpMethod == "PUT")
            let body = try JSONSerialization.jsonObject(with: accountBody(request)) as! [String: Any]
            #expect((body["data"] as? [String: Any])?["name"] as? String == expectedName)
            return .init(200, savedJSON)
        }
        #expect(try await api.savePlace(id: place.id, snapshot: snapshot).id == "osm:w123")
    }

    @Test func unsafeSavedLinksAndCoordinatesDoNotBecomeNativeLinksOrMapPins() throws {
        let data = Data(#"{"name":"Парк","lat":999,"lon":71,"photo":{"url":"javascript:alert(1)","page":"file:///tmp/photo"},"website":"https://name:secret@example.com","url":"file:///tmp/text","image":"/cards/local.jpg"}"#.utf8)
        let place = try JSONDecoder().decode(SavedPlaceSnapshot.self, from: data).place(id: "p")
        #expect(place.coordinate == nil && place.websiteURL == nil && place.sourceURL == nil)
        #expect(place.imageURL?.absoluteString == "https://seruendesh.site/cards/local.jpg")
        #expect(place.imageSourceURL == nil)
    }
}

private let accountUserJSON = #"{"id":"user-1","email":"aslan@example.com","name":"Аслан","lang":"ru","created_at":"2026-10-21T14:00:00.123456"}"#
private let savedJSON = #"{"poi_id":"osm:w123","data":{"name":"Кофейня","category":"Кофе","categoryKey":"cafe","iconKey":"coffee","lat":51.128,"lon":71.43,"description":"Место для кофе","photo":{"url":"https://images.example/cafe.jpg","page":"https://commons.wikimedia.org/wiki/File:Cafe.jpg","author":"Автор","license":"CC BY-SA"}},"created_at":"2026-10-21T14:00:00+00:00"}"#

private final class MemorySessionVault: SessionCookieVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    func load(for baseURL: URL) -> Data? { lock.withLock { data } }
    func store(_ data: Data?, for baseURL: URL) { lock.withLock { self.data = data } }
}
private struct AccountHTTPStub: Sendable {
    let status: Int
    let body: Data
    let headers: [String:String]
    init(_ status: Int, _ body: String, headers: [String:String] = [:]) { self.status = status; self.body = Data(body.utf8); self.headers = headers }
}
private final class AccountURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> AccountHTTPStub)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.handler!
        Task {
        do {
            let reply = try await handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers.merging(["Content-Type":"application/json"]) { first, _ in first })!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}
private actor AccountReplyGate {
    private var held: CheckedContinuation<AccountHTTPStub,Never>?
    private var started: CheckedContinuation<Void,Never>?
    func wait() async -> AccountHTTPStub {
        await withCheckedContinuation { held = $0; started?.resume(); started = nil }
    }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release(_ reply: AccountHTTPStub) { held?.resume(returning: reply); held = nil }
}
private func accountBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; result.append(buffer, count: count) }
    return result
}
