import SwiftUI

/// Owned by WalkView so leaving the chat for a map or plan keeps the reading
/// position. Scroll geometry is a restoration value, not observable UI state.
@MainActor
final class ChatScrollState {
    var offset: CGFloat?
    var conversationID: UUID?
    var followsLatest = true

    func reset(for id: UUID?) {
        offset = nil
        conversationID = id
        followsLatest = true
    }
}

struct ChatScreen: View {
    let availableHeight: CGFloat
    let scrollState: ChatScrollState
    var collapsed = false
    var focusComposer: Bool = false
    var focusDismissal: Int = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    var onEditing: () -> Void = {}
    var onCompactHeightChange: (CGFloat) -> Void = { _ in }
    var onSettings: ((WalkSettingsSheet) -> Void)? = nil
    var onProfile: () -> Void = {}
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @Environment(ChatAttachmentLoader.self) private var attachmentLoader
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var headingHeight: CGFloat = 32
    @State private var composerHeight: CGFloat = 74
    @State private var showsJournal = false
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var hasRestoredScroll = false
    @State private var userIsScrolling = false
    @State private var showsLatestButton = false
    @AccessibilityFocusState private var errorFocused: Bool

    private var showsWelcome: Bool {
        app.messages.isEmpty && !app.isResponding && app.responseError == nil
    }
    private var conditions: String {
        ([app.origin, "до \(app.duration) мин"] + (app.withKids ? ["с ребёнком"] : []) + (app.onlyFree ? ["бесплатно"] : [])).joined(separator: " · ")
    }

    var body: some View {
        let hidesSheetTitle = !collapsed && showsWelcome
        let visibleHeadingHeight = hidesSheetTitle ? 0 : headingHeight
        let revealHeight = collapsed ? 0 : max(0, availableHeight - visibleHeadingHeight - composerHeight)
        let progress = min(1, revealHeight / 140)
        VStack(spacing: 0) {
            if !hidesSheetTitle {
                Text("Куда пойдём?").font(.title3.weight(.semibold))
                    .foregroundStyle(SeruColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("compact-panel")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if height > 0 { headingHeight = height }
                    }
            }
            conversation(isActive: mascotActive && !showsJournal && !collapsed && revealHeight >= 120)
                .frame(height: max(160, revealHeight), alignment: .top)
                .opacity(progress)
                .frame(height: revealHeight, alignment: .top)
                .clipped()
                .contentShape(.rect)
                .allowsHitTesting(revealHeight >= 120)
                .disabled(revealHeight < 120)
                .accessibilityElement(children: revealHeight >= 120 ? .contain : .ignore)
                .accessibilityHidden(revealHeight < 120)

            ChatComposer(
                focusOnAppear: focusComposer,
                focusDismissal: focusDismissal,
                onFocusChange: onFocusChange,
                onEditing: onEditing,
                onFilters: { onSettings?(.filters) },
                mascotActive: mascotActive && !showsJournal
            )
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
        }
        .frame(height: availableHeight, alignment: .bottom)
        .foregroundStyle(SeruColor.ink)
        .background(SeruColor.surface)
        .onChange(of: headingHeight + composerHeight, initial: true) { _, height in onCompactHeightChange(height) }
        .onChange(of: app.responseError) { _, error in
            guard let error else { return }
            AccessibilityNotification.Announcement(error).post()
            if scrollState.followsLatest { errorFocused = true }
        }
        .sheet(isPresented: $showsJournal) { JournalView() }
        .onDisappear { onFocusChange(false) }
    }

