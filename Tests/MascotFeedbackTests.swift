import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor
struct MascotFeedbackTests {
    private func storage() -> UserDefaults {
        UserDefaults(suiteName: "seru.mascot-feedback.tests.\(UUID().uuidString)")!
    }

    @Test func repeatedFeedbackIsANewEventAndAnOldDismissalCannotHideIt() throws {
        let app = AppModel(defaults: storage())
        app.emitMascotFeedback(kind: .photoError, message: "Не удалось открыть фото")
        let first = try #require(app.mascotFeedback)
        app.emitMascotFeedback(kind: .photoError, message: first.message)
        let second = try #require(app.mascotFeedback)

        #expect(second.id != first.id)
        app.dismissMascotFeedback(id: first.id)
        #expect(app.mascotFeedback == second)
        app.dismissMascotFeedback(id: second.id)
        #expect(app.mascotFeedback == nil)
    }

    @Test func aPlaceSaveReactsOnlyWhenItBecomesSaved() throws {
        let app = AppModel(defaults: storage())
        let place = DemoData.places[0]
        if app.isSaved(place) { app.toggleSaved(place) }
        app.mascotFeedback = nil

        app.toggleSaved(place)
        let feedback = try #require(app.mascotFeedback)
        #expect(feedback.kind == .saved)
        #expect(app.isSaved(place))
        #expect(app.toast == nil)

        app.toggleSaved(place)
        #expect(!app.isSaved(place))
        #expect(app.mascotFeedback == nil)
        #expect(app.toast == "Место удалено из избранного")

        app.toast = "Не удалось открыть карту"
        app.toggleSaved(place)
        #expect(app.toast == "Не удалось открыть карту")
    }

    @Test func eventAndRouteRemovalNeverCreatesASavedReaction() throws {
        let app = AppModel(defaults: storage())
        let event = try #require(app.events.first)
        let route = DemoData.featuredRoute
        if app.isEventSaved(event) { app.toggleSavedEvent(event) }
        if app.isRouteSaved(route) { app.toggleSavedRoute(route) }
        app.mascotFeedback = nil

        app.toggleSavedEvent(event)
        #expect(app.mascotFeedback?.kind == .saved)
        app.toggleSavedEvent(event)
        #expect(app.mascotFeedback == nil)

        app.toggleSavedRoute(route)
        #expect(app.mascotFeedback?.kind == .saved)
        app.toggleSavedRoute(route)
        #expect(app.mascotFeedback == nil)
    }

    @Test func removalPreservesAnUnrelatedPhotoErrorReaction() {
        let app = AppModel(defaults: storage())
        let place = DemoData.places[0]
        if !app.isSaved(place) { app.toggleSaved(place) }
        app.emitMascotFeedback(kind: .photoError, message: "Фото слишком большое")
        let photoError = app.mascotFeedback

        app.toggleSaved(place)

        #expect(!app.isSaved(place))
        #expect(app.mascotFeedback == photoError)
    }

    @Test func startupAndEmptyRecommendationDoNotAnnounceReady() async throws {
        let backend = IntegrationBackend()
        await backend.setResponse(#"{"summary":"Ничего не найдено","recommendations":[],"ideas":[],"route":null}"#)
        let app = AppModel(defaults: storage(), backend: backend)
        #expect(app.mascotFeedback == nil)
        await app.bootstrap()
        #expect(app.mascotFeedback == nil)

        app.sendMessage("Найди место")
        try await waitUntil { !app.isResponding }
        #expect(app.responseError == nil)
        #expect(app.places.isEmpty)
        #expect(app.mascotFeedback == nil)
    }

    @Test func realRecommendationCompletionEmitsOneReadyAndOpeningItAgainDoesNot() async throws {
        let app = AppModel(defaults: storage(), backend: IntegrationBackend())
        app.sendMessage("Найди парк")
        try await waitUntil { !app.isResponding }
        let feedback = try #require(app.mascotFeedback)
        #expect(feedback.kind == .ready)
        #expect(!app.places.isEmpty)

        app.dismissMascotFeedback(id: feedback.id)
        app.showResults(placeIDs: app.places.map(\.id))
        #expect(app.mascotFeedback == nil)
    }

    @Test func failedRecommendationAndUnavailablePlanDoNotAnnounceReady() async throws {
        let backend = IntegrationBackend()
        await backend.setFailure(true)
        let app = AppModel(defaults: storage(), backend: backend)
        app.sendMessage("Найди парк")
        try await waitUntil { !app.isResponding }
        #expect(app.responseError != nil)
        #expect(app.mascotFeedback == nil)

        await app.retryPlan()
        #expect(app.planError != nil)
        #expect(app.currentPlan == nil)
        #expect(app.mascotFeedback == nil)
    }

    @Test func canceledRecommendationCannotReplaceANewerReaction() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingRecommendations(true)
        let app = AppModel(defaults: storage(), backend: backend)
        app.sendMessage("Найди парк")
        await backend.waitForRecommendation(1)
        app.cancelResponse()
        app.emitMascotFeedback(kind: .photoError, message: "Выбери другое фото")
        let newer = app.mascotFeedback

        try await backend.releaseRecommendation(1)
        await backend.waitForFinishedRecommendations(1)
        for _ in 0..<10 { await Task.yield() }

        #expect(app.mascotFeedback == newer)
        #expect(app.places.isEmpty)
    }

