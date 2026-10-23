import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor
struct SavedEventsTests {
    private func storage() -> UserDefaults {
        UserDefaults(suiteName: "seru.saved-events.tests.\(UUID().uuidString)")!
    }

    @Test func legacyEventIDsAcquireSnapshotsWhenTheirFeedArrivesLater() async throws {
        let defaults = storage()
        defaults.set("ticketon:today|not-in-feed", forKey: "seruendesh.savedEventIDs")
        let backend = IntegrationBackend()
        let app = AppModel(defaults: defaults, backend: backend)
        #expect(app.savedEvents.isEmpty)

        await backend.setEventPages(IntegrationBackend.datedEventPages)
        await app.refreshEvents()

        let data = defaults.data(forKey: "seruendesh.savedEventSnapshots")
        let snapshots = try data.map { try JSONDecoder().decode([CityEvent].self, from: $0) } ?? []
        #expect(snapshots.map(\.id) == ["ticketon:today"])
        #expect(snapshots.first?.title == "Утреннее событие")
        #expect(app.savedEvents.map(\.id) == ["ticketon:today"])
        #expect(app.isEventSaved(try #require(app.events.first)))
        #expect(AppModel(defaults: defaults, backend: IntegrationBackend()).savedEvents.map(\.id) == ["ticketon:today"])
        #expect(defaults.string(forKey: "seruendesh.savedEventIDs") == "ticketon:today|not-in-feed")
    }

    @Test func refreshUpdatesSavedSnapshotWithoutDiscardingEventsMissingFromFeed() async throws {
        let defaults = storage()
        defaults.set("jazz|stars", forKey: "seruendesh.savedEventIDs")
        defaults.set(try JSONEncoder().encode([DemoData.events[0], DemoData.events[2]]),
                     forKey: "seruendesh.savedEventSnapshots")
        let backend = IntegrationBackend()
        await backend.setEventPages([0: """
        {"items":[{"id":"jazz","title":"Новая программа джаза","start":"2026-10-21","price_from":0}],"total":1,"offset":0,"limit":100,"today":"2026-10-21"}
        """])
        let app = AppModel(defaults: defaults, backend: backend)

        await app.refreshEvents()

        let data = try #require(defaults.data(forKey: "seruendesh.savedEventSnapshots"))
        let snapshots = try JSONDecoder().decode([CityEvent].self, from: data)
        #expect(snapshots.first(where: { $0.id == "jazz" })?.title == "Новая программа джаза")
        #expect(snapshots.first(where: { $0.id == "stars" })?.title == "Астрономический вечер под открытым небом")
        #expect(app.savedEvents.first(where: { $0.id == "jazz" })?.title == "Новая программа джаза")
        #expect(AppModel(defaults: defaults, backend: IntegrationBackend()).savedEvents.count == 2)
    }

    @Test func savedLiveEventSurvivesAnEmptyFeedAndRemovalSurvivesRelaunch() async throws {
        let defaults = storage()
        let backend = IntegrationBackend()
        await backend.setEventPages(IntegrationBackend.datedEventPages)
        let app = AppModel(defaults: defaults, backend: backend)
        await app.refreshEvents()
        let event = try #require(app.events.first)

        app.toggleSavedEvent(event)

        #expect(app.isEventSaved(event))
        #expect(app.savedEvents == [event])
        let reopened = AppModel(defaults: defaults, backend: IntegrationBackend())
        await reopened.refreshEvents()
        #expect(reopened.events.isEmpty)
        #expect(reopened.savedEvents == [event])
        #expect(reopened.isEventSaved(event))

        reopened.toggleSavedEvent(event)

        #expect(!reopened.isEventSaved(event))
        #expect(reopened.savedEvents.isEmpty)
        let empty = AppModel(defaults: defaults, backend: IntegrationBackend())
        #expect(empty.savedEvents.isEmpty)
        #expect(!empty.isEventSaved(event))
    }

    @Test func legacyDemoBookmarksKeepTheSameNamespaceAndRetainUnknownIDsWhenToggled() {
        let defaults = storage()
        defaults.set("jazz|unknown-legacy-id", forKey: "seruendesh.savedEventIDs")
        let demo = AppModel(defaults: defaults)

        #expect(demo.savedEvents.map(\.id) == ["jazz"])
        #expect(demo.isEventSaved(DemoData.events[0]))
        let live = AppModel(defaults: defaults, backend: IntegrationBackend())
        #expect(live.savedEvents.map(\.id) == ["jazz"])

        live.toggleSavedEvent(DemoData.events[2])
        #expect(live.savedEvents.map(\.id) == ["jazz", "stars"])
        #expect(Set((defaults.string(forKey: "seruendesh.savedEventIDs") ?? "").split(separator: "|").map(String.init)) ==
                ["jazz", "stars", "unknown-legacy-id"])

        let reopened = AppModel(defaults: defaults)
        #expect(reopened.savedEvents.map(\.id) == ["jazz", "stars"])
        reopened.toggleSavedEvent(DemoData.events[0])
        #expect(reopened.savedEvents.map(\.id) == ["stars"])
        #expect(defaults.string(forKey: "seruendesh.savedEventIDs") == "stars|unknown-legacy-id")
    }

    @Test func malformedSnapshotsDoNotEraseLegacyBookmarksBeforeFeedRecovery() async throws {
        let defaults = storage()
        defaults.set("ticketon:today", forKey: "seruendesh.savedEventIDs")
        defaults.set(Data("invalid JSON".utf8), forKey: "seruendesh.savedEventSnapshots")
        let backend = IntegrationBackend()
        let app = AppModel(defaults: defaults, backend: backend)
        #expect(app.savedEvents.isEmpty)
        #expect(defaults.string(forKey: "seruendesh.savedEventIDs") == "ticketon:today")

        await backend.setEventPages(IntegrationBackend.datedEventPages)
        await app.refreshEvents()

        #expect(app.isEventSaved(try #require(app.events.first)))
        #expect(app.savedEvents.map(\.id) == ["ticketon:today"])
        #expect(AppModel(defaults: defaults, backend: IntegrationBackend()).savedEvents.map(\.id) == ["ticketon:today"])
    }
}
