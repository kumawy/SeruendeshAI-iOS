import SwiftUI

struct SplashTransitionView: View, Animatable {
    let phase: SplashPhase
    let size: CGSize
    let center: CGPoint
    let background: Color
    let fill: Color
    let dotDiameter: Double
    var spiralProgress: Double
    var expansionProgress: Double
    var revealProgress: Double
    let shortFade: Bool

    nonisolated var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { .init(spiralProgress, .init(expansionProgress, revealProgress)) }
        set {
            spiralProgress = newValue.first
            expansionProgress = newValue.second.first
            revealProgress = newValue.second.second
        }
    }

    private var coveringRadius: Double {
        SplashGeometry.coveringRadius(width: size.width, height: size.height,
                                      centerX: center.x, centerY: center.y) + 2
    }

    var body: some View {
        ZStack {
            if phase == .reveal && !shortFade {
                fill.mask {
                    if revealProgress <= 0 {
                        Rectangle().fill(.white)
                    } else {
                        // Transparent center, opaque exterior: the overlay itself
                        // recedes, leaving the real mounted root underneath.
                        RadialGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.82),
                            .init(color: .white, location: 1)
                        ], center: UnitPoint(x: center.x / max(1, size.width), y: center.y / max(1, size.height)),
                        startRadius: 0, endRadius: max(0.1, coveringRadius / 0.82 * revealProgress))
                    }
                }
            } else {
                background.opacity(shortFade ? 1 - revealProgress : 1)
                if !shortFade && [.spiral, .expand].contains(phase) {
                    let p = phase == .expand ? expansionProgress : 0
                    let radius = dotDiameter / 2 + (coveringRadius - dotDiameter / 2) * p
                    Circle().fill(fill)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                        .opacity(phase == .expand ? 1 : dotOpacity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private var dotOpacity: Double {
        let p = min(1, max(0, (spiralProgress - 0.90) / 0.09))
        return p * p * (3 - 2 * p)
    }
}
