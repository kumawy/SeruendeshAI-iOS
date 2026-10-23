import SwiftUI

struct WalkPlanContent: View {
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var audioGuide = ItineraryAudioGuide()
    @State private var showingEditor = false

    private var route: WalkRoute? { app.currentPlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let route {
                header(route)
                timeline(route)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: route.placeIDs)
                audioWidget(route)
                actions(route)
            } else if app.isLoadingPlan {
                VStack(spacing: 12) {
                    WalkStateMascot(scene: .routing, isActive: mascotActive)
                        .frame(width: 156, height: 156)
                    Text("Составляем план прогулки").font(.subheadline)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                planUnavailable
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .task {
            if app.currentPlan == nil && !app.isLoadingPlan && app.planError == nil { await app.retryPlan() }
        }
        .onDisappear { audioGuide.stop() }
        .sheet(isPresented: $showingEditor) {
            if let route {
                PlanStopsEditor(places: route.placeIDs.map { app.place(id: $0) }) { ids in
                    audioGuide.stop()
                    app.updatePlan(placeIDs: ids)
                    if !ids.isEmpty, app.currentPlan?.placeIDs != ids {
                        app.toast = "Не все остановки поместились в выбранное время. Проверь обновлённый план."
                    }
                }
            }
        }
    }

    private var planUnavailable: some View {
        VStack(alignment: .leading, spacing: 14) {
            WalkStateMascot(scene: .routeBlocked, isActive: mascotActive)
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity)
            Text("В плане пока нет остановок")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
            Text(app.planError ?? "Попробуй изменить время или пожелания к прогулке.")
                .font(.subheadline)
                .foregroundStyle(SeruColor.muted)
            PrimaryAction(title: "Составить заново", symbol: "arrow.clockwise") {
                Task { await app.retryPlan() }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .seruCard(radius: 16)
    }

    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) мин" }
        if remainder == 0 { return "\(hours) ч" }
        return "\(hours) ч \(remainder) мин"
    }

    private func stops(_ route: WalkRoute) -> [WalkPlanStop] {
        route.placeIDs.enumerated().map { index, id in
            let place = app.place(id: id)
            return WalkPlanStop(place: place, number: index + 1, title: place.name,
                detail: place.visitMinutes > 0 ? "Около \(place.visitMinutes) мин на месте" : place.category,
                asset: nil, nextID: index + 1 < route.placeIDs.count ? route.placeIDs[index + 1] : nil)
        }
    }

    private func guideText(_ route: WalkRoute) -> String {
        stops(route).map { "Остановка \($0.number). \($0.title). \($0.place.reason)" }.joined(separator: " ")
    }

