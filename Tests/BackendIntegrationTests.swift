import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor
struct BackendIntegrationTests {
    private func storage() -> UserDefaults { UserDefaults(suiteName: "seru.live.tests.\(UUID().uuidString)")! }

    @Test func liveAppStartsWithoutInventedRecommendationsOrEvents() {
        let app = AppModel(defaults: storage(), backend: IntegrationBackend())
        #expect(app.usesBackend)
        #expect(app.places.isEmpty)
        #expect(app.events.isEmpty)
        #expect(app.savedPlaces.isEmpty)
        #expect(app.savedRoutes.isEmpty)
    }

    @Test func chatAppliesServerPlacesAndPreservesUnknownRatingAndPhoto() async throws {
        let backend = IntegrationBackend()
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse() }

        app.sendMessage("  Хочу спокойную прогулку  ")
        try await waitUntil { !app.isResponding }

        #expect(app.responseError == nil)
        #expect(app.query == "Хочу спокойную прогулку")
        #expect(app.places.map(\.id) == ["osm:w42"])
        let place = try #require(app.places.first)
        #expect(place.isLive)
        #expect(place.name == "Парк с сервера")
        #expect(place.rating.isEmpty)
        #expect(place.imageURL == nil)
        #expect(place.imageAsset.isEmpty)
        #expect(place.travelMinutes == 7)
        #expect(place.visitMinutes == 15)
        #expect(place.distance == "560 м")
        #expect(place.hours == "Часы уточняй")
        #expect(place.reason.contains("Рядом и тихо"))
        #expect(place.reason.contains("Прогуляться"))
        #expect(place.coordinate == GeoPoint(latitude: 51.129, longitude: 71.431))
        #expect(place.isFree)
        #expect(app.messages.map(\.text) == ["Хочу спокойную прогулку", "Ответ настоящего API"])
        #expect(app.messages.last?.placeIDs == ["osm:w42"])
        let requests = await backend.requests
        #expect(requests.count == 1)
        #expect(requests.first?.query == "Хочу спокойную прогулку")
        #expect(requests.first?.duration == nil)
    }

    @Test func failureShowsNoDemoDataAndRetryDoesNotDuplicateUserMessage() async throws {
        let backend = IntegrationBackend()
        await backend.setFailure(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse() }

        app.sendMessage("Найди парк")
        try await waitUntil { !app.isResponding }

        #expect(app.responseError?.contains("интернет") == true)
        #expect(app.places.isEmpty)
        #expect(app.currentPlan == nil)
        #expect(app.messages.count == 1)
        #expect(app.messages.first?.role == .user)

        await backend.setFailure(false)
        app.retryResponse()
        try await waitUntil { !app.isResponding }

        #expect(app.responseError == nil)
        #expect(app.places.map(\.id) == ["osm:w42"])
        #expect(app.messages.filter { $0.role == .user }.map(\.text) == ["Найди парк"])
        #expect(app.messages.filter { $0.role == .assistant }.count == 1)
        let requests = await backend.requests
        #expect(requests.map(\.query) == ["Найди парк", "Найди парк"])
    }

    @Test func canceledOlderReplyCannotOverwriteNewerReplyWhenProviderIgnoresCancellation() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingRecommendations(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer {
            app.cancelResponse()
            Task { await backend.releaseAllRecommendations() }
        }

        app.sendMessage("Первый запрос")
        try await waitForBackend { await backend.calls >= 1 }
        app.cancelResponse()
        #expect(!app.isResponding)

        app.sendMessage("Новый запрос")
        try await waitForBackend { await backend.calls >= 2 }
        try await backend.releaseRecommendation(2, response: IntegrationBackend.newerResponse)
        try await waitUntil { !app.isResponding }
        #expect(app.places.map(\.id) == ["osm:w99"])
        #expect(app.messages.last?.text == "Новый ответ")

        try await backend.releaseRecommendation(1)
        try await waitForBackend { await backend.finishedRecommendations >= 2 }
        // The provider has returned; allow its suspended MainActor consumer to resume.
        try await Task.sleep(for: .milliseconds(10))

        #expect(app.query == "Новый запрос")
        #expect(app.places.map(\.id) == ["osm:w99"])
        #expect(app.messages.filter { $0.role == .assistant }.map(\.text) == ["Новый ответ"])
        #expect(app.responseError == nil)
        #expect(!app.isResponding)
    }

    @Test func liveSavedPlaceAndRouteSnapshotsSurviveRelaunchWithTheirStopsAndGeometry() async throws {
        let backend = IntegrationBackend()
        await backend.setResponse(IntegrationBackend.plannedResponse)
        let defaults = storage()
        let app = AppModel(defaults: defaults, backend: backend)
        defer { app.cancelResponse() }

        app.sendMessage("Составь маршрут")
        try await waitUntil { !app.isResponding }
        let place = try #require(app.places.first)
        let route = try #require(app.currentPlan)
        #expect(route.placeIDs == ["osm:w42", "osm:w43"])
        #expect(route.legs.first?.points.first == GeoPoint(latitude: 51.128, longitude: 71.43))
        app.toggleSaved(place)
        app.toggleSavedRoute(route)

        let reopened = AppModel(defaults: defaults, backend: IntegrationBackend())
        #expect(reopened.savedPlaces.map(\.id) == ["osm:w42"])
        #expect(reopened.savedRoutes.map(\.id) == ["native-plan"])
        #expect(reopened.savedPlaces.first?.rating.isEmpty == true)
        #expect(reopened.savedPlaces.first?.imageAsset.isEmpty == true)
        #expect(reopened.savedRoutes.first == route)
        #expect(reopened.savedRoutes.first?.originLabel == "Байтерек")
        #expect(reopened.savedRoutes.first?.originCoordinate == GeoPoint(latitude: 51.128, longitude: 71.43))
        #expect(reopened.place(id: "osm:w43").name == "Аллея с сервера")
        #expect(reopened.place(id: "osm:w43").isLive)

        reopened.toggleSaved(place)
        let routeOnly = AppModel(defaults: defaults, backend: IntegrationBackend())
        #expect(routeOnly.savedPlaces.isEmpty)
        #expect(routeOnly.savedRoutes.first == route)
        #expect(routeOnly.place(id: "osm:w42").name == "Парк с сервера")
        routeOnly.toggleSavedRoute(route)
        let empty = AppModel(defaults: defaults, backend: IntegrationBackend())
        #expect(empty.savedPlaces.isEmpty)
        #expect(empty.savedRoutes.isEmpty)
    }

    @Test func bootstrapUsesServerTodayAndSessionDatesAndLoadsEveryEventPageOnce() async throws {
        let backend = IntegrationBackend()
        await backend.setEventPages(IntegrationBackend.datedEventPages)
        let app = AppModel(defaults: storage(), backend: backend)

        await app.bootstrap()
        await app.bootstrap()

        #expect(app.landmarks.map(\.id) == ["baiterek"])
        #expect(app.originCoordinate == GeoPoint(latitude: 51.128, longitude: 71.43))
        #expect(app.photoSearchAvailable)
        #expect(app.eventsError == nil)
        #expect(!app.isLoadingEvents)
        #expect(app.events.map(\.id) == ["ticketon:today", "sxodim:tomorrow"])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Almaty"))
        let today = calendar.dateComponents([.year, .month, .day, .hour], from: app.eventToday)
        #expect(today.year == 2026)
        #expect(today.month == 10)
        #expect(today.day == 21)
        #expect(today.hour == 0)
        let currentEvent = try #require(app.events.first)
        #expect(currentEvent.dateLabel == "Сегодня")
        #expect(currentEvent.time == "04:30")
        #expect(currentEvent.price == "Цена уточняется")
        #expect(!currentEvent.isFree)
        #expect(currentEvent.travelMinutes == 0)
        #expect(currentEvent.imageAsset.isEmpty)
        #expect(currentEvent.imageURL?.absoluteString == "https://images.example/today.jpg")
        let tomorrow = try #require(app.events.last)
        #expect(tomorrow.dateLabel == "Завтра")
        #expect(tomorrow.isTomorrow)
        #expect(tomorrow.time == "19:30")
        #expect(tomorrow.sessionDates.count == 2)
        #expect(tomorrow.isFree)
        let offsets = await backend.eventOffsets
        let metadataCalls = await backend.metadataCalls
        #expect(offsets == [0, 2])
        #expect(metadataCalls == 1)
    }

    @Test func routePreviewUsesServerCoordinatesAndChosenOrigin() async throws {
        let backend = IntegrationBackend()
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse() }
        await app.bootstrap()
        app.sendMessage("Найди парк")
        try await waitUntil { !app.isResponding }
        let place = try #require(app.places.first)

        await app.loadRoutePreview(for: place)

        let preview = try #require(app.routePreview)
        #expect(!app.isLoadingRoute)
        #expect(app.routeError == nil)
        #expect(preview.placeID == "osm:w42")
        #expect(preview.travelMinutes == 7)
        #expect(preview.distanceMeters == 560)
        #expect(preview.geometry == "network")
        #expect(preview.points == [GeoPoint(latitude: 51.128, longitude: 71.43), GeoPoint(latitude: 51.129, longitude: 71.431)])
        #expect(preview.origin == GeoPoint(latitude: 51.128, longitude: 71.43))
        let origins = await backend.routeOrigins
        #expect(origins == [.landmark("baiterek")])
    }

    @Test func eventFeedFailureKeepsLiveCatalogEmptyAndMetadataStillAvailable() async {
        let backend = IntegrationBackend()
        await backend.setEventsFailure(true)
        let app = AppModel(defaults: storage(), backend: backend)

        await app.bootstrap()

        #expect(app.events.isEmpty)
        #expect(app.eventsError?.contains("интернет") == true)
        #expect(!app.isLoadingEvents)
        #expect(app.landmarks.map(\.id) == ["baiterek"])
        #expect(app.photoSearchAvailable)
    }

    @Test func changingFiltersDiscardsTheInFlightReplyAndNextRequestUsesNewChoice() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingRecommendations(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.sendMessage("Прогулка")
        try await waitForBackend { await backend.calls >= 1 }

        app.withKids = true
        try await backend.releaseRecommendation(1)
        try await waitForBackend { await backend.finishedRecommendations >= 1 }
        try await Task.sleep(for: .milliseconds(10))
        #expect(app.places.isEmpty)
        #expect(app.messages.filter { $0.role == .assistant }.isEmpty)
        #expect(!app.isResponding)

        await backend.setHoldingRecommendations(false)
        app.sendMessage("Теперь с ребёнком")
        try await waitUntil { !app.isResponding }
        let requests = await backend.requests
        #expect(requests.count == 2)
        #expect(requests.first?.withKids == false)
        #expect(requests.last?.withKids == true)
        #expect(app.messages.filter { $0.role == .assistant }.count == 1)
    }

    @Test func changingAddressWhileGeocodingNeverRelabelsOldCoordinatesAsNewAddress() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingGeocodes(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.saveOrigin("Адрес А")
        app.sendMessage("Первый поиск")
        try await waitForBackend { await backend.geocodeQueries == ["Адрес А"] }

        app.saveOrigin("Адрес Б")
        try await backend.releaseGeocode(query: "Адрес А", lat: 51.16, lon: 71.42)
        try await Task.sleep(for: .milliseconds(10))
        #expect(app.origin == "Адрес Б")
        #expect(app.originCoordinate == nil)
        #expect(app.places.isEmpty)
        #expect(!app.isResponding)

        app.sendMessage("Поиск от нового адреса")
        try await waitForBackend { await backend.geocodeQueries.count >= 2 }
        try await backend.releaseGeocode(query: "Адрес Б", lat: 51.17, lon: 71.45)
        try await waitUntil { !app.isResponding }
        let requests = await backend.requests
        #expect(requests.count == 1)
        #expect(requests.last?.origin == .location(lat: 51.17, lon: 71.45, label: "Адрес Б"))
        #expect(app.originCoordinate == GeoPoint(latitude: 51.17, longitude: 71.45))
    }

    @Test func journalRestoreCannotReuseAnotherWalksGeocodedOrigin() async throws {
        let backend = IntegrationBackend()
        let app = AppModel(defaults: storage(), backend: backend)
        app.sendMessage("Прогулка от Байтерека")
        try await waitUntil { !app.isResponding }
        let saved = try #require(app.journalEntries.first)
        app.startNewWalk()
        await backend.setHoldingGeocodes(true)
        app.saveOrigin("Адрес А")
        app.sendMessage("Другая прогулка")
        try await waitForBackend { await backend.geocodeQueries == ["Адрес А"] }
        try await backend.releaseGeocode(query: "Адрес А", lat: 51.16, lon: 71.42)
        try await waitUntil { !app.isResponding }
        app.restoreJournalEntry(id: saved.id)
        app.sendMessage("Продолжим первую прогулку")
        try await waitUntil { !app.isResponding }
        #expect(await backend.requests.last?.origin == .landmark("baiterek"))
    }

    @Test func slowRouteIdeaCannotReplaceANewerChatAnswer() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingIdeas(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.showPlan()
        try await waitForBackend { await backend.ideaCalls >= 1 }

        app.sendMessage("Новый поиск")
        try await waitUntil { !app.isResponding }
        #expect(app.currentPlan == nil)
        #expect(app.places.map(\.id) == ["osm:w42"])
        try await backend.releaseIdeas()
        try await Task.sleep(for: .milliseconds(10))

        #expect(app.currentPlan == nil)
        #expect(app.places.map(\.id) == ["osm:w42"])
        #expect(app.messages.last?.text == "Ответ настоящего API")
        #expect(!app.isLoadingPlan)
    }

    @Test func resetDiscardsRouteIdeaEvenWhenProviderReturnsAfterCancellation() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingIdeas(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.showPlan()
        try await waitForBackend { await backend.ideaCalls >= 1 }

        app.resetWalk()
        try await backend.releaseIdeas()
        try await Task.sleep(for: .milliseconds(10))

        #expect(app.screen == .home)
        #expect(app.currentPlan == nil)
        #expect(app.places.isEmpty)
        #expect(app.messages.isEmpty)
        #expect(!app.isLoadingPlan)
    }

    @Test func initialResultsRequestLoadsBackendWithoutAnExplicitNewQuery() async throws {
        let backend = IntegrationBackend()
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse() }

        app.showResults()
        try await waitForBackend { await backend.calls >= 1 }
        try await waitUntil { !app.isResponding }

        #expect(app.screen == .results)
        #expect(app.places.map(\.id) == ["osm:w42"])
        let requests = await backend.requests
        #expect(requests.first?.query.isEmpty == false)
        #expect(app.messages.isEmpty)
    }

    @Test func modelOwnedRouteRequestSurvivesCancellationOfItsCallerTask() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingRoutes(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.sendMessage("Найди парк")
        try await waitUntil { !app.isResponding }
        let place = try #require(app.places.first)
        let caller = Task { await app.loadRoutePreview(for: place) }
        try await waitForBackend { await backend.routeCalls >= 1 }

        caller.cancel()
        try await backend.releaseRoute()
        await caller.value
        try await waitUntil { app.routePreview != nil && !app.isLoadingRoute }

        #expect(app.routePreview?.placeID == "osm:w42")
        #expect(app.routePreview?.points.count == 2)
        #expect(app.routeError == nil)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw IntegrationWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func waitForBackend(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw IntegrationWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum IntegrationWaitError: Error { case timedOut, missingPendingRecommendation }

actor IntegrationBackend: SeruBackend {
    var failure = false
    var delay: Duration = .zero
    var calls = 0
    private(set) var requests: [APIRecommendRequest] = []
    private(set) var metadataCalls = 0
    private(set) var eventOffsets: [Int] = []
    private(set) var routeOrigins: [APIOrigin] = []
    private var responseJSON = IntegrationBackend.response
    private var eventPages: [Int: String] = [:]
    private var eventsFailure = false
    private var holdingRecommendations = false
    private var pendingRecommendations: [Int: CheckedContinuation<APIRecommendationResponse, any Error>] = [:]
    private var recommendationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var finishedRecommendations = 0
    private var finishedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var ideaCalls = 0
    private(set) var routeCalls = 0
    private(set) var geocodeQueries: [String] = []
    private var holdingIdeas = false
    private var holdingRoutes = false
    private var holdingGeocodes = false
    private var pendingIdeas: CheckedContinuation<[APIRouteIdea], any Error>?
    private var pendingRoute: CheckedContinuation<APIRouteToPlace, any Error>?
    private var pendingGeocodes: [String: CheckedContinuation<[APIGeocodeResult], any Error>] = [:]
    func setFailure(_ value: Bool) { failure = value }
    func setDelay(_ value: Duration) { delay = value }
    func setResponse(_ value: String) { responseJSON = value }
    func setEventPages(_ value: [Int: String]) { eventPages = value }
    func setEventsFailure(_ value: Bool) { eventsFailure = value }
    func setHoldingRecommendations(_ value: Bool) { holdingRecommendations = value }
    func setHoldingIdeas(_ value: Bool) { holdingIdeas = value }
    func setHoldingRoutes(_ value: Bool) { holdingRoutes = value }
    func setHoldingGeocodes(_ value: Bool) { holdingGeocodes = value }
    func releaseIdeas() throws {
        let result: [APIRouteIdea] = try decode(Self.ideaResponse)
        guard let continuation = pendingIdeas else { throw IntegrationWaitError.missingPendingRecommendation }
        pendingIdeas = nil
        continuation.resume(returning: result)
    }
    func releaseRoute() throws {
        let result: APIRouteToPlace = try decode(Self.routeResponse)
        guard let continuation = pendingRoute else { throw IntegrationWaitError.missingPendingRecommendation }
        pendingRoute = nil
        continuation.resume(returning: result)
    }
    func releaseGeocode(query: String, lat: Double, lon: Double) throws {
        guard let continuation = pendingGeocodes.removeValue(forKey: query) else { throw IntegrationWaitError.missingPendingRecommendation }
        continuation.resume(returning: [APIGeocodeResult(label: query, lat: lat, lon: lon, source: "openstreetmap")])
    }
    func releaseHeldRequests() {
        releaseAllRecommendations()
        pendingIdeas?.resume(throwing: CancellationError()); pendingIdeas = nil
        pendingRoute?.resume(throwing: CancellationError()); pendingRoute = nil
        for continuation in pendingGeocodes.values { continuation.resume(throwing: CancellationError()) }
        pendingGeocodes.removeAll()
    }
    func waitForRecommendation(_ count: Int) async {
        if calls >= count { return }
        await withCheckedContinuation { recommendationWaiters.append((count, $0)) }
    }
    func waitForFinishedRecommendations(_ count: Int) async {
        if finishedRecommendations >= count { return }
        await withCheckedContinuation { finishedWaiters.append((count, $0)) }
    }
    func releaseRecommendation(_ call: Int, response: String? = nil) throws {
        let result: APIRecommendationResponse = try decode(response ?? responseJSON)
        guard let continuation = pendingRecommendations.removeValue(forKey: call) else { throw IntegrationWaitError.missingPendingRecommendation }
        continuation.resume(returning: result)
    }
    func releaseAllRecommendations() {
        let result = Result<APIRecommendationResponse, any Error> { try decode(responseJSON) }
        for continuation in pendingRecommendations.values { continuation.resume(with: result) }
        pendingRecommendations.removeAll()
    }
    func metadata() async throws -> APIMetadata {
        metadataCalls += 1
        return try decode("{\"landmarks\":[{\"key\":\"baiterek\",\"name\":\"Байтерек\",\"lat\":51.128,\"lon\":71.430}],\"features\":{\"photo\":true}}")
    }
    func recommend(_ request: APIRecommendRequest, photo: Data?) async throws -> APIRecommendationResponse {
        calls += 1
        requests.append(request)
        let call = calls
        for (_, waiter) in recommendationWaiters.filter({ $0.0 <= calls }) { waiter.resume() }
        recommendationWaiters.removeAll { $0.0 <= calls }
        defer {
            finishedRecommendations += 1
            for (_, waiter) in finishedWaiters.filter({ $0.0 <= finishedRecommendations }) { waiter.resume() }
            finishedWaiters.removeAll { $0.0 <= finishedRecommendations }
        }
        if failure { throw APIError.network(.notConnectedToInternet) }
        if holdingRecommendations {
            // Deliberately ignore cancellation: AppModel must reject obsolete results itself.
            return try await withCheckedThrowingContinuation { pendingRecommendations[call] = $0 }
        }
        let sleep = delay
        if sleep != .zero { try? await Task.sleep(for: sleep) }
        return try decode(responseJSON)
    }
    func events(query: String?, price: String?, limit: Int, offset: Int) async throws -> APIEventPage {
        eventOffsets.append(offset)
        if eventsFailure { throw APIError.network(.notConnectedToInternet) }
        return try decode(eventPages[offset] ?? "{\"items\":[],\"total\":0,\"offset\":0,\"limit\":100,\"today\":\"2026-10-21\"}")
    }
    func route(poiID: String, origin: APIOrigin) async throws -> APIRouteToPlace {
        routeOrigins.append(origin)
        routeCalls += 1
        if holdingRoutes { return try await withCheckedThrowingContinuation { pendingRoute = $0 } }
        return try decode(Self.routeResponse)
    }
    func routeIdeas(origin: APIOrigin) async throws -> [APIRouteIdea] {
        ideaCalls += 1
        if holdingIdeas { return try await withCheckedThrowingContinuation { pendingIdeas = $0 } }
        return []
    }
    func geocode(query: String) async throws -> [APIGeocodeResult] {
        geocodeQueries.append(query)
        if holdingGeocodes { return try await withCheckedThrowingContinuation { pendingGeocodes[query] = $0 } }
        return []
    }
    private func decode<T: Decodable>(_ text: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(text.utf8)) }

    static let response = """
    {"request_id":"native-test","summary":"Ответ настоящего API","recommendations":[{"poi_id":"osm:w42","name":"Парк с сервера","category":"park","lat":51.129,"lon":71.431,"distance_m":500,"walk_distance_m":560,"travel_min":7,"why":"Рядом и тихо","what_to_do":"Прогуляться","visit_min":[10,20],"visit_suggested_min":15,"category_label":"Парк","category_detail":"park","icon":"trees","source":"poi_data","rating":null,"photo":null,"opening":{"label":"Часы уточняй"},"badges":["free"]}],"ideas":[],"notes":[],"route":null,"disclaimer":""}
    """

    static let newerResponse = """
    {"request_id":"newer","summary":"Новый ответ","recommendations":[{"poi_id":"osm:w99","name":"Новое место","category":"park","lat":51.13,"lon":71.44}],"route":null}
    """

    static let plannedResponse = """
    {"request_id":"native-plan","summary":"Маршрут с сервера","recommendations":[{"poi_id":"osm:w42","name":"Парк с сервера","category":"park","lat":51.129,"lon":71.431,"travel_min":7,"visit_suggested_min":15,"category_label":"Парк","icon":"trees","rating":null,"photo":null},{"poi_id":"osm:w43","name":"Аллея с сервера","category":"park","lat":51.13,"lon":71.432,"travel_min":3,"visit_suggested_min":20,"category_label":"Парк","icon":"trees"}],"used_context":{"time_budget_min":45,"location":{"source":"landmark","label":"Байтерек","lat":51.128,"lon":71.43}},"route":{"order":["osm:w42","osm:w43"],"total_min":45,"fits_budget":true,"summary":"Парк и аллея","legs":[{"from_id":"start","to_id":"osm:w42","travel_min":7,"distance_m":560,"geometry":"network","polyline":[[51.128,71.43],[51.129,71.431]]},{"from_id":"osm:w42","to_id":"osm:w43","travel_min":3,"distance_m":180,"geometry":"network","polyline":[[51.129,71.431],[51.13,71.432]]}]}}
    """

    static let routeResponse = """
    {"poi_id":"osm:w42","name":"Парк с сервера","mode":"walk","distance_m":560,"travel_min":7,"geometry":"network","polyline":[[51.128,71.43],[51.129,71.431]],"origin":{"lat":51.128,"lon":71.43},"origin_source":"landmark"}
    """
    static var ideaResponse: String { "[{\"key\":\"green\",\"title\":\"План из старого запроса\",\"response\":\(plannedResponse)}]" }

    static let datedEventPages = [
        0: """
        {"items":[{"id":"ticketon:today","title":"Утреннее событие","start":"2026-10-20T23:30:00Z","schedule_kind":"continuous","price_from":null,"image_url":"https://images.example/today.jpg","sources":[{"name":"ticketon","url":"https://ticketon.kz/event/today"}]},{"id":"sxodim:tomorrow","title":"Выступления","start":"2026-10-20","sessions":["2026-10-22T19:30:00+05:00","2026-10-24T19:30:00+05:00"],"schedule_kind":"sessions","price_from":0,"currency":"KZT"}],"total":3,"offset":0,"limit":100,"today":"2026-10-21"}
        """,
        2: """
        {"items":[{"id":"ticketon:today","title":"Повтор события","start":"2026-10-20T23:30:00Z"}],"total":3,"offset":2,"limit":100,"today":"2026-10-21"}
        """
    ]
}
