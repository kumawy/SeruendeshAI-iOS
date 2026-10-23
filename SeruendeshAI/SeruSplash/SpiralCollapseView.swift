import SwiftUI
import Metal

struct SpiralCollapseView: View, Animatable {
    let image: CGImage
    var progress: Double
    let side: CGFloat
    let strength: Double
    let usesMetal: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Group {
            if usesMetal {
                Image(decorative: image, scale: 1)
                    .resizable().interpolation(.high)
                    .frame(width: side, height: side)
                    .layerEffect(ShaderLibrary.seruSpiralCollapse(
                        .float2(Float(side), Float(side)), .float(Float(progress)), .float(Float(strength))),
                        maxSampleOffset: CGSize(width: side, height: side), isEnabled: progress > 0)
            } else {
                SpiralCanvasFallback(image: image, progress: progress, strength: strength)
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }

    static func metalIsAvailable() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeDefaultLibrary(bundle: .main) else { return false }
        return library.functionNames.contains("seruSpiralCollapse")
    }
}

/// Missing-Metal fallback: independent concentric slices follow the same radial
/// twist. It approximates the continuous shader with 40 annuli, not one rotation.
private struct SpiralCanvasFallback: View {
    let image: CGImage
    let progress: Double
    let strength: Double

    var body: some View {
        Canvas { context, size in
            let picture = context.resolve(Image(decorative: image, scale: 1))
            let p = min(1, max(0, progress))
            guard p < 1 else { return }
            if p == 0 { context.draw(picture, in: CGRect(origin: .zero, size: size)); return }
            let radius = hypot(size.width, size.height) / 2
            let scale = max(0.002, 1 - pow(p, 2.4))
            let fadeProgress = min(1, max(0, (p - 0.92) / 0.08))
            let fade = 1 - fadeProgress * fadeProgress * (3 - 2 * fadeProgress)
            for index in 0..<40 {
                let inner = radius * Double(index) / 40
                let outer = radius * Double(index + 1) / 40 + 0.6
                let normalized = (inner + outer) / min(size.width, size.height)
                let angle = -strength * p * p * (0.12 + 0.88 * exp(-1.8 * normalized * normalized))
                var slice = context
                slice.translateBy(x: size.width / 2, y: size.height / 2)
                slice.scaleBy(x: scale, y: scale)
                slice.rotate(by: .radians(angle))
                var annulus = Path(ellipseIn: CGRect(x: -outer, y: -outer, width: 2 * outer, height: 2 * outer))
                annulus.addEllipse(in: CGRect(x: -inner, y: -inner, width: 2 * inner, height: 2 * inner))
                slice.clip(to: annulus, style: FillStyle(eoFill: true))
                slice.opacity = fade
                slice.draw(picture, in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                              width: size.width, height: size.height))
            }
        }
    }
}
