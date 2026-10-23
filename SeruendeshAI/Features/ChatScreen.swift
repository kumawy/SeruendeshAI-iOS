import SwiftUI

struct ChatScreen: View {
    let availableHeight: CGFloat
    var collapsed = false
    var focusComposer: Bool = false
    var focusDismissal: Int = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    var onEditing: () -> Void = {}
    var onCompactHeightChange: (CGFloat) -> Void = { _ in }
    var onSettings: ((WalkSettingsSheet) -> Void)? = nil
    var mascotActive: Bool = true
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headingHeight: CGFloat = 32
    @State private var composerHeight: CGFloat = 74
    private var source: String { scheme == .dark ? "chat-dark" : "chat" }

    private var showsWelcome: Bool {
        app.messages.isEmpty && !app.isResponding && app.responseError == nil
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
                        // The last measured height still sizes the compact panel
                        // while the expanded empty chat omits its old heading.
                        if height > 0 { headingHeight = height }
                    }
            }

            conversation(isActive: mascotActive && !collapsed && revealHeight >= 120)
                .frame(height: max(160, revealHeight), alignment: .top)
                .offset(y: 12 * (1 - progress))
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
                onFocusChange: { focused in
                    onFocusChange(focused)
                },
                onEditing: onEditing,
                onFilters: { onSettings?(.filters) },
                mascotActive: mascotActive
            )
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
        }
        .frame(height: availableHeight, alignment: .bottom)
        .foregroundStyle(SeruColor.ink)
        .background(SeruColor.surface)
        .onChange(of: headingHeight + composerHeight, initial: true) { _, height in
            onCompactHeightChange(height)
        }
        .onDisappear { onFocusChange(false) }
    }

    private func conversation(isActive: Bool) -> some View {
        VStack(spacing: 0) {
            if showsWelcome {
                HStack {
                    Spacer()
                    chatOptions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                chatHeader
            }
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if showsWelcome {
                                welcome(availableHeight: viewport.size.height, isActive: isActive)
                            }
                            ForEach(app.messages) { message in
                                messageBubble(message.text, isUser: message.role == .user, attachment: message.attachmentData)
                                if message.showsRoute {
                                    if app.usesBackend { liveRouteCard(message) }
                                    else { routeCard }
                                }
                            }
                            if app.isResponding {
                                HStack(spacing: 12) {
                                    WalkStateMascot(scene: .thinking, isActive: isActive)
                                        .frame(width: 72, height: 72)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Подбираю места…").font(.subheadline)
                                        Button("Отмена") { app.cancelResponse() }.font(.caption)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(SeruColor.ink)
                                .padding(14)
                                .background(SeruColor.assistantBubble, in: RoundedRectangle(cornerRadius: 20))
                            }
                            if let error = app.responseError {
                                HStack(alignment: .top, spacing: 12) {
                                    WalkStateMascot(scene: .connectionError, isActive: isActive)
                                        .frame(width: 80, height: 80)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(error).font(.subheadline).accessibilityIdentifier("response-error")
                                        Button("Повторить") { app.retryResponse() }
                                            .font(.subheadline.weight(.semibold)).tint(SeruColor.action)
                                    }
                                }
                                .padding(14)
                                .foregroundStyle(SeruColor.ink)
                                .background(SeruColor.field, in: RoundedRectangle(cornerRadius: 18))
                            }
                            if !app.isResponding && app.responseError == nil && app.places.isEmpty
                                && app.messages.last?.role == .assistant {
                                HStack(spacing: 12) {
                                    WalkStateMascot(scene: .noPlaces, isActive: isActive)
                                        .frame(width: 88, height: 88)
                                    Text("Попробуй увеличить время или изменить условия.")
                                        .font(.subheadline)
                                        .foregroundStyle(SeruColor.muted)
                                }
                                .accessibilityIdentifier("chat-no-places")
                            }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: viewport.size.height, alignment: showsWelcome ? .center : .top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: app.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    }
                    .onChange(of: app.isResponding) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: app.messages.isEmpty)
    }

    private func welcome(availableHeight: CGFloat, isActive: Bool) -> some View {
        let mascotSize = min(144, max(88, availableHeight * 0.30))
        return VStack(spacing: 16) {
            WalkStateMascot(scene: .greeting, isActive: isActive, isDecorative: false)
                .frame(width: mascotSize, height: mascotSize)
                .accessibilityLabel("Серу")
                .accessibilityIdentifier("chat-welcome-mascot")
            Text("Куда сегодня хотите?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("chat-welcome-title")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-welcome")
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            Image(decorative: "SeruMascot").resizable().scaledToFit()
                .frame(width: 44, height: 48)
            Text("Серу").font(.headline)
            Spacer()
            chatOptions
        }.padding(.horizontal, 16)
    }

    private var chatOptions: some View {
        Menu {
            Button("Места рядом", systemImage: "map") { app.showResults() }
                .accessibilityIdentifier("chat-nearby")
            Button("План прогулки", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { app.showPlan() }
                .accessibilityIdentifier("open-plan")
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                .background(SeruColor.field, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Места и план прогулки")
        .accessibilityIdentifier("chat-options")
    }

    private func messageBubble(_ text: String, isUser: Bool, attachment: Data? = nil) -> some View {
        HStack {
            if isUser { Spacer(minLength: 35) }
            VStack(alignment: .leading, spacing: 10) {
                if let attachment, let image = UIImage(data: attachment) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 220, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .contentShape(.rect).allowsHitTesting(false)
                        .accessibilityLabel("Прикреплённое фото")
                }
                Text(text).font(.system(.subheadline, design: .default)).lineSpacing(4)
                    .accessibilityIdentifier(isUser ? "user-message" : "assistant-message")
            }
                .foregroundStyle(isUser ? .white : SeruColor.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    isUser ? (scheme == .dark ? SeruColor.field : SeruColor.forest) : SeruColor.assistantBubble,
                    in: UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: isUser ? 24 : 7,
                                               bottomTrailingRadius: isUser ? 7 : 24, topTrailingRadius: 24)
                )
            if !isUser { Spacer(minLength: 25) }
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("\(source)-asset-003").resizable().scaledToFill()
                .frame(height: 130).clipped()
                .allowsHitTesting(false).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("Линейный парк и Sensily")
                    .font(.system(.headline, design: .default)).fixedSize(horizontal: false, vertical: true)
                Text("55 мин · 1.6 км").font(.caption).foregroundStyle(SeruColor.muted)
                PrimaryAction(title: "На карту", symbol: "map") { app.showResults() }
                    .accessibilityIdentifier("chat-show-places")
            }.padding(14)
        }
        .background(SeruColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(SeruColor.line.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder private func liveRouteCard(_ message: ChatMessage) -> some View {
        if let firstID = message.placeIDs.first {
            let place = app.place(id: firstID)
            let plan = message.routeID.flatMap { app.route(id: $0) }
            VStack(alignment: .leading, spacing: 0) {
                PlaceArtwork(place: place).frame(height: 130).clipped()
                    .allowsHitTesting(false).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    Text(plan?.name ?? (message.placeIDs.count == 1 ? place.name : "Места рядом"))
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(plan.map { "\($0.duration) мин · \($0.distance)" } ?? "\(place.travelMinutes) мин пешком · \(place.distance)")
                        .font(.caption).foregroundStyle(SeruColor.muted)
                    PrimaryAction(title: "На карту", symbol: "map") { app.showResults(placeIDs: message.placeIDs) }
                        .accessibilityIdentifier("chat-show-places")
                }.padding(14)
            }
            .background(SeruColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SeruColor.line.opacity(0.5), lineWidth: 1))
        }
    }

}
