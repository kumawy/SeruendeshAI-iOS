import SwiftUI

struct EventsView: View {
    var mascotActive: Bool = true
    var onProfile: () -> Void = {}
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var day: EventDay = .today
    @State private var freeOnly = false
    @State private var category = "Все категории"
    @State private var selectedDate = Date.now
    @State private var now = Date.now
    @State private var showingDatePicker = false
    @State private var showingFilters = false
    @FocusState private var searchFocused: Bool

    private var shouldAnimateMascot: Bool {
        mascotActive && app.tab == .events && !showingDatePicker && !showingFilters && !searchFocused
    }

    private var emptyStateKind: EventsEmptyState {
        EventsEmptyState.select(query: query, hasCategoryFilter: category != "Все категории", freeOnly: freeOnly)
    }

    private var categories: [String] {
        ["Все категории"] + Set(app.events.map(\.category).filter { !$0.isEmpty }).sorted()
    }

    private var filteredEvents: [CityEvent] {
        app.events.filter { event in
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = search.isEmpty ||
                "\(event.title) \(event.venue) \(event.category)".localizedStandardContains(search)
            return EventPresentation.matchesDay(event, day: day, selectedDate: selectedDate, now: now) &&
                matchesSearch && (!freeOnly || event.isFree) &&
                (category == "Все категории" || event.category == category)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("События")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(SeruColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        ProfileButton(action: onProfile)
                        .accessibilityIdentifier("events-profile")
                    }
                    .padding(.horizontal, 16)
                    searchField
                        .padding(.horizontal, 16)
                    dayFilters
                    if category != "Все категории" {
                        selectedCategoryChip
                            .padding(.horizontal, 16)
                    }
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
                        LazyVStack(spacing: 24) {
                            ForEach(filteredEvents) { event in
                                VStack(spacing: 24) {
                                    EventFeedCard(event: event, dateText: EventPresentation.cardDate(
                                        event, day: day, selectedDate: selectedDate, now: now
                                    ))
                                    Rectangle()
                                        .fill(SeruColor.line)
                                        .frame(height: 1)
                                        .accessibilityHidden(true)
                                }
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
            .refreshable { await refreshCurrentDay() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refreshCurrentDay()
                // Almaty's midnight may differ from the device's calendar-day notification.
                while !Task.isCancelled {
                    let next = EventPresentation.nextDayChange(after: .now)
                    do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
                    catch { return }
                    await refreshCurrentDay()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                guard scenePhase == .active else { return }
                Task { await refreshCurrentDay() }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: CityEvent.self) { event in
                EventDetailView(event: event)
            }
            .sheet(isPresented: $showingDatePicker) {
                EventDatePickerSheet(selectedDate: selectedDate) { date in
                    selectedDate = date
                    day = .date
                }
            }
            .sheet(isPresented: $showingFilters) {
                EventFiltersSheet(categories: categories, freeOnly: freeOnly, category: category,
                                  day: day, selectedDate: selectedDate) { free, selectedCategory, selectedDay, date in
                    freeOnly = free
                    category = selectedCategory
                    day = selectedDay
                    selectedDate = date
                }
            }
        }
        .tint(SeruColor.action)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SeruColor.muted)
            TextField("Поиск событий", text: $query,
                      prompt: Text("Поиск событий").foregroundStyle(SeruColor.muted))
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
                    .font(.body.weight(.medium))
                    .foregroundStyle(SeruColor.ink)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if freeOnly || category != "Все категории" {
                            Circle()
                                .fill(SeruColor.action)
                                .frame(width: 9, height: 9)
                        }
                    }
            }
            .accessibilityLabel("Фильтры событий")
            .accessibilityIdentifier("events-filters")
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(SeruColor.field, in: .rect(cornerRadius: 12))
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
                    title: day == .date ? EventPresentation.selectedDateLabel(selectedDate) : "Выбрать дату",
                    symbol: "calendar",
                    isSelected: day == .date
                ) {
                    showingDatePicker = true
                }
                EventFilterPill(title: "Бесплатно", isSelected: freeOnly) {
                    freeOnly.toggle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var eventCount: some View {
        Text(EventPresentation.eventCount(filteredEvents.count))
            .contentTransition(.numericText(value: Double(filteredEvents.count)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: filteredEvents.count)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("events-empty-state")
    }

    private var emptyStateScene: SeruMascotScene {
        switch emptyStateKind {
        case .noMatches: .searchEmpty
        case .noEventsOnSelectedDay: .calendarEmpty
        }
    }

    private var emptyStateTitle: String {
        switch emptyStateKind {
        case .noMatches: "По этим условиям событий нет"
        case .noEventsOnSelectedDay:
            day == .all ? "Событий пока нет" : day == .weekend ? "На выходные событий нет" : "На эту дату событий нет"
        }
    }

    private var emptyStateActionTitle: String {
        switch emptyStateKind {
        case .noMatches: "Сбросить фильтры"
        case .noEventsOnSelectedDay:
            day != .all ? "Показать все даты" : "Обновить"
        }
    }

    private func resolveEmptyState() {
        switch emptyStateKind {
        case .noMatches:
            resetFilters()
        case .noEventsOnSelectedDay:
            if day != .all { day = .all }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(showsMascot ? "events-load-failure" : "events-refresh-error")
    }

    private var selectedCategoryChip: some View {
        HStack {
            EventFilterPill(title: category, symbol: "xmark", isSelected: true, wrapsTitle: true) {
                category = "Все категории"
            }
            .accessibilityLabel("Убрать фильтр категории «\(category)»")
            .accessibilityIdentifier("events-active-category")
            Spacer(minLength: 0)
        }
    }

    private func refreshCurrentDay() async {
        now = .now
        if app.usesBackend { await app.refreshEvents() }
    }

    private func resetFilters() {
        query = ""
        day = .all
        freeOnly = false
        category = "Все категории"
    }

}

private struct EventFilterPill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var symbol: String? = nil
    let isSelected: Bool
    var wrapsTitle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .fixedSize(horizontal: !wrapsTitle, vertical: true)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? SeruColor.background : SeruColor.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isSelected ? SeruColor.ink : SeruColor.field, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EventFeedCard: View {
    let event: CityEvent
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: event) {
                VStack(alignment: .leading, spacing: 16) {
                    EventPhoto(event: event, height: 224)
                        .overlay(alignment: .top) { EventPhotoBadges(event: event).padding(12) }
                        .clipShape(.rect(cornerRadius: 12))
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(event.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(SeruColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Text(dateText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SeruColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(event.venue)
                                .font(.subheadline)
                                .foregroundStyle(SeruColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SeruColor.muted)
                            .padding(.top, 5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть информацию о событии")
            .accessibilityIdentifier("event-detail-\(event.id)")
            if let destination = EventProviderDestination.forEvent(event) {
                EventProviderAction(destination: destination)
                    .accessibilityIdentifier("event-provider-link-\(event.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.black.opacity(0.78), in: .capsule)
        }
    }
}

private struct EventPhotoBadges: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let event: CityEvent

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            EventPriceBadge(event: event)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            if let destination = EventProviderDestination.forEvent(event) {
                Text(destination.provider.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(destination.provider.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(destination.provider.background, in: .capsule)
                    .accessibilityLabel(destination.isListing
                        ? "Афиша \(destination.provider.title)" : "Источник \(destination.provider.title)")
                    .accessibilityIdentifier("event-provider-badge-\(event.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension EventProvider {
    var background: Color {
        switch self {
        // Sxodim's red is slightly deepened so white text also passes at small sizes.
        case .sxodim: Color(hex: "D83525")
        case .ticketon: Color(hex: "4EBC73")
        }
    }

    var foreground: Color {
        switch self {
        case .sxodim: .white
        case .ticketon: Color(hex: "102718")
        }
    }
}

private struct EventProviderAction: View {
    let destination: EventProviderDestination

    var body: some View {
        Link(destination: destination.url) {
            HStack(spacing: 8) {
                Text(destination.actionTitle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(destination.provider.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(destination.provider.background, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(SeruPressStyle())
        .accessibilityHint(destination.isListing
            ? "Открыть афишу на сайте \(destination.provider.title)"
            : "Открыть страницу события на сайте \(destination.provider.title)")
    }
}

struct EventDetailView: View {
    let event: CityEvent
    @State private var now = Date.now

    private var sessions: [Date] { EventPresentation.sessions(event, now: now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EventPhoto(event: event, height: 250)
                    .overlay(alignment: .top) { EventPhotoBadges(event: event).padding(12) }
                    .clipShape(.rect(cornerRadius: 12))
                Text(event.title)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(SeruColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Label(EventPresentation.cardDate(event, day: .all, selectedDate: now, now: now), systemImage: "calendar")
                        .fontWeight(.medium)
                    if let venue = EventPresentation.venueURL(event) {
                        Link(destination: venue) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Label(event.venue, systemImage: "mappin.and.ellipse")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(SeruColor.ink)
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityHint("Найти площадку и выбрать маршрут в Картах")
                        .accessibilityIdentifier("event-venue-map")
                    } else {
                        Label(event.venue, systemImage: "mappin.and.ellipse")
                    }
                    if event.isFree || !event.price.isEmpty {
                        Label(event.isFree ? "Вход свободный" : event.price, systemImage: "ticket")
                            .foregroundStyle(SeruColor.muted)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(SeruColor.line)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                if sessions.count > 1 {
                    sessionList
                }
                Text(event.description)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(SeruColor.ink)
                    .textSelection(.enabled)
                if let destination = EventProviderDestination.forEvent(event) {
                    EventProviderAction(destination: destination)
                        .accessibilityIdentifier("event-provider-link-\(event.id)")
                    if destination.isListing {
                        Text("Ссылка ведёт в городскую афишу.")
                            .font(.footnote)
                            .foregroundStyle(SeruColor.muted)
                    }
                } else if event.isLive, let source = EventProviderDestination.validatedWebURL(event.sourceURL) {
                    Link(destination: source) {
                        Label("Подробнее у организатора", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(SeruColor.background)
        .tint(SeruColor.action)
        .navigationTitle("Событие")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .task { now = .now }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(EventPresentation.sessionCount(sessions.count))
                .font(.headline)
                .foregroundStyle(SeruColor.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(sessions, id: \.self) { session in
                Label(EventPresentation.sessionLabel(session), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(SeruColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .accessibilityIdentifier("event-sessions")
    }
}

private struct EventDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftDate: Date
    let apply: (Date) -> Void

    init(selectedDate: Date, apply: @escaping (Date) -> Void) {
        _draftDate = State(initialValue: selectedDate)
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    DatePicker("Дата события", selection: $draftDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("events-date-picker")
                    PrimaryAction(title: "Показать события", symbol: "calendar") {
                        apply(draftDate)
                        dismiss()
                    }
                    .accessibilityIdentifier("events-apply-date")
                }
                .padding(20)
            }
            .background(SeruColor.background)
            .navigationTitle("Выбрать дату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .environment(\.calendar, EventPresentation.calendar)
        .environment(\.timeZone, EventPresentation.calendar.timeZone)
        .presentationDetents([.medium, .large])
    }
}

private struct EventFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [String]
    @State private var freeOnly: Bool
    @State private var category: String
    @State private var day: EventDay
    @State private var selectedDate: Date
    let apply: (Bool, String, EventDay, Date) -> Void

    init(categories: [String], freeOnly: Bool, category: String, day: EventDay,
         selectedDate: Date, apply: @escaping (Bool, String, EventDay, Date) -> Void) {
        self.categories = categories
        _freeOnly = State(initialValue: freeOnly)
        _category = State(initialValue: category)
        _day = State(initialValue: day)
        _selectedDate = State(initialValue: selectedDate)
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Подборка") {
                    Toggle("Только бесплатные", isOn: $freeOnly)
                    Picker("Категория", selection: $category) {
                        ForEach(categories, id: \.self) { name in Text(name).tag(name) }
                    }
                }
                Section("Когда") {
                    Picker("День", selection: $day) {
                        ForEach(EventDay.pills) { option in Text(option.rawValue).tag(option) }
                        Text("Выбранная дата").tag(EventDay.date)
                    }
                    if day == .date {
                        DatePicker("Дата", selection: $selectedDate, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Сбросить фильтры") {
                        freeOnly = false
                        category = "Все категории"
                        day = .all
                    }
                    .frame(minHeight: 44)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SeruColor.background)
            .navigationTitle("Фильтры событий")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.frame(minHeight: 44)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        apply(freeOnly, category, day, selectedDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                }
            }
        }
        .tint(SeruColor.action)
        .environment(\.calendar, EventPresentation.calendar)
        .environment(\.timeZone, EventPresentation.calendar.timeZone)
        .presentationDetents([.medium, .large])
    }
}
