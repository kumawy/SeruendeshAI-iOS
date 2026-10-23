import Foundation
import Observation

/// The authenticated session and its favorites. Guest favorites belong to AppModel.
@MainActor @Observable
final class AccountStore {
    private(set) var user: AccountUser?
    private(set) var isRestoring = false
    private(set) var isWorking = false
    var error: String?
    var notice: String?
    private(set) var savedPlaces: [Place] = []
    var confirmedSavedPlaceIDs: Set<String> { Set(confirmed.keys) }
    private(set) var isSyncing = false
    var syncError: String?
    var passwordResetAvailable = false
    private(set) var isShowingCachedData = false
    private(set) var hasLoadedSaved = false

    @ObservationIgnored private let backend: (any SeruAccountBackend)?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var authenticationID = UUID()
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var savedRevision = 0
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var sessionVerified = false
    @ObservationIgnored private var confirmed: [String: Place] = [:]
    @ObservationIgnored private var desired: [String: Bool] = [:]
    @ObservationIgnored private var pendingPlaces: [String: Place] = [:]
    @ObservationIgnored private var failedChanges: [String: FailedChange] = [:]
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]

    init(backend: (any SeruAccountBackend)?, defaults: UserDefaults? = nil) {
        self.backend = backend
        self.defaults = defaults
        guard backend != nil, let cached = cachedSession() else { return }
        user = cached.user
        confirmed = Dictionary(cached.places.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        savedPlaces = confirmed.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        hasLoadedSaved = cached.hasLoadedSaved
        isShowingCachedData = true
    }

    func restore() async {
        guard let backend, !isWorking, !isRestoring else { return }
        let operation = UUID()
        authenticationID = operation
        isRestoring = true
        error = nil
        defer { if authenticationID == operation { isRestoring = false } }
        do {
            let restored = try await backend.currentUser()
            guard authenticationID == operation, !Task.isCancelled else { return }
            if restored == nil, user != nil { expireSession() }
            else if restored?.id != user?.id { setSession(restored) }
            else { user = restored }
            sessionVerified = restored != nil
            if restored != nil { await refreshSaved() }
        } catch is CancellationError { }
        catch {
            guard authenticationID == operation, !Task.isCancelled else { return }
            if isUnauthorized(error) { expireSession() }
            else { self.error = error.localizedDescription }
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        guard let backend else { return unavailable() }
        guard let email = validatedEmail(email) else { return false }
        guard !password.isEmpty, password.count <= 128 else {
            error = "Введи пароль (не больше 128 символов)."; return false
        }
        return await authenticate { try await backend.signIn(email: email, password: password) }
    }

    func register(name: String, email: String, password: String) async -> Bool {
        guard let backend else { return unavailable() }
        let name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (2...80).contains(name.count) else {
            error = "Имя должно содержать от 2 до 80 символов."; return false
        }
        guard let email = validatedEmail(email), validNewPassword(password) else { return false }
        return await authenticate { try await backend.register(name: name, email: email, password: password) }
    }

    func signOut() async -> Bool {
        guard let backend else { return unavailable() }
        return await endSession { try await backend.signOut() }
    }

    func deleteAccount() async -> Bool {
        guard let backend else { return unavailable() }
        return await endSession { try await backend.deleteAccount() }
    }

    func requestPasswordReset(email: String) async -> Bool {
        guard let backend else { return unavailable() }
        guard let email = validatedEmail(email) else { return false }
        guard passwordResetAvailable else {
            error = "Восстановление пароля сейчас недоступно. Попробуй позже."; return false
        }
        guard !isWorking, !isRestoring else { return false }
        let operation = beginAuthentication()
        defer { finishAuthentication(operation) }
        do {
            try await backend.requestPasswordReset(email: email)
            guard authenticationID == operation, !Task.isCancelled else { return false }
            notice = "Если аккаунт с этой почтой существует, на неё придёт ссылка для смены пароля."
            return true
        } catch is CancellationError { return false }
        catch {
            guard authenticationID == operation, !Task.isCancelled else { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func confirmPasswordReset(token: String, password: String) async -> Bool {
        guard let backend else { return unavailable() }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { error = "Открой ссылку из письма для смены пароля."; return false }
        guard validNewPassword(password) else { return false }
        return await authenticate { try await backend.confirmPasswordReset(token: token, password: password) }
    }

    func refreshSaved() async {
        guard let backend, user != nil else { return }
        guard sessionVerified else { await restore(); return }
        let session = sessionID
        let refresh = UUID()
        let revision = savedRevision
        refreshID = refresh
        refreshing = true
        updateSyncing()
        defer {
            if sessionID == session, refreshID == refresh {
                refreshing = false
                updateSyncing()
            }
        }
        do {
            let items = try await backend.savedPlaces()
            guard sessionID == session, refreshID == refresh, !Task.isCancelled else { return }
            // A list captured before a heart change must never undo that change.
            guard savedRevision == revision, saveTasks.isEmpty else { return }
            confirmed = items.reduce(into: [:]) { result, item in
                result[item.id] = item.snapshot.place(id: item.id)
            }
            savedPlaces = confirmed.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            hasLoadedSaved = true
            isShowingCachedData = false
            persistCache()
            syncError = savedFailureMessage
        } catch is CancellationError { }
        catch {
            guard sessionID == session, refreshID == refresh, !Task.isCancelled else { return }
            if isUnauthorized(error) { expireSession() }
            else { syncError = error.localizedDescription }
        }
    }

    func retrySavedChanges() async {
        guard backend != nil, user != nil else { return }
        let session = sessionID
        let changes = failedChanges.sorted { $0.key < $1.key }.map(\.value)
        syncError = nil
        for change in changes {
            guard sessionID == session, !Task.isCancelled else { return }
            // Another heart action may have superseded a later entry while a prior retry awaited.
            guard failedChanges[change.place.id]?.id == change.id else { continue }
            queue(change.place, saved: change.saved, clearError: false)
            await saveTasks[change.place.id]?.value
        }
        guard sessionID == session, !Task.isCancelled else { return }
        if failedChanges.isEmpty { await refreshSaved() }
    }

    func isSaved(_ place: Place) -> Bool { savedPlaces.contains { $0.id == place.id } }

    func toggleSaved(_ place: Place) {
        guard backend != nil, user != nil else {
            syncError = "Войди в аккаунт, чтобы сохранить место на сервере."; return
        }
        guard !isShowingCachedData else {
            syncError = "Пока показан кэш. Подключись к интернету и обнови избранное."; return
        }
        queue(place, saved: !isSaved(place))
    }

    /// Uploads only after an explicit user action. Failed entries stay in guest storage.
    @discardableResult
    func importGuestPlaces(_ places: [Place]) async -> [String] {
        guard backend != nil, user != nil else {
            syncError = "Войди в аккаунт, чтобы перенести избранное."; return []
        }
        guard !isShowingCachedData else {
            syncError = "Сначала обнови избранное, чтобы подтвердить аккаунт."; return []
        }
        let session = sessionID
        syncError = savedFailureMessage
        notice = nil
        var imported: [String] = []
        var seen = Set<String>()
        for place in places where seen.insert(place.id).inserted {
            guard sessionID == session, !Task.isCancelled else { return [] }
            if confirmed[place.id] == nil || !isSaved(place) {
                queue(place, saved: true, clearError: false)
                await saveTasks[place.id]?.value
            }
            guard sessionID == session, !Task.isCancelled else { return [] }
            if confirmed[place.id] != nil, isSaved(place) { imported.append(place.id) }
        }
        syncError = savedFailureMessage
        if !imported.isEmpty { notice = "В аккаунт сохранено мест: \(imported.count)." }
        return imported
    }

    private func authenticate(_ operation: @Sendable () async throws -> AccountUser) async -> Bool {
        guard !isWorking, !isRestoring else { return false }
        let request = beginAuthentication()
        defer { finishAuthentication(request) }
        do {
            let authenticated = try await operation()
            guard authenticationID == request, !Task.isCancelled else { return false }
            setSession(authenticated)
            sessionVerified = true
            await refreshSaved()
            // A successful auth result remains valid when loading favorites failed.
            return user?.id == authenticated.id
        } catch is CancellationError { return false }
        catch {
            guard authenticationID == request, !Task.isCancelled else { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    private func endSession(_ operation: @Sendable () async throws -> Void) async -> Bool {
        guard !isWorking, !isRestoring else { return false }
        let request = beginAuthentication()
        defer { finishAuthentication(request) }
        do {
            try await operation()
            guard authenticationID == request, !Task.isCancelled else { return false }
            setSession(nil)
            return true
        } catch is CancellationError { return false }
        catch {
            guard authenticationID == request, !Task.isCancelled else { return false }
            if isUnauthorized(error) { expireSession() }
            else { self.error = error.localizedDescription }
            return false
        }
    }

    private func beginAuthentication() -> UUID {
        authenticationID = UUID()
        isRestoring = false
        isWorking = true
        error = nil
        notice = nil
        return authenticationID
    }

    private func finishAuthentication(_ operation: UUID) {
        if authenticationID == operation { isWorking = false }
    }

    private func setSession(_ value: AccountUser?) {
        let cached = cachedSession().flatMap { $0.user.id == value?.id ? $0 : nil }
        sessionID = UUID()
        refreshID = UUID()
        savedRevision += 1
        for task in saveTasks.values { task.cancel() }
        saveTasks.removeAll()
        desired.removeAll()
        pendingPlaces.removeAll()
        failedChanges.removeAll()
        confirmed.removeAll()
        savedPlaces.removeAll()
        refreshing = false
        syncError = nil
        updateSyncing()
        user = value
        sessionVerified = false
        hasLoadedSaved = false
        isShowingCachedData = false
        if let cached {
            confirmed = Dictionary(cached.places.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            savedPlaces = confirmed.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            hasLoadedSaved = cached.hasLoadedSaved
            isShowingCachedData = true
        }
        if value == nil { defaults?.removeObject(forKey: cacheKey) }
        else { persistCache() }
    }

    private func expireSession() {
        setSession(nil)
        error = "Сессия истекла. Войди в аккаунт ещё раз."
    }

    private func queue(_ place: Place, saved: Bool, clearError: Bool = true) {
        guard !place.id.isEmpty else { syncError = "Не удалось сохранить место без идентификатора."; return }
        savedRevision += 1
        failedChanges.removeValue(forKey: place.id)
        desired[place.id] = saved
        pendingPlaces[place.id] = place
        if clearError { syncError = savedFailureMessage }
        setVisible(place, saved: saved)
        guard saveTasks[place.id] == nil else { return }
        let session = sessionID
        saveTasks[place.id] = Task { [weak self] in await self?.drain(placeID: place.id, session: session) }
        updateSyncing()
    }

    private func drain(placeID: String, session: UUID) async {
        defer {
            if sessionID == session {
                saveTasks.removeValue(forKey: placeID)
                desired.removeValue(forKey: placeID)
                pendingPlaces.removeValue(forKey: placeID)
                updateSyncing()
            }
        }
        guard let backend else { return }
        while sessionID == session, !Task.isCancelled, let target = desired[placeID] {
            guard target != (confirmed[placeID] != nil), let place = pendingPlaces[placeID] else { break }
            do {
                if target {
                    let item = try await backend.savePlace(id: placeID, snapshot: SavedPlaceSnapshot(place: place))
                    guard sessionID == session, !Task.isCancelled else { return }
                    guard item.id == placeID else { throw APIError.invalidResponse }
                    confirmed[placeID] = item.snapshot.place(id: item.id)
                } else {
                    try await backend.removeSavedPlace(id: placeID)
                    guard sessionID == session, !Task.isCancelled else { return }
                    confirmed.removeValue(forKey: placeID)
                }
                persistCache()
                // Keep the most recent visible intent while a second write is needed.
                if desired[placeID] == (confirmed[placeID] != nil) {
                    setVisible(confirmed[placeID] ?? place, saved: confirmed[placeID] != nil)
                }
            } catch is CancellationError { return }
            catch {
                guard sessionID == session, !Task.isCancelled else { return }
                if isUnauthorized(error) { expireSession() }
                else {
                    let latestTarget = desired[placeID] ?? target
                    if latestTarget != (confirmed[placeID] != nil) {
                        failedChanges[placeID] = FailedChange(place: pendingPlaces[placeID] ?? place, saved: latestTarget, message: error.localizedDescription)
                    }
                    setVisible(confirmed[placeID] ?? place, saved: confirmed[placeID] != nil)
                    syncError = savedFailureMessage ?? error.localizedDescription
                }
                return
            }
        }
    }

    private func setVisible(_ place: Place, saved: Bool) {
        savedPlaces.removeAll { $0.id == place.id }
        if saved { savedPlaces.append(place) }
        savedPlaces.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private struct FailedChange {
        let id = UUID()
        let place: Place
        let saved: Bool
        let message: String
    }
    private struct CachedSession: Codable {
        let user: AccountUser
        let places: [Place]
        let hasLoadedSaved: Bool
    }
    private var cacheKey: String {
        let scope = (backend as? BackendAPI)?.baseURL.absoluteString ?? "account"
        return "seru.account.cachedSession." + Data(scope.utf8).base64EncodedString()
    }
    private func cachedSession() -> CachedSession? {
        guard let data = defaults?.data(forKey: cacheKey), data.count <= 4 * 1024 * 1024,
              let value = try? JSONDecoder().decode(CachedSession.self, from: data),
              !value.user.id.isEmpty else { return nil }
        return value
    }
    private func persistCache() {
        guard let user else { return }
        let value = CachedSession(user: user, places: confirmed.values.sorted { $0.id < $1.id }, hasLoadedSaved: hasLoadedSaved)
        if let bytes = try? JSONEncoder().encode(value), bytes.count <= 4 * 1024 * 1024 {
            defaults?.set(bytes, forKey: cacheKey)
        }
    }
    private var savedFailureMessage: String? { failedChanges.sorted { $0.key < $1.key }.first?.value.message }
    private func updateSyncing() { isSyncing = refreshing || !saveTasks.isEmpty }
    private func isUnauthorized(_ error: any Error) -> Bool {
        if case .http(let status, _) = error as? APIError { return status == 401 }
        return false
    }
    private func unavailable() -> Bool {
        error = "Аккаунт доступен при подключении к серверу."; return false
    }
    private func validatedEmail(_ value: String) -> String? {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 254, parts.count == 2, !parts[0].isEmpty,
              parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !email.contains(where: \.isWhitespace) else {
            error = "Введи корректный адрес почты."; return nil
        }
        return email
    }
    private func validNewPassword(_ password: String) -> Bool {
        guard (8...128).contains(password.count) else {
            error = "Пароль должен содержать от 8 до 128 символов."; return false
        }
        return true
    }
}
