import SwiftUI

struct RoutePreviewContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var showsMapChooser = false

    let place: Place
    var route: WalkRoute? = nil
    var mascotActive: Bool = true
    var owningTab: AppTab = .walk

    private var livePreview: RoutePreview? {
        guard route == nil, app.routePreview?.placeID == place.id else { return nil }
        return app.routePreview
    }
    private var originCoordinate: GeoPoint? { route?.originCoordinate ?? livePreview?.origin ?? app.originCoordinate }
    private var origin: String { route?.originLabel ?? livePreview?.originLabel ?? app.origin }
    private var destinationPlace: Place { stops.last ?? place }
    private var stops: [Place] { route?.placeIDs.map { app.place(id: $0) } ?? [place] }
    private var estimatedMeters: Int? {
        guard !place.isLive, let start = originCoordinate, let end = place.coordinate else { return nil }
        return WalkPlanner.estimatedDistance(from: start, to: end)
    }
    private var minutes: Int? {
        if let route { return route.duration }
        if place.isLive { return livePreview?.travelMinutes }
        return estimatedMeters.map { Int(ceil(Double($0) / 75)) }
    }
    private var distance: String {
        if let route { return route.distance }
        if let livePreview { return walkDistanceLabel(livePreview.distanceMeters) }
        return estimatedMeters.map(walkDistanceLabel) ?? ""
    }
    private var fullRouteURL: URL? {
        MapLinks.orderedWalk(origin: origin, originCoordinate: originCoordinate, places: stops,
                             returnsToStart: route?.returnsToStart == true)
    }
    private var shareText: String {
        if let route { return MapLinks.shareRoute(route, places: stops) }
        var single = WalkRoute(id: place.id, name: "Пеший маршрут", subtitle: "", duration: minutes ?? 0,
                               distance: distance, placeIDs: [place.id])
        single.originLabel = origin; single.originCoordinate = originCoordinate
        return MapLinks.shareRoute(single, places: [place])
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
            if place.isLive && route == nil { await app.loadRoutePreview(for: place) }
        }
        .confirmationDialog("Открыть в картах", isPresented: $showsMapChooser, titleVisibility: .visible) {
            ForEach(ExternalMapProvider.allCases) { provider in
                Button(mapActionTitle(provider)) { openMap(provider) }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            if route != nil { Text("Apple Maps сохранит все остановки. В других картах откроется последняя точка или путь до неё.") }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(route?.name ?? "Маршрут")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("route-title")
            if place.isLive && route == nil {
                liveRouteStatus
            } else if minutes != nil {
                routeMetrics
            } else {
                Text("Время пути пока не рассчитано. Открой место в Картах и выбери старт.")
                    .font(.subheadline)
                    .foregroundStyle(SeruColor.muted)
            }
            if let route {
                if route.returnsToStart == true {
                    Label("С возвратом к старту", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                } else if let back = route.returnMinutes, route.returnsToStart == false {
                    Text("Обратно к старту — ещё примерно \(back) мин.")
                        .font(.footnote)
                } else if route.returnsToStart == nil {
                    Text("Возврат к старту не указан.").font(.footnote)
                }
                if route.fitsBudget == false {
                    Label("Маршрут дольше выбранного времени", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                }
            }
            if (!place.isLive && route == nil && estimatedMeters != nil) ||
                route?.legs.contains(where: { $0.geometry != "network" }) == true {
                Text("Пунктир на карте — примерный путь. Время оценено с запасом по расстоянию. Проверь проходы в Картах.")
                    .font(.footnote)
                    .foregroundStyle(SeruColor.muted)
            }
        }
        .foregroundStyle(SeruColor.ink)
    }

    @ViewBuilder private var liveRouteStatus: some View {
        if app.isLoadingRoute && livePreview == nil {
            routeLoading
        } else if let error = app.routeError, livePreview == nil {
            VStack(alignment: .leading, spacing: 12) {
                WalkStateMascot(scene: .routeBlocked, isActive: mascotActive && !showsMapChooser, owningTab: owningTab)
                    .frame(width: 148, height: 148)
                    .frame(maxWidth: .infinity)
                Text("Не удалось построить маршрут").font(.headline)
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
            if preview.geometry != "network" {
                Text("Путь оценён примерно. Проверь пешеходный маршрут в Картах.")
                    .font(.footnote)
                    .foregroundStyle(SeruColor.muted)
            }
        } else { routeLoading }
    }

    private var routeLoading: some View {
        VStack(spacing: 12) {
            WalkStateMascot(scene: .routing, isActive: mascotActive && app.isLoadingRoute && !showsMapChooser, owningTab: owningTab)
                .frame(width: 148, height: 148)
            Text("Строим маршрут").font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }

    private var routeMetrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { metricItems }
                VStack(alignment: .leading, spacing: 8) { metricItems }
            }
            if route != nil { Text("Всего, с остановками").font(.caption).foregroundStyle(SeruColor.muted) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("route-loaded")
    }

    @ViewBuilder private var metricItems: some View {
        if let minutes {
            Text("\(minutes) мин")
                .font(.title.weight(.bold))
                .foregroundStyle(SeruColor.ink)
        }
        if !distance.isEmpty { Text(distance).font(.title3).foregroundStyle(SeruColor.muted) }
    }

    private var waypoints: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Старт: \(origin.isEmpty ? "не задан" : origin)", systemImage: "flag.fill")
                .font(.subheadline.weight(.medium))
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                Button { app.showPlace(stop) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 26, height: 26)
                            .background(SeruColor.surface, in: .circle)
                        Text(stop.name)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Остановка \(index + 1). \(stop.name)")
                .accessibilityHint("Открыть информацию о месте")
            }
            if route?.returnsToStart == true {
                Label("Возврат: \(origin)", systemImage: "flag.checkered")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(SeruColor.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeruColor.field, in: .rect(cornerRadius: 12))
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if fullRouteURL != nil {
                PrimaryAction(title: route == nil ? "Пешком в Apple Maps" : "Весь маршрут в Apple Maps", symbol: "arrow.up.right") {
                    openMap(.apple)
                }
                .accessibilityIdentifier("route-open-apple")
            }
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

    private func mapActionTitle(_ provider: ExternalMapProvider) -> String {
        if provider == .apple, fullRouteURL != nil {
            return route == nil ? "Пешком в Apple Maps" : "Весь маршрут в Apple Maps"
        }
        let hasRoute = originCoordinate?.isValid == true && destinationPlace.coordinate?.isValid == true
        if provider == .twoGIS, route != nil, hasRoute { return "До последней остановки в 2ГИС" }
        return provider.actionTitle(hasRoute: hasRoute)
    }

    private func openMap(_ provider: ExternalMapProvider) {
        let link = provider == .apple ? fullRouteURL ?? MapLinks.place(provider: .apple, destination: destinationPlace.name, coordinate: destinationPlace.coordinate)
            : MapLinks.destinationRoute(provider: provider, destination: destinationPlace.name, coordinate: destinationPlace.coordinate,
                                        origin: origin, originCoordinate: originCoordinate)
        guard let link else { app.toast = "Для этого места пока нет данных карты"; return }
        openURL(link) { accepted in if !accepted { app.toast = "Не удалось открыть карту" } }
    }
}
