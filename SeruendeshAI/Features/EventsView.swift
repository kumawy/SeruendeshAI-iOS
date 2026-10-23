import SwiftUI

struct EventsView: View {
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var day: EventDay = .today
    @State private var freeOnly = false
    @State private var savedOnly = false
    @State private var category = "Все категории"
    @State private var selectedDate = Date.now
    @State private var demoToday = Calendar.current.startOfDay(for: .now)
    @State private var showingDatePicker = false
    @State private var showingFilters = false
    @FocusState private var searchFocused: Bool

    private var shouldAnimateMascot: Bool {
        mascotActive && app.tab == .events && !showingDatePicker && !showingFilters && !searchFocused
    }

    private var emptyStateKind: EventsEmptyState {
        EventsEmptyState.select(savedOnly: savedOnly, hasSavedEvents: !app.savedEvents.isEmpty,
                                query: query, hasCategoryFilter: category != "Все категории", freeOnly: freeOnly)
    }

    private var categories: [String] {
        ["Все категории"] + Set(app.events.map(\.category)).sorted()
    }

    private var eventCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .gmt
        return calendar
    }

    private var filteredEvents: [CityEvent] {
        app.events.filter { event in
            let matchesDay: Bool
            if event.isLive {
                matchesDay = matchesLiveDay(event)
            } else {
                let eventDate = Calendar.current.date(
                    byAdding: .day, value: event.isTomorrow ? 1 : 0, to: demoToday
                ) ?? demoToday
                switch day {
                case .all: matchesDay = true
                case .today: matchesDay = !event.isTomorrow
                case .tomorrow: matchesDay = event.isTomorrow
                case .weekend: matchesDay = Calendar.current.isDateInWeekend(eventDate)
                case .date: matchesDay = Calendar.current.isDate(eventDate, inSameDayAs: selectedDate)
                }
            }
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = search.isEmpty ||
                "\(event.title) \(event.venue) \(event.category)".localizedStandardContains(search)
            return matchesDay && matchesSearch && (!freeOnly || event.isFree) &&
                (!savedOnly || app.isEventSaved(event)) &&
                (category == "Все категории" || event.category == category)
        }
    }

    private func matchesLiveDay(_ event: CityEvent) -> Bool {
        let today = eventCalendar.startOfDay(for: app.eventToday)
        switch day {
        case .all:
            return true
        case .today:
            return eventOccurs(event, on: today)
        case .tomorrow:
            guard let tomorrow = eventCalendar.date(byAdding: .day, value: 1, to: today) else { return false }
            return eventOccurs(event, on: tomorrow)
        case .date:
            return eventOccurs(event, on: selectedDate)
        case .weekend:
            // Include the current weekend, or the next one from the backend's Almaty date.
            guard let weekendStart = (0..<7).compactMap({
                eventCalendar.date(byAdding: .day, value: $0, to: today)
            }).first(where: { eventCalendar.isDateInWeekend($0) }) else { return false }
            return (0..<2).compactMap {
                eventCalendar.date(byAdding: .day, value: $0, to: weekendStart)
            }.filter {
                eventCalendar.isDateInWeekend($0)
            }.contains {
                eventOccurs(event, on: $0)
            }
        }
    }

    private func eventOccurs(_ event: CityEvent, on date: Date) -> Bool {
        if !event.sessionDates.isEmpty {
            return event.sessionDates.contains { eventCalendar.isDate($0, inSameDayAs: date) }
        }
        guard let start = event.startDate ?? event.endDate else { return false }
        let startDay = eventCalendar.startOfDay(for: start)
        let endDay = eventCalendar.startOfDay(for: event.endDate ?? start)
        let selectedDay = eventCalendar.startOfDay(for: date)
        return selectedDay >= startDay && selectedDay <= max(startDay, endDay)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    searchField
                        .padding(.horizontal, 16)
                    dayFilters
                    if !app.usesBackend || !app.events.isEmpty ||
                        (!app.isLoadingEvents && app.eventsError == nil) {
                        eventCount
                            .padding(.horizontal, 16)
                    }
                    if app.usesBackend, let error = app.eventsError, !app.events.isEmpty {
                        eventsFailure(error)
                            .padding(.horizontal, 16)
                    }

                    if app.usesBackend && app.isLoadingEvents && app.events.isEmpty {
                        eventsLoading
                            .padding(.horizontal, 16)
                    } else if app.usesBackend, let error = app.eventsError, app.events.isEmpty {
                        eventsFailure(error, showsMascot: true)
                            .padding(.horizontal, 16)
                    } else if filteredEvents.isEmpty {
                        emptyState
                            .padding(.horizontal, 16)
                    } else {
                        LazyVStack(spacing: 20) {
                            ForEach(filteredEvents) { event in
                                EventFeedCard(
                                    event: event,
                                    isSaved: app.isEventSaved(event),
                                    toggleSaved: { app.toggleSavedEvent(event) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(SeruColor.background)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await app.refreshEvents() }
            .task {
                if app.usesBackend && app.events.isEmpty && !app.isLoadingEvents {
                    await app.refreshEvents()
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: CityEvent.self) { event in
                EventDetailView(
                    event: event,
                    isSaved: app.isEventSaved(event),
                    toggleSaved: { app.toggleSavedEvent(event) }
                )
            }
            .sheet(isPresented: $showingDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showingFilters) {
                filterSheet
            }
        }
        .tint(SeruColor.action)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SeruColor.muted)
            TextField("Поиск событий", text: $query)
                .font(.subheadline)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("Поиск событий")
                .accessibilityIdentifier("events-search")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SeruColor.muted)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Очистить поиск")
            }

            Button {
                searchFocused = false
                showingFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SeruColor.ink)
                    .frame(width: 44, height: 44)
                    .background(SeruColor.field, in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if freeOnly || savedOnly || category != "Все категории" {
                            Circle()
                                .fill(SeruColor.action)
                                .frame(width: 9, height: 9)
                        }
                    }
            }
            .accessibilityLabel("Фильтры событий")
            .accessibilityIdentifier("events-filters")
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(SeruColor.surface, in: .capsule)
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }

    private var selectedDateLabel: String {
        guard app.usesBackend else {
            return selectedDate.formatted(.dateTime.day().month(.abbreviated))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = eventCalendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: selectedDate)
    }

    private var dayFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(EventDay.pills) { option in
                    EventFilterPill(title: option.rawValue, isSelected: day == option) {
                        day = option
                    }
                }
                EventFilterPill(
                    title: day == .date ? selectedDateLabel : "Выбрать дату",
                    symbol: "calendar",
                    isSelected: day == .date
                ) {
                    showingDatePicker = true
                }
                EventFilterPill(title: "Бесплатно", isSelected: freeOnly) {
                    freeOnly.toggle()
                }
                if savedOnly {
                    EventFilterPill(title: "Сохранённые", symbol: "heart.fill", isSelected: true) {
                        savedOnly = false
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var eventCount: some View {
        Text("\(filteredEvents.count) \(eventCountWord(filteredEvents.count))")
            .font(.subheadline)
            .foregroundStyle(SeruColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Событий найдено: \(filteredEvents.count)")
            .accessibilityIdentifier("events-count")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            stateMascot(emptyStateScene)
            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("events-empty-title")
            PrimaryAction(title: emptyStateActionTitle, action: resolveEmptyState)
                .accessibilityIdentifier("events-empty-action")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .seruCard(radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("events-empty-state")
    }

    private var emptyStateScene: SeruMascotScene {
        switch emptyStateKind {
        case .noSavedEvents: .emptyBox
        case .noMatches: .searchEmpty
        case .noEventsOnSelectedDay: .calendarEmpty
        }
    }

    private var emptyStateTitle: String {
        switch emptyStateKind {
        case .noSavedEvents: "Пока нет сохранённых событий"
        case .noMatches: "По этим условиям событий нет"
        case .noEventsOnSelectedDay:
            day == .all ? "Событий пока нет" : day == .weekend ? "На выходные событий нет" : "На эту дату событий нет"
        }
    }

    private var emptyStateActionTitle: String {
        switch emptyStateKind {
        case .noSavedEvents: "Показать все события"
        case .noMatches: "Сбросить фильтры"
        case .noEventsOnSelectedDay:
            day != .all ? "Показать все даты" : savedOnly ? "Показать все события" : "Обновить"
        }
    }

    private func resolveEmptyState() {
        switch emptyStateKind {
        case .noSavedEvents, .noMatches:
            resetFilters()
        case .noEventsOnSelectedDay:
            if day != .all { day = .all }
            else if savedOnly { savedOnly = false }
            else { Task { await app.refreshEvents() } }
        }
    }

    private var eventsLoading: some View {
        VStack(spacing: 16) {
            stateMascot(.postersLoading)
            Text("Загружаем события")
                .font(.headline)
                .foregroundStyle(SeruColor.ink)
                .accessibilityIdentifier("events-loading-title")
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220)
        .seruCard(radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("events-loading")
    }

    private func stateMascot(_ scene: SeruMascotScene) -> some View {
        SeruMascotAnimation(scene: scene, isActive: shouldAnimateMascot)
            .frame(width: 168, height: 168)
            .accessibilityIdentifier("events-mascot-\(scene.rawValue)")
    }

    private func eventsFailure(_ message: String, showsMascot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsMascot {
                stateMascot(.connectionError)
                    .frame(maxWidth: .infinity)
            }
            Label("Не удалось загрузить события", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(SeruColor.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SeruColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("events-error")
            PrimaryAction(title: "Повторить", symbol: "arrow.clockwise") {
                Task { await app.refreshEvents() }
            }
            .accessibilityIdentifier("events-retry")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .seruCard(radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(showsMascot ? "events-load-failure" : "events-refresh-error")
    }

    private var datePickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    DatePicker("Дата события", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.calendar, app.usesBackend ? eventCalendar : .current)
                        .environment(\.timeZone, app.usesBackend ? eventCalendar.timeZone : .current)
                    PrimaryAction(title: "Показать события", symbol: "calendar") {
                        day = .date
                        showingDatePicker = false
                    }
                }
                .padding(20)
            }
            .background(SeruColor.background)
            .navigationTitle("Выбрать дату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showingDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Подборка") {
                    Toggle("Только бесплатные", isOn: $freeOnly)
                    Toggle("Сохранённые", isOn: $savedOnly)
                        .accessibilityIdentifier("events-saved-filter")
                    Picker("Категория", selection: $category) {
                        ForEach(categories, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                Section("Когда") {
                    Picker("День", selection: $day) {
                        ForEach(EventDay.pills) { option in
                            Text(option.rawValue).tag(option)
                        }
                        Text("Выбранная дата").tag(EventDay.date)
                    }
                    if day == .date {
                        DatePicker("Дата", selection: $selectedDate, displayedComponents: .date)
                            .environment(\.calendar, app.usesBackend ? eventCalendar : .current)
                            .environment(\.timeZone, app.usesBackend ? eventCalendar.timeZone : .current)
                    }
                }
                Section {
                    Button("Сбросить фильтры") { resetFilters() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SeruColor.background)
            .tint(SeruColor.action)
            .navigationTitle("Фильтры событий")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showingFilters = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func resetFilters() {
        query = ""
        day = .all
        freeOnly = false
        savedOnly = false
        category = "Все категории"
    }

    private func eventCountWord(_ count: Int) -> String {
        if (11...14).contains(count % 100) { return "событий" }
        switch count % 10 {
        case 1: return "событие"
        case 2...4: return "события"
        default: return "событий"
        }
    }
}

private enum EventDay: String, Identifiable, Hashable {
    case all = "Все"
    case today = "Сегодня"
    case tomorrow = "Завтра"
    case weekend = "Выходные"
    case date = "Дата"

    static let pills: [EventDay] = [.all, .today, .tomorrow, .weekend]
    var id: String { rawValue }
}

private struct EventFilterPill: View {
    let title: String
    var symbol: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .fixedSize()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? SeruColor.onAction : SeruColor.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(isSelected ? SeruColor.action : SeruColor.surface, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EventFeedCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let event: CityEvent
    let isSaved: Bool
    let toggleSaved: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                NavigationLink(value: event) {
                    EventPhoto(event: event, height: 192)
                        .overlay(alignment: .topLeading) {
                            EventPriceBadge(event: event)
                                .padding(12)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Подробнее: \(event.title)")
                .accessibilityHint("Открыть информацию о событии")
                .accessibilityIdentifier("event-photo-\(event.id)")

                Button(action: toggleSaved) {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(SeruColor.action)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "Убрать событие из сохранённых" : "Сохранить событие")
                .accessibilityValue(isSaved ? "Сохранено" : "Не сохранено")
                .accessibilityIdentifier("save-event-\(event.id)")
                .padding(8)
            }

            NavigationLink(value: event) {
                VStack(alignment: .leading, spacing: 8) {
                    dateLabel
                    Text(event.title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(SeruColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    metadataLayout {
                        Label(event.venue, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(SeruColor.muted)
                            .multilineTextAlignment(.leading)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 2) }
                        HStack(spacing: 2) {
                            Text("Подробнее")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SeruColor.action)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть информацию о событии")
            .accessibilityIdentifier("event-detail-\(event.id)")
        }
        .background(SeruColor.surface)
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }

    private var dateLabel: some View {
        Label(eventDisplayDate(event), systemImage: event.isLive || event.isTomorrow ? "calendar" : "clock")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SeruColor.action)
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }
}

private struct EventPhoto: View {
    let event: CityEvent
    let height: CGFloat

    var body: some View {
        EventArtwork(event: event)
            .frame(height: height)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }
}

private struct EventPriceBadge: View {
    let event: CityEvent

    var body: some View {
        if event.isFree || !event.price.isEmpty {
            Text(event.isFree ? "Бесплатно" : event.price)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SeruColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: .capsule)
        }
    }
}

struct EventDetailView: View {
    let event: CityEvent
    let isSaved: Bool
    let toggleSaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EventPhoto(event: event, height: 250)
                    .clipShape(.rect(cornerRadius: 20))
                Text(event.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SeruColor.ink)
                VStack(alignment: .leading, spacing: 14) {
                    Label(eventDisplayDate(event), systemImage: "calendar")
                    Label(event.venue, systemImage: "mappin.and.ellipse")
                    if !event.isLive || event.travelMinutes > 0 {
                        Label("\(event.travelMinutes) мин пешком", systemImage: "figure.walk")
                    }
                    if event.isFree || !event.price.isEmpty {
                        Label(event.isFree ? "Вход свободный" : event.price, systemImage: "ticket")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(SeruColor.action)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .seruCard(radius: 16)
                Text(event.description)
                    .font(.body)
                    .foregroundStyle(SeruColor.ink)
                if event.isLive, let source = event.sourceURL {
                    Link(destination: source) {
                        Label("Подробнее у организатора", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .foregroundStyle(SeruColor.action)
                }
                PrimaryAction(
                    title: isSaved ? "Убрать из сохранённых" : "Сохранить событие",
                    symbol: isSaved ? "heart.fill" : "heart",
                    action: toggleSaved
                )
                .accessibilityValue(isSaved ? "Сохранено" : "Не сохранено")
                .accessibilityIdentifier("event-save-\(event.id)")
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(SeruColor.background)
        .navigationTitle("Событие")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
    }
}

private func eventDisplayDate(_ event: CityEvent) -> String {
    if event.isLive {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Almaty")
        formatter.dateFormat = "d MMM yyyy"
        if !event.sessionDates.isEmpty {
            let dates = event.sessionDates.sorted()
            if let first = dates.first, let last = dates.last {
                let label = formatter.string(from: first)
                if dates.count > 1 {
                    return "\(label) — \(formatter.string(from: last)) · \(dates.count) сеансов"
                }
                return event.time.isEmpty ? label : "\(label) · \(event.time)"
            }
        }
        if let start = event.startDate ?? event.endDate {
            let label = formatter.string(from: start)
            if let end = event.endDate, formatter.string(from: end) != label {
                return "\(label) — \(formatter.string(from: end))"
            }
            return event.time.isEmpty ? label : "\(label) · \(event.time)"
        }
        return event.dateLabel.isEmpty ? "Дата уточняется" : event.dateLabel
    }
    return event.dateLabel.contains(event.time) || event.time.isEmpty
        ? event.dateLabel
        : "\(event.dateLabel) · \(event.time)"
}
