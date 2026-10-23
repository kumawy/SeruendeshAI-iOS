import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    let account: AccountStore
    var tab: AppTab = .walk
    private(set) var screen: WalkScreen = .home
    var query = ""
    var chatDraft = ""
    var chatAttachmentData: Data?
    var duration = 60 { didSet { if !applyingResponse { durationEdited = true; if duration != oldValue { contextChanged() } } } }
    var origin = "Байтерек"
    var onlyFree = false { didSet { if !applyingResponse && oldValue != onlyFree { contextChanged() } } }
    var withKids = false { didSet { if !applyingResponse && oldValue != withKids { contextChanged() } } }
    var theme: AppTheme = .system { didSet { defaults.set(theme.rawValue, forKey: "seru.theme") } }
    private(set) var places = Array(DemoData.places.prefix(3))
    private(set) var events = DemoData.events
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    private(set) var responseError: String?
    private(set) var isLoadingEvents = false
    private(set) var eventsError: String?
    private(set) var eventToday = Date.now
    private(set) var landmarks: [StartLandmark] = []
    private(set) var photoSearchAvailable = false
    private(set) var originCoordinate: GeoPoint?
    private(set) var routePreview: RoutePreview?
    private(set) var isLoadingRoute = false
    private(set) var routeError: String?
    private(set) var currentPlan: WalkRoute?
    private(set) var isLoadingPlan = false
    private(set) var planError: String?
    var toast: String?
    var mascotFeedback: MascotFeedback?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let backend: (any SeruBackend)?
    @ObservationIgnored private var history: [WalkScreen] = []
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var planRequestID = UUID()
    @ObservationIgnored private var contextRevision = 0
    @ObservationIgnored private var responseID = UUID()
    @ObservationIgnored private var routeRequestID = UUID()
    @ObservationIgnored private var routeTarget: Place?
    @ObservationIgnored private var pendingRequest: (text: String, photo: Data?, reply: Bool)?
    @ObservationIgnored private var resolvedOrigin: APIOrigin?
    @ObservationIgnored private var hasBootstrapped = false
    @ObservationIgnored private var durationEdited = false
    @ObservationIgnored private var applyingResponse = false
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var pendingGuestImportIDs: [String: Set<String>] = [:]
    private var placeCatalog: [String: Place] = [:]
    private var guestPlaceSnapshots: [String: Place] = [:]
    private var routeCatalog: [String: WalkRoute] = [:]
    private var savedIDs: Set<String> = []
    private var savedRouteIDs: Set<String> = []
    private var savedEventIDs: Set<String> = []
    private var savedEventSnapshots: [String: CityEvent] = [:]
    var usesBackend: Bool { backend != nil }

    init(defaults: UserDefaults = .standard, backend: (any SeruBackend)? = nil, accountBackend: (any SeruAccountBackend)? = nil) {
        self.defaults = defaults; self.backend = backend
        account = AccountStore(backend: accountBackend ?? (backend as? any SeruAccountBackend))
        theme = AppTheme(rawValue: defaults.string(forKey: "seru.theme") ?? "dark") ?? .dark
        origin = defaults.string(forKey: "seru.origin") ?? "Байтерек"
        if backend != nil {
            places = []; events = []
            let cached = defaults.data(forKey: "seru.live.placeSnapshots").flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
            placeCatalog = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            let routes = defaults.data(forKey: "seru.live.routeSnapshots").flatMap { try? JSONDecoder().decode([WalkRoute].self, from: $0) } ?? []
            routeCatalog = Dictionary(routes.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            savedIDs = Set(defaults.stringArray(forKey: "seru.live.saved.places") ?? [])
            savedRouteIDs = Set(defaults.stringArray(forKey: "seru.live.saved.routes") ?? [])
            guestPlaceSnapshots = placeCatalog.filter { savedIDs.contains($0.key) }
        } else {
            placeCatalog = Dictionary(uniqueKeysWithValues: DemoData.places.map { ($0.id, $0) })
            routeCatalog = Dictionary(uniqueKeysWithValues: DemoData.routes.map { ($0.id, $0) })
            savedIDs = Set(defaults.stringArray(forKey: "seru.saved.places") ?? ["garden", "coffee", "river"])
            savedRouteIDs = Set(defaults.stringArray(forKey: "seru.saved.routes") ?? ["green-heart", "evening-river"])
            photoSearchAvailable = true
        }
        savedEventIDs = Set((defaults.string(forKey: "seruendesh.savedEventIDs") ?? "").split(separator: "|").map(String.init))
        let eventSnapshots = defaults.data(forKey: "seruendesh.savedEventSnapshots")
            .flatMap { try? JSONDecoder().decode([CityEvent].self, from: $0) } ?? []
        savedEventSnapshots = Dictionary(eventSnapshots.filter { savedEventIDs.contains($0.id) }.map { ($0.id, $0) },
                                         uniquingKeysWith: { _, new in new })
        cacheSavedEvents()
    }

    var guestSavedPlaces: [Place] { usesBackend ? savedIDs.sorted().compactMap { guestPlaceSnapshots[$0] } : DemoData.places.filter { savedIDs.contains($0.id) } }
    var savedPlaces: [Place] { account.user == nil ? guestSavedPlaces : account.savedPlaces }
    var savedRoutes: [WalkRoute] { usesBackend ? savedRouteIDs.sorted().compactMap { routeCatalog[$0] } : DemoData.routes.filter { savedRouteIDs.contains($0.id) } }
    var savedEvents: [CityEvent] { savedEventIDs.sorted().compactMap { savedEventSnapshots[$0] } }
    func isSaved(_ place: Place) -> Bool { account.user == nil ? savedIDs.contains(place.id) : account.isSaved(place) }
    func isRouteSaved(_ route: WalkRoute) -> Bool { savedRouteIDs.contains(route.id) }
    func isEventSaved(_ event: CityEvent) -> Bool { savedEventIDs.contains(event.id) }
    func place(id: String) -> Place {
        placeCatalog[id] ?? account.savedPlaces.first(where: { $0.id == id }) ?? Place(id: id, name: "Место недоступно", category: "", subtitle: "", imageAsset: "",
            travelMinutes: 0, visitMinutes: 0, distance: "", hours: "Часы уточняй", rating: "", reason: "Обнови рекомендации.",
            symbol: "mappin", isFree: false, isChildFriendly: false, isLive: usesBackend)
    }
    func route(id: String) -> WalkRoute? { routeCatalog[id] }

    func emitMascotFeedback(kind: MascotFeedback.Kind, message: String) {
        mascotFeedback = MascotFeedback(kind: kind, message: message)
    }

    /// A timeout belonging to an earlier reaction must never dismiss a newer one.
    func dismissMascotFeedback(id: UUID) {
        guard mascotFeedback?.id == id else { return }
        mascotFeedback = nil
    }

    private func dismissSavedFeedback() {
        if mascotFeedback?.kind == .saved { mascotFeedback = nil }
    }

    func toggleSaved(_ place: Place) {
        if account.user != nil {
            let wasSaved = account.isSaved(place)
            account.toggleSaved(place)
            if !wasSaved && account.isSaved(place) {
                if toast == "Место удалено из избранного" { toast = nil }
                emitMascotFeedback(kind: .saved, message: "Место добавлено в избранное")
            } else if wasSaved && !account.isSaved(place) {
                dismissSavedFeedback()
            }
            return
        }
        placeCatalog[place.id] = place
        if savedIDs.contains(place.id) {
            savedIDs.remove(place.id); guestPlaceSnapshots.removeValue(forKey: place.id)
        } else {
            savedIDs.insert(place.id); guestPlaceSnapshots[place.id] = place
        }
        defaults.set(savedIDs.sorted(), forKey: usesBackend ? "seru.live.saved.places" : "seru.saved.places")
        persistSnapshots()
        if savedIDs.contains(place.id) {
            if toast == "Место удалено из избранного" { toast = nil }
            emitMascotFeedback(kind: .saved, message: "Место сохранено")
        } else {
            dismissSavedFeedback()
            toast = "Место удалено из избранного"
        }
    }
    func importGuestSavedPlaces() async {
        guard let userID = account.user?.id else { return }
        let places = guestSavedPlaces
        pendingGuestImportIDs[userID, default: []].formUnion(places.map(\.id))
        let imported = await account.importGuestPlaces(places)
        guard account.user?.id == userID else { return }
        removeImportedGuestIDs(Set(imported), userID: userID)
    }
    func retryAccountSavedChanges() async {
        guard let userID = account.user?.id else { return }
        await account.retrySavedChanges()
        guard account.user?.id == userID else { return }
        let confirmed = account.confirmedSavedPlaceIDs
        removeImportedGuestIDs((pendingGuestImportIDs[userID] ?? []).intersection(confirmed), userID: userID)
    }
    private func removeImportedGuestIDs(_ ids: Set<String>, userID: String) {
        savedIDs.subtract(ids)
        for id in ids { guestPlaceSnapshots.removeValue(forKey: id) }
        pendingGuestImportIDs[userID]?.subtract(ids)
        defaults.set(savedIDs.sorted(), forKey: "seru.live.saved.places")
        persistSnapshots()
    }
    func toggleSavedRoute(_ route: WalkRoute) {
        routeCatalog[route.id] = route
        if savedRouteIDs.contains(route.id) { savedRouteIDs.remove(route.id) } else { savedRouteIDs.insert(route.id) }
        defaults.set(savedRouteIDs.sorted(), forKey: usesBackend ? "seru.live.saved.routes" : "seru.saved.routes")
        persistSnapshots()
        if savedRouteIDs.contains(route.id) {
            if toast == "План удалён из избранного" { toast = nil }
            emitMascotFeedback(kind: .saved, message: "План сохранён")
        } else {
            dismissSavedFeedback()
            toast = "План удалён из избранного"
        }
    }
    func toggleSavedEvent(_ event: CityEvent) {
        if savedEventIDs.contains(event.id) {
            savedEventIDs.remove(event.id)
            savedEventSnapshots.removeValue(forKey: event.id)
        } else {
            savedEventIDs.insert(event.id)
            savedEventSnapshots[event.id] = event
        }
        defaults.set(savedEventIDs.sorted().joined(separator: "|"), forKey: "seruendesh.savedEventIDs")
        persistSavedEvents()
        if savedEventIDs.contains(event.id) {
            emitMascotFeedback(kind: .saved, message: "Событие сохранено")
        } else {
            dismissSavedFeedback()
        }
    }
    private func cacheSavedEvents() {
        for event in events where savedEventIDs.contains(event.id) {
            savedEventSnapshots[event.id] = event
        }
        persistSavedEvents()
    }
    private func persistSavedEvents() {
        if let data = try? JSONEncoder().encode(savedEvents) {
            defaults.set(data, forKey: "seruendesh.savedEventSnapshots")
        }
    }
    private func persistSnapshots() {
        guard usesBackend else { return }
        let routes = savedRouteIDs.compactMap { routeCatalog[$0] }
        let needed = savedIDs.union(routes.flatMap(\.placeIDs))
        if let data = try? JSONEncoder().encode(needed.compactMap { guestPlaceSnapshots[$0] ?? placeCatalog[$0] }) { defaults.set(data, forKey: "seru.live.placeSnapshots") }
        if let data = try? JSONEncoder().encode(routes) { defaults.set(data, forKey: "seru.live.routeSnapshots") }
    }

    func bootstrap() async {
        guard let backend, !hasBootstrapped else { return }
        hasBootstrapped = true
        async let feed: Void = refreshEvents()
        do {
            let meta = try await backend.metadata()
            landmarks = meta.landmarks.map { StartLandmark(id: $0.key, name: $0.name, coordinate: GeoPoint(latitude: $0.lat, longitude: $0.lon)) }
            photoSearchAvailable = meta.features.photo
            account.passwordResetAvailable = meta.features.passwordResetEmail
            if let selected = matchingLandmark() { originCoordinate = selected.coordinate }
        } catch is CancellationError { hasBootstrapped = false }
        catch { toast = error.localizedDescription }
        await feed
    }
    func refreshEvents() async {
        guard let backend, !isLoadingEvents else { return }
        isLoadingEvents = true; eventsError = nil
        defer { isLoadingEvents = false }
        do {
            var rows: [CityEvent] = []; var offset = 0
            repeat {
                let page = try await backend.events(query: nil, price: nil, limit: 100, offset: offset)
                try Task.checkCancellation()
                let today = BackendMapping.date(page.today) ?? Date.now
                eventToday = today
                rows.append(contentsOf: page.items.map { BackendMapping.event($0, today: today) })
                offset += page.items.count
                if page.items.isEmpty || offset >= page.total { break }
            } while offset < 1000
            var seen = Set<String>()
            events = rows.filter { seen.insert($0.id).inserted }
            cacheSavedEvents()
        } catch is CancellationError { }
        catch { eventsError = error.localizedDescription }
    }

    func showResults(for text: String? = nil) {
        if let text { query = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if usesBackend {
            if text != nil || needsRefresh || places.isEmpty {
                requestRecommendation(query.isEmpty ? "Куда пойти на прогулку?" : query, photo: nil, reply: false)
            }
        } else { refreshDemoPlaces() }
        navigate(to: .results)
    }
    func showResults(placeIDs: [String]) {
        places = placeIDs.compactMap { placeCatalog[$0] }
        navigate(to: .results)
    }
    func showPlace(_ place: Place) { placeCatalog[place.id] = place; navigate(to: .detail(place.id)) }
    func showRoute(_ place: Place) {
        placeCatalog[place.id] = place
        navigate(to: .route(place.id))
        if usesBackend { Task { await loadRoutePreview(for: place) } }
    }
    func showFullRoute(_ route: WalkRoute) { routeCatalog[route.id] = route; navigate(to: .route("walk:\(route.id)")) }
    var routeForCurrentScreen: WalkRoute? {
        guard case .route(let id) = screen, id.hasPrefix("walk:") else { return nil }
        return routeCatalog[String(id.dropFirst(5))]
    }
    func showPlan() {
        navigate(to: .plan)
        if usesBackend && currentPlan == nil { Task { await retryPlan() } }
    }
    func retryPlan() async {
        guard let backend else { return }
        if isLoadingPlan { await planTask?.value; return }
        planRequestID = UUID(); let token = planRequestID
        isLoadingPlan = true; planError = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.planRequestID == token { self.isLoadingPlan = false; self.planTask = nil } }
            do {
                let ideas = try await backend.routeIdeas(origin: self.resolveOrigin())
                guard !Task.isCancelled, self.planRequestID == token else { return }
                guard let idea = ideas.first(where: { $0.response.route != nil }) else {
                    self.planError = "Пока нет готового маршрута. Попробуй уточнить пожелания в чате."
                    return
                }
                self.apply(idea.response, reply: false, planTitle: idea.title)
                self.emitMascotFeedback(kind: .ready, message: "План прогулки готов")
            } catch {
                if self.planRequestID == token && !(error is CancellationError) && !Task.isCancelled {
                    self.planError = error.localizedDescription
                }
            }
        }
        planTask = task
        await task.value
    }
    func showChat() { navigate(to: .chat) }
    func goBack() { screen = history.popLast() ?? .home }

    func resetWalk() {
        contextChanged()
        routeRequestID = UUID(); routePreview = nil; isLoadingRoute = false; routeError = nil; routeTarget = nil
        currentPlan = nil; planError = nil
        history.removeAll(); screen = .home; query = ""; chatDraft = ""; chatAttachmentData = nil; messages.removeAll()
        applyingResponse = true; duration = 60; onlyFree = false; withKids = false; applyingResponse = false
        durationEdited = false; needsRefresh = false
        places = usesBackend ? [] : Array(DemoData.places.prefix(3))
    }
    func saveOrigin(_ value: String) {
        guard value != origin else { return }
        contextChanged()
        origin = value; resolvedOrigin = nil; originCoordinate = matchingLandmark()?.coordinate
        routePreview = nil; routeRequestID = UUID(); isLoadingRoute = false; currentPlan = nil; needsRefresh = true
        defaults.set(value, forKey: "seru.origin")
    }
    private func contextChanged() {
        contextRevision += 1; needsRefresh = true
        cancelResponse()
        planRequestID = UUID(); planTask?.cancel(); planTask = nil; isLoadingPlan = false; planError = nil; currentPlan = nil
        routeRequestID = UUID(); routeTask?.cancel(); routeTask = nil; isLoadingRoute = false; routeError = nil; routePreview = nil
    }
    private func matchingLandmark() -> StartLandmark? {
        let name = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        return landmarks.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.id.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
    private func resolveOrigin() async throws -> APIOrigin {
        let selectedName = origin
        let revision = contextRevision
        if let resolvedOrigin { return resolvedOrigin }
        if let selected = matchingLandmark() {
            originCoordinate = selected.coordinate
            return .landmark(selected.id)
        }
        let aliases = ["Байтерек": "baiterek", "ЭКСПО": "expo", "Хан Шатыр": "khan_shatyr", "Mega Silk Way": "mega_silk_way", "Ботанический сад": "botanical_garden"]
        if let key = aliases[origin] { return .landmark(key) }
        guard let backend else { return .landmark("baiterek") }
        let results = try await backend.geocode(query: selectedName)
        guard revision == contextRevision, origin == selectedName, !Task.isCancelled else { throw CancellationError() }
        guard let first = results.first else { throw APIError.invalidLocation }
        let point = GeoPoint(latitude: (first.lat * 1000).rounded() / 1000, longitude: (first.lon * 1000).rounded() / 1000)
        guard point.isValid else { throw APIError.invalidLocation }
        originCoordinate = point
        let resolved = APIOrigin.location(lat: point.latitude, lon: point.longitude, label: selectedName)
        resolvedOrigin = resolved
        return resolved
    }

    func sendMessage(_ text: String, attachment: Data? = nil) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!input.isEmpty || attachment != nil), !isResponding else { return }
        let trimmed = input.isEmpty ? "Что за место на фото?" : input
        query = trimmed
        messages.append(ChatMessage(role: .user, text: trimmed, attachmentData: attachment))
        if usesBackend { requestRecommendation(trimmed, photo: attachment, reply: true) }
        else {
            isResponding = true
            responseTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.refreshDemoPlaces()
                let reply = self.places.isEmpty ? "Подходящих мест нет. Увеличь время или измени фильтры." : "Подобрал места рядом с \(self.origin). Посмотри на карте."
                self.messages.append(ChatMessage(role: .assistant, text: reply, showsRoute: !self.places.isEmpty))
                self.isResponding = false
            }
        }
    }
    private func requestRecommendation(_ text: String, photo: Data?, reply: Bool) {
        guard let backend, !isResponding else { return }
        contextChanged()
        responseID = UUID(); let token = responseID
        pendingRequest = (text, photo, reply)
        responseError = nil; isResponding = true
        responseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let start = try await self.resolveOrigin()
                let request = APIRecommendRequest(query: text, origin: start,
                    duration: self.durationEdited ? self.duration : nil, withKids: self.withKids, onlyFree: self.onlyFree)
                let response = try await backend.recommend(request, photo: photo)
                guard !Task.isCancelled, self.responseID == token else { return }
                self.apply(response, reply: reply)
                self.isResponding = false; self.responseTask = nil; self.pendingRequest = nil
                if self.currentPlan != nil || !self.places.isEmpty {
                    self.emitMascotFeedback(kind: .ready,
                        message: self.currentPlan == nil ? "Места подобраны" : "План прогулки готов")
                }
            } catch {
                guard self.responseID == token else { return }
                self.isResponding = false; self.responseTask = nil
                if !(error is CancellationError) && !Task.isCancelled { self.responseError = error.localizedDescription }
            }
        }
    }
    func retryResponse() {
        guard let pendingRequest, !isResponding else { return }
        requestRecommendation(pendingRequest.text, photo: pendingRequest.photo, reply: pendingRequest.reply)
    }
    private func apply(_ response: APIRecommendationResponse, reply: Bool, planTitle: String? = nil) {
        let mapped = (response.recommendations + response.ideas).map(BackendMapping.place)
        for place in mapped { placeCatalog[place.id] = place }
        places = mapped; needsRefresh = false
        if let context = response.usedContext {
            applyingResponse = true; duration = context.timeBudgetMin; applyingResponse = false
            if let location = context.location, location.source != "none" {
                let point = GeoPoint(latitude: location.lat, longitude: location.lon)
                if point.isValid {
                    originCoordinate = point; origin = location.label
                    resolvedOrigin = .location(lat: point.latitude, lon: point.longitude, label: location.label)
                }
            }
        }
        currentPlan = response.route.map { BackendMapping.route($0, response: response, places: mapped, title: planTitle) }
        if currentPlan?.originLabel == nil { currentPlan?.originLabel = origin }
        if let currentPlan { routeCatalog[currentPlan.id] = currentPlan }
        if reply {
            let parts = ([response.summary] + response.notes + [response.disclaimer]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            var seen = Set<String>()
            let unique = parts.filter { seen.insert($0).inserted }
            let answer = unique.isEmpty ? "Уточни, что хочется увидеть и откуда начнём." : unique.joined(separator: "\n\n")
            messages.append(ChatMessage(role: .assistant, text: answer, showsRoute: !mapped.isEmpty,
                placeIDs: mapped.map(\.id), routeID: currentPlan?.id))
        }
    }
    func sendChatDraft() -> Bool {
        let input = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!input.isEmpty || chatAttachmentData != nil), !isResponding else { return false }
        sendMessage(input, attachment: chatAttachmentData)
        chatDraft = ""; chatAttachmentData = nil; showChat(); return true
    }
    func cancelResponse() {
        responseID = UUID(); responseTask?.cancel(); responseTask = nil
        isResponding = false; responseError = nil; pendingRequest = nil
        if mascotFeedback?.kind == .ready { mascotFeedback = nil }
    }

    func loadRoutePreview(for place: Place) async {
        guard let backend, place.isLive else { return }
        if routePreview?.placeID == place.id { return }
        if isLoadingRoute && routeTarget?.id == place.id { await routeTask?.value; return }
        routeTask?.cancel()
        routeTarget = place; routeRequestID = UUID(); let token = routeRequestID
        routePreview = nil; isLoadingRoute = true; routeError = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.routeRequestID == token { self.isLoadingRoute = false; self.routeTask = nil } }
            do {
                let result = try await backend.route(poiID: place.id, origin: self.resolveOrigin())
                guard !Task.isCancelled, self.routeRequestID == token else { return }
                self.routePreview = RoutePreview(placeID: result.poiID, travelMinutes: result.travelMin, distanceMeters: result.distanceM,
                    points: BackendMapping.points(result.polyline), geometry: result.geometry,
                    origin: result.origin.map { GeoPoint(latitude: $0.lat, longitude: $0.lon) }, originLabel: self.origin)
                self.emitMascotFeedback(kind: .ready, message: "Маршрут готов")
            } catch {
                if self.routeRequestID == token && !(error is CancellationError) && !Task.isCancelled {
                    self.routeError = error.localizedDescription
                }
            }
        }
        routeTask = task
        await task.value
    }
    func retryRoute() async {
        guard let routeTarget else { return }
        routePreview = nil
        await loadRoutePreview(for: routeTarget)
    }
    private func navigate(to destination: WalkScreen) {
        tab = .walk
        guard screen != destination else { return }
        history.append(screen); screen = destination
    }
    private func refreshDemoPlaces() {
        var filtered = DemoData.places.prefix(3).filter {
            $0.travelMinutes + $0.visitMinutes <= duration && (!onlyFree || $0.isFree) && (!withKids || $0.isChildFriendly)
        }
        let text = query.lowercased()
        if text.contains("без кофе") { filtered.removeAll { $0.id == "coffee" } }
        if text.contains("коф") && !text.contains("без кофе") { filtered.sort { ($0.id == "coffee" ? 0 : 1) < ($1.id == "coffee" ? 0 : 1) } }
        else if text.contains("ближе") { filtered.sort { $0.travelMinutes < $1.travelMinutes } }
        places = filtered
    }
}
