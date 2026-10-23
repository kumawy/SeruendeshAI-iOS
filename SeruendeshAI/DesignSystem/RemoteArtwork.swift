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
                        } else if phase.error != nil {
                            VStack(spacing: 8) {
                                placeholder
                                Text("Фото пока недоступно")
                                    .font(.caption)
                                    .foregroundStyle(SeruColor.muted)
                            }
                            .padding(12)
                        } else {
                            ZStack {
                                placeholder
                                ProgressView().tint(SeruColor.action)
                            }
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
            .font(.largeTitle.weight(.light))
            .foregroundStyle(SeruColor.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
