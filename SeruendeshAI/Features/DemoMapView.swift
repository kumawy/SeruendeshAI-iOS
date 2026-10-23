import SwiftUI

/// An entirely local interactive canvas using the map artwork supplied in Figma.
/// It intentionally performs no geocoding, location requests or network tile loading.
struct DemoMapView: View {
    let screen: WalkScreen
    let visibleHeight: CGFloat
    var showsContent = true
    var onBackgroundTap: () -> Void = {}
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    private var isRoute: Bool { if case .route = screen { true } else { false } }
    private var isPlan: Bool { screen == .plan }
    private var isHome: Bool { screen == .home }
    private var routeDestination: Place {
        if let id = app.routeForCurrentScreen?.placeIDs.last { return app.place(id: id) }
        if case .route(let id) = screen { return app.place(id: id) }
        return app.place(id: "garden")
    }
    private var routeStart: String {
        if let id = app.routeForCurrentScreen?.placeIDs.first { return app.place(id: id).name }
        return app.origin
    }
    private var mapAsset: String {
        if isRoute { return "route-asset-000" }
        switch screen {
        case .results: return "results-asset-000"
        case .detail: return "detail-asset-000"
        case .plan: return "plan-asset-000"
        case .chat: return "chat-asset-000"
        default: return "home-asset-000"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if showsContent {
                ZStack(alignment: .top) {
                    ZStack {
                        SeruColor.background
                        Button(action: onBackgroundTap) {
                            Color.clear
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Свернуть панель")
                        .accessibilityIdentifier("map-background")
                        Image(mapAsset).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .saturation(scheme == .dark ? 0.25 : 1)
                            .overlay {
                                if scheme == .dark { Color.black.opacity(0.68) }
                            }
                            .compositingGroup()
                            .allowsHitTesting(false).accessibilityHidden(true)
                        if isRoute {
                            routeOverlay(size: geometry.size)
                        }
                        if scheme == .light {
                            LinearGradient(colors: [SeruColor.forest.opacity(0.04), .clear, SeruColor.field.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                                .allowsHitTesting(false)
                        }
                        markerLayer(size: CGSize(width: geometry.size.width, height: max(160, visibleHeight)))
                    }
                    .scaleEffect(min(max(scale * magnification, 0.85), 3))
                    .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                    .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            offset.width = min(max(offset.width + value.translation.width, -180), 180)
                            offset.height = min(max(offset.height + value.translation.height, -180), 180)
                        })
                    .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { scale = min(max(scale * $0.magnification, 0.85), 3) })
                    VStack {
                        Spacer(minLength: 6)
                        HStack {
                            Spacer()
                            mapControls
                        }
                    }
                    .frame(height: max(visibleHeight - 12, 60))
                    .padding(.horizontal, 16)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Карта прогулки по Астане")
        .accessibilityHidden(!showsContent)
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            if visibleHeight > 420 {
                VStack(spacing: 0) {
                    Button { scale = min(scale + 0.3, 3) } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }.accessibilityLabel("Приблизить карту")
                    Divider().frame(width: 22)
                    Button { scale = max(scale - 0.3, 0.85) } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }.accessibilityLabel("Отдалить карту")
                }
                .font(.system(size: 17)).foregroundStyle(SeruColor.action)
                .glassEffect(.regular, in: .capsule)
            }
            GlassCircleButton(symbol: "location.fill", label: "Центрировать карту") { resetMap() }
        }
    }

    @ViewBuilder private func routeOverlay(size: CGSize) -> some View {
        if scheme == .dark {
            Image("route-dark-asset-005").renderingMode(.template)
                .resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
                .foregroundStyle(SeruColor.action)
                .allowsHitTesting(false).accessibilityHidden(true)
        } else {
            Image("route-asset-005").resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func resetMap() { withAnimation(.smooth(duration: 0.25)) { scale = 1; offset = .zero } }

    @ViewBuilder private func markerLayer(size: CGSize) -> some View {
        if isRoute {
            mapPin(title: "Старт: \(routeStart)", symbol: "location.fill", selected: true) {
                if let id = app.routeForCurrentScreen?.placeIDs.first {
                    app.showPlace(app.place(id: id))
                } else { app.toast = "Начало маршрута: \(routeStart)" }
            }
                .position(x: size.width * 0.40, y: size.height * 0.27)
            mapPin(title: routeDestination.name, symbol: routeDestination.symbol, selected: true) { app.showPlace(routeDestination) }
                .position(x: size.width * 0.62, y: size.height * 0.70)
        } else if isPlan {
            ForEach(Array(DemoData.featuredRoute.placeIDs.enumerated()), id: \.element) { i, id in
                mapPin(title: ["Байтерек", "Нуржол", "Ботанический сад"][i], symbol: "\(i + 1).circle.fill", selected: true) {
                    app.showPlace(app.place(id: id))
                }
                .position(x: size.width * [0.28, 0.66, 0.48][i], y: max(110, size.height * [0.30, 0.55, 0.80][i]))
            }
        } else {
            mapPin(title: isHome ? "Байтерек" : "Вы здесь · Байтерек", symbol: isHome ? "flag.fill" : "location.circle.fill", selected: true) {
                app.showPlace(app.place(id: "baiterek"))
            }
            .position(x: size.width * 0.46, y: max(100, size.height * 0.42))
            if !isHome {
                mapPin(title: "Ботанический сад", symbol: "tree.fill", selected: false) { app.showPlace(app.place(id: "garden")) }
                    .position(x: size.width * 0.70, y: max(82, size.height * 0.28))
                mapPin(title: "Бульвар Нуржол", symbol: "cup.and.saucer.fill", selected: false) { app.showPlace(app.place(id: "coffee")) }
                    .position(x: size.width * 0.55, y: max(160, size.height * 0.70))
            } else {
                Circle().fill(SeruColor.action).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(SeruColor.surface, lineWidth: 2))
                    .position(x: size.width * 0.42, y: size.height * 0.70)
            }
        }
    }

    private func mapPin(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: selected ? 18 : 13, weight: .semibold))
                    .foregroundStyle(selected ? SeruColor.onAction : SeruColor.action)
                    .frame(width: selected ? 40 : 30, height: selected ? 40 : 30)
                    .background(selected ? SeruColor.action : SeruColor.surface, in: Circle())
                Text(title).font(.system(size: 10, weight: .semibold, design: .default))
                    .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 140)
                    .foregroundStyle(SeruColor.ink).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(SeruColor.surface.opacity(0.95), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
