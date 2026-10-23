import Foundation

enum EventDay: String, Identifiable, Hashable, Sendable {
    case all = "Все"
    case today = "Сегодня"
    case tomorrow = "Завтра"
    case weekend = "Выходные"
    case date = "Дата"

    static let pills: [EventDay] = [.all, .today, .tomorrow, .weekend]
    var id: String { rawValue }
}

/// Values for the system editor. Creating a draft never writes to Calendar.
struct EventCalendarDraft: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let location: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let notes: String
    let url: URL?
}

enum EventPresentation {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .gmt
        return calendar
    }

    static func nextDayChange(after now: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
    }

    /// Only actual starts belong here. A closing label such as «до 21:00» is not a session.
    static func sessions(_ event: CityEvent, now: Date) -> [Date] {
        if !event.sessionDates.isEmpty { return Array(Set(event.sessionDates)).sorted() }
        if event.isLive {
            return !event.time.isEmpty ? event.startDate.map { [$0] } ?? [] : []
        }
        let components = event.time.split(separator: ":")
        guard components.count == 2, let hour = Int(components[0]), let minute = Int(components[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: localDay(event, now: now)) else { return [] }
        return [start]
    }

    static func matchesDay(_ event: CityEvent, day: EventDay, selectedDate: Date, now: Date) -> Bool {
        guard let dates = filterDays(day, selectedDate: selectedDate, now: now) else { return true }
        return dates.contains { occurs(event, on: $0, now: now) }
    }

    static func cardDate(_ event: CityEvent, day: EventDay, selectedDate: Date, now: Date) -> String {
        let actual = sessions(event, now: now)
        if !actual.isEmpty {
            let selectedDays = filterDays(day, selectedDate: selectedDate, now: now)
            let matching = actual.filter { session in
                selectedDays?.contains { calendar.isDate(session, inSameDayAs: $0) } ?? true
            }
            if let next = matching.first(where: { $0 >= now }) ?? matching.first ?? actual.first {
                let label = day == .date ? selectedDateLabel(next) : dayLabel(next, now: now)
                return "\(label) · \(format(next, pattern: "HH:mm"))"
            }
        }
        if !event.isLive {
            let localDate = localDay(event, now: now)
            let label = day == .date ? selectedDateLabel(localDate) : dayLabel(localDate, now: now)
            return event.time.isEmpty ? label : "\(label) · \(event.time)"
        }
        guard let start = event.startDate ?? event.endDate else {
            return event.dateLabel.isEmpty ? "Дата уточняется" : event.dateLabel
        }
        if let dates = filterDays(day, selectedDate: selectedDate, now: now),
           let matching = dates.first(where: { occurs(event, on: $0, now: now) }) {
            return day == .date ? selectedDateLabel(matching) : dayLabel(matching, now: now)
        }
        let first = dayLabel(start, now: now)
        if let end = event.endDate, !calendar.isDate(start, inSameDayAs: end) {
            return "\(first) — \(format(end, pattern: "d MMM"))"
        }
        return first
    }

    static func sessionLabel(_ date: Date) -> String {
        format(date, pattern: "d MMMM yyyy · HH:mm")
    }

    static func selectedDateLabel(_ date: Date) -> String { format(date, pattern: "d MMM") }

    static func sessionCount(_ count: Int) -> String {
        "\(count) \(plural(count, one: "сеанс", few: "сеанса", many: "сеансов"))"
    }

    static func eventCount(_ count: Int) -> String {
        "\(count) \(plural(count, one: "событие", few: "события", many: "событий"))"
    }

    static func calendarDraft(_ event: CityEvent, session: Date? = nil, now: Date) -> EventCalendarDraft? {
        let actual = sessions(event, now: now)
        if let session, !actual.contains(session) { return nil }
        let chosen = session ?? actual.first(where: { $0 >= now }) ?? actual.first
        let allDay = chosen == nil
        let start: Date
        let end: Date
        var notes = event.description
        if let chosen {
            start = chosen
            if event.isLive, event.sessionDates.isEmpty, let knownEnd = event.endDate, knownEnd > chosen {
                end = knownEnd
            } else {
                end = chosen.addingTimeInterval(3_600)
                notes += "\n\nВремя окончания не указано — проверь его у организатора. В календаре предложен 1 час."
            }
        } else {
            guard let first = event.isLive ? event.startDate ?? event.endDate : localDay(event, now: now) else { return nil }
            start = calendar.startOfDay(for: first)
            let last = event.isLive ? max(start, calendar.startOfDay(for: event.endDate ?? first)) : start
            end = nextDayChange(after: last)
            if !event.time.isEmpty { notes += "\n\nЧасы: \(event.time). Точное время начала уточни у организатора." }
        }
        return EventCalendarDraft(id: "\(event.id)-\(start.timeIntervalSince1970)", title: event.title,
                                  location: event.venue, start: start, end: end, isAllDay: allDay,
                                  notes: notes, url: event.sourceURL)
    }

    /// Search opens the venue; the event feed does not contain a verified destination coordinate.
    static func venueURL(_ event: CityEvent) -> URL? {
        let venue = event.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !venue.isEmpty, venue != "Место уточняется" else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: "\(venue), Астана")]
        return components.url
    }

    private static func occurs(_ event: CityEvent, on date: Date, now: Date) -> Bool {
        if !event.isLive { return calendar.isDate(localDay(event, now: now), inSameDayAs: date) }
        if !event.sessionDates.isEmpty {
            return event.sessionDates.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        guard let first = event.startDate ?? event.endDate else { return false }
        let start = calendar.startOfDay(for: first)
        let end = max(start, calendar.startOfDay(for: event.endDate ?? first))
        let selected = calendar.startOfDay(for: date)
        return selected >= start && selected <= end
    }

    private static func filterDays(_ day: EventDay, selectedDate: Date, now: Date) -> [Date]? {
        let today = calendar.startOfDay(for: now)
        switch day {
        case .all: return nil
        case .today: return [today]
        case .tomorrow: return [nextDayChange(after: today)]
        case .date: return [calendar.startOfDay(for: selectedDate)]
        case .weekend:
            guard let first = (0..<7).compactMap({ calendar.date(byAdding: .day, value: $0, to: today) })
                .first(where: { calendar.isDateInWeekend($0) }) else { return [] }
            return [first, nextDayChange(after: first)].filter { calendar.isDateInWeekend($0) }
        }
    }

    private static func localDay(_ event: CityEvent, now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return event.isTomorrow ? nextDayChange(after: today) : today
    }

    private static func dayLabel(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Сегодня" }
        if calendar.isDate(date, inSameDayAs: nextDayChange(after: now)) { return "Завтра" }
        return format(date, pattern: "d MMM")
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        if (11...14).contains(abs(count) % 100) { return many }
        switch abs(count) % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
