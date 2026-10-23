import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor
struct WalkRecoveryTests {
    private func storage() -> UserDefaults { UserDefaults(suiteName: "seru.recovery.tests.\(UUID().uuidString)")! }

    // Missing draft/session persistence must lose the restored text, photo and preferences.
    @Test func relaunchRestoresDraftPhotoAndWalkPreferences() {
        let defaults = storage()
        let app = AppModel(defaults: defaults)
        app.duration = 45
        app.onlyFree = true
        app.withKids = true
        app.saveOrigin("Ботанический сад")
        app.chatDraft = "Давай к воде"
        app.chatAttachmentData = Data([1, 2, 3, 4])

        let reopened = AppModel(defaults: defaults)
        #expect(reopened.chatDraft == "Давай к воде")
        #expect(reopened.chatAttachmentData == Data([1, 2, 3, 4]))
        #expect(reopened.duration == 45)
        #expect(reopened.onlyFree)
        #expect(reopened.withKids)
        #expect(reopened.origin == "Ботанический сад")
    }

    // Reusing the static featured route ignores filters and the total time budget.
    @Test func localPlanFitsDurationAndEveryStopRespectsFilters() {
        let app = AppModel(defaults: storage())
        app.duration = 60
        app.onlyFree = true
        app.withKids = true
        app.showResults(for: "Прогулка")
        app.showPlan()
        #expect(app.currentPlan != nil)
        #expect((app.currentPlan?.duration ?? 1000) <= 60)
        #expect(app.currentPlan?.originLabel == "Байтерек")
        #expect(app.currentPlan?.placeIDs.isEmpty == false)
        #expect(app.currentPlan?.placeIDs.allSatisfy { app.place(id: $0).isFree && app.place(id: $0).isChildFriendly } == true)
    }

    // A transient metadata failure must not permanently disable landmarks/features.
    @Test func bootstrapRetriesMetadataAfterTransientFailure() async {
        let backend = RecoveringMetadataBackend()
        let app = AppModel(defaults: storage(), backend: backend)
        await app.bootstrap()
        #expect(app.landmarks.isEmpty)
        await app.bootstrap()
        #expect(app.landmarks.map(\.id) == ["baiterek"])
        #expect(app.photoSearchAvailable)
    }

