import SwiftUI

struct PlaceDetailContent: View {
    @Environment(AppModel.self) private var app
    @State private var showingPhoto = false
    let place: Place

    private var hasPhoto: Bool { place.isLive ? place.imageURL != nil : !place.imageAsset.isEmpty }
    private var estimatedTravel: (minutes: Int, distance: String)? {
        guard !place.isLive, let start = app.originCoordinate, let end = place.coordinate else { return nil }
        let meters = WalkPlanner.estimatedDistance(from: start, to: end)
        return (Int(ceil(Double(meters) / 75)), walkDistanceLabel(meters))
    }
    private var travelMinutes: Int? { estimatedTravel?.minutes ?? (place.isLive && place.travelMinutes > 0 ? place.travelMinutes : nil) }
    private var distance: String { estimatedTravel?.distance ?? (place.isLive ? place.distance : "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            gallery
            imageAttribution
            metrics
            if let travelMinutes {
                Text(place.isLive
                     ? "Оценка из подборки: \(travelMinutes) мин пешком\(distance.isEmpty ? "" : " · " + distance). Для текущего старта построй маршрут."
                     : "От старта «\(app.origin)»: примерно \(travelMinutes) мин пешком\(distance.isEmpty ? "" : " · " + distance).")
                    .font(.footnote)
                    .foregroundStyle(SeruColor.muted)
            }
            actions
            placeFacts
            description
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .sheet(isPresented: $showingPhoto) { DetailPhotoViewer(place: place) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(.title.weight(.bold))
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { categoryAndRating }
                VStack(alignment: .leading, spacing: 6) { categoryAndRating }
            }
        }
    }

