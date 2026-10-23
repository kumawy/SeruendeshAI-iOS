import SwiftUI

struct RoutePreviewContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var showsMapChooser = false

    let place: Place
    var route: WalkRoute? = nil
    var mascotActive: Bool = true
    var owningTab: AppTab = .walk

    private var isLive: Bool { route?.isLive ?? place.isLive }
    private var isGarden: Bool { !isLive && place.name.localizedCaseInsensitiveContains("Ботаническ") }
    private var livePreview: RoutePreview? {
        guard route == nil, app.routePreview?.placeID == place.id else { return nil }
        return app.routePreview
    }
    private var minutes: Int {
        if let route { return route.duration }
        if isLive { return livePreview?.travelMinutes ?? 0 }
        return isGarden ? 22 : place.travelMinutes
    }
    private var distance: String {
        if let route { return route.distance }
        if isLive {
            guard let meters = livePreview?.distanceMeters, meters > 0 else { return "" }
            return walkDistanceLabel(meters)
        }
        return isGarden ? "1.8 км" : place.distance
    }
    private var destinationPlace: Place {
        route?.placeIDs.last.map { app.place(id: $0) } ?? place
    }
    private var destination: String {
        if route != nil { return destinationPlace.name }
        return isGarden ? "Северный вход, Ботанический сад" : place.name
    }
    private var origin: String {
        if let route, route.isLive { return route.originLabel ?? "Начальная точка" }
        if let firstID = route?.placeIDs.first { return app.place(id: firstID).name }
        if isLive {
            return livePreview?.originLabel ?? (app.origin.isEmpty ? "Начальная точка" : app.origin)
        }
        return app.origin.isEmpty ? "Монумент Байтерек" : app.origin
    }
    private var shareText: String {
        let details = [minutes > 0 ? "\(minutes) мин" : nil, distance.isEmpty ? nil : distance]
            .compactMap { $0 }.joined(separator: " · ")
        return "Пеший маршрут: \(origin) → \(destination). \(details.isEmpty ? "" : details + ". ")SeruendeshAI."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            overview
            waypoints
            actions
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .task(id: place.id) {
            if isLive && route == nil {
                await app.loadRoutePreview(for: place)
            }
        }
        .confirmationDialog("Открыть маршрут", isPresented: $showsMapChooser, titleVisibility: .visible) {
            ForEach(ExternalMapProvider.allCases) { provider in
                Button(provider.rawValue) { openMap(provider) }
            }
            Button("Отмена", role: .cancel) { }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Маршрут")
                .font(.headline)
                .foregroundStyle(SeruColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("route-title")
            if isLive && route == nil {
                liveRouteStatus
            } else {
                routeMetrics
            }
        }
    }

    @ViewBuilder private var liveRouteStatus: some View {
        if app.isLoadingRoute && livePreview == nil {
            routeLoading
        } else if let error = app.routeError, livePreview == nil {
            VStack(alignment: .leading, spacing: 12) {
                WalkStateMascot(scene: .routeBlocked, isActive: mascotActive && !showsMapChooser,
                                owningTab: owningTab)
                    .frame(width: 148, height: 148)
                    .frame(maxWidth: .infinity)
                Text("Не удалось построить маршрут")
                    .font(.headline)
                    .foregroundStyle(SeruColor.ink)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(SeruColor.muted)
                    .accessibilityIdentifier("route-error")
                PrimaryAction(title: "Повторить", symbol: "arrow.clockwise") {
                    Task { await app.loadRoutePreview(for: place) }
                }
            }
        } else if let preview = livePreview {
            routeMetrics
            if preview.geometry == "straight" {
                Text("Оценка по прямой. Пешеходный путь уточняйте в картах.")
                    .font(.caption)
                    .foregroundStyle(SeruColor.muted)
            }
        } else {
            routeLoading
        }
    }

    private var routeLoading: some View {
        VStack(spacing: 12) {
            WalkStateMascot(scene: .routing,
                            isActive: mascotActive && app.isLoadingRoute && !showsMapChooser,
                            owningTab: owningTab)
                .frame(width: 148, height: 148)
            Text("Строим маршрут").font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }

    private var routeMetrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !isLive || minutes > 0 {
                Text("\(minutes) мин")
                    .font(.title.weight(.bold))
                    .tracking(-0.4)
                    .foregroundStyle(SeruColor.ink)
            }
            if !distance.isEmpty {
                Text("\(minutes > 0 ? "· " : "")\(distance)")
                    .font(.title3)
                    .foregroundStyle(SeruColor.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("route-loaded")
    }

    private var waypoints: some View {
        VStack(alignment: .leading, spacing: 6) {
            waypoint(name: origin, isStart: true)
            Rectangle()
                .fill(SeruColor.line)
                .frame(width: 1, height: 14)
                .padding(.leading, 5)
                .accessibilityHidden(true)
            waypoint(name: destination, isStart: false)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeruColor.field, in: .rect(cornerRadius: 12))
    }

    private func waypoint(name: String, isStart: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isStart ? SeruColor.surface : SeruColor.ink)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(SeruColor.ink, lineWidth: 1.5))
                .accessibilityHidden(true)
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isStart ? "Откуда" : "Куда"): \(name)")
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button { openMap(.twoGIS) } label: {
                HStack(spacing: 8) {
                    Text("Открыть в 2ГИС")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(SeruColor.onAction)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(SeruColor.action, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Button { showsMapChooser = true } label: {
                    Label("Другие карты", systemImage: "map")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SeruColor.ink)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(SeruColor.field, in: .rect(cornerRadius: 12))
                }
                ShareLink(item: shareText) {
                    ItineraryActionLabel(title: "Поделиться", screen: "route", index: 16)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func openMap(_ provider: ExternalMapProvider) {
        let url: URL?
        if isLive {
            let originCoordinate = route?.originCoordinate ?? livePreview?.origin
            url = LiveMapLink.url(
                provider: provider,
                destination: destinationPlace.name,
                coordinate: destinationPlace.coordinate,
                origin: origin,
                originCoordinate: originCoordinate
            )
        } else {
            url = provider.url(destination: destinationPlace.name, origin: origin + ", Астана")
        }
        guard let url else { return }
        openURL(url) { accepted in
            if !accepted { app.toast = "Не удалось открыть карту" }
        }
    }
}
