import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor
struct AppModelTests {
    private func storage() -> UserDefaults {
        UserDefaults(suiteName: "seru.tests.\(UUID().uuidString)")!
    }

    @Test func defaultThemeFollowsSystemAndExplicitPreferenceSurvives() {
        let defaults = storage()
        #expect(AppModel(defaults: defaults).theme == .system)

        defaults.set("light", forKey: "seru.theme")
        #expect(AppModel(defaults: defaults).theme == .light)

        defaults.set("system", forKey: "seru.theme")
        #expect(AppModel(defaults: defaults).theme == .system)
    }

    @Test func savingPersistsAndRemovingLastPlaceSurvivesRelaunch() {
        let defaults = storage()
        let app = AppModel(defaults: defaults)
        let place = DemoData.places[0]
        if app.isSaved(place) { app.toggleSaved(place) }
        app.toggleSaved(place)
        #expect(app.isSaved(place))
        let reopened = AppModel(defaults: defaults)
        #expect(reopened.isSaved(place))
        for saved in reopened.savedPlaces { reopened.toggleSaved(saved) }
        #expect(AppModel(defaults: defaults).savedPlaces.isEmpty)
    }

    @Test func backRestoresResultsAndQueryAfterRoutePreview() {
        let app = AppModel(defaults: storage())
        app.showResults(for: "Кофе в тихом месте")
        #expect(app.screen == .results)
        let place = DemoData.places[1]
        app.showPlace(place)
        app.showRoute(place)
        app.goBack()
        #expect(app.screen == .detail(place.id))
        app.goBack()
        #expect(app.screen == .results)
        #expect(app.query == "Кофе в тихом месте")
    }

    @Test func whitespaceCannotStartConversation() {
        let app = AppModel(defaults: storage())
        app.sendMessage(" \n ")
        #expect(app.messages.isEmpty)
        #expect(!app.isResponding)
    }

    @Test func durationRefinementKeepsOnlyPlacesThatFit() {
        let app = AppModel(defaults: storage())
        app.duration = 30
        app.showResults(for: "Прогулка")
        #expect(app.places.allSatisfy { $0.travelMinutes + $0.visitMinutes <= 30 })
        #expect(app.screen == .results)
    }

    @Test func savedRouteIsSeparateFromPlaceAndPersists() {
        let defaults = storage()
        let app = AppModel(defaults: defaults)
        let route = DemoData.featuredRoute
        if app.isRouteSaved(route) { app.toggleSavedRoute(route) }
        app.toggleSavedRoute(route)
        #expect(AppModel(defaults: defaults).isRouteSaved(route))
        #expect(app.savedRoutes.contains(route))
    }

    @Test func familyFilterChangesRecommendations() {
        let app = AppModel(defaults: storage())
        app.withKids = true
        app.showResults()
        #expect(!app.places.isEmpty)
        #expect(app.places.allSatisfy { $0.isChildFriendly })
        #expect(!app.places.contains { $0.id == "coffee" })
        app.withKids = false
        app.showResults()
        #expect(app.places.contains { $0.id == "coffee" })
    }

    @Test func sendingPhotoKeepsAttachmentInConversation() {
        let app = AppModel(defaults: storage())
        let photo = Data([1, 2, 3])
        app.sendMessage("", attachment: photo)
        #expect(app.messages.count == 1)
        #expect(app.messages.first?.attachmentData == photo)
        #expect(app.messages.first?.text == "Что за место на фото?")
        app.cancelResponse()
    }

    @Test func sendingSharedDraftMovesToChatAndKeepsMessageContents() {
        let app = AppModel(defaults: storage())
        defer { app.cancelResponse() }
        let photo = Data([4, 5, 6])
        app.chatDraft = "  Прогулка у реки \n"
        app.chatAttachmentData = photo

        #expect(app.sendChatDraft())
        #expect(app.screen == .chat)
        #expect(app.messages.first?.text == "Прогулка у реки")
        #expect(app.messages.first?.attachmentData == photo)
        #expect(app.chatDraft.isEmpty)
        #expect(app.chatAttachmentData == nil)
    }

    @Test func sharedDraftCanSendPhotoWithoutText() {
        let app = AppModel(defaults: storage())
        defer { app.cancelResponse() }
        let photo = Data([7, 8, 9])
        app.chatAttachmentData = photo

        #expect(app.sendChatDraft())
        #expect(app.messages.first?.attachmentData == photo)
        #expect(app.screen == .chat)
        #expect(app.chatAttachmentData == nil)
    }

    @Test func emptySharedDraftStaysUnsent() {
        let app = AppModel(defaults: storage())
        app.chatDraft = " \n "

        #expect(!app.sendChatDraft())
        #expect(app.chatDraft == " \n ")
        #expect(app.messages.isEmpty)
        #expect(app.screen == .home)
    }

    @Test func busyConversationPreservesNextDraftAndPhoto() {
        let app = AppModel(defaults: storage())
        defer { app.cancelResponse() }
        app.sendMessage("Первый запрос")
        let photo = Data([10, 11, 12])
        app.chatDraft = "Следующий запрос"
        app.chatAttachmentData = photo

        #expect(!app.sendChatDraft())
        #expect(app.chatDraft == "Следующий запрос")
        #expect(app.chatAttachmentData == photo)
        #expect(app.messages.count == 1)
        #expect(app.screen == .home)
    }

    @Test func resettingWalkClearsSharedDraftAndPhoto() {
        let app = AppModel(defaults: storage())
        app.chatDraft = "Незаконченный запрос"
        app.chatAttachmentData = Data([13, 14, 15])

        app.resetWalk()

        #expect(app.chatDraft.isEmpty)
        #expect(app.chatAttachmentData == nil)
    }
}