    @ViewBuilder private var categoryAndRating: some View {
        Text(place.category).font(.subheadline).foregroundStyle(SeruColor.muted)
        if !place.rating.isEmpty {
            Label(place.rating, systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
        }
    }

    private var gallery: some View {
        Button { showingPhoto = true } label: {
            PlaceArtwork(place: place)
                .frame(height: 192)
                .clipShape(.rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
                .overlay(alignment: .bottomTrailing) {
                    if hasPhoto {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body)
                            .padding(12)
                            .background(.regularMaterial, in: .circle)
                            .padding(10)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!hasPhoto)
        .accessibilityLabel(hasPhoto ? "Открыть фото: \(place.name)" : "Фото места пока нет")
        .accessibilityHint(hasPhoto ? "Фото можно увеличить" : "")
        .accessibilityIdentifier("detail-photo")
    }

    @ViewBuilder private var imageAttribution: some View {
        if place.imageURL != nil {
            if let source = place.imageSourceURL {
                Link(place.imageCredit ?? "Источник фото", destination: source)
                    .font(.caption)
                    .foregroundStyle(SeruColor.muted)
                    .frame(minHeight: 44, alignment: .leading)
            } else if let credit = place.imageCredit, !credit.isEmpty {
                Text(credit).font(.caption).foregroundStyle(SeruColor.muted)
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
        if place.visitMinutes > 0 {
            ItineraryMetric(screen: "detail", index: 12, text: "Визит около \(place.visitMinutes) мин")
        }
        if !place.hours.isEmpty {
            ItineraryMetric(screen: "detail", index: 13, text: place.hours)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryAction(title: "Маршрут от выбранного старта", symbol: "figure.walk") { app.showRoute(place) }
                .accessibilityIdentifier("build-route")
            HStack(spacing: 8) {
                Button { app.toggleSaved(place) } label: {
                    ItineraryActionLabel(title: app.isSaved(place) ? "Сохранено" : "Сохранить", screen: "detail", index: 22, selected: app.isSaved(place))
                }
                .accessibilityValue(app.isSaved(place) ? "Сохранено" : "Не сохранено")
                .accessibilityIdentifier("detail-save-\(place.id)")
                ShareLink(item: MapLinks.sharePlace(place)) {
                    ItineraryActionLabel(title: "Поделиться", screen: "detail", index: 23)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var placeFacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Перед визитом").font(.headline).accessibilityAddTraits(.isHeader)
            if let address = place.address, !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse")
                    .textSelection(.enabled)
            }
            if let map = MapLinks.place(provider: .apple, destination: place.name, coordinate: place.coordinate) {
                Link(destination: map) {
                    Label("Открыть место в Картах", systemImage: "map")
                        .frame(minHeight: 44)
                }
            }
            if let phone = place.phone, !phone.isEmpty {
                if let url = phoneURL(phone) {
                    Link(destination: url) { Label(phone, systemImage: "phone").frame(minHeight: 44) }
                } else { Label(phone, systemImage: "phone").textSelection(.enabled) }
            }
            if let website = place.websiteURL {
                Link(destination: website) { Label("Сайт места", systemImage: "globe").frame(minHeight: 44) }
            }
            Label(accessibilityLabel, systemImage: "figure.roll")
            if !priceDescriptions.isEmpty {
                ForEach(priceDescriptions, id: \.self) { text in Label(text, systemImage: "ticket") }
            } else {
                Label(place.isFree ? "Вход свободный" : "Стоимость уточни перед визитом", systemImage: "ticket")
            }
        }
        .font(.subheadline)
        .foregroundStyle(SeruColor.ink)
        .tint(SeruColor.action)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityLabel: String {
        switch place.accessibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes": return "Доступность: доступно"
        case "no": return "Доступность: есть ограничения"
        case "limited", "partial": return "Доступность: частично доступно"
        case nil, "", "unknown": return "Доступность уточни перед визитом"
        default: return "Доступность: \(place.accessibility ?? "")"
        }
    }

    private var priceDescriptions: [String] {
        Array(Set((place.prices ?? []).compactMap { fields in
            let label = scalar(fields["label"]) ?? scalar(fields["name"]) ?? scalar(fields["title"])
            let amount = scalar(fields["amount"]) ?? scalar(fields["price"]) ?? scalar(fields["value"])
            let currency = scalar(fields["currency"])
            let unit = currency == "KZT" ? "₸" : currency
            let price = amount.map { amount in
                amount == "0" ? "Бесплатно" : amount + (unit.map { " " + $0 } ?? "")
            } ?? scalar(fields["text"])
            let parts = [label, price].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        })).sorted()
    }

    private func scalar(_ value: APIJSONValue?) -> String? {
        switch value {
        case .string(let text): return text
        case .number(let number):
            return number.formatted(.number.locale(Locale(identifier: "ru_RU")))
        default: return nil
        }
    }

    private func phoneURL(_ text: String) -> URL? {
        let number = text.filter { $0.isNumber || $0 == "+" }
        guard number.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(number)")
    }

    private var description: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if !place.reason.isEmpty { Text(place.reason).textSelection(.enabled) }
                if !place.subtitle.isEmpty, place.subtitle != place.address { Text(place.subtitle) }
                if place.reason.isEmpty && place.subtitle.isEmpty { Text("Подробности уточни у места перед визитом.") }
                if let credit = place.descriptionCredit, !credit.isEmpty { Text(credit).font(.caption) }
                if let source = place.sourceURL {
                    Link("Источник информации", destination: source).frame(minHeight: 44)
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

private struct DetailPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let place: Place
    @State private var scale: CGFloat = 1
    @State private var startingScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    PlaceArtwork(place: place, contentMode: .fit)
                        .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                }
                .defaultScrollAnchor(.center)
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { scale = min(max(startingScale * $0.magnification, 1), 4) }
                    .onEnded { _ in startingScale = scale })
                .onTapGesture(count: 2) { setScale(scale > 1 ? 1 : 2) }
            }
            .background(SeruColor.background)
            .navigationTitle("Фото места")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { setScale(max(1, scale - 0.5)) } label: {
                        Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Уменьшить фото")
                    .disabled(scale <= 1)
                    Button { setScale(min(4, scale + 0.5)) } label: {
                        Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Увеличить фото")
                    .disabled(scale >= 4)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
    }

    private func setScale(_ value: CGFloat) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            scale = value; startingScale = value
        }
    }
}
