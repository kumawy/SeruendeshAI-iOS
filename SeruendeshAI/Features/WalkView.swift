import SwiftUI

struct WalkView: View {
    let topClearance: CGFloat
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @Environment(ChatAttachmentLoader.self) private var attachmentLoader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detent: PanelSize = .compact
    @State private var chatScrollState = ChatScrollState()
    @State private var settings: WalkSettingsSheet?
    @State private var utilitySheet: UtilitySheet?
    @State private var keyboardActive = false
    @State private var focusComposer = false
    @State private var focusDismissal = 0
    @State private var compactContentHeight: CGFloat = 106
    @State private var scrollOffsets: [WalkScreen: CGFloat] = [:]
    @State private var dragStartHeight: CGFloat?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragBeganWithKeyboard = false
    @GestureState private var isDragging = false

    enum PanelSize { case compact, medium, expanded }
    private enum UtilitySheet: String, Identifiable {
        case journal, profile
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.height
            let height = draggedPanelHeight(in: total)
            let visibleMapHeight = max(0, total - height)
            let showsMap = app.screen != .chat || visibleMapHeight > topClearance + 96
            ZStack(alignment: .bottom) {
                if app.usesBackend {
                    LiveMapView(screen: app.screen, visibleHeight: visibleMapHeight, showsContent: showsMap,
                                onBackgroundTap: closeChat)
                } else {
                    DemoMapView(screen: app.screen, visibleHeight: visibleMapHeight, showsContent: showsMap,
                                onBackgroundTap: closeChat)
                }
                VStack(spacing: 0) {
                    panelHandle(in: total)
                    if app.screen == .home || app.screen == .chat {
                        ChatScreen(
                            availableHeight: max(0, height - 44),
                            scrollState: chatScrollState,
                            collapsed: app.screen == .home && dragStartHeight == nil,
                            focusComposer: focusComposer,
                            focusDismissal: focusDismissal,
                            onFocusChange: { focused in
                                if app.screen == .home || app.screen == .chat {
                                    keyboardActive = focused
                                    if focused {
                                        focusComposer = false
                                        detent = .expanded
                                    }
                                }
                            },
                            onEditing: {
                                if app.screen == .home { openChat(focus: true) }
                            },
                            onCompactHeightChange: { height in
                                if abs(compactContentHeight - height) > 1 { compactContentHeight = height }
                            },
                            onSettings: presentSettings,
                            onProfile: { dismissComposer(); utilitySheet = .profile },
                            mascotActive: mascotActive && settings == nil
                        )
                    } else {
                        panelBack
                        scrollingContent(for: app.screen)
                    }
                }
                .frame(height: height, alignment: .top)
                .background(SeruColor.surface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            }
            .background(showsMap ? SeruColor.background : SeruColor.surface)
            .animation(dragStartHeight != nil ? nil : SeruMotion.panel(reduceMotion: reduceMotion), value: height)
            .onChange(of: isDragging) { _, active in
                if !active && dragStartHeight != nil {
                    finishDrag(translation: dragTranslation, predictedTranslation: dragTranslation, in: total)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(item: $settings) { kind in WalkSettingsView(kind: kind) }
        .sheet(item: $utilitySheet) { kind in
            switch kind {
            case .journal: JournalView()
            case .profile: ProfileView()
            }
        }
        .toolbar(keyboardActive ? .hidden : .visible, for: .tabBar)
        .onChange(of: app.screen, initial: true) { _, next in
            switch next {
            case .home: detent = .compact; focusComposer = false
            case .chat:
                if dragStartHeight == nil && detent == .compact {
                    detent = focusComposer ? .expanded : .medium
                }
            default: detent = .medium; dismissComposer()
            }
        }
    }

    private func openChat(focus: Bool) {
        focusComposer = focus
        app.showChat()
        detent = focus ? .expanded : .medium
    }

    private func closeChat() {
        dismissComposer()
        while app.screen != .home { app.goBack() }
        detent = .compact
    }

    private func presentSettings(_ kind: WalkSettingsSheet) {
        dismissComposer()
        if app.screen == .home { openChat(focus: false) }
        settings = kind
    }

    private func scrollingContent(for screen: WalkScreen) -> some View {
        PanelScrollView(offset: Binding(
            get: { scrollOffsets[screen] ?? 0 },
            set: { scrollOffsets[screen] = $0 }
        )) {
            panelContent.padding(.bottom, 20)
        }.id(screen)
    }

    private func panelHeight(in total: CGFloat) -> CGFloat {
        if app.screen == .home { return height(for: .compact, in: total) }
        if keyboardActive || (typeSize.isAccessibilitySize && app.screen != .chat) {
            return height(for: .expanded, in: total)
        }
        return height(for: detent, in: total)
    }

    private func height(for size: PanelSize, in total: CGFloat) -> CGFloat {
        let maximum = max(180, total - topClearance)
        switch size {
        case .compact: return min(compactContentHeight + 44, maximum)
        case .medium:
            let fraction = typeSize.isAccessibilitySize ? 0.78 : 0.56
            let minimum: CGFloat = typeSize.isAccessibilitySize ? 560 : 420
            return min(max(total * fraction, minimum), maximum)
        case .expanded: return maximum
        }
    }

    private func draggedPanelHeight(in total: CGFloat) -> CGFloat {
        guard let start = dragStartHeight, !dragBeganWithKeyboard else { return panelHeight(in: total) }
        let minimum = height(for: app.screen == .home || app.screen == .chat ? .compact : .medium, in: total)
        return min(max(start - dragTranslation, minimum), height(for: .expanded, in: total))
    }

    private func panelHandle(in total: CGFloat) -> some View {
        Button {
            if app.screen == .home { openChat(focus: false) }
            else if detent == .expanded { dismissComposer(); detent = .medium }
            else { detent = .expanded }
        } label: {
            Capsule().fill(SeruColor.line).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detent == .expanded ? "Свернуть панель" : "Развернуть панель")
        .accessibilityValue(app.screen == .home ? "Свёрнуто" : detent == .expanded ? "Полностью" : "Наполовину")
        .accessibilityIdentifier("panel-handle")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if app.screen == .home { openChat(focus: false) } else { detent = .expanded }
            case .decrement:
                if app.screen == .chat && detent == .medium { closeChat() }
                else { dismissComposer(); detent = .medium }
            @unknown default: break
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = panelHeight(in: total)
                        dragBeganWithKeyboard = keyboardActive
                        if keyboardActive { dismissComposer() }
                    }
                    dragTranslation = value.translation.height
                    if app.screen == .home && value.translation.height < -10 {
                        app.showChat()
                    }
                }
                .onEnded { value in
                    finishDrag(translation: value.translation.height,
                               predictedTranslation: value.predictedEndTranslation.height, in: total)
                }
        )
    }

