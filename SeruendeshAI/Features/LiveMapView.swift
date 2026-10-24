import MapKit
import SwiftUI

/// Uses verified local or supplied server coordinates. The default city is a camera
/// fallback, never a substitute for the selected starting point or GPS.
struct LiveMapView: View {
    let screen: WalkScreen
    let visibleHeight: CGFloat
    var showsContent = true
    var isEmbedded = false
    var onBackgroundTap: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Namespace private var mapScope
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: Self.defaultCenter, distance: 8_000)
    )
    @State private var currentCamera: MapCamera?
    @State private var lastFitTarget: LiveMapFitTarget?

    private static let defaultCenter = CLLocationCoordinate2D(latitude: 51.128, longitude: 71.430)

    var body: some View {
        GeometryReader { geometry in
            let presentation = mapPresentation
            MapReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Map(position: $position, interactionModes: isEmbedded ? [] : [.pan, .zoom, .rotate],
                        scope: mapScope) {
                        ForEach(presentation.lines) { line in
                            // A casing keeps the line legible over streets and park
                            // artwork. Estimates remain visibly dashed in both layers.
                            MapPolyline(coordinates: line.points.map(mapCoordinate))
                                .stroke(.white.opacity(0.9), style: StrokeStyle(
                                    lineWidth: 8, lineCap: .round, lineJoin: .round,
                                    dash: line.isEstimated ? [8, 10] : []
                                ))
                            MapPolyline(coordinates: line.points.map(mapCoordinate))
                                .stroke(Color(hex: "27634F"), style: StrokeStyle(
                                    lineWidth: 4, lineCap: .round, lineJoin: .round,
                                    dash: line.isEstimated ? [8, 10] : []
                                ))
                        }
                        ForEach(presentation.places) { place in
                            if let point = place.coordinate {
                                Annotation(place.name, coordinate: mapCoordinate(point), anchor: .center) {
                                    Button { app.showPlace(place) } label: {
                                        MapPlaceBadge(
                                            number: presentation.stopNumber(for: place.id),
                                            symbol: place.symbol,
                                            isStart: point == presentation.origin
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(markerTitle(place, presentation: presentation))
                                    .accessibilityHint("Открыть место")
                                    .accessibilityIdentifier("map-place-\(place.id)")
                                }
                                .annotationTitles(.hidden)
                            }
                        }
                        if let origin = presentation.origin, !presentation.places.contains(where: { $0.coordinate == origin }) {
                            Annotation("Старт: \(presentation.originLabel)", coordinate: mapCoordinate(origin), anchor: .center) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(hex: "174B3E"))
                                    .frame(width: 32, height: 32)
                                    .background(.white, in: .circle)
                                    .overlay { Circle().strokeBorder(Color(hex: "174B3E"), lineWidth: 2) }
                                    .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
                                    .frame(width: 44, height: 44)
                                    .accessibilityLabel("Старт: \(presentation.originLabel)")
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .mapControls { }
                    .onMapCameraChange { context in currentCamera = context.camera }
                    .simultaneousGesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).onEnded { gesture in
                        // A gesture on the map preserves native panning and zooming.
                        // Native double-tap zoom and marker taps never collapse it.
                        guard !isEmbedded, case .second(let tap) = gesture else { return }
                        if !isAnnotationTap(tap.location, presentation: presentation, proxy: proxy) {
                            onBackgroundTap()
                        }
                    })
                    .accessibilityIdentifier("map-background")
                    .accessibilityActions {
                        if !isEmbedded {
                            Button("Свернуть панель", action: onBackgroundTap)
                        }
                    }

                    if !isEmbedded && visibleHeight > 180 {
                        controls(size: geometry.size, target: presentation.fitTarget)
                    }
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
            .onChange(of: isEmbedded) { _, _ in
                lastFitTarget = nil
                fitIfNeeded(presentation.fitTarget, size: geometry.size)
            }
        }
        // Keep the actual map and its camera mounted behind the chat panel.
        .opacity(showsContent ? 1 : 0)
        .allowsHitTesting(showsContent)
        .accessibilityHidden(!showsContent)
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
            places = actualPlaces(ids: [id])
        } else if case .route(let id) = screen, route == nil {
            places = actualPlaces(ids: [id])
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
        let numberedStops: [String]
        if let route { numberedStops = route.placeIDs }
        else if case .route(let id) = screen { numberedStops = [id] }
        else { numberedStops = [] }

        return LiveMapPresentation(places: places, origin: origin,
                                   originLabel: route?.originLabel ?? preview?.originLabel ?? app.origin,
                                   numberedStops: numberedStops, lines: lines,
                                   fitTarget: LiveMapFitTarget(focus: focus, points: fitPoints))
    }

    private func markerTitle(_ place: Place, presentation: LiveMapPresentation) -> String {
        let title = if let number = presentation.stopNumber(for: place.id) { "Остановка \(number). \(place.name)" }
        else { place.name }
        return place.coordinate == presentation.origin ? "Старт. \(title)" : title
    }

    private func actualPlaces(ids: [String]) -> [Place] {
        ids.compactMap { id in
            let place = app.place(id: id)
            return place.id == id ? place : nil
        }
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
                .font(.system(size: 18, weight: .medium))
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
        let minimumMeters: Double
        switch screen {
        case .plan, .route: minimumMeters = points.isEmpty ? 3_000 : 220
        default: minimumMeters = points.isEmpty ? 3_000 : 650
        }
        let minimumSpan = MKMapPointsPerMeterAtLatitude(latitude) * minimumMeters
        let boundsWidth = max(maxX - minX, minimumSpan) * 1.25
        let boundsHeight = max(maxY - minY, minimumSpan) * 1.25
        let visible = min(max(visibleHeight, 1), size.height)
        let top = isEmbedded ? min(24, visible * 0.15) : min(104, max(24, visible * 0.25))
        let bottom = isEmbedded ? min(24, visible * 0.15) : min(44, visible * 0.15)
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
            // Compact annotations use a full44pt hit area without place-title bubbles.
            return CGRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56).contains(location)
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

    func stopNumber(for placeID: String) -> Int? {
        numberedStops.firstIndex(of: placeID).map { $0 + 1 }
    }
}

/// A compact visual pin inside a full44pt touch target.
private struct MapPlaceBadge: View {
    let number: Int?
    let symbol: String
    let isStart: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let number {
                    Text(number, format: .number)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color(hex: "174B3E"), in: .circle)
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)

            // A start that is also a stop retains its sequence number.
            if isStart {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: "174B3E"))
                    .frame(width: 16, height: 16)
                    .background(.white, in: .circle)
                    .offset(x: 4, y: 3)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .accessibilityHidden(true)
    }
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
