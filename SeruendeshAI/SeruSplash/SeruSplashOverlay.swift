import SwiftUI
import UIKit

struct SeruSplashOverlay: View {
    let coordinator: SplashCoordinator
    let artwork: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SeruColor.background.ignoresSafeArea()
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(236, geometry.size.width * 0.58),
                               height: min(236, geometry.size.height * 0.6))
                        .scaleEffect(coordinator.usesReducedMotion || coordinator.phase != .preparing ? 1 : 0.985)
                        .animation(coordinator.usesReducedMotion ? nil : .easeOut(duration: 0.26),
                                   value: coordinator.phase == .preparing)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(1 - coordinator.revealProgress)
            .animation(.easeOut(duration: coordinator.fadeDuration), value: coordinator.revealProgress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Серу")
            .accessibilityIdentifier("seru-splash-overlay")
        }
    }
}

/// Launch presentation is an overlay on one continuously mounted root, so a
/// quick handoff keeps navigation, incoming links, and bootstrap tasks intact.
struct SeruSplashContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = SplashCoordinator()
    @State private var artwork = SplashArtwork.load()
    @ViewBuilder let content: Content

    var body: some View {
        content
            .environment(\.seruSplashIsPresented, !coordinator.isComplete)
            .allowsHitTesting(coordinator.isComplete)
            .accessibilityHidden(!coordinator.isComplete)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("seru-main-content")
            .overlay {
                if !coordinator.isComplete {
                    SeruSplashOverlay(coordinator: coordinator, artwork: artwork)
                }
            }
            .background(SeruColor.background.ignoresSafeArea())
            .task {
                #if DEBUG
                let forced = UserDefaults.standard.bool(forKey: "seru.splash.reduceMotion")
                #else
                let forced = false
                #endif
                coordinator.start(reduceMotion: reduceMotion || forced, artworkAvailable: artwork != nil)
            }
            .onChange(of: reduceMotion) { _, enabled in
                if enabled { coordinator.reduceMotionChanged() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { coordinator.cancel() }
            }
            .onChange(of: coordinator.isComplete) { _, complete in
                if complete { artwork = nil }
            }
            .onDisappear { coordinator.cancel() }
    }
}

@MainActor
private enum SplashArtwork {
    static func load() -> UIImage? {
        guard !SplashSessionGate.shared.hasStarted else { return nil }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "seru.splash.missingAssets") { return nil }
        #endif
        // The asset catalog caches one existing image. No PNG sequence, shader,
        // frame predecode, or asynchronous resource preparation delays launch.
        return UIImage(named: "SeruMascot")
    }
}

extension EnvironmentValues {
    @Entry var seruSplashIsPresented = false
}