    private func conversation(isActive: Bool) -> some View {
        VStack(spacing: 0) {
            chatHeader
            Button { onSettings?(.filters) } label: {
                HStack(alignment: .center, spacing: 8) {
                    Text(conditions).font(.caption).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(SeruColor.muted)
            .padding(.horizontal, 16)
            .accessibilityLabel("Условия прогулки: \(conditions)")
            .accessibilityIdentifier("chat-current-conditions")

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        if showsWelcome {
                            welcome(availableHeight: viewport.size.height, isActive: isActive)
                                .padding(.vertical, 12)
                                .frame(width: max(0, viewport.size.width - 32))
                                .padding(.horizontal, 16)
                                .frame(minHeight: viewport.size.height)
                                .id("chat-bottom")
                        } else {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(app.messages) { message in
                                    VStack(alignment: .leading, spacing: 12) {
                                        messageBubble(message)
                                        if message.showsRoute { recommendationCard(message) }
                                    }
                                    .id(message.id)
                                }
                                if app.isResponding { responseProgress(isActive: isActive) }
                                if let error = app.responseError { responseFailure(error, isActive: isActive) }
                                if !app.isResponding && app.responseError == nil && app.places.isEmpty
                                    && app.messages.last?.role == .assistant {
                                    HStack(spacing: 12) {
                                        WalkStateMascot(scene: .noPlaces, isActive: isActive).frame(width: 88, height: 88)
                                        Text("Попробуй увеличить время или изменить условия.")
                                            .font(.subheadline).foregroundStyle(SeruColor.muted)
                                    }
                                    .accessibilityIdentifier("chat-no-places")
                                }
                                Color.clear.frame(height: 1).id("chat-bottom")
                            }
                            .frame(width: max(0, viewport.size.width - 32), alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8).padding(.bottom, 16)
                            .frame(minHeight: viewport.size.height, alignment: .top)
                        }
                    }
                    .scrollPosition($position)
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .scrollDismissesKeyboard(.interactively)
                    .onScrollPhaseChange { _, phase in
                        userIsScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    }
                    .onScrollGeometryChange(for: ChatScrollMetrics.self) { geometry in
                        ChatScrollMetrics(offset: max(0, geometry.contentOffset.y),
                                          nearBottom: geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80)
                    } action: { _, value in
                        guard hasRestoredScroll else { return }
                        scrollState.offset = value.offset
                        if userIsScrolling { scrollState.followsLatest = value.nearBottom }
                        showsLatestButton = !value.nearBottom && !showsWelcome
                    }
                    .task {
                        if scrollState.conversationID != app.messages.first?.id {
                            scrollState.reset(for: app.messages.first?.id)
                        }
                        if let offset = scrollState.offset { position.scrollTo(y: offset) }
                        else { position.scrollTo(edge: .bottom) }
                        hasRestoredScroll = true
                    }
                    .onChange(of: app.messages.first?.id) { _, firstID in
                        guard scrollState.conversationID != firstID else { return }
                        scrollState.reset(for: firstID)
                        position.scrollTo(edge: .bottom)
                    }
                    .onChange(of: app.messages.last?.id) { _, _ in
                        if scrollState.followsLatest || app.messages.last?.role == .user { scrollToLatest(proxy) }
                    }
                    .onChange(of: app.isResponding) { _, _ in
                        if scrollState.followsLatest { scrollToLatest(proxy) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showsLatestButton {
                            Button { scrollToLatest(proxy) } label: {
                                Image(systemName: "arrow.down").font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                            .tint(SeruColor.action).padding(12)
                            .accessibilityLabel("К последнему сообщению")
                            .accessibilityIdentifier("chat-latest")
                        }
                    }
                }
            }
        }
        .animation(SeruMotion.feedback(reduceMotion: reduceMotion), value: app.messages.isEmpty)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        scrollState.followsLatest = true
        withAnimation(SeruMotion.scroll(reduceMotion: reduceMotion)) {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }

    private func welcome(availableHeight: CGFloat, isActive: Bool) -> some View {
        let mascotSize = min(144, max(72, availableHeight * 0.3))
        return VStack(spacing: 16) {
            WalkStateMascot(scene: .greeting, isActive: isActive, isDecorative: false)
                .frame(width: mascotSize, height: mascotSize)
                .accessibilityLabel("Серу").accessibilityIdentifier("chat-welcome-mascot")
            Text("Куда сегодня пойдём?")
                .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("chat-welcome-title")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain).accessibilityIdentifier("chat-welcome")
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Button { showsJournal = true } label: {
                if typeSize.isAccessibilitySize {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18)).frame(width: 44, height: 44)
                } else {
                    SeruMenuLabel(title: "Журнал", symbol: "clock.arrow.circlepath")
                        .font(.subheadline).frame(minHeight: 44)
                }
            }
            .accessibilityLabel("Журнал прогулок").accessibilityIdentifier("chat-journal")
            Spacer(minLength: 0)
            if app.currentPlan != nil {
                Button { app.showPlan() } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 18)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("План прогулки").accessibilityIdentifier("open-current-plan")
            }
            Button {
                attachmentLoader.clear()
                scrollState.reset(for: nil)
                app.startNewWalk()
            } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 18)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Новая прогулка").accessibilityIdentifier("chat-new-walk")
            chatOptions
        }
        .buttonStyle(.plain).foregroundStyle(SeruColor.action).padding(.horizontal, 16)
    }

    private var chatOptions: some View {
        Menu {
            Button { app.showResults() } label: { SeruMenuLabel(title: "Места рядом", symbol: "map") }
                .accessibilityIdentifier("chat-nearby")
            Button { app.showPlan() } label: {
                SeruMenuLabel(title: "План прогулки", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .accessibilityIdentifier("open-plan")
            Button(action: onProfile) { SeruMenuLabel(title: "Профиль", symbol: "person.crop.circle") }
                .accessibilityIdentifier("chat-profile")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                .background(SeruColor.field, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Места и план прогулки").accessibilityIdentifier("chat-options")
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 35) }
            VStack(alignment: .leading, spacing: 10) {
                if let attachment = message.attachmentData {
                    ChatPhotoAttachment(data: attachment)
                        .frame(width: 220, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                Text(message.text).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                    .accessibilityIdentifier(isUser ? "user-message" : "assistant-message")
            }
            .foregroundStyle(isUser ? .white : SeruColor.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                isUser ? (scheme == .dark ? SeruColor.field : SeruColor.forest) : SeruColor.assistantBubble,
                in: UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: isUser ? 24 : 7,
                                           bottomTrailingRadius: isUser ? 7 : 24, topTrailingRadius: 24)
            )
            .contextMenu {
                Button { UIPasteboard.general.string = message.text } label: {
                    SeruMenuLabel(title: "Скопировать текст", symbol: "doc.on.doc")
                }
            }
            if !isUser { Spacer(minLength: 25) }
        }
    }

    @ViewBuilder private func recommendationCard(_ message: ChatMessage) -> some View {
        let places = message.snapshot?.places ?? message.placeIDs.map { app.place(id: $0) }
        let plan = message.snapshot?.plan
        if let first = places.first {
            VStack(alignment: .leading, spacing: 0) {
                PlaceArtwork(place: first).frame(height: 130).clipped().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(plan?.name ?? (places.count == 1 ? first.name : "Места для прогулки"))
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let plan {
                        Text("≈ \(plan.duration) мин · \(plan.distance)").font(.caption).foregroundStyle(SeruColor.muted)
                    } else {
                        Text(SeruText.placeCount(places.count)).font(.caption).foregroundStyle(SeruColor.muted)
                    }
                    if let context = message.snapshot?.context {
                        Text("От \(context.origin) · до \(context.duration) мин")
                            .font(.caption).foregroundStyle(SeruColor.muted)
                    }
                    PrimaryAction(title: "На карту", symbol: "map") { app.openRecommendation(message) }
                        .accessibilityIdentifier("chat-show-places")
                }.padding(14)
            }
            .background(SeruColor.surface).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SeruColor.line.opacity(0.5), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat-recommendation-\(message.id)")
        }
    }

    private func responseProgress(isActive: Bool) -> some View {
        HStack(spacing: 12) {
            WalkStateMascot(scene: .thinking, isActive: isActive).frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text("Подбираю места…").font(.subheadline)
                Button("Отмена") { app.cancelResponse() }.font(.subheadline).frame(minHeight: 44)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(SeruColor.ink).padding(14)
        .background(SeruColor.assistantBubble, in: RoundedRectangle(cornerRadius: 20))
    }

    private func responseFailure(_ error: String, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            WalkStateMascot(scene: .connectionError, isActive: isActive).frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 10) {
                Text(error).font(.subheadline).accessibilityIdentifier("response-error").accessibilityFocused($errorFocused)
                Button("Повторить") { app.retryResponse() }
                    .font(.subheadline.weight(.semibold)).tint(SeruColor.action).frame(minHeight: 44)
            }
        }
        .padding(14).foregroundStyle(SeruColor.ink)
        .background(SeruColor.field, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ChatScrollMetrics: Equatable {
    let offset: CGFloat
    let nearBottom: Bool
}
