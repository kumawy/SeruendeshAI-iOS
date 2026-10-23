import Foundation

enum SplashPhase: String, Sendable {
    case preparing, wave, spiral, expand, reveal, done
}

struct SplashTiming: Sendable {
    var waveDuration = 1.8
    var spiralDuration = 0.64
    var expandDuration = 0.6
    var revealDuration = 0.6
    var reducedMotionHold = 0.1
    var reducedMotionFade = 0.3
    var mascotContentHeight = 270.0
    var dotDiameter = 12.0
    var spiralStrength = 4.2
    var revealBlur = 14.0

    var totalDuration: Double {
        waveDuration + spiralDuration + expandDuration + revealDuration
    }
}

struct SplashFrameManifest: Codable, Sendable {
    var fps: Double
    var frameCount: Int
    var durationSeconds: Double
    var canvasWidth: Int
    var canvasHeight: Int
    var framesPattern: String
    var startIndex: Int
    var loop: Bool
    var alpha: Bool
    var handoffFrame: Int

    enum ValidationError: Error {
        case unsupportedFrameRate
        case unsupportedFrameCount
        case unsupportedCanvas
        case inconsistentDuration
        case unsafeFramesPattern
        case invalidStartOrHandoff
        case requiresTransparentNonLoopingSequence
        case frameIndexOutOfRange
    }

    /// Accept only the authored sequence. A malformed manifest must fall back to Home,
    /// rather than allocating arbitrary image sizes or resolving arbitrary bundle paths.
    func validate() throws {
        guard fps.isFinite, fps == 30 else {
            throw ValidationError.unsupportedFrameRate
        }
        guard frameCount == 54 else {
            throw ValidationError.unsupportedFrameCount
        }
        guard canvasWidth == 768, canvasHeight == 768 else {
            throw ValidationError.unsupportedCanvas
        }
        guard durationSeconds.isFinite,
              abs(durationSeconds - Double(frameCount) / fps) < 0.000_001 else {
            throw ValidationError.inconsistentDuration
        }
        // Whitelisting the single supported format also excludes traversal, absolute
        // paths, null bytes, and unsafe printf directives before frame lookup.
        guard framesPattern == "frames/%04d.png" else {
            throw ValidationError.unsafeFramesPattern
        }
        guard startIndex == 0, handoffFrame == frameCount - 1 else {
            throw ValidationError.invalidStartOrHandoff
        }
        guard alpha, !loop else {
            throw ValidationError.requiresTransparentNonLoopingSequence
        }
    }

    func frameName(at index: Int) throws -> String {
        try validate()
        guard (startIndex..<frameCount).contains(index) else {
            throw ValidationError.frameIndexOutOfRange
        }
        return String(format: "%04d.png", index)
    }
}

enum SplashGeometry {
    static func coveringRadius(width: Double, height: Double, centerX: Double, centerY: Double) -> Double {
        let farthestX = max(abs(centerX), abs(width - centerX))
        let farthestY = max(abs(centerY), abs(height - centerY))
        return hypot(farthestX, farthestY)
    }
}

@MainActor
final class SplashSessionGate {
    static let shared = SplashSessionGate()
    private(set) var hasStarted = false
    private(set) var hasCompleted = false

    /// The claim survives cancellation or a recreated root during the same process.
    func begin() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }

    func complete() {
        hasCompleted = true
    }
}
