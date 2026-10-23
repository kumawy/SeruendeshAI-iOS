import SwiftUI

struct PlaceDetailContent: View {
    @Environment(AppModel.self) private var app
    @State private var selectedPhoto: DetailPhoto?

    let place: Place

    private var isGarden: Bool {
        !place.isLive && place.name.localizedCaseInsensitiveContains("Ботаническ")
    }

    private var photos: [DetailPhoto] {
        if place.isLive {
            return [DetailPhoto(id: place.id, asset: "", title: place.name, place: place)]
        }
        if isGarden {
            return [
                DetailPhoto(id: "lagoon", asset: "detail-asset-001", title: "Искусственный пруд и кувшинки"),
                DetailPhoto(id: "alley", asset: "detail-asset-002", title: "Аллея для медитации"),
                DetailPhoto(id: "bridge", asset: "detail-asset-003", title: "Мост с подсветкой")
            ]
        }
        return [DetailPhoto(id: place.id, asset: place.imageAsset, title: place.name)]
    }

    private var shareText: String {
        let metrics = [
            place.travelMinutes > 0 ? "\(place.travelMinutes) мин пешком" : nil,
            place.distance.isEmpty ? nil : place.distance
        ].compactMap { $0 }.joined(separator: ", ")
        return "\(place.name) — \(place.category). \(metrics.isEmpty ? "" : metrics + ". ")Найдено в SeruendeshAI."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            gallery
            imageAttribution
            metrics
            actions
            description
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .sheet(item: $selectedPhoto) { photo in
            DetailPhotoViewer(photo: photo)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(.title.weight(.bold))
                .tracking(-0.4)
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Text(place.category)
                    .font(.subheadline)
                    .foregroundStyle(SeruColor.muted)
                if !place.rating.isEmpty {
                    Label(place.rating, systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SeruColor.ink)
                }
            }
        }
    }

    private var gallery: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(photos) { photo in
                    DetailGalleryPhoto(
                        photo: photo,
                        width: isGarden ? (photo.id == "lagoon" ? 270 : 240) : 308,
                        action: { selectedPhoto = photo }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.trailing, 16)
        .padding(.horizontal, -16)
    }

    @ViewBuilder private var imageAttribution: some View {
        if place.isLive, place.imageURL != nil {
            if let source = place.imageSourceURL {
                Link(place.imageCredit ?? "Источник фото", destination: source)
                    .font(.caption)
                    .foregroundStyle(SeruColor.muted)
            } else if let credit = place.imageCredit, !credit.isEmpty {
                Text(credit)
                    .font(.caption)
                    .foregroundStyle(SeruColor.muted)
            }
        }
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { metricItems }
            VStack(alignment: .leading, spacing: 7) { metricItems }
        }
    }

    @ViewBuilder private var metricItems: some View {
        if !place.isLive || place.travelMinutes > 0 {
            ItineraryMetric(screen: "detail", index: 11, text: "\(place.travelMinutes) мин пешком")
        }
        if !place.isLive || place.visitMinutes > 0 {
            ItineraryMetric(screen: "detail", index: 12, text: "Визит \(place.visitMinutes) мин")
        }
        if !place.hours.isEmpty {
            ItineraryMetric(screen: "detail", index: 13, text: place.hours)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { app.showRoute(place) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                    Text("Построить маршрут")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if !place.distance.isEmpty {
                        Text(place.distance)
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(SeruColor.onAction)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 16)
                .background(SeruColor.action, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("build-route")
            HStack(spacing: 8) {
                Button { app.toggleSaved(place) } label: {
                    ItineraryActionLabel(title: app.isSaved(place) ? "Сохранено" : "Сохранить", screen: "detail", index: 22, selected: app.isSaved(place))
                }
                .accessibilityValue(app.isSaved(place) ? "Сохранено" : "Не сохранено")
                .accessibilityIdentifier("detail-save-\(place.id)")
                ShareLink(item: shareText) {
                    ItineraryActionLabel(title: "Поделиться", screen: "detail", index: 23)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var description: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if !place.reason.isEmpty { Text(place.reason) }
                if isGarden {
                    Text("Ботанический сад Астаны — зелёное пространство на левом берегу. Здесь есть оранжерея, пруд, прогулочные и велосипедные дорожки.\n\n\(place.subtitle)")
                } else if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                }
                if place.isLive {
                    if let credit = place.descriptionCredit, !credit.isEmpty {
                        Text(credit).font(.caption)
                    }
                    if let source = place.sourceURL {
                        Link("Источник информации", destination: source)
                    }
                    if let website = place.websiteURL, website != place.sourceURL {
                        Link("Сайт места", destination: website)
                    }
                }
            }
            .font(.subheadline)
            .lineSpacing(3)
            .foregroundStyle(SeruColor.muted)
            .padding(.top, 8)
        } label: {
            Text("О месте")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .frame(minHeight: 44)
        }
        .tint(SeruColor.muted)
    }
}

private struct DetailPhoto: Identifiable {
    let id: String
    let asset: String
    let title: String
    var place: Place? = nil
}

private struct DetailGalleryPhoto: View {
    let photo: DetailPhoto
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            artwork
                .frame(width: width, height: 176)
                .clipShape(.rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(photo.place?.isLive == true && photo.place?.imageURL == nil)
        .accessibilityLabel("Открыть фото: \(photo.title)")
    }

    @ViewBuilder private var artwork: some View {
        if let place = photo.place {
            PlaceArtwork(place: place)
        } else {
            Image(photo.asset)
                .resizable()
                .scaledToFill()
        }
    }
}

private struct DetailPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: DetailPhoto

    var body: some View {
        NavigationStack {
            artwork
                .accessibilityLabel(photo.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SeruColor.background)
                .navigationTitle("Фотографии")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let place = photo.place {
            PlaceArtwork(place: place, contentMode: .fit)
        } else {
            Image(photo.asset)
                .resizable()
                .scaledToFit()
        }
    }
}
