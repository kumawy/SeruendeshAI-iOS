import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor @Suite(.serialized)
struct AppAccountIntegrationTests {
    private func fixture() -> (AppModel, UserDefaults, AppAccountBackend, Place, Place) {
        let defaults = UserDefaults(suiteName: "account-integration-\(UUID().uuidString)")!
        var guest = DemoData.places[0]; guest.isLive = true
        var server = DemoData.places[1]; server.isLive = true
        defaults.set([guest.id], forKey: "seru.live.saved.places")
        defaults.set(try! JSONEncoder().encode([guest]), forKey: "seru.live.placeSnapshots")
        let backend = AppAccountBackend(place: server)
        return (AppModel(defaults: defaults, backend: BackendAPI(), accountBackend: backend), defaults, backend, guest, server)
    }

    private func changed(_ place: Place, values: [String: Any]) -> Place {
        var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as! [String: Any]
        json.merge(values) { _, new in new }
        return try! JSONDecoder().decode(Place.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func signedInFavoritesAreSeparateFromGuestAndResolveTheirServerSnapshots() async throws {
        let (app, defaults, _, guest, server) = fixture()
        #expect(app.savedPlaces.map(\.id) == [guest.id])
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        #expect(app.savedPlaces.map(\.id) == [server.id])
        #expect(app.isSaved(server))
        #expect(!app.isSaved(guest))
        #expect(app.place(id: server.id).name == server.name)
        #expect(defaults.stringArray(forKey: "seru.live.saved.places") == [guest.id])
        #expect(await app.account.signOut())
        #expect(app.savedPlaces.map(\.id) == [guest.id])
    }

    @Test func guestImportRequiresAnExplicitActionAndOnlyConfirmedPlacesAreRemovedLocally() async throws {
        let (app, defaults, backend, guest, server) = fixture()
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        #expect(await backend.saveCount == 0)
        #expect(app.guestSavedPlaces.map(\.id) == [guest.id])
        await app.importGuestSavedPlaces()
        #expect(await backend.saveCount == 1)
        #expect(Set(app.savedPlaces.map(\.id)) == Set([guest.id, server.id]))
        #expect(app.guestSavedPlaces.isEmpty)
        #expect(defaults.stringArray(forKey: "seru.live.saved.places") == [])
    }

    @Test func serverFavoriteToggleDoesNotWriteGuestCollections() async throws {
        let (app, defaults, backend, guest, server) = fixture()
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        app.toggleSaved(server)
        for _ in 0..<1000 {
            let savedOnServer = await backend.hasSaved(server.id)
            if !app.account.isSyncing && !savedOnServer { break }
            await Task.yield()
        }
        #expect(!app.isSaved(server))
        #expect(!(await backend.hasSaved(server.id)))
        #expect(defaults.stringArray(forKey: "seru.live.saved.places") == [guest.id])
    }

    @Test func signedInToggleNeverReplacesTheGuestSnapshotForTheSamePlaceID() async throws {
        let (app, _, backend, guest, _) = fixture()
        let cloud = changed(guest, values: ["name": "Снимок другого аккаунта"])
        await backend.replaceSaved(with: cloud)
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        app.toggleSaved(cloud)
        while app.account.isSyncing { await Task.yield() }
        #expect(await app.account.signOut())
        #expect(app.savedPlaces.first?.name == guest.name)
    }

    @Test func navigatingAccountPlaceNeverChangesTheGuestFavoriteSnapshot() async throws {
        let (app, _, backend, guest, _) = fixture()
        let cloud = changed(guest, values: ["name": "Снимок аккаунта"])
        await backend.replaceSaved(with: cloud)
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        app.showPlace(cloud)
        #expect(app.place(id: guest.id).name == cloud.name)
        #expect(await app.account.signOut())
        #expect(app.guestSavedPlaces.first?.name == guest.name)
    }

    @Test func newRecommendationSnapshotTakesPrecedenceOverAnOlderCloudFavorite() async throws {
        let (app, _, _, _, server) = fixture()
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        let fresh = changed(server, values: ["reason": "Новый ответ для другого старта", "travelMinutes": 42])
        app.showPlace(fresh)
        #expect(app.place(id: fresh.id).reason == fresh.reason)
        #expect(app.place(id: fresh.id).travelMinutes == 42)
    }

    @Test func retryOfAnExplicitFailedGuestImportClearsOnlyConfirmedImportedIDs() async throws {
        let (app, defaults, backend, guest, _) = fixture()
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        await backend.rejectSaves(true)
        await app.importGuestSavedPlaces()
        #expect(app.guestSavedPlaces.map(\.id) == [guest.id])
        await backend.rejectSaves(false)
        await app.retryAccountSavedChanges()
        #expect(app.isSaved(guest))
        #expect(app.guestSavedPlaces.isEmpty)
        #expect(defaults.stringArray(forKey: "seru.live.saved.places") == [])
    }

    @Test func optimisticSaveDuringImportRetryCannotDeleteTheOnlyLocalCopy() async throws {
        let (app, _, backend, guest, _) = fixture()
        #expect(await app.account.signIn(email: "member@example.com", password: "test-password"))
        await backend.rejectSaves(true)
        await app.importGuestSavedPlaces()
        await backend.rejectSaves(false)
        await backend.holdNextSave()
        app.toggleSaved(guest)
        while !(await backend.isHoldingSave()) { await Task.yield() }
        await app.retryAccountSavedChanges()
        #expect(app.guestSavedPlaces.map(\.id) == [guest.id])
        await backend.releaseHeldSave(failing: true)
        while app.account.isSyncing { await Task.yield() }
        #expect(!app.isSaved(guest))
        #expect(app.guestSavedPlaces.map(\.id) == [guest.id])
    }
}

private actor AppAccountBackend: SeruAccountBackend {
    let member = AccountUser(id: "member", email: "member@example.com", name: "Участник", lang: "ru", createdAt: Date())
    var user: AccountUser?
    var saved: [APISavedPlace]
    private(set) var saveCount = 0
    private var savesRejected = false
    private var shouldHoldSave = false
    private var heldSave: CheckedContinuation<Void, Never>?
    init(place: Place) { saved = [APISavedPlace(id: place.id, snapshot: SavedPlaceSnapshot(place: place), createdAt: Date())] }
    func currentUser() async throws -> AccountUser? { user }
    func signIn(email: String, password: String) async throws -> AccountUser { user = member; return member }
    func register(name: String, email: String, password: String) async throws -> AccountUser { user = member; return member }
    func signOut() async throws { user = nil }
    func deleteAccount() async throws { user = nil; saved = [] }
    func requestPasswordReset(email: String) async throws { }
    func confirmPasswordReset(token: String, password: String) async throws -> AccountUser { user = member; return member }
    func savedPlaces() async throws -> [APISavedPlace] { saved }
    func savePlace(id: String, snapshot: SavedPlaceSnapshot) async throws -> APISavedPlace {
        saveCount += 1
        if shouldHoldSave {
            shouldHoldSave = false
            await withCheckedContinuation { heldSave = $0 }
        }
        if savesRejected { throw APIError.network(.notConnectedToInternet) }
        let row = APISavedPlace(id: id, snapshot: snapshot, createdAt: Date())
        saved.removeAll { $0.id == id }; saved.append(row); return row
    }
    func removeSavedPlace(id: String) async throws { saved.removeAll { $0.id == id } }
    func hasSaved(_ id: String) -> Bool { saved.contains { $0.id == id } }
    func replaceSaved(with place: Place) { saved = [APISavedPlace(id: place.id, snapshot: SavedPlaceSnapshot(place: place))] }
    func rejectSaves(_ value: Bool) { savesRejected = value }
    func holdNextSave() { shouldHoldSave = true }
    func isHoldingSave() -> Bool { heldSave != nil }
    func releaseHeldSave(failing: Bool) { savesRejected = failing; heldSave?.resume(); heldSave = nil }
}