    @Test func completedRouteReactsOnceAndCachedRouteDoesNotReactAgain() async throws {
        let app = AppModel(defaults: storage(), backend: IntegrationBackend())
        app.sendMessage("Найди парк")
        try await waitUntil { !app.isResponding }
        app.mascotFeedback = nil
        let place = try #require(app.places.first)

        await app.loadRoutePreview(for: place)
        let feedback = try #require(app.mascotFeedback)
        #expect(feedback.kind == .ready)
        #expect(app.routePreview?.placeID == place.id)
        app.dismissMascotFeedback(id: feedback.id)
        await app.loadRoutePreview(for: place)
        #expect(app.mascotFeedback == nil)
    }

    @Test func completedPlanReactsOnlyAfterTheBackendReturns() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingIdeas(true)
        let app = AppModel(defaults: storage(), backend: backend)
        let request = Task { await app.retryPlan() }
        try await waitUntil { app.isLoadingPlan }
        #expect(app.mascotFeedback == nil)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while await backend.ideaCalls == 0 && clock.now < deadline { await Task.yield() }
        #expect(await backend.ideaCalls > 0)

        try await backend.releaseIdeas()
        await request.value

        #expect(app.currentPlan != nil)
        #expect(app.mascotFeedback?.kind == .ready)
        #expect(!app.isLoadingPlan)
    }

    @Test func accountSaveReactionDoesNotClaimOrHideServerSynchronization() async throws {
        let backend = FeedbackAccountBackend()
        let app = AppModel(defaults: storage(), accountBackend: backend)
        #expect(await app.account.signIn(email: "member@example.com", password: "password"))
        let place = DemoData.places[0]

        app.toggleSaved(place)
        let feedback = try #require(app.mascotFeedback)
        #expect(feedback.kind == .saved)
        #expect(feedback.message == "Место добавлено в избранное")
        #expect(app.account.isSyncing)
        #expect(app.account.confirmedSavedPlaceIDs.isEmpty)
        await backend.waitForSave()
        await backend.failSave()
        try await waitUntil { !app.account.isSyncing }

        #expect(!app.isSaved(place))
        #expect(app.account.syncError != nil)
        #expect(app.mascotFeedback == feedback)
    }

    @Test func accountRemovalDismissesThePendingSavedReactionBeforeSynchronizationFinishes() async throws {
        let backend = FeedbackAccountBackend()
        let app = AppModel(defaults: storage(), accountBackend: backend)
        #expect(await app.account.signIn(email: "member@example.com", password: "password"))
        let place = DemoData.places[0]
        app.toggleSaved(place)
        #expect(app.mascotFeedback?.kind == .saved)
        await backend.waitForSave()

        app.toggleSaved(place)

        #expect(!app.isSaved(place))
        #expect(app.mascotFeedback == nil)
        await backend.failSave()
        try await waitUntil { !app.account.isSyncing }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}

private actor FeedbackAccountBackend: SeruAccountBackend {
    private let user = AccountUser(id: "member", email: "member@example.com", name: "Участник")
    private var save: CheckedContinuation<APISavedPlace, any Error>?
    private var saveWaiter: CheckedContinuation<Void, Never>?

    func currentUser() async throws -> AccountUser? { user }
    func signIn(email: String, password: String) async throws -> AccountUser { user }
    func register(name: String, email: String, password: String) async throws -> AccountUser { user }
    func signOut() async throws { }
    func deleteAccount() async throws { }
    func requestPasswordReset(email: String) async throws { }
    func confirmPasswordReset(token: String, password: String) async throws -> AccountUser { user }
    func savedPlaces() async throws -> [APISavedPlace] { [] }
    func removeSavedPlace(id: String) async throws { }
    func savePlace(id: String, snapshot: SavedPlaceSnapshot) async throws -> APISavedPlace {
        try await withCheckedThrowingContinuation { continuation in
            save = continuation
            saveWaiter?.resume()
            saveWaiter = nil
        }
    }
    func waitForSave() async {
        guard save == nil else { return }
        await withCheckedContinuation { saveWaiter = $0 }
    }
    func failSave() {
        save?.resume(throwing: APIError.network(.notConnectedToInternet))
        save = nil
    }
}
