import SwiftUI

struct SeruSplashOverlay: View {
    let coordinator: SplashCoordinator
    let safeArea: EdgeInsets
    let dark: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: (safeArea.leading + size.width - safeArea.trailing) / 2,
                                 y: (safeArea.top + size.height - safeArea.bottom) / 2)
            let timing = coordinator.timing
            let available = max(100, size.height - safeArea.top - safeArea.bottom)
            // Content occupies y=59…705 in the authored 768px padded canvas.
            let side = min(timing.mascotContentHeight, available * 0.52) / (646.0 / 768.0)
            ZStack {
                SplashTransitionView(phase: coordinator.phase, size: size, center: center,
                                     background: Color(hex: dark ? "101010" : "F5F5F5"),
                                     fill: Color(hex: dark ? "263A31" : "174B3E"),
                                     dotDiameter: timing.dotDiameter,
                                     spiralProgress: coordinator.spiralProgress,
                                     expansionProgress: coordinator.expansionProgress,
                                     revealProgress: coordinator.revealProgress,
                                     shortFade: coordinator.isShortFade)
                if ([.preparing, .wave, .spiral].contains(coordinator.phase) || coordinator.isShortFade), let image = coordinator.player.image {
                    SpiralCollapseView(image: image, progress: coordinator.spiralProgress,
                                       side: side, strength: timing.spiralStrength, usesMetal: coordinator.usesMetal)
                        .opacity(coordinator.isShortFade ? 1 - coordinator.revealProgress : 1)
                        .position(center)
                }
                #if DEBUG
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Состояние заставки")
                    .accessibilityValue(coordinator.phase.rawValue)
                    .accessibilityIdentifier("seru-splash-phase")
                #endif
            }
            .contentShape(Rectangle())
            .accessibilityIdentifier("seru-splash-overlay")
        }
    }
}

/// Owns only launch presentation. The existing content stays at the same tree
/// position for the entire process, retaining navigation and async bootstrap.
struct SeruSplashContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coordinator = SplashCoordinator()
    @State private var launchIsDark: Bool?
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            content
                .environment(\.seruSplashIsPresented, !coordinator.isComplete)
                .blur(radius: coordinator.isComplete ? 0 : (1 - coordinator.revealProgress) * coordinator.timing.revealBlur)
                .opacity(coordinator.isComplete ? 1 : 0.88 + 0.12 * coordinator.revealProgress)
                .allowsHitTesting(coordinator.isComplete)
                .accessibilityHidden(!coordinator.isComplete)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("seru-main-content")
                .overlay {
                    if !coordinator.isComplete {
                        SeruSplashOverlay(coordinator: coordinator, safeArea: geometry.safeAreaInsets,
                                          dark: launchIsDark ?? (colorScheme == .dark))
                            .ignoresSafeArea()
                    }
                }
        }
        .background(SeruColor.background.ignoresSafeArea())
        .task {
            launchIsDark = colorScheme == .dark
            #if DEBUG
            let forced = UserDefaults.standard.bool(forKey: "seru.splash.reduceMotion")
            #else
            let forced = false
            #endif
            coordinator.start(reduceMotion: reduceMotion || forced)
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { coordinator.reduceMotionChanged() } }
        .onDisappear { coordinator.cancel() }
    }
}

extension EnvironmentValues {
    @Entry var seruSplashIsPresented = false
}
