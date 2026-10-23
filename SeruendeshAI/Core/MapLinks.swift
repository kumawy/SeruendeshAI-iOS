import Foundation

enum ExternalMapProvider: String, CaseIterable, Identifiable, Sendable {
    case apple = "Apple Maps"
    case twoGIS = "2ГИС"
    case yandex = "Яндекс Карты"

    var id: String { rawValue }

    func actionTitle(hasRoute: Bool) -> String {
        if self == .yandex { return "Открыть место в Яндекс Картах" }
        if !hasRoute { return "Открыть место в \(rawValue)" }
        return "Маршрут в \(rawValue)"
    }

    func url(destination: String, origin: String? = nil) -> URL? {
        MapLinks.destinationRoute(provider: self, destination: destination, coordinate: nil, origin: origin)
    }
}

enum MapLinks {
    /// Native iOS 18.4+ multistop walking URL. Named stops remain in order if a coordinate is unavailable.
    static func orderedWalk(origin: String, originCoordinate: GeoPoint?, places: [Place],
                            returnsToStart: Bool = false) -> URL? {
        guard !places.isEmpty, let source = location(origin, coordinate: originCoordinate) else { return nil }
        let stops = places.compactMap { location($0.name, coordinate: $0.coordinate) }
        guard stops.count == places.count, let final = stops.last else { return nil }
        var items = [URLQueryItem(name: "source", value: source),
                     URLQueryItem(name: "destination", value: returnsToStart ? source : final)]
        items += (returnsToStart ? stops : Array(stops.dropLast())).map { URLQueryItem(name: "waypoint", value: $0) }
        items.append(URLQueryItem(name: "mode", value: "walking"))
        return url(host: "maps.apple.com", path: "/directions", items: items)
    }

    static func place(provider: ExternalMapProvider, destination: String, coordinate: GeoPoint?) -> URL? {
        let point = coordinate.flatMap { $0.isValid ? $0 : nil }
        let name = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard point != nil || !name.isEmpty else { return nil }
        switch provider {
        case .apple:
            var items = [URLQueryItem(name: "name", value: name)]
            if let point { items.append(URLQueryItem(name: "coordinate", value: latLon(point))) }
            else { items.append(URLQueryItem(name: "address", value: name + ", Астана")) }
            return url(host: "maps.apple.com", path: "/place", items: items)
        case .twoGIS:
            if let point { return url(host: "2gis.kz", path: "/astana/geo/\(lonLat(point))") }
            return url(host: "2gis.kz", path: "/astana/search/\(name)")
        case .yandex:
            let items: [URLQueryItem]
            if let point {
                items = [URLQueryItem(name: "ll", value: lonLat(point)),
                         URLQueryItem(name: "pt", value: lonLat(point)), URLQueryItem(name: "z", value: "16")]
            } else { items = [URLQueryItem(name: "text", value: name + ", Астана")] }
            return url(host: "yandex.kz", path: "/maps/163/astana/", items: items)
        }
    }

    static func destinationRoute(provider: ExternalMapProvider, destination: String, coordinate: GeoPoint?,
                                 origin: String? = nil, originCoordinate: GeoPoint? = nil) -> URL? {
        let destinationPoint = coordinate.flatMap { $0.isValid ? $0 : nil }
        let startPoint = originCoordinate.flatMap { $0.isValid ? $0 : nil }
        switch provider {
        case .apple:
            guard let target = location(destination, coordinate: destinationPoint) else { return nil }
            // Legacy address parameters remain supported for name-only destinations.
            var items = [URLQueryItem(name: "daddr", value: target), URLQueryItem(name: "dirflg", value: "w")]
            if let start = location(origin ?? "", coordinate: startPoint) {
                items.append(URLQueryItem(name: "saddr", value: start))
            }
            return url(host: "maps.apple.com", path: "/", items: items)
        case .twoGIS:
            guard let destinationPoint, let startPoint else {
                return place(provider: provider, destination: destination, coordinate: destinationPoint)
            }
            return url(host: "2gis.kz", path: "/astana/directions/tab/pedestrian/points/\(lonLat(startPoint))|\(lonLat(destinationPoint))")
        case .yandex:
            return place(provider: provider, destination: destination, coordinate: destinationPoint)
        }
    }

    static func sharePlace(_ place: Place) -> String {
        [place.name, place.address ?? place.subtitle,
         self.place(provider: .apple, destination: place.name, coordinate: place.coordinate)?.absoluteString ?? ""]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func shareRoute(_ route: WalkRoute, places: [Place]) -> String {
        let catalog = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = route.placeIDs.compactMap { catalog[$0] }
        var lines = [route.name]
        if let origin = route.originLabel, !origin.isEmpty { lines.append("Старт: \(origin)") }
        let metrics = [route.duration > 0 ? "Примерно \(route.duration) мин" : nil,
                       route.distance.isEmpty ? nil : route.distance].compactMap { $0 }
        if !metrics.isEmpty { lines.append(metrics.joined(separator: " · ")) }
        for (index, place) in ordered.enumerated() {
            lines.append("\(index + 1). \(place.name)")
            if let link = self.place(provider: .apple, destination: place.name, coordinate: place.coordinate) {
                lines.append(link.absoluteString)
            }
        }
        if ordered.count == route.placeIDs.count,
           let link = orderedWalk(origin: route.originLabel ?? "", originCoordinate: route.originCoordinate,
                                  places: ordered, returnsToStart: route.returnsToStart == true) {
            lines.append("Полный маршрут: \(link.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }

    private static func location(_ name: String, coordinate: GeoPoint?) -> String? {
        if let coordinate, coordinate.isValid { return latLon(coordinate) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return name.contains("Астана") ? name : name + ", Астана"
    }

    private static func latLon(_ point: GeoPoint) -> String { "\(point.latitude),\(point.longitude)" }
    private static func lonLat(_ point: GeoPoint) -> String { "\(point.longitude),\(point.latitude)" }

    private static func url(host: String, path: String, items: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = path
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}

/// Compatibility for existing callers; all URL construction lives in the Foundation helper.
enum LiveMapLink {
    static func url(provider: ExternalMapProvider, destination: String, coordinate: GeoPoint?,
                    origin: String? = nil, originCoordinate: GeoPoint? = nil) -> URL? {
        MapLinks.destinationRoute(provider: provider, destination: destination, coordinate: coordinate,
                                  origin: origin, originCoordinate: originCoordinate)
    }
}

func walkDistanceLabel(_ meters: Int) -> String {
    let meters = max(0, meters)
    if meters < 1_000 { return "\(meters) м" }
    return String(format: "%.1f км", locale: Locale(identifier: "ru_RU"), Double(meters) / 1_000)
}
