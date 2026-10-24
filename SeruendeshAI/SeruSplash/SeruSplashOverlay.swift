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
                    let side = min(328, geometry.size.width * 0.82, geometry.size.height * 0.65)
                    Group {
                        if coordinator.usesReducedMotion {
                            Image(uiImage: artwork).resizable().scaledToFit()
                        } else {
                            SeruMascotAnimation(scene: .greeting)
                        }
                    }
                    .frame(width: side, height: side)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(coordinator.usesReducedMotion ? 1 - coordinator.revealProgress : 1)
            .animation(coordinator.usesReducedMotion ? .easeOut(duration: coordinator.fadeDuration) : nil,
                       value: coordinator.revealProgress)
            .animation(.easeOut(duration: coordinator.timing.reducedMotionFade),
                       value: coordinator.usesReducedMotion)
            .mask {
                if coordinator.usesReducedMotion {
                    Rectangle()
                } else {
                    SplashRevealCover(progress: coordinator.revealProgress)
                        .fill(style: FillStyle(eoFill: true))
                        .animation(.easeInOut(duration: coordinator.fadeDuration),
                                   value: coordinator.revealProgress)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Серу")
            .accessibilityIdentifier("seru-splash-overlay")
        }
    }
}

/// Only the launch cover is masked: the real app stays mounted underneath.
/// The transparent circle reaches every corner, in either orientation.
@Animatable
private struct SplashRevealCover: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let radius = (hypot(rect.width, rect.height) / 2 + 1) * min(max(progress, 0), 1)
        var path = Path(rect)
        if radius > 0 {
            path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius,
                                       width: radius * 2, height: radius * 2))
        }
        return path
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
                        .ignoresSafeArea()
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
        // A still is available immediately while the shared bounded player loads
        // the greeting. Playback never delays the coordinator's launch deadline.
        return UIImage(named: "SeruMascot")
    }
}

extension EnvironmentValues {
    @Entry var seruSplashIsPresented = false
}