    private func header(_ route: WalkRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(route.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(SeruColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                ShareLink(item: MapLinks.shareRoute(route, places: route.placeIDs.map { app.place(id: $0) })) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(SeruColor.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Поделиться планом прогулки")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { planMetrics(route) }
                VStack(alignment: .leading, spacing: 8) { planMetrics(route) }
            }
            .font(.subheadline)
            .foregroundStyle(SeruColor.muted)
            returnInfo(route)
            if route.legs.contains(where: { $0.geometry != "network" }) {
                Text("Время и пунктир на карте — примерная оценка. Проверь пешеходный путь в Картах.")
                    .font(.footnote)
                    .foregroundStyle(SeruColor.muted)
            }
            Button { showingEditor = true } label: {
                Label("Изменить остановки", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("plan-edit-stops")
        }
    }

    @ViewBuilder private func planMetrics(_ route: WalkRoute) -> some View {
        if route.duration > 0 { Label(durationLabel(route.duration), systemImage: "clock") }
        if !route.distance.isEmpty { Label(route.distance, systemImage: "figure.walk") }
    }

    @ViewBuilder private func returnInfo(_ route: WalkRoute) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if route.returnsToStart == true {
                Label("Возврат к старту включён\(route.returnMinutes.map { " · " + durationLabel($0) } ?? "")", systemImage: "arrow.uturn.backward")
            } else if let minutes = route.returnMinutes {
                if route.returnsToStart == false {
                    Label("Обратно к старту — ещё около \(durationLabel(minutes))", systemImage: "arrow.uturn.backward")
                    Text("С возвратом — \(durationLabel(route.duration + minutes)). Ты выбрал \(durationLabel(app.duration)).")
                } else {
                    Text("Обратный путь — \(durationLabel(minutes)). Уточни, включён ли он в общее время.")
                }
            } else if route.returnsToStart == false {
                Text("Прогулка заканчивается у последней остановки. Обратный путь не рассчитан.")
            } else if route.returnsToStart == nil {
                Text("Возврат к старту не указан.")
            }
            if route.fitsBudget == false || route.duration > app.duration {
                Label("План дольше выбранного времени. Убери остановку или увеличь время прогулки.", systemImage: "exclamationmark.circle")
            } else if route.returnsToStart == false, let back = route.returnMinutes,
                      route.duration + back > app.duration {
                Label("С возвратом прогулка займёт больше выбранного времени.", systemImage: "exclamationmark.circle")
            }
        }
        .font(.footnote)
        .foregroundStyle(SeruColor.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("plan-return-info")
    }

    private func timeline(_ route: WalkRoute) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Старт: \(route.originLabel ?? app.origin)", systemImage: "flag.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeruColor.ink)
            if let initial = route.legs.first, initial.fromID == "start" {
                Text("\(initial.travelMinutes) мин · \(walkDistanceLabel(initial.distanceMeters))")
                    .font(.caption)
                    .foregroundStyle(SeruColor.muted)
                    .padding(.top, 6)
            }
            ForEach(stops(route)) { stop in
                WalkPlanTimelineRow(stop: stop, transfer: transfer(after: stop, route: route), action: { app.showPlace(stop.place) })
                    .padding(.top, stop.number == 1 ? 16 : 0)
            }
            if route.returnsToStart == true {
                Label("Возврат: \(route.originLabel ?? app.origin)", systemImage: "flag.checkered")
                    .font(.subheadline)
                    .foregroundStyle(SeruColor.muted)
                    .padding(.top, 16)
            }
        }
    }

    private func transfer(after stop: WalkPlanStop, route: WalkRoute) -> WalkPlanTransfer? {
        guard let nextID = stop.nextID,
              let leg = route.legs.first(where: { $0.fromID == stop.id && $0.toID == nextID }),
              leg.travelMinutes > 0 || leg.distanceMeters > 0 else { return nil }
        return WalkPlanTransfer(minutes: leg.travelMinutes, distance: leg.distanceMeters > 0 ? walkDistanceLabel(leg.distanceMeters) : "")
    }

    private func audioWidget(_ route: WalkRoute) -> some View {
        Button { audioGuide.toggle(text: guideText(route)) } label: {
            HStack(spacing: 10) {
                Label("Аудиогид", systemImage: "headphones")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: audioGuide.isPlaying ? "stop.fill" : "play.fill")
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
            PrimaryAction(title: "Посмотреть маршрут", symbol: "map") { app.showFullRoute(route) }
                .accessibilityIdentifier("plan-route")
            if let url = MapLinks.orderedWalk(origin: route.originLabel ?? app.origin, originCoordinate: route.originCoordinate,
                    places: route.placeIDs.map { app.place(id: $0) }, returnsToStart: route.returnsToStart == true) {
                Button {
                    openURL(url) { accepted in if !accepted { app.toast = "Не удалось открыть карту" } }
                } label: {
                    Label("Весь маршрут в Apple Maps", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SeruColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 12)
                        .background(SeruColor.field, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan-open-full-route")
            }
        }
    }
}

private struct PlanStopsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var places: [Place]
    let apply: ([String]) -> Void

    init(places: [Place], apply: @escaping ([String]) -> Void) {
        _places = State(initialValue: places)
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(places) { place in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name).font(.body)
                                if place.visitMinutes > 0 {
                                    Text("Около \(place.visitMinutes) мин на месте")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) { places.removeAll { $0.id == place.id } } label: {
                                Image(systemName: "trash").font(.system(size: 17))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Убрать \(place.name) из плана")
                            .accessibilityIdentifier("plan-remove-\(place.id)")
                        }
                        .frame(minHeight: 44)
                    }
                    .onMove { places.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Перетаскивай остановки за ручку справа. Время и расстояние пересчитаются примерно. Если времени не хватит, часть остановок не попадёт в план.")
                }
                if places.isEmpty { Text("Все остановки убраны. Можно закрыть окно, чтобы отменить изменения.") }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Остановки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.frame(minHeight: 44)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { apply(places.map(\.id)); dismiss() }
                        .fontWeight(.semibold)
                        .frame(minHeight: 44)
                }
            }
        }
        .tint(SeruColor.action)
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
