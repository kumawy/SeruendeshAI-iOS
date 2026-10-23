import SwiftUI

struct WalkPlanContent: View {
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var audioGuide = ItineraryAudioGuide()

    private var route: WalkRoute? { app.usesBackend ? app.currentPlan : DemoData.featuredRoute }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let route {
                header(route)
                timeline(route)
                audioWidget(route)
                actions(route)
            } else if app.isLoadingPlan {
                VStack(spacing: 12) {
                    WalkStateMascot(scene: .routing, isActive: mascotActive)
                        .frame(width: 156, height: 156)
                    Text("Составляем план прогулки").font(.subheadline)
                }
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if app.planError != nil {
                planUnavailable
            } else {
                // The model-owned request starts on appearance; do not imply a failure before it starts.
                WalkStateMascot(scene: .routing, isActive: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .task {
            if app.usesBackend && app.currentPlan == nil && !app.isLoadingPlan && app.planError == nil {
                await app.retryPlan()
            }
        }
        .onDisappear { audioGuide.stop() }
    }

    private var planUnavailable: some View {
        VStack(alignment: .leading, spacing: 14) {
            WalkStateMascot(scene: .routeBlocked, isActive: mascotActive)
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity)
            Label("План пока не готов", systemImage: "map")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
            Text(app.planError ?? "Попробуйте составить прогулку ещё раз.")
                .font(.subheadline)
                .foregroundStyle(SeruColor.muted)
            PrimaryAction(title: "Повторить", symbol: "arrow.clockwise") {
                Task { await app.retryPlan() }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .seruCard(radius: 16)
    }

    private func durationLabel(_ route: WalkRoute) -> String {
        let hours = route.duration / 60
        let minutes = route.duration % 60
        if hours == 0 { return "\(minutes) мин" }
        if minutes == 0 { return "\(hours) ч" }
        return "\(hours) ч \(minutes) мин"
    }

    private func stops(_ route: WalkRoute) -> [WalkPlanStop] {
        if !route.isLive {
            return [
                WalkPlanStop(place: app.place(id: "baiterek"), number: 1, title: "Монумент Байтерек", detail: "15 мин на месте", asset: "plan-asset-001", nextID: "coffee"),
                WalkPlanStop(place: app.place(id: "coffee"), number: 2, title: "Бульвар Нуржол и кофе", detail: "20 мин на месте", asset: "plan-asset-002", nextID: "garden"),
                WalkPlanStop(place: app.place(id: "garden"), number: 3, title: "Ботанический сад", detail: "35 мин на месте", asset: "plan-asset-003", nextID: nil)
            ]
        }
        return route.placeIDs.enumerated().map { index, id in
            let place = app.place(id: id)
            return WalkPlanStop(
                place: place,
                number: index + 1,
                title: place.name,
                detail: place.visitMinutes > 0 ? "\(place.visitMinutes) мин на месте" : place.category,
                asset: nil,
                nextID: index + 1 < route.placeIDs.count ? route.placeIDs[index + 1] : nil
            )
        }
    }

    private func guideText(_ route: WalkRoute) -> String {
        if !route.isLive {
            return "Начнём у монумента Байтерек. С площади отправимся по бульвару Нуржол, где можно рассмотреть современную архитектуру и остановиться на кофе. Затем пройдём к Ботаническому саду. Здесь есть оранжерея, пруд и дорожки среди зелени."
        }
        return stops(route).map { stop in
            "Остановка \(stop.number). \(stop.title). \(stop.place.reason)"
        }.joined(separator: " ")
    }

    private func shareText(_ route: WalkRoute) -> String {
        let details = [
            route.duration > 0 ? durationLabel(route) : nil,
            route.distance.isEmpty ? nil : route.distance,
            "\(route.placeIDs.count) \(stopCountWord(route.placeIDs.count))"
        ].compactMap { $0 }.joined(separator: " · ")
        return "\(route.name): \(route.subtitle). \(details). SeruendeshAI."
    }

    private func stopCountWord(_ count: Int) -> String {
        if (11...14).contains(count % 100) { return "остановок" }
        switch count % 10 {
        case 1: return "остановка"
        case 2...4: return "остановки"
        default: return "остановок"
        }
    }

    private func header(_ route: WalkRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(route.name)
                    .font(.title.weight(.bold))
                    .tracking(-0.4)
                    .foregroundStyle(SeruColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                ShareLink(item: shareText(route)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(SeruColor.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Поделиться планом прогулки")
            }
            HStack(spacing: 12) {
                if !route.isLive || route.duration > 0 {
                    Label(durationLabel(route), systemImage: "clock")
                }
                if !route.distance.isEmpty {
                    Label(route.distance, systemImage: "figure.walk")
                }
            }
            .font(.subheadline)
            .foregroundStyle(SeruColor.muted)
            if route.isLive && route.legs.contains(where: { $0.geometry == "straight" }) {
                Text("Часть пути оценена по прямой. Уточните маршрут в картах.")
                    .font(.caption)
                    .foregroundStyle(SeruColor.muted)
            }
        }
    }

    private func timeline(_ route: WalkRoute) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if route.isLive, let initial = route.legs.first, initial.fromID == "start" {
                Label(route.originLabel ?? "Начальная точка", systemImage: "location.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(SeruColor.ink)
                Text("\(initial.travelMinutes) мин · \(walkDistanceLabel(initial.distanceMeters))")
                    .font(.caption).foregroundStyle(SeruColor.muted).padding(.top, 6).padding(.bottom, 16)
            }
            ForEach(stops(route)) { stop in
                WalkPlanTimelineRow(
                    stop: stop,
                    transfer: transfer(after: stop, route: route),
                    action: { app.showPlace(stop.place) }
                )
            }
        }
    }

    private func transfer(after stop: WalkPlanStop, route: WalkRoute) -> WalkPlanTransfer? {
        guard let nextID = stop.nextID else { return nil }
        if !route.isLive {
            return stop.number == 1
                ? WalkPlanTransfer(minutes: 8, distance: "650 м")
                : WalkPlanTransfer(minutes: 12, distance: "950 м")
        }
        guard let leg = route.legs.first(where: { $0.fromID == stop.id && $0.toID == nextID }),
              leg.travelMinutes > 0 || leg.distanceMeters > 0 else { return nil }
        return WalkPlanTransfer(
            minutes: leg.travelMinutes,
            distance: leg.distanceMeters > 0 ? walkDistanceLabel(leg.distanceMeters) : ""
        )
    }

    private func audioWidget(_ route: WalkRoute) -> some View {
        Button { audioGuide.toggle(text: guideText(route)) } label: {
            HStack(spacing: 10) {
                Label("Аудиогид", systemImage: "headphones")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: audioGuide.isPlaying ? "stop.fill" : "play.fill")
                    .font(.subheadline)
            }
            .foregroundStyle(SeruColor.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(SeruColor.field, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audioGuide.isPlaying ? "Остановить аудиогид" : "Включить аудиогид")
        .accessibilityIdentifier("plan-audio-guide")
    }

    private func actions(_ route: WalkRoute) -> some View {
        VStack(spacing: 10) {
            Button {
                app.showFullRoute(route)
            } label: {
                Label("Посмотреть маршрут", systemImage: "map")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SeruColor.onAction)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(SeruColor.action, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan-route")
            HStack(spacing: 8) { secondaryActions(route) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func secondaryActions(_ route: WalkRoute) -> some View {
        Button {
            guard let finalID = route.placeIDs.last else { return }
            let finalPlace = app.place(id: finalID)
            let url = route.isLive
                ? LiveMapLink.url(provider: .twoGIS, destination: finalPlace.name, coordinate: finalPlace.coordinate,
                                  origin: route.originLabel, originCoordinate: route.originCoordinate)
                : ExternalMapProvider.twoGIS.url(destination: finalPlace.name)
            guard let url else { return }
            openURL(url) { accepted in
                if !accepted { app.toast = "Не удалось открыть карту" }
            }
        } label: {
            ItineraryActionLabel(title: "Открыть в 2ГИС", screen: "plan", index: 22)
        }
        Button { app.toggleSavedRoute(route) } label: {
            ItineraryActionLabel(title: app.isRouteSaved(route) ? "Сохранено" : "Сохранить", screen: "plan", index: 23, selected: app.isRouteSaved(route))
        }
        .accessibilityValue(app.isRouteSaved(route) ? "Сохранено" : "Не сохранено")
        .accessibilityIdentifier("plan-save-route")
    }
}

private struct WalkPlanStop: Identifiable {
    let place: Place
    let number: Int
    let title: String
    let detail: String
    let asset: String?
    let nextID: String?
    var id: String { place.id }
}

private struct WalkPlanTransfer {
    let minutes: Int
    let distance: String
}

private struct WalkPlanTimelineRow: View {
    let stop: WalkPlanStop
    let transfer: WalkPlanTransfer?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WalkTimelineStop(stop: stop, action: action)
            if let transfer {
                WalkTimelineTransfer(minutes: transfer.minutes, distance: transfer.distance)
            }
        }
    }
}

private struct WalkTimelineStop: View {
    let stop: WalkPlanStop
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(stop.number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .frame(width: 30, height: 30)
                .background(SeruColor.field, in: .circle)
                .accessibilityHidden(true)
            Button(action: action) {
                HStack(spacing: 12) {
                    PlaceArtwork(place: stop.place, bundledAsset: stop.asset)
                        .frame(width: 58, height: 58)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stop.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SeruColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(stop.detail)
                            .font(.caption)
                            .foregroundStyle(SeruColor.muted)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Остановка \(stop.number). \(stop.title). \(stop.detail)")
            .accessibilityHint("Открыть информацию о месте")
            .accessibilityIdentifier("plan-stop-\(stop.id)")
        }
    }
}

private struct WalkTimelineTransfer: View {
    let minutes: Int
    let distance: String

    private var label: String {
        [minutes > 0 ? "\(minutes) мин" : nil, distance.isEmpty ? nil : distance]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(SeruColor.line)
                .frame(width: 1, height: 26)
                .frame(width: 30)
                .accessibilityHidden(true)
            Label(label, systemImage: "figure.walk")
                .font(.caption)
                .foregroundStyle(SeruColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