    private func dismissComposer() {
        focusComposer = false
        keyboardActive = false
        focusDismissal += 1
    }

    private func finishDrag(translation: CGFloat, predictedTranslation: CGFloat, in total: CGFloat) {
        guard dragStartHeight != nil else { return }
        let target: PanelSize
        if dragBeganWithKeyboard {
            target = translation > 25 ? .medium : .expanded
        } else {
            let start = dragStartHeight ?? panelHeight(in: total)
            let momentum = min(max((predictedTranslation - translation) * 0.2, -80), 80)
            let projectedHeight = start - translation - momentum
            let options: [PanelSize] = app.screen == .home || app.screen == .chat
                ? [.compact, .medium, .expanded] : [.medium, .expanded]
            target = options.min {
                abs(height(for: $0, in: total) - projectedHeight) < abs(height(for: $1, in: total) - projectedHeight)
            } ?? .medium
        }
        dragStartHeight = nil
        dragTranslation = 0
        dragBeganWithKeyboard = false
        if target == .compact {
            if app.screen == .chat { closeChat() }
            else { detent = .compact }
        } else {
            if app.screen == .home { app.showChat() }
            detent = target
        }
    }

    private var panelBack: some View {
        HStack {
            Button { app.goBack() } label: {
                SeruMenuLabel(title: "Назад", symbol: "chevron.left").font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
            .accessibilityIdentifier("walk-back")
            Spacer()
            if app.screen == .results {
                Button { settings = .filters } label: {
                    SeruMenuLabel(title: "Условия", symbol: "slider.horizontal.3").font(.subheadline).frame(minHeight: 44)
                }
            }
            Menu {
                Button { utilitySheet = .journal } label: { SeruMenuLabel(title: "Журнал прогулок", symbol: "clock.arrow.circlepath") }
                Button {
                    attachmentLoader.clear()
                    app.startNewWalk()
                } label: { SeruMenuLabel(title: "Новая прогулка", symbol: "square.and.pencil") }
                Button { utilitySheet = .profile } label: { SeruMenuLabel(title: "Профиль", symbol: "person.crop.circle") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Журнал и профиль").accessibilityIdentifier("walk-options")
        }
        .foregroundStyle(SeruColor.action).padding(.horizontal, 16)
    }

    @ViewBuilder private var panelContent: some View {
        switch app.screen {
        case .home: EmptyView()
        case .results: ResultsPanel(onSettings: { settings = .filters }, mascotActive: mascotActive && settings == nil)
        case .detail(let id): PlaceDetailContent(place: app.place(id: id))
        case .route(let id): RoutePreviewContent(place: app.place(id: id), route: app.routeForCurrentScreen,
                                               mascotActive: mascotActive && settings == nil)
        case .plan: WalkPlanContent(mascotActive: mascotActive && settings == nil)
        case .chat: EmptyView()
        }
    }
}

private struct PanelScrollView<Content: View>: View {
    @Binding var offset: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var position = ScrollPosition(edge: .top)
    @State private var hasRestored = false
    var body: some View {
        ScrollView { content() }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in
                if hasRestored { offset = max(0, value) }
            }
            .task {
                let saved = offset
                position.scrollTo(y: saved)
                hasRestored = true
            }
    }
}

struct ResultsPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var errorFocused: Bool
    let onSettings: () -> Void
    var mascotActive: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onSettings) {
                    Label("\(app.origin) · \(app.duration) мин", systemImage: "mappin")
                        .font(.system(.caption, design: .default))
                        .frame(minHeight: 44)
                }
                Spacer(minLength: 2)
                Text(SeruText.placeCount(app.places.count)).font(.caption).foregroundStyle(SeruColor.muted)
                    .contentTransition(.numericText(value: Double(app.places.count)))
                    .animation(SeruMotion.feedback(reduceMotion: reduceMotion), value: app.places.count)
            }.foregroundStyle(SeruColor.ink)
            if app.isResponding {
                HStack(spacing: 16) {
                    WalkStateMascot(scene: .thinking, isActive: mascotActive)
                        .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Подбираю места…").font(.subheadline)
                        Button("Отмена") { app.cancelResponse() }.frame(minHeight: 44)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = app.responseError {
                HStack(alignment: .top, spacing: 16) {
                    WalkStateMascot(scene: .connectionError, isActive: mascotActive)
                        .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.subheadline).foregroundStyle(SeruColor.muted)
                            .accessibilityIdentifier("response-error").accessibilityFocused($errorFocused)
                        Button("Повторить") { app.retryResponse() }.frame(minHeight: 44)
                    }
                }
            } else if app.places.isEmpty {
                ContentUnavailableView {
                    WalkStateMascot(scene: .noPlaces, isActive: mascotActive)
                        .frame(width: 148, height: 148)
                    Text("Пока нет подходящих мест")
                } description: {
                    Text("Попробуй увеличить время или изменить условия.")
                } actions: {
                    Button("Изменить условия", action: onSettings).buttonStyle(.borderedProminent)
                }
            }
            ForEach(app.places) { place in
                HStack(alignment: .top, spacing: 10) {
                    Button { app.showPlace(place) } label: {
                        HStack(spacing: 12) {
                            PlaceThumbnail(place: place)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(place.name).font(.system(.subheadline, design: .default, weight: .bold)).foregroundStyle(SeruColor.ink)
                                    .lineLimit(2)
                                HStack(spacing: 5) {
                                    Label("\(place.travelMinutes) мин", systemImage: "figure.walk")
                                    Text("· \(place.distance)")
                                }.font(.system(.caption2, design: .default)).foregroundStyle(SeruColor.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("place-\(place.id)")
                    SavePlaceButton(place: place)
                }
                .padding(10).background(SeruColor.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            Button { app.showChat() } label: {
                Label("Уточнить", systemImage: "bubble.left")
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(SeruColor.action)
                    .background(SeruColor.field, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .onChange(of: app.responseError) { _, error in
            if let error {
                AccessibilityNotification.Announcement(error).post()
                errorFocused = true
            }
        }
    }
}

/// Feature-level activity, with viewport visibility and Reduce Motion owned by the player.
struct WalkStateMascot: View {
    let scene: SeruMascotScene
    var isActive: Bool = true
    var isDecorative: Bool = true
    var owningTab: AppTab = .walk
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SeruMascotAnimation(scene: scene,
                            isActive: isActive && app.tab == owningTab && scenePhase == .active)
            .accessibilityHidden(isDecorative)
    }
}