    // Canceling on changed preferences must explain why the submitted request has no answer.
    @Test func changingFilterExplainsInterruptedReply() async throws {
        let backend = IntegrationBackend()
        await backend.setHoldingRecommendations(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.sendMessage("Хочу гулять")
        await backend.waitForRecommendation(1)
        app.onlyFree = true
        app.duration = 90
        app.withKids = true
        #expect(!app.isResponding)
        #expect(app.responseError?.isEmpty == false)
        #expect(app.messages.first?.text == "Хочу гулять")
    }
    @Test func oldAnswerRestoresItsOwnPlacesPlanAndPreferences() async throws {
        let app = AppModel(defaults: storage())
        app.duration = 60
        app.onlyFree = true
        app.sendMessage("Тихая прогулка")
        try await waitForReply(app)
        let oldAnswer = try #require(app.messages.last)
        let oldIDs = app.places.map(\.id)
        let oldPlan = app.currentPlan
        app.onlyFree = false
        app.duration = 90
        app.saveOrigin("Ботанический сад")
        app.sendMessage("Кофе")
        try await waitForReply(app)

        app.openRecommendation(oldAnswer)
        #expect(app.onlyFree)
        #expect(app.duration == 60)
        #expect(app.origin == "Байтерек")
        #expect(app.places.map(\.id) == oldIDs)
        #expect(app.currentPlan == oldPlan)
        #expect(oldAnswer.snapshot?.context.onlyFree == true)
    }

    @Test func newWalkClearsAnInterruptedRequestsErrorAndRetry() async {
        let backend = IntegrationBackend()
        await backend.setHoldingRecommendations(true)
        let app = AppModel(defaults: storage(), backend: backend)
        defer { app.cancelResponse(); Task { await backend.releaseHeldRequests() } }
        app.sendMessage("Старая прогулка")
        await backend.waitForRecommendation(1)
        app.startNewWalk()
        #expect(app.responseError == nil)
        #expect(app.messages.isEmpty)
        app.retryResponse()
        await Task.yield()
        #expect(!app.isResponding)
        #expect(await backend.requests.count == 1)
    }

    @Test func interruptedReplyCanActuallyBeRetriedAfterRelaunch() async {
        let defaults = storage()
        let backend = IntegrationBackend()
        await backend.setHoldingRecommendations(true)
        let original = AppModel(defaults: defaults, backend: backend)
        original.sendMessage("Продолжи после перезапуска")
        await backend.waitForRecommendation(1)
        let reopened = AppModel(defaults: defaults, backend: backend)
        #expect(reopened.responseError != nil)
        reopened.retryResponse()
        #expect(reopened.isResponding)
        #expect(reopened.messages.filter { $0.role == .user }.count == 1)
        reopened.cancelResponse()
        original.cancelResponse()
        await backend.releaseHeldRequests()
    }

    @Test func journalRestoresConversationAndNewWalkArchivesInsteadOfDeleting() async throws {
        let defaults = storage()
        let app = AppModel(defaults: defaults)
        app.sendMessage("Прогулка у воды")
        try await waitForReply(app)
        let entry = try #require(app.journalEntries.first)
        app.startNewWalk()
        #expect(app.messages.isEmpty)
        #expect(app.journalEntries.contains { $0.id == entry.id })
        app.restoreJournalEntry(id: entry.id)
        #expect(app.messages.first?.text == "Прогулка у воды")
        #expect(app.messages.last?.snapshot != nil)
        let reopened = AppModel(defaults: defaults)
        #expect(reopened.messages.map(\.id) == app.messages.map(\.id))
        reopened.deleteJournalEntry(id: entry.id)
        #expect(AppModel(defaults: defaults).journalEntries.isEmpty)
    }

    @Test func removingAndReorderingPlanStopsRecalculatesWithoutRetainingOldLegs() {
        let app = AppModel(defaults: storage())
        app.duration = 180
        app.showResults(for: "Прогулка")
        app.showPlan()
        let original = app.currentPlan
        app.updatePlan(placeIDs: ["park", "coffee", "park", "missing"])
        #expect(app.currentPlan?.placeIDs == ["park", "coffee"])
        #expect(app.currentPlan?.legs.map(\.toID) == ["park", "coffee"])
        #expect(app.currentPlan?.legs.last?.fromID == "park")
        #expect(app.currentPlan?.duration != original?.duration)
        #expect(app.currentPlan?.legs.allSatisfy { $0.geometry == "estimate" } == true)
    }

    @Test func corruptedJournalAndLegacyPlaceCacheAreSafe() throws {
        let defaults = storage()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{bad json".utf8).write(to: folder.appendingPathComponent("journal.json"))
        defaults.set(Data("old cache".utf8), forKey: "seru.live.placeSnapshots")
        let app = AppModel(defaults: defaults, journalDirectory: folder)
        #expect(app.journalEntries.isEmpty)
        #expect(app.chatDraft.isEmpty)
        app.chatDraft = "После повреждения"
        #expect(AppModel(defaults: defaults, journalDirectory: folder).chatDraft == "После повреждения")
    }


    @Test func explicitDurationSurvivesAServerResponseWithALargerBudget() async throws {
        let backend = IntegrationBackend()
        await backend.setResponse(IntegrationBackend.plannedResponse)
        let app = AppModel(defaults: storage(), backend: backend)
        app.duration = 30
        app.sendMessage("Прогулка на полчаса")
        try await waitForReply(app)
        #expect(app.duration == 30)
        #expect((app.currentPlan?.duration ?? 0) <= 30)
        #expect(app.messages.last?.snapshot?.context.duration == 30)
    }

    @Test func editedPlanWithoutMessagesIsArchivedWhenStartingAnotherWalk() throws {
        let defaults = storage()
        let app = AppModel(defaults: defaults)
        app.duration = 180
        app.showPlan()
        app.updatePlan(placeIDs: ["coffee", "park"])
        let plan = try #require(app.currentPlan)
        app.startNewWalk()
        let archived = try #require(app.journalEntries.first)
        #expect(archived.plan == plan)
        let reopened = AppModel(defaults: defaults)
        reopened.restoreJournalEntry(id: archived.id)
        #expect(reopened.currentPlan == plan)
    }

    @Test func removedStopDoesNotReappearWhenPlanIsReopened() {
        let app = AppModel(defaults: storage())
        app.duration = 180
        app.showResults(for: "Прогулка")
        app.showPlan()
        app.updatePlan(placeIDs: [])
        app.showChat()
        app.showPlan()
        #expect(app.currentPlan == nil)
        #expect(app.planError != nil)
    }

    @Test func originChangeRecalculatesLocalPlanWithoutReusingTheOldStart() {
        let app = AppModel(defaults: storage())
        app.showResults(for: "Прогулка")
        app.showPlan()
        app.saveOrigin("Ботанический сад")
        #expect(app.currentPlan?.originLabel == "Ботанический сад")
    }

    @Test func restorePreventsAnUncancellableReplyFromReplacingTheJournalWalk() async throws {
        let backend = IntegrationBackend()
        let app = AppModel(defaults: storage(), backend: backend)
        app.sendMessage("Первая прогулка")
        try await waitForReply(app)
        let saved = try #require(app.journalEntries.first)
        app.startNewWalk()
        await backend.setHoldingRecommendations(true)
        app.sendMessage("Вторая прогулка")
        await backend.waitForRecommendation(2)
        app.restoreJournalEntry(id: saved.id)
        try await backend.releaseRecommendation(2, response: IntegrationBackend.newerResponse)
        await backend.waitForFinishedRecommendations(2)
        await Task.yield()
        #expect(app.query == "Первая прогулка")
        #expect(app.places.map(\.id) == ["osm:w42"])
        #expect(app.messages.last?.text == "Ответ настоящего API")
    }

    @Test func unknownReturnAndBudgetFactsRemainUnknownWhileKnownFactsSurviveMapping() throws {
        let absent = try JSONDecoder().decode(APIRecommendationResponse.self, from: Data(#"{"recommendations":[{"poi_id":"p","name":"Парк","address":"Кунаева 1","phone":"+77170000000","accessibility":"yes","prices":[{"label":"Вход","amount":0}]}],"route":{"order":["p"],"total_min":10}}"#.utf8))
        let place = try #require(absent.recommendations.first.map(BackendMapping.place))
        let route = try #require(absent.route.map { BackendMapping.route($0, response: absent, places: [place]) })
        #expect(place.address == "Кунаева 1")
        #expect(place.phone == "+77170000000")
        #expect(place.accessibility == "yes")
        #expect(place.prices?.first?["amount"] == .number(0))
        #expect(route.returnMinutes == nil)
        #expect(route.returnsToStart == nil)
        #expect(route.fitsBudget == nil)
    }

    @Test func undoPlaceRemovalRestoresTheGuestFavoriteAfterRelaunch() {
        let defaults = storage()
        let app = AppModel(defaults: defaults)
        let place = DemoData.places[0]
        app.toggleSaved(place)
        #expect(!app.isSaved(place))
        #expect(app.recentlyRemovedPlace?.id == place.id)
        app.undoSavedRemoval()
        #expect(app.isSaved(place))
        #expect(app.recentlyRemovedPlace == nil)
        #expect(AppModel(defaults: defaults).isSaved(place))
    }


    @Test func knownOriginChangesRecalculateTheActualStartEstimate() {
        let app = AppModel(defaults: storage())
        app.duration = 180
        app.showResults(for: "Прогулка")
        let fromBaiterek = app.places.first { $0.id == "garden" }?.travelMinutes
        app.saveOrigin("Ботанический сад")
        app.showResults()
        #expect(app.places.first { $0.id == "garden" }?.travelMinutes == 0)
        #expect((fromBaiterek ?? 0) > 0)
        #expect(app.currentPlan?.originCoordinate != nil)
    }

    @Test func localFavoritesUseTheSameCurrentOriginEstimateAsResults() {
        let app = AppModel(defaults: storage())
        app.duration = 180
        app.showResults(for: "Прогулка")
        #expect(app.savedPlaces.first { $0.id == "garden" }?.travelMinutes == app.places.first { $0.id == "garden" }?.travelMinutes)
        app.saveOrigin("Ботанический сад")
        #expect(app.savedPlaces.first { $0.id == "garden" }?.travelMinutes == 0)
        #expect(app.savedPlaces.first { $0.id == "garden" }?.distance == "0 м")
    }

    @Test func unknownLocalOriginCannotProduceAPlanClaimingItsTravelTime() {
        let app = AppModel(defaults: storage())
        app.saveOrigin("Неизвестный адрес 123")
        app.showResults(for: "Прогулка")
        app.showPlan()
        #expect(app.currentPlan == nil)
        #expect(app.planError != nil)
    }

    @Test func journalBoundsEntriesAndPhotoBytesAndDeletingPurgesSidecars() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = storage()
        let app = AppModel(defaults: defaults, journalDirectory: folder)
        for index in 0..<24 {
            app.chatDraft = "Прогулка \(index)"
            app.chatAttachmentData = Data(repeating: UInt8(index), count: 2 * 1024 * 1024)
            app.startNewWalk()
        }
        let retainedPhotoBytes = app.journalEntries.compactMap(\.draftPhoto).reduce(0) { $0 + $1.count }
        #expect(retainedPhotoBytes <= 24 * 1024 * 1024)
        let reopened = AppModel(defaults: defaults, journalDirectory: folder)
        #expect(reopened.journalEntries.count == 20)
        #expect(reopened.journalEntries.last?.title == "Прогулка 4")
        let photoBytes = reopened.journalEntries.compactMap(\.draftPhoto).reduce(0) { $0 + $1.count }
        #expect(photoBytes <= 24 * 1024 * 1024)
        #expect(reopened.journalEntries.first?.draftPhoto == Data(repeating: 23, count: 2 * 1024 * 1024))
        for entry in reopened.journalEntries { reopened.deleteJournalEntry(id: entry.id) }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.pathExtension == "photo" })
        #expect(AppModel(defaults: defaults, journalDirectory: folder).journalEntries.isEmpty)
    }

    private func waitForReply(_ app: AppModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while app.isResponding {
            guard ContinuousClock.now < deadline else { throw RecoveryWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

}

private actor RecoveringMetadataBackend: SeruBackend {
    private var failed = false
    private let wrapped = IntegrationBackend()
    func metadata() async throws -> APIMetadata {
        if !failed { failed = true; throw APIError.network(.notConnectedToInternet) }
        return try await wrapped.metadata()
    }
    func recommend(_ request: APIRecommendRequest, photo: Data?) async throws -> APIRecommendationResponse { try await wrapped.recommend(request, photo: photo) }
    func events(query: String?, price: String?, limit: Int, offset: Int) async throws -> APIEventPage { try await wrapped.events(query: query, price: price, limit: limit, offset: offset) }
    func route(poiID: String, origin: APIOrigin) async throws -> APIRouteToPlace { try await wrapped.route(poiID: poiID, origin: origin) }
    func routeIdeas(origin: APIOrigin) async throws -> [APIRouteIdea] { try await wrapped.routeIdeas(origin: origin) }
    func geocode(query: String) async throws -> [APIGeocodeResult] { try await wrapped.geocode(query: query) }
}

private enum RecoveryWaitError: Error { case timedOut }
