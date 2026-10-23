import SwiftUI

struct AppRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.seruSplashIsPresented) private var splashIsPresented
    @State private var presentation: RootPresentation?
    @State private var deferredPresentation: RootPresentation?
    @State private var attachmentLoader = ChatAttachmentLoader()

    var body: some View {
        @Bindable var app = app
        GeometryReader { geometry in
            TabView(selection: $app.tab) {
                Tab(value: AppTab.walk) {
                    WalkView(
                        topClearance: geometry.safeAreaInsets.top + (app.screen == .home ? 64 : 8),
                        mascotActive: presentation == nil && !splashIsPresented
                    )
                } label: {
                    Image(app.tab == .walk ? "NavCompassActive" : "NavCompassInactive")
                        .renderingMode(.original)
                        .accessibilityLabel("Прогулка")
                }
                Tab(value: AppTab.events) {
                    EventsView(mascotActive: presentation == nil && !splashIsPresented,
                               onProfile: { presentation = .profile })
                } label: {
                    Image(app.tab == .events ? "NavTicketActive" : "NavTicketInactive")
                        .renderingMode(.original)
                        .accessibilityLabel("События")
                }
                Tab(value: AppTab.saved) {
                    SavedView(mascotActive: presentation == nil && !splashIsPresented)
                } label: {
                    Image(app.tab == .saved ? "NavHeartActive" : "NavHeartInactive")
                        .renderingMode(.original)
                        .accessibilityLabel("Избранное")
                }
            }
            .tint(SeruColor.action)
            .overlay(alignment: .top) {
                if app.tab == .walk && app.screen == .home {
                    AppBrandHeader(onProfile: { presentation = .profile })
                }
            }
        }
        .background(SeruColor.background.ignoresSafeArea())
        .sheet(item: $presentation) { destination in
            switch destination {
            case .profile: ProfileView()
            case .passwordReset(let token, _): AccountView(resetToken: token).id(destination.id)
            }
        }
        .onOpenURL { url in
            if let token = PasswordResetLink.token(from: url) {
                let destination = RootPresentation.passwordReset(token, UUID())
                if splashIsPresented { deferredPresentation = destination }
                else { presentation = destination }
            }
        }
        .onChange(of: splashIsPresented) { _, isPresented in
            if !isPresented, let destination = deferredPresentation {
                deferredPresentation = nil
                presentation = destination
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    let store = app.account
                    async let account: Void = store.restore()
                    await app.bootstrap()
                    await account
                }
            }
        }
        .onChange(of: app.account.syncError) { _, error in
            if let error { app.toast = error }
        }
        .onChange(of: app.account.error) { _, error in
            if let error { app.toast = error }
        }
        .overlay(alignment: .top) {
            if let toast = app.toast {
                HStack(spacing: 12) {
                    Text(toast).font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if toast == "Место удалено из избранного", app.recentlyRemovedPlace != nil {
                        Button("Отменить") { app.undoSavedRemoval() }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("saved-undo")
                    }
                }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 16)
                    .padding(.top, 66)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: "\(app.toast ?? ""):\(app.recentlyRemovedPlace?.id ?? "")") {
            guard let toast = app.toast else { return }
            AccessibilityNotification.Announcement(toast).post()
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            app.toast = nil
        }
        .animation(SeruMotion.panel(reduceMotion: reduceMotion), value: app.toast != nil)
        .overlay(alignment: .bottom) {
            if let feedback = app.mascotFeedback,
               app.toast == nil, presentation == nil, !splashIsPresented {
                MascotFeedbackBanner(feedback: feedback, isActive: scenePhase == .active)
                    .id(feedback.id)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 88)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .task(id: app.mascotFeedback?.id) {
            guard let feedback = app.mascotFeedback else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            app.dismissMascotFeedback(id: feedback.id)
        }
        .environment(attachmentLoader)
        .task {
            let account = app.account
            async let session: Void = account.restore()
            await app.bootstrap()
            await session
        }
    }
}

private struct MascotFeedbackBanner: View {
    let feedback: MascotFeedback
    let isActive: Bool

    private var scene: SeruMascotScene {
        switch feedback.kind {
        case .saved: .saved
        case .ready: .ready
        case .photoError: .photoError
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            SeruMascotAnimation(scene: scene, isActive: isActive)
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            Text(feedback.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SeruColor.surface, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mascot-feedback-\(scene.rawValue)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview { AppRootView().environment(AppModel()) }

private enum RootPresentation: Identifiable {
    case profile
    case passwordReset(String, UUID)
    var id: String {
        switch self { case .profile: "profile"; case .passwordReset(_, let id): "password-reset-\(id)" }
    }
}
