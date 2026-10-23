import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor
struct AccountStoreTests {
    @Test func restoreLoadsOnlyTheCurrentAccountsServerFavorites() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        #expect(store.user?.id == "user-a")
        #expect(store.savedPlaces.map(\.id) == ["garden"])
        #expect(!store.isRestoring)
        #expect(!store.isSyncing)
        #expect(store.error == nil)
    }

    @Test func guestRestoreAndNetworkFailureAreDistinct() async {
        let backend = AccountTestBackend()
        let store = AccountStore(backend: backend)
        await store.restore()
        #expect(store.user == nil)
        #expect(store.error == nil)
        await backend.setFailure(.restore, .network(.notConnectedToInternet))
        await store.restore()
        #expect(store.user == nil)
        #expect(store.error?.contains("интернет") == true)
        #expect(!store.isRestoring)
    }

    @Test func restoringAnExpiredCookieExplainsWhyTheAuthenticatedAccountDisappeared() async {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        #expect(store.user?.id == "user-a")
        #expect(!store.savedPlaces.isEmpty)

        // /auth/me returns a guest payload with HTTP 200 after cookie expiry.
        await backend.setSession(nil)
        await store.restore()

        #expect(store.user == nil)
        #expect(store.savedPlaces.isEmpty)
        #expect(store.error != nil)
        #expect(!store.isRestoring)
        #expect(!store.isSyncing)
    }

    @Test func signInNormalizesEmailAndLoadsServerFavoritesWithoutImportingGuestData() async throws {
        let backend = AccountTestBackend()
        await backend.setSaved([Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        #expect(await store.signIn(email: "  FIRST@EXAMPLE.COM \n", password: "secret123"))
        #expect(store.user?.email == "first@example.com")
        #expect(store.savedPlaces.map(\.id) == ["garden"])
        #expect(!store.isWorking)
        #expect(await backend.writeCount == 0)
    }

    @Test func badCredentialsShowAnErrorWithoutInventingAnAccount() async {
        let backend = AccountTestBackend()
        await backend.setFailure(.signIn, .http(status: 401, code: "invalid_credentials"))
        let store = AccountStore(backend: backend)
        #expect(!(await store.signIn(email: "first@example.com", password: "wrong")))
        #expect(store.user == nil)
        #expect(store.error != nil)
        #expect(store.notice == nil)
        #expect(!store.isWorking)
    }

    @Test func rejectedLogoutAndDeletionKeepTheConfirmedAccountAndFavorites() async {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.signOut, .network(.timedOut))
        #expect(!(await store.signOut()))
        #expect(store.user?.id == "user-a")
        #expect(store.savedPlaces.map(\.id) == ["garden"])
        await backend.setFailure(.delete, .http(status: 500, code: nil))
        #expect(!(await store.deleteAccount()))
        #expect(store.user?.id == "user-a")
        #expect(store.savedPlaces.map(\.id) == ["garden"])
        #expect(store.error != nil)
    }

    @Test func successfulLogoutAndDeletionClearOnlyAccountState() async {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        #expect(await store.signOut())
        #expect(store.user == nil)
        #expect(store.savedPlaces.isEmpty)
        #expect(await store.signIn(email: "first@example.com", password: "secret123"))
        #expect(await store.deleteAccount())
        #expect(store.user == nil)
        #expect(store.savedPlaces.isEmpty)
    }

    @Test func lateSavedResultFromPreviousAccountCannotAppearInNewAccount() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setHoldingSaved(true)
        let oldRefresh = Task { await store.refreshSaved() }
        try await Self.wait { await backend.heldSavedCount == 1 }
        #expect(await store.signOut())
        await backend.setHoldingSaved(false)
        await backend.setSaved([Self.saved(Self.coffee)])
        #expect(await store.signIn(email: "second@example.com", password: "secret123"))
        await backend.releaseSaved()
        await oldRefresh.value
        #expect(store.user?.id == "user-b")
        #expect(store.savedPlaces.map(\.id) == ["coffee"])
    }

    @Test func expiredProtectedSessionClearsPrivateFavoritesAndRequestsSignIn() async {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.saved, .http(status: 401, code: "session_expired"))
        await store.refreshSaved()
        #expect(store.user == nil)
        #expect(store.savedPlaces.isEmpty)
        #expect(store.error != nil)
        #expect(!store.isSyncing)
    }

    @Test func rapidHeartChangesStaySerializedAndFinishAtTheLatestIntent() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setHoldingWrites(true)
        store.toggleSaved(Self.park)
        #expect(store.isSaved(Self.park))
        try await Self.wait { await backend.writeCount == 1 }
        store.toggleSaved(Self.park)
        #expect(!store.isSaved(Self.park))
        await backend.releaseWrite()
        try await Self.wait { await backend.writeCount == 2 }
        await backend.releaseWrite()
        try await Self.waitOnMain { !store.isSyncing }
        #expect(!store.isSaved(Self.park))
        #expect(await backend.serverSavedIDs == [])
        #expect(await backend.writeOperations == ["save:garden", "remove:garden"])
    }

    @Test func saveFailureRollsBackTheHeartAndAllowsExplicitRetry() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.write, .network(.notConnectedToInternet))
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(!store.isSaved(Self.park))
        #expect(store.savedPlaces.isEmpty)
        #expect(store.syncError != nil)
        await backend.setFailure(.write, nil)
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.isSaved(Self.park))
        #expect(store.syncError == nil)
        #expect(await backend.serverSavedIDs == ["garden"])
    }

    @Test func lateRefreshCannotResurrectAPlaceRemovedWhileItWasLoading() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setHoldingSaved(true)
        let refresh = Task { await store.refreshSaved() }
        try await Self.wait { await backend.heldSavedCount == 1 }
        store.toggleSaved(Self.park)
        try await Self.wait { await backend.writeCount == 1 }
        try await Self.waitOnMain { !store.isSaved(Self.park) }
        await backend.releaseSaved()
        await refresh.value
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.savedPlaces.isEmpty)
        #expect(await backend.serverSavedIDs == [])
    }

    @Test func explicitGuestImportReportsOnlyConfirmedPlacesWhenOneUploadFails() async {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        await backend.setFailingPlace("coffee")
        let store = AccountStore(backend: backend)
        await store.restore()
        let imported = await store.importGuestPlaces([Self.park, Self.coffee])
        #expect(imported == ["garden"])
        #expect(store.savedPlaces.map(\.id) == ["garden"])
        #expect(store.syncError != nil)
        #expect(await backend.serverSavedIDs == ["garden"])
    }

    @Test func retryingGuestImportClearsThePreviousFailureOnlyAfterConfirmedUploads() async {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        await backend.setFailingPlace("coffee")
        let store = AccountStore(backend: backend)
        await store.restore()
        #expect(await store.importGuestPlaces([Self.park, Self.coffee]) == ["garden"])
        #expect(store.syncError != nil)
        await backend.setFailingPlace(nil)
        #expect(await store.importGuestPlaces([Self.coffee]) == ["coffee"])
        #expect(store.syncError == nil)
        #expect(Set(store.savedPlaces.map(\.id)) == ["garden", "coffee"])
    }

    @Test func mismatchedSaveResponseCannotInsertAnUnrelatedFavorite() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        await backend.setMismatchedSavedID(true)
        let store = AccountStore(backend: backend)
        await store.restore()
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.savedPlaces.isEmpty)
        #expect(!store.isSaved(Self.park))
        #expect(store.syncError != nil)
    }

    @Test func invalidFormInputDoesNotStartNetworkWorkOrClaimSuccess() async {
        let backend = AccountTestBackend()
        let store = AccountStore(backend: backend)
        #expect(!(await store.register(name: " ", email: "broken", password: "123")))
        #expect(store.error != nil)
        #expect(!(await store.register(name: "Серу", email: "ok@example.com", password: "123")))
        #expect(!(await store.signIn(email: "broken", password: "secret123")))
        #expect(!(await store.signIn(email: "ok@example.com", password: "")))
        #expect(await backend.authCalls == 0)
        #expect(!store.isWorking)
        #expect(store.user == nil)
    }

    @Test func registrationAndPasswordRecoveryUseConfirmedServerResults() async {
        let backend = AccountTestBackend()
        let store = AccountStore(backend: backend)
        #expect(await store.register(name: "  Аслан   Мурат ", email: "FIRST@example.com", password: "secret123"))
        #expect(store.user?.name == "Аслан Мурат")
        #expect(await store.signOut())
        #expect(!(await store.requestPasswordReset(email: "first@example.com")))
        #expect(await backend.resetRequests == 0)
        store.passwordResetAvailable = true
        #expect(await store.requestPasswordReset(email: "first@example.com"))
        #expect(store.notice != nil)
        #expect(store.user == nil)
        #expect(!(await store.confirmPasswordReset(token: "", password: "secret123")))
        #expect(await store.confirmPasswordReset(token: "valid-token", password: "newsecret123"))
        #expect(store.user?.id == "user-a")
    }

    @Test func restorationMustFinishBeforeSignInCanChangeTheSessionCookie() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        await backend.setHoldingRestore(true)
        let store = AccountStore(backend: backend)
        let restore = Task { await store.restore() }
        try await Self.wait { await backend.isHoldingRestore }
        #expect(!(await store.signIn(email: "second@example.com", password: "secret123")))
        #expect(await backend.authCalls == 0)
        await backend.releaseRestore()
        await restore.value
        #expect(store.user?.id == "user-a")
        #expect(await store.signIn(email: "second@example.com", password: "secret123"))
        #expect(store.user?.id == "user-b")
        #expect(!store.isWorking)
        #expect(!store.isRestoring)
    }

    @Test func retrySavedChangesReplaysTheFailedIntentAfterRollingBackTheHeart() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.write, .network(.notConnectedToInternet))
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(!store.isSaved(Self.park))
        #expect(store.syncError != nil)
        await backend.setFailure(.write, nil)
        await store.retrySavedChanges()
        #expect(store.isSaved(Self.park))
        #expect(await backend.serverSavedIDs == ["garden"])
        #expect(store.syncError == nil)
    }

    @Test func retryCannotReplayAnObsoleteFailureOverANewerHeartIntent() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.coffee), Self.saved(Self.park)])
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.write, .network(.notConnectedToInternet))
        store.toggleSaved(Self.coffee)
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.isSaved(Self.coffee))
        #expect(store.isSaved(Self.park))

        await backend.setFailure(.write, nil)
        await backend.setHoldingWrites(true)
        let retry = Task { await store.retrySavedChanges() }
        try await Self.wait { await backend.writeCount == 3 }
        // Coffee's retry is held while the user changes and confirms the garden twice.
        await backend.setHoldingWrites(false)
        store.toggleSaved(Self.park)
        try await Self.wait { await backend.serverSavedIDs == ["coffee"] }
        store.toggleSaved(Self.park)
        try await Self.wait { await backend.serverSavedIDs == ["coffee", "garden"] }
        await backend.releaseWrite()
        await retry.value

        #expect(store.isSaved(Self.park))
        #expect(!store.isSaved(Self.coffee))
        #expect(await backend.serverSavedIDs == ["garden"])
        #expect(store.syncError == nil)
    }

    @Test func confirmedFavoriteIDsNeverTreatPendingOrFailedWritesAsServerAcknowledgements() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setHoldingWrites(true)
        store.toggleSaved(Self.park)
        try await Self.wait { await backend.writeCount == 1 }
        #expect(store.isSaved(Self.park))
        #expect(store.confirmedSavedPlaceIDs.isEmpty)
        await backend.releaseWrite(failure: .network(.notConnectedToInternet))
        try await Self.waitOnMain { !store.isSyncing }
        #expect(!store.isSaved(Self.park))
        #expect(store.confirmedSavedPlaceIDs.isEmpty)

        await backend.setHoldingWrites(false)
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.confirmedSavedPlaceIDs == ["garden"])
        #expect(await backend.serverSavedIDs == ["garden"])
    }

    @Test func savingAnotherPlaceAndRefreshingCannotHideARemainingFailedFavorite() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.write, .network(.notConnectedToInternet))
        store.toggleSaved(Self.park)
        store.toggleSaved(Self.coffee)
        try await Self.waitOnMain { !store.isSyncing }
        await backend.setFailure(.write, nil)
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.isSaved(Self.park))
        #expect(!store.isSaved(Self.coffee))
        #expect(store.syncError != nil)
        await store.refreshSaved()
        #expect(store.syncError != nil)
        await store.retrySavedChanges()
        #expect(store.isSaved(Self.coffee))
        #expect(store.syncError == nil)
    }

    @Test func failedFavoriteFromThePreviousAccountCannotBeRetriedForANewAccount() async throws {
        let backend = AccountTestBackend()
        await backend.setSession(.first)
        let store = AccountStore(backend: backend)
        await store.restore()
        await backend.setFailure(.write, .network(.notConnectedToInternet))
        store.toggleSaved(Self.park)
        try await Self.waitOnMain { !store.isSyncing }
        #expect(store.syncError != nil)
        #expect(await store.signOut())
        await backend.setFailure(.write, nil)
        #expect(await store.signIn(email: "second@example.com", password: "secret123"))
        await store.retrySavedChanges()
        #expect(store.user?.id == "user-b")
        #expect(store.savedPlaces.isEmpty)
        #expect(await backend.serverSavedIDs == [])
        #expect(await backend.writeOperations == ["save:garden"])
    }

    @Test func refreshingACachedSessionVerifiesIdentityBeforeReplacingFavorites() async {
        let defaults = UserDefaults(suiteName: "seru.cache.identity.\(UUID().uuidString)")!
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        await AccountStore(backend: backend, defaults: defaults).restore()
        await backend.setSession(.second, saved: [Self.saved(Self.coffee)])
        let reopened = AccountStore(backend: backend, defaults: defaults)
        await backend.setFailure(.restore, .network(.notConnectedToInternet))
        await reopened.refreshSaved()
        #expect(reopened.user?.id == "user-a")
        #expect(reopened.savedPlaces.map(\.id) == ["garden"])
        #expect(reopened.isShowingCachedData)
        await backend.setFailure(.restore, nil)
        await reopened.refreshSaved()
        #expect(reopened.user?.id == "user-b")
        #expect(reopened.savedPlaces.map(\.id) == ["coffee"])
        #expect(!reopened.isShowingCachedData)
    }

    @Test func cachedFavoritesSurviveAnOfflineColdRestore() async {
        let suite = "account-cache-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let original = AccountStore(backend: backend, defaults: defaults)
        await original.restore()
        await backend.setFailure(.restore, .network(.notConnectedToInternet))
        let reopened = AccountStore(backend: backend, defaults: defaults)
        #expect(reopened.user?.id == "user-a")
        #expect(reopened.savedPlaces.map(\.id) == ["garden"])
        #expect(reopened.isShowingCachedData)
        await reopened.restore()
        #expect(reopened.savedPlaces.map(\.id) == ["garden"])
        #expect(reopened.isShowingCachedData)
        #expect(reopened.error != nil)
    }

    @Test func logoutAndAccountSwitchNeverRestoreAnotherAccountsFavorites() async {
        let suite = "account-cache-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let store = AccountStore(backend: backend, defaults: defaults)
        await store.restore()
        #expect(await store.signOut())
        #expect(AccountStore(backend: backend, defaults: defaults).user == nil)
        await backend.setSession(.second, saved: [Self.saved(Self.coffee)])
        await store.restore()
        let reopened = AccountStore(backend: backend, defaults: defaults)
        #expect(reopened.user?.id == "user-b")
        #expect(reopened.savedPlaces.map(\.id) == ["coffee"])
        await backend.setFailure(.restore, .http(status: 401, code: "session_expired"))
        await reopened.restore()
        #expect(reopened.user == nil)
        #expect(reopened.savedPlaces.isEmpty)
        #expect(AccountStore(backend: backend, defaults: defaults).user == nil)
    }

    @Test func failedRefreshKeepsCacheUntilSuccessfulEmptyResponse() async {
        let suite = "account-cache-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AccountTestBackend()
        await backend.setSession(.first, saved: [Self.saved(Self.park)])
        let original = AccountStore(backend: backend, defaults: defaults)
        await original.restore()
        await backend.setFailure(.saved, .network(.notConnectedToInternet))
        let reopened = AccountStore(backend: backend, defaults: defaults)
        await reopened.restore()
        #expect(reopened.savedPlaces.map(\.id) == ["garden"])
        #expect(reopened.isShowingCachedData)
        await backend.setFailure(.saved, nil)
        await backend.setSaved([])
        await reopened.refreshSaved()
        #expect(reopened.savedPlaces.isEmpty)
        #expect(reopened.hasLoadedSaved)
        #expect(!reopened.isShowingCachedData)
        #expect(AccountStore(backend: backend, defaults: defaults).savedPlaces.isEmpty)
    }

    private static var park: Place { DemoData.places[0] }
    private static var coffee: Place { DemoData.places[1] }
    private static func saved(_ place: Place) -> APISavedPlace { APISavedPlace(id: place.id, snapshot: SavedPlaceSnapshot(place: place)) }
    private static func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 { if await condition() { return }; try await Task.sleep(for: .milliseconds(2)) }
        throw AccountWaitError.timeout
    }
    private static func waitOnMain(_ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(2)) }
        throw AccountWaitError.timeout
    }
}

