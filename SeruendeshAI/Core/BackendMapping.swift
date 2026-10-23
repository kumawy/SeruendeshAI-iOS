import Foundation

enum BackendMapping {
    static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return result
    }

    static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = iso.date(from: value) { return result }
        iso.formatOptions = [.withInternetDateTime]
        if let result = iso.date(from: value) { return result }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = value.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value)
    }

    static func distance(_ meters: Int) -> String {
        meters < 1000 ? "\(max(0, meters)) м" : String(format: "%.1f км", Double(meters) / 1000)
    }

    static func points(_ polyline: [[Double]]) -> [GeoPoint] {
        polyline.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            let point = GeoPoint(latitude: pair[0], longitude: pair[1])
            return point.isValid ? point : nil
        }
    }

    static func place(_ value: APIRecommendation) -> Place {
        let coordinate = GeoPoint(latitude: value.lat, longitude: value.lon)
        let reasons = [value.why, value.whatToDo, value.description ?? ""].filter { !$0.isEmpty }
        var place = Place(
            id: value.poiID, name: value.name,
            category: value.categoryLabel + (value.source == "generated" ? " · Идея Серу" : ""),
            subtitle: value.address ?? value.categoryLabel, imageAsset: "",
            travelMinutes: value.travelMin, visitMinutes: value.visitSuggestedMin,
            distance: distance(value.walkDistanceM ?? value.distanceM),
            hours: value.opening?.label ?? "Часы уточняй",
            rating: value.rating.map { String(format: "%.1f", $0) } ?? "",
            reason: reasons.joined(separator: "\n\n"), symbol: symbol(value.icon),
            isFree: value.badges.contains("free"), isChildFriendly: value.badges.contains("kids")
        )
        place.isLive = true
        place.coordinate = coordinate.isValid ? coordinate : nil
        place.imageURL = value.photo?.url
        if let photo = value.photo {
            place.imageCredit = [photo.author, photo.license].filter { !$0.isEmpty }.joined(separator: " · ")
            place.imageSourceURL = photo.page ?? value.sourceURL
        }
        place.sourceURL = value.descriptionURL ?? value.sourceURL
        place.websiteURL = value.website
        place.address = value.address
        place.phone = value.phone
        place.accessibility = value.accessibility == "unknown" ? nil : value.accessibility
        place.prices = value.prices.isEmpty ? nil : value.prices
        place.descriptionCredit = value.descriptionAttribution.map(\.attribution).filter { !$0.isEmpty }.joined(separator: "\n")
        return place
    }

    static func event(_ value: APIEvent, today: Date) -> CityEvent {
        let sessions = value.sessions.compactMap { date($0) }.sorted()
        let start = date(value.start)
        let end = date(value.end)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let next = sessions.first { $0 >= calendar.startOfDay(for: today) } ?? start
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM"
        let dayLabel: String
        if let next, calendar.isDate(next, inSameDayAs: today) { dayLabel = "Сегодня" }
        else if let next, calendar.isDate(next, inSameDayAs: tomorrow) { dayLabel = "Завтра" }
        else { dayLabel = next.map { formatter.string(from: $0) } ?? "Дата уточняется" }
        let time: String
        if let next, (value.start?.contains("T") == true || !sessions.isEmpty) {
            formatter.dateFormat = "HH:mm"
            time = formatter.string(from: next)
        } else { time = "" }
        let price: String
        if let amount = value.priceFrom {
            price = amount == 0 ? "Бесплатно" : "от \(Int(amount)) \(value.currency == "KZT" || value.currency == nil ? "₸" : value.currency!)"
        } else { price = "Цена уточняется" }
        var event = CityEvent(
            id: value.id, title: value.title, venue: value.venue ?? value.address ?? "Место уточняется",
            dateLabel: dayLabel, time: time, price: price, imageAsset: "", category: value.categoryLabel,
            travelMinutes: 0, isTomorrow: next.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false,
            isFree: value.priceFrom == 0, description: value.description ?? "Подробности можно посмотреть у организатора."
        )
        event.isLive = true; event.imageURL = value.imageURL; event.sourceURL = value.sources.first?.url
        event.startDate = start; event.endDate = end; event.sessionDates = sessions
        return event
    }

    static func route(_ value: APIRoute, response: APIRecommendationResponse, places: [Place], title: String? = nil) -> WalkRoute {
        let ordered = value.order.filter { id in places.contains { $0.id == id } }
        var route = WalkRoute(
            id: response.requestID.isEmpty ? UUID().uuidString : response.requestID,
            name: title ?? (value.summary.isEmpty ? "Прогулка с Серу" : value.summary),
            subtitle: ordered.compactMap { id in places.first { $0.id == id }?.name }.joined(separator: " · "),
            duration: value.totalMin, distance: distance(value.legs.reduce(0) { $0 + $1.distanceM }), placeIDs: ordered
        )
        route.isLive = true
        route.returnMinutes = value.backMin
        route.returnsToStart = value.returnsToStart
        route.fitsBudget = value.fitsBudget
        route.originLabel = response.usedContext?.location?.label ?? response.usedContext?.locationLabel
        if let location = response.usedContext?.location {
            route.originCoordinate = GeoPoint(latitude: location.lat, longitude: location.lon)
        } else { route.originCoordinate = points(value.legs.first?.polyline ?? []).first }
        route.legs = value.legs.map {
            WalkLeg(fromID: $0.fromID, toID: $0.toID, travelMinutes: $0.travelMin,
                    distanceMeters: $0.distanceM, points: points($0.polyline), geometry: $0.geometry)
        }
        return route
    }

    private static func symbol(_ name: String) -> String {
        switch name {
        case "trees", "flower": "tree.fill"
        case "coffee", "cake": "cup.and.saucer.fill"
        case "museum", "landmark", "monument", "gallery": "building.columns.fill"
        case "baby": "figure.and.child.holdinghands"
        case "ticket", "theatre", "cinema": "ticket.fill"
        case "music", "mic": "music.note"
        case "utensils", "burger": "fork.knife"
        case "shopping", "store", "gift": "bag.fill"
        case "waves", "fish": "water.waves"
        case "book": "books.vertical.fill"
        case "laptop": "laptopcomputer"
        case "activity": "figure.walk"
        default: "mappin.circle.fill"
        }
    }
}
