import MapKit
import SwiftUI

/// Uses verified local or supplied server coordinates. The default city is a camera
/// fallback, never a substitute for the selected starting point or GPS.
struct LiveMapView: View {
    let screen: WalkScreen
    let visibleHeight: CGFloat
    var showsContent = true
    var onBackgroundTap: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Namespace private var mapScope
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: Self.defaultCenter, distance: 8_000)
    )
    @State private var currentCamera: MapCamera?
    @State private var selectedPlaceID: String?
    @State private var lastFitTarget: LiveMapFitTarget?

    private static let defaultCenter = CLLocationCoordinate2D(latitude: 51.128, longitude: 71.430)

    var body: some View {
        GeometryReader { geometry in
            let presentation = mapPresentation
            MapReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Map(position: $position, interactionModes: [.pan, .zoom, .rotate],
                        selection: $selectedPlaceID, scope: mapScope) {
                        ForEach(presentation.lines) { line in
                            MapPolyline(coordinates: line.points.map(mapCoordinate))
                                .stroke(SeruColor.action, style: StrokeStyle(
                                    lineWidth: 5, lineCap: .round, lineJoin: .round,
                                    dash: line.isEstimated ? [8, 6] : []
                                ))
                        }
                        ForEach(presentation.places) { place in
                            if let point = place.coordinate {
                                Marker(markerTitle(place, presentation: presentation), systemImage: place.symbol, coordinate: mapCoordinate(point))
                                    .tint(SeruColor.action)
                                    .tag(place.id)
                            }
                        }
                        if let origin = presentation.origin, !presentation.places.contains(where: { $0.coordinate == origin }) {
                            Marker("Старт: \(presentation.originLabel)", systemImage: "flag.fill", coordinate: mapCoordinate(origin))
                                .tint(.gray)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .mapControls { }
                    .onMapCameraChange { context in currentCamera = context.camera }
                    .simultaneousGesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).onEnded { gesture in
                        // A gesture on the map preserves native panning and zooming.
                        // Native double-tap zoom and marker taps never collapse it.
                        guard case .second(let tap) = gesture else { return }
                        if !isAnnotationTap(tap.location, presentation: presentation, proxy: proxy) {
                            onBackgroundTap()
                        }
                    })
                    .accessibilityIdentifier("map-background")
                    .accessibilityAction(named: Text("Свернуть панель"), onBackgroundTap)

                    controls(size: geometry.size, target: presentation.fitTarget)
                }
            }
            .onChange(of: presentation.fitTarget, initial: true) { _, target in
                fitIfNeeded(target, size: geometry.size)
            }
            .onChange(of: visibleHeight) { _, _ in
                // A sheet drag only retries a pending fit. It never resets a
                // camera the user has already panned or zoomed.
                fitIfNeeded(presentation.fitTarget, size: geometry.size)
            }
            .onChange(of: showsContent) { _, visible in
                if visible { fitIfNeeded(presentation.fitTarget, size: geometry.size) }
            }
            .onChange(of: screen) { _, _ in
                fitIfNeeded(presentation.fitTarget, size: geometry.size)
            }
        }
        // Keep the actual map and its camera mounted behind the chat panel.
        .opacity(showsContent ? 1 : 0)
        .allowsHitTesting(showsContent)
        .accessibilityHidden(!showsContent)
        .onChange(of: selectedPlaceID) { _, id in
            guard let id else { return }
            selectedPlaceID = nil
            let place = app.place(id: id)
            if place.id == id { app.showPlace(place) }
        }
    }

    private var mapPresentation: LiveMapPresentation {
        let route: WalkRoute? = if case .route = screen { app.routeForCurrentScreen } else if screen == .plan { app.currentPlan } else { nil }
        let preview: RoutePreview? = if case .route(let id) = screen, app.routePreview?.placeID == id { app.routePreview } else { nil }
        let origin = (route?.originCoordinate ?? preview?.origin ?? app.originCoordinate).flatMap { isValidMapPoint($0) ? $0 : nil }
        let routePlaces: [Place]?
        if let route {
            routePlaces = actualPlaces(ids: route.placeIDs)
        } else if screen == .plan, let plan = app.currentPlan {
            routePlaces = actualPlaces(ids: plan.placeIDs)
        } else {
            routePlaces = nil
        }
        var places = routePlaces ?? app.places
        if case .detail(let id) = screen {
            appendPlace(id: id, to: &places)
        } else if case .route(let id) = screen, route == nil {
            appendPlace(id: id, to: &places)
        }
        var seenIDs = Set<String>()
        places = places.filter { place in
            guard let point = place.coordinate, isValidMapPoint(point) else { return false }
            return seenIDs.insert(place.id).inserted
        }

        var lines: [LiveMapLine] = []
        if let route {
            lines = route.legs.compactMap { leg in
                // Reject malformed geometry instead of inventing connecting paths.
                guard leg.points.count > 1, leg.points.allSatisfy(isValidMapPoint) else { return nil }
                return LiveMapLine(id: "\(route.id):\(leg.id)", points: leg.points,
                                   isEstimated: leg.geometry != "network")
            }
        } else if case .route(let id) = screen,
                  let preview = app.routePreview, preview.placeID == id,
                  preview.points.count > 1, preview.points.allSatisfy(isValidMapPoint) {
            lines = [LiveMapLine(id: "preview:\(id)", points: preview.points,
                                 isEstimated: preview.geometry != "network")]
        }

        if lines.isEmpty, route == nil, case .route(let id) = screen, !app.usesBackend,
           let start = origin, let end = places.first(where: { $0.id == id })?.coordinate, start != end {
            lines = [LiveMapLine(id: "estimate:\(id)", points: [start, end], isEstimated: true)]
        }

        let focus: String
        var fitPoints: [GeoPoint]
        if case .detail(let id) = screen {
            focus = "detail:\(id)"
            fitPoints = places.first(where: { $0.id == id })?.coordinate.map { [$0] } ?? []
        } else {
            if let route { focus = "route:\(route.id)" }
            else if case .route(let id) = screen { focus = "preview:\(id)" }
            else if screen == .plan { focus = "plan:\(app.currentPlan?.id ?? "")" }
            else { focus = "places" }
            fitPoints = lines.flatMap(\.points) + places.compactMap(\.coordinate)
            if let origin { fitPoints.append(origin) }
        }
        return LiveMapPresentation(places: places, origin: origin,
                                   originLabel: route?.originLabel ?? preview?.originLabel ?? app.origin,
                                   numberedStops: route?.placeIDs ?? [], lines: lines,
                                   fitTarget: LiveMapFitTarget(focus: focus, points: fitPoints))
    }

    private func markerTitle(_ place: Place, presentation: LiveMapPresentation) -> String {
        if let index = presentation.numberedStops.firstIndex(of: place.id) { return "\(index + 1). \(place.name)" }
        return place.name
    }

    private func actualPlaces(ids: [String]) -> [Place] {
        ids.compactMap { id in
            let place = app.place(id: id)
            return place.id == id ? place : nil
        }
    }

    private func appendPlace(id: String, to places: inout [Place]) {
        guard !places.contains(where: { $0.id == id }) else { return }
        let place = app.place(id: id)
        if place.id == id { places.append(place) }
    }

    private func controls(size: CGSize, target: LiveMapFitTarget) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    if visibleHeight > 420 {
                        MapCompass(scope: mapScope)
                        VStack(spacing: 0) {
                            mapButton(symbol: "plus", label: "Приблизить карту") { zoom(by: 0.6) }
                            Divider().frame(width: 24)
                            mapButton(symbol: "minus", label: "Отдалить карту") { zoom(by: 1.6) }
                        }
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                    mapButton(symbol: "scope", label: "Показать старт и места прогулки") {
                        let points = target.points
                        position = .rect(fittingRect(points: points, size: size))
                        lastFitTarget = target
                    }
                    .background(.regularMaterial, in: .circle)
                }
            }
        }
        .frame(height: max(0, min(visibleHeight, size.height) - 12))
        .padding(.horizontal, 16)
    }

    private func mapButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func zoom(by factor: Double) {
        var camera = currentCamera ?? position.camera ?? MapCamera(
            centerCoordinate: Self.defaultCenter, distance: 8_000
        )
        camera.distance = min(max(camera.distance * factor, 150), 2_000_000)
        position = .camera(camera)
    }

    private func fitIfNeeded(_ target: LiveMapFitTarget, size: CGSize) {
        guard showsContent, screen != .chat, visibleHeight > 120,
              size.width > 0, size.height > 0, lastFitTarget != target else { return }
        position = .rect(fittingRect(points: target.points, size: size))
        lastFitTarget = target
    }

    private func fittingRect(points: [GeoPoint], size: CGSize) -> MKMapRect {
        let mapPoints = points.map { MKMapPoint(mapCoordinate($0)) }
        let fallback = MKMapPoint(Self.defaultCenter)
        let minX = mapPoints.map(\.x).min() ?? fallback.x
        let maxX = mapPoints.map(\.x).max() ?? fallback.x
        let minY = mapPoints.map(\.y).min() ?? fallback.y
        let maxY = mapPoints.map(\.y).max() ?? fallback.y
        let latitude = points.first?.latitude ?? Self.defaultCenter.latitude
        let minimumSpan = MKMapPointsPerMeterAtLatitude(latitude) * (points.isEmpty ? 3_000 : 650)
        let boundsWidth = max(maxX - minX, minimumSpan) * 1.25
        let boundsHeight = max(maxY - minY, minimumSpan) * 1.25
        let visible = min(max(visibleHeight, 1), size.height)
        let top = min(104, max(24, visible * 0.25))
        let bottom = min(44, visible * 0.15)
        let viewportWidth = max(size.width - 48, 1)
        let viewportHeight = max(visible - top - bottom, 60)
        let mapPointsPerPixel = max(boundsWidth / viewportWidth, boundsHeight / viewportHeight)
        // Shift the fitted camera south so the route occupies the unobscured
        // top viewport, with space for the app header and the bottom panel.
        return MKMapRect(
            x: (minX + maxX) / 2 - mapPointsPerPixel * size.width / 2,
            y: (minY + maxY) / 2 - mapPointsPerPixel * (top + viewportHeight / 2),
            width: mapPointsPerPixel * size.width,
            height: mapPointsPerPixel * size.height
        )
    }

    private func isAnnotationTap(_ location: CGPoint, presentation: LiveMapPresentation, proxy: MapProxy) -> Bool {
        let coordinates = presentation.places.compactMap(\.coordinate) + (presentation.origin.map { [$0] } ?? [])
        return coordinates.contains { coordinate in
            guard let point = proxy.convert(mapCoordinate(coordinate), to: .local) else { return false }
            // Includes the native marker's title and pin above its map anchor.
            return CGRect(x: point.x - 96, y: point.y - 84, width: 192, height: 112).contains(location)
        }
    }
}

private struct LiveMapPresentation {
    let places: [Place]
    let origin: GeoPoint?
    let originLabel: String
    let numberedStops: [String]
    let lines: [LiveMapLine]
    let fitTarget: LiveMapFitTarget
}

private struct LiveMapLine: Identifiable {
    let id: String
    let points: [GeoPoint]
    let isEstimated: Bool
}

private struct LiveMapFitTarget: Equatable {
    let focus: String
    let points: [GeoPoint]
}

private func mapCoordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
}

private func isValidMapPoint(_ point: GeoPoint) -> Bool {
    guard point.latitude.isFinite, point.longitude.isFinite,
          CLLocationCoordinate2DIsValid(mapCoordinate(point)) else { return false }
    let projected = MKMapPoint(mapCoordinate(point))
    return projected.x.isFinite && projected.y.isFinite
}
