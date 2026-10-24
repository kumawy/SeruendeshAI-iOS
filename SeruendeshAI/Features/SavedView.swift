import SwiftUI

struct SavedView: View {
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @State private var presentation: SavedPresentation?
    @State private var accountOpen = false

    var body: some View {
        let hasAccountStatus = app.usesBackend && showsAccountStatus

        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                GeometryReader { viewport in
                    ScrollView {
                        VStack(spacing: 0) {
                            if hasAccountStatus {
                                accountStatus
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 20)
                            }

                            if app.account.user != nil && !app.account.hasLoadedSaved && app.savedPlaces.isEmpty {
                                unavailableAccountPlaces
                                    .padding(24)
                                    .frame(maxWidth: .infinity)
                            } else if app.savedPlaces.isEmpty {
                                emptyState
                                    .frame(minHeight: hasAccountStatus ? nil : viewport.size.height)
                            } else {
                                LazyVStack(spacing: 20) {
                                    ForEach(app.savedPlaces) { place in
                                        SavedPlaceCard(
                                            place: place,
                                            isSaved: app.isSaved(place),
                                            showDetail: { presentation = .place(place) },
                                            showRoute: { presentation = .route(place) },
                                            toggleSaved: { app.toggleSaved(place) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 28)
                            }
                        }
                    }
                    .accessibilityIdentifier("saved-places-content")
                    .refreshable {
                        if app.account.user != nil { await app.account.refreshSaved() }
                    }
                }
            }
            .background(SeruColor.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $presentation) { destination in
                savedSheet(destination)
            }
            .sheet(isPresented: $accountOpen) { ProfileView() }
            .onChange(of: app.tab) {
                if app.tab == .walk {
                    presentation = nil
                }
            }
        }
        .tint(SeruColor.action)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Избранное")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("saved-title")

            ProfileButton { accountOpen = true }
                .accessibilityIdentifier(app.account.user == nil ? "saved-sign-in" : "saved-account")
        }
    }

    private var showsAccountStatus: Bool {
        if app.account.isRestoring { return true }
        if app.account.user == nil { return app.account.error != nil }
        return app.account.isSyncing || app.account.syncError != nil || app.account.isShowingCachedData || !app.guestSavedPlaces.isEmpty
    }

    @ViewBuilder
    private var accountStatus: some View {
        if app.account.isRestoring {
            ProgressView("Проверяем аккаунт")
                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        } else if app.account.user == nil {
            if let error = app.account.error {
                Text(error).font(.subheadline).foregroundStyle(SeruColor.muted)
                    .accessibilityIdentifier("saved-session-error")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if app.account.isShowingCachedData {
                    Label("Показана последняя сохранённая копия. Для изменений обнови избранное.", systemImage: "internaldrive")
                        .font(.subheadline).foregroundStyle(SeruColor.muted)
                        .accessibilityIdentifier("saved-cached-data")
                }
                if app.account.isSyncing {
                    ProgressView("Синхронизация")
                        .font(.subheadline).accessibilityIdentifier("saved-syncing")
                }
                if let error = app.account.syncError {
                    Text(error).font(.subheadline).foregroundStyle(SeruColor.muted)
                        .accessibilityIdentifier("saved-sync-error")
                    Button("Повторить", systemImage: "arrow.clockwise") {
                        Task { await app.retryAccountSavedChanges() }
                    }.disabled(app.account.isSyncing)
                }
                if !app.guestSavedPlaces.isEmpty {
                    Button("Добавить места с устройства", systemImage: "icloud.and.arrow.up") {
                        Task { await app.importGuestSavedPlaces() }
                    }
                    .font(.subheadline).frame(minHeight: 44)
                    .disabled(app.account.isSyncing || app.account.isWorking || app.account.isShowingCachedData)
                    .accessibilityIdentifier("saved-import-guest")
                }
            }
        }
    }

    @ViewBuilder private var unavailableAccountPlaces: some View {
        if app.account.isRestoring || app.account.isSyncing {
            ProgressView("Загружаем избранное")
                .accessibilityIdentifier("saved-loading")
        } else {
            ContentUnavailableView {
                Label("Не удалось загрузить избранное", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Проверь подключение и попробуй ещё раз.")
            } actions: {
                Button("Повторить") { Task { await app.account.restore() } }
            }
            .accessibilityIdentifier("saved-load-error")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            SavedMascotAnimation(isActive: mascotActive && app.tab == .saved && !accountOpen && presentation == nil)
                .frame(width: 208, height: 208)
                .padding(.bottom, 24)

            Text("Пока пусто")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 290)
                .accessibilityIdentifier("saved-empty-title")

            Text("Любимые места появятся здесь")
                .font(.subheadline).foregroundStyle(SeruColor.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            PrimaryAction(title: "Найти места", symbol: "magnifyingglass") {
                app.tab = .walk
            }
            .frame(maxWidth: 240)
            .padding(.top, 24)
            .accessibilityIdentifier("saved-empty-discover")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private func savedSheet(_ destination: SavedPresentation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch destination {
                    case .place(let place):
                        PlaceDetailContent(place: place)
                    case .route(let place):
                        RoutePreviewContent(place: place,
                                            mascotActive: mascotActive && presentation != nil && !accountOpen,
                                            owningTab: .saved)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(SeruColor.background)
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { presentation = nil }
                }
            }
        }
        .tint(SeruColor.action)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private enum SavedPresentation: Identifiable {
    case place(Place)
    case route(Place)

    var id: String {
        switch self {
        case .place(let place): return "place-\(place.id)"
        case .route(let place): return "route-\(place.id)"
        }
    }

    var title: String {
        switch self {
        case .place: return "Место"
        case .route: return "Маршрут"
        }
    }
}

private struct SavedPlaceCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let place: Place
    let isSaved: Bool
    let showDetail: () -> Void
    let showRoute: () -> Void
    let toggleSaved: () -> Void

    private var displayImageAsset: String {
        if place.isLive { return "" }
        return switch place.id {
        case "garden": "saved-asset-000"
        case "coffee": "saved-asset-001"
        case "river": "saved-asset-002"
        default: place.imageAsset
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Button(action: showDetail) {
                    thumbnail
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Подробнее: \(place.name)")
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 0) {
                        Button(action: showDetail) {
                            Text(place.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(SeruColor.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("saved-place-\(place.id)")
                        if !dynamicTypeSize.isAccessibilitySize {
                            bookmark
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            rating
                            hours
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            rating
                            hours
                        }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        bookmark
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    walkingDistance
                    Spacer(minLength: 4)
                    routeButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    walkingDistance
                    routeButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(SeruColor.line)
                .frame(height: 1)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
    }

    private var thumbnail: some View {
        PlaceArtwork(place: place, bundledAsset: displayImageAsset)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 80 : 88,
                   height: dynamicTypeSize.isAccessibilitySize ? 80 : 88)
            .clipped()
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    private var bookmark: some View {
        Button(action: toggleSaved) {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSaved ? Color.red : SeruColor.action)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(app.account.user != nil && app.account.isShowingCachedData)
        .sensoryFeedback(.selection, trigger: isSaved)
        .accessibilityLabel(isSaved ? "Удалить \(place.name) из избранного" : "Сохранить \(place.name)")
    }

    @ViewBuilder private var rating: some View {
        if !place.rating.isEmpty {
            Label(place.rating, systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .accessibilityLabel("Рейтинг \(place.rating)")
        }
    }

    private var hours: some View {
        Text(place.hours)
            .font(.caption)
            .foregroundStyle(SeruColor.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var walkingDistance: some View {
        let parts = [
            place.distance.isEmpty ? nil : place.distance,
            place.travelMinutes > 0 ? "~\(place.travelMinutes) мин" : nil
        ].compactMap { $0 }
        if !parts.isEmpty {
            Label(parts.joined(separator: " · "), systemImage: "figure.walk")
                .font(.footnote)
                .foregroundStyle(SeruColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var routeButton: some View {
        Button(action: showRoute) {
            Label("Маршрут", systemImage: "arrow.turn.up.right")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeruColor.action)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Маршрут к месту \(place.name)")
        .accessibilityIdentifier("saved-place-route-\(place.id)")
    }
}