private enum AccountWaitError: Error { case timeout }
private extension AccountUser {
    static let first = AccountUser(id: "user-a", email: "first@example.com", name: "Первый")
    static let second = AccountUser(id: "user-b", email: "second@example.com", name: "Второй")
}

private actor AccountTestBackend: SeruAccountBackend {
    enum Operation: Hashable { case restore, signIn, signOut, delete, saved, write, reset }
    private var session: AccountUser?
    private var items: [APISavedPlace] = []
    private var failures: [Operation: APIError] = [:]
    private var holdingSaved = false
    private var pendingSaved: [(CheckedContinuation<[APISavedPlace], any Error>, [APISavedPlace])] = []
    private var holdingWrites = false
    private var pendingWrite: (CheckedContinuation<Void, any Error>, String, SavedPlaceSnapshot?)?
    private var holdingRestore = false
    private var pendingRestore: (CheckedContinuation<AccountUser?, any Error>, AccountUser?)?
    private var failingPlace: String?
    private var mismatchedSavedID = false
    private(set) var authCalls = 0
    private(set) var writeOperations: [String] = []
    private(set) var resetRequests = 0
    var heldSavedCount: Int { pendingSaved.count }
    var isHoldingRestore: Bool { pendingRestore != nil }
    var writeCount: Int { writeOperations.count }
    var serverSavedIDs: [String] { items.map(\.id).sorted() }
    func setSession(_ user: AccountUser?, saved: [APISavedPlace] = []) { session = user; items = saved }
    func setSaved(_ saved: [APISavedPlace]) { items = saved }
    func setFailure(_ operation: Operation, _ failure: APIError?) { failures[operation] = failure }
    func setHoldingSaved(_ value: Bool) { holdingSaved = value }
    func setHoldingWrites(_ value: Bool) { holdingWrites = value }
    func setHoldingRestore(_ value: Bool) { holdingRestore = value }
    func setFailingPlace(_ id: String?) { failingPlace = id }
    func setMismatchedSavedID(_ value: Bool) { mismatchedSavedID = value }
    func currentUser() async throws -> AccountUser? {
        if let failure = failures[.restore] { throw failure }
        if holdingRestore { return try await withCheckedThrowingContinuation { pendingRestore = ($0, session) } }
        return session
    }
    func register(name: String, email: String, password: String) async throws -> AccountUser {
        authCalls += 1
        session = AccountUser(id: "user-a", email: email, name: name)
        return session!
    }
    func signIn(email: String, password: String) async throws -> AccountUser {
        authCalls += 1
        if let failure = failures[.signIn] { throw failure }
        session = email == "second@example.com" ? .second : .first
        return session!
    }
    func signOut() async throws {
        if let failure = failures[.signOut] { throw failure }
        session = nil
    }
    func deleteAccount() async throws {
        if let failure = failures[.delete] { throw failure }
        session = nil; items = []
    }
    func requestPasswordReset(email: String) async throws {
        resetRequests += 1
        if let failure = failures[.reset] { throw failure }
    }
    func confirmPasswordReset(token: String, password: String) async throws -> AccountUser {
        session = .first
        return .first
    }
    func savedPlaces() async throws -> [APISavedPlace] {
        if let failure = failures[.saved] { throw failure }
        if holdingSaved { return try await withCheckedThrowingContinuation { pendingSaved.append(($0, items)) } }
        return items
    }
    func savePlace(id: String, snapshot: SavedPlaceSnapshot) async throws -> APISavedPlace {
        writeOperations.append("save:\(id)")
        if let failure = failures[.write] { throw failure }
        if failingPlace == id { throw APIError.http(status: 500, code: nil) }
        if holdingWrites { try await withCheckedThrowingContinuation { pendingWrite = ($0, id, snapshot) } }
        else { applyWrite(id: id, snapshot: snapshot) }
        return APISavedPlace(id: mismatchedSavedID ? "unrelated" : id, snapshot: snapshot)
    }
    func removeSavedPlace(id: String) async throws {
        writeOperations.append("remove:\(id)")
        if let failure = failures[.write] { throw failure }
        if holdingWrites { try await withCheckedThrowingContinuation { pendingWrite = ($0, id, nil) } }
        else { applyWrite(id: id, snapshot: nil) }
    }
    func releaseSaved() {
        let pending = pendingSaved; pendingSaved = []
        for (continuation, snapshot) in pending { continuation.resume(returning: snapshot) }
    }
    func releaseRestore() {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil; pending.0.resume(returning: pending.1)
    }
    func releaseWrite(failure: APIError? = nil) {
        guard let pending = pendingWrite else { return }
        pendingWrite = nil
        if let failure { pending.0.resume(throwing: failure) }
        else { applyWrite(id: pending.1, snapshot: pending.2); pending.0.resume() }
    }
    private func applyWrite(id: String, snapshot: SavedPlaceSnapshot?) {
        items.removeAll { $0.id == id }
        if let snapshot { items.append(APISavedPlace(id: id, snapshot: snapshot)) }
    }
}
