import SwiftUI

/// Keeps live content tied to its own image, with a neutral category fallback.
struct PlaceArtwork: View {
    let place: Place
    var bundledAsset: String? = nil
    var contentMode: ContentMode = .fill

    var body: some View {
        RemoteArtwork(
            url: place.imageURL,
            asset: place.isLive ? nil : (bundledAsset ?? place.imageAsset),
            symbol: place.symbol.isEmpty ? "mappin.and.ellipse" : place.symbol,
            contentMode: contentMode
        )
    }
}

struct EventArtwork: View {
    let event: CityEvent
    var contentMode: ContentMode = .fill

    private var symbol: String {
        let category = event.category.lowercased()
        if category.contains("музык") || category.contains("концерт") { return "music.note" }
        if category.contains("выстав") || category.contains("искусств") { return "photo.artframe" }
        if category.contains("театр") || category.contains("спектак") { return "theatermasks" }
        if category.contains("кино") { return "film" }
        if category.contains("спорт") { return "figure.run" }
        return "calendar"
    }

    var body: some View {
        RemoteArtwork(
            url: event.imageURL,
            asset: event.isLive ? nil : event.imageAsset,
            symbol: symbol,
            contentMode: contentMode
        )
    }
}

private struct RemoteArtwork: View {
    let url: URL?
    let asset: String?
    let symbol: String
    let contentMode: ContentMode

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SeruColor.field
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            placeholder
                        }
                    }
                } else if let asset, !asset.isEmpty {
                    Image(asset)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var placeholder: some View {
        Image(systemName: symbol)
            .font(.system(size: 32, weight: .light))
            .foregroundStyle(SeruColor.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Uses live coordinates where available and keeps name searches in Astana.
enum LiveMapLink {
    static func url(
        provider: ExternalMapProvider,
        destination: String,
        coordinate: GeoPoint?,
        origin: String? = nil,
        originCoordinate: GeoPoint? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        switch provider {
        case .apple:
            components.host = "maps.apple.com"
            components.path = "/"
            components.queryItems = [
                URLQueryItem(name: "daddr", value: coordinate.map(location) ?? destination + ", Астана"),
                URLQueryItem(name: "dirflg", value: "w")
            ]
            if let start = originCoordinate.map(location) ?? origin, !start.isEmpty {
                components.queryItems?.append(URLQueryItem(name: "saddr", value: start))
            }
        case .twoGIS:
            components.host = "2gis.kz"
            if let coordinate, let originCoordinate {
                components.path = "/astana/directions/points/\(originCoordinate.longitude),\(originCoordinate.latitude)|\(coordinate.longitude),\(coordinate.latitude)"
            } else if let coordinate {
                components.path = "/astana/geo/\(coordinate.longitude),\(coordinate.latitude)"
            } else { components.path = "/astana/search/" + destination }
        case .yandex:
            components.host = "yandex.kz"
            components.path = "/maps/163/astana/"
            if let coordinate {
                components.queryItems = [
                    URLQueryItem(name: "ll", value: "\(coordinate.longitude),\(coordinate.latitude)"),
                    URLQueryItem(name: "pt", value: "\(coordinate.longitude),\(coordinate.latitude)"),
                    URLQueryItem(name: "z", value: "16")
                ]
            } else {
                components.queryItems = [URLQueryItem(name: "text", value: destination + ", Астана")]
            }
        }
        return components.url
    }

    private static func location(_ point: GeoPoint) -> String {
        "\(point.latitude),\(point.longitude)"
    }
}

func walkDistanceLabel(_ meters: Int) -> String {
    if meters < 1_000 { return "\(meters) м" }
    return String(format: "%.1f км", locale: Locale(identifier: "ru_RU"), Double(meters) / 1_000)
}
