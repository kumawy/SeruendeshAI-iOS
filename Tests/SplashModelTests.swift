import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct SplashModelTests {
    @Test func manifestDecodesBundledContractAndNamesFirstAndHandoffFrames() throws {
        let manifest = try decodeManifest()

        try manifest.validate()
        #expect(try manifest.frameName(at: 0) == "0000.png")
        #expect(try manifest.frameName(at: manifest.handoffFrame) == "0053.png")
    }

    @Test func frameLookupRejectsIndicesOutsideTheSequence() throws {
        let manifest = try decodeManifest()

        #expect(throws: (any Error).self) { try manifest.frameName(at: -1) }
        #expect(throws: (any Error).self) { try manifest.frameName(at: 54) }
    }

    @Test func manifestRejectsUnsafeFramePathsAndFormattingDirectives() throws {
        for pattern in ["../%04d.png", "/frames/%04d.png", "frames/../../%04d.png", "frames/%s.png", "frames/%04d/%04d.png", "frames/%04d.png\0"] {
            var manifest = try decodeManifest()
            manifest.framesPattern = pattern

            #expect(throws: (any Error).self) { try manifest.validate() }
            #expect(throws: (any Error).self) { try manifest.frameName(at: 0) }
        }
    }

    @Test func manifestRejectsMissingTransparencyAndUnintendedLooping() throws {
        var opaque = try decodeManifest()
        opaque.alpha = false
        #expect(throws: (any Error).self) { try opaque.validate() }

        var looping = try decodeManifest()
        looping.loop = true
        #expect(throws: (any Error).self) { try looping.validate() }
    }

    @Test func manifestRejectsUnboundedAndMismatchedFrameMetadata() throws {
        for count in [0, 53, 55, Int.max] {
            var manifest = try decodeManifest()
            manifest.frameCount = count
            #expect(throws: (any Error).self) { try manifest.validate() }
        }

        for rate in [0.0, -30.0, 60.0, Double.infinity, Double.nan] {
            var manifest = try decodeManifest()
            manifest.fps = rate
            #expect(throws: (any Error).self) { try manifest.validate() }
        }

        for size in [0, -768, 767, Int.max] {
            var manifest = try decodeManifest()
            manifest.canvasWidth = size
            #expect(throws: (any Error).self) { try manifest.validate() }
            manifest.canvasWidth = 768
            manifest.canvasHeight = size
            #expect(throws: (any Error).self) { try manifest.validate() }
        }
    }

    @Test func manifestRejectsDurationDisagreementAndInvalidHandoff() throws {
        for duration in [0.0, 1.7, 1.9, Double.infinity, Double.nan] {
            var manifest = try decodeManifest()
            manifest.durationSeconds = duration
            #expect(throws: (any Error).self) { try manifest.validate() }
        }

        for (start, handoff) in [(1, 53), (-1, 53), (0, 52), (0, 54), (0, -1)] {
            var manifest = try decodeManifest()
            manifest.startIndex = start
            manifest.handoffFrame = handoff
            #expect(throws: (any Error).self) { try manifest.validate() }
        }
    }

    @Test func totalDurationTracksTheFourFullMotionPhases() {
        var timing = SplashTiming()
        #expect(abs(timing.totalDuration - 3.64) < 0.000_001)

        timing.waveDuration = 2
        timing.spiralDuration = 1
        timing.expandDuration = 0.5
        timing.revealDuration = 0.25
        timing.reducedMotionHold = 10
        timing.reducedMotionFade = 10
        #expect(timing.totalDuration == 3.75)
    }

    @Test func coveringRadiusReachesFarthestCornerAcrossOrientationAndOffCenter() {
        #expect(SplashGeometry.coveringRadius(width: 300, height: 400, centerX: 150, centerY: 200) == 250)
        #expect(SplashGeometry.coveringRadius(width: 400, height: 300, centerX: 200, centerY: 150) == 250)
        #expect(SplashGeometry.coveringRadius(width: 300, height: 400, centerX: 0, centerY: 0) == 500)
        let outsideCenter = SplashGeometry.coveringRadius(width: 300, height: 400, centerX: -100, centerY: 200)
        #expect(abs(outsideCenter - 447.213_595_499_957_93) < 0.000_001)
    }

    @Test @MainActor func sessionGateClaimsOnlyOneLaunchAndCompletionIsIdempotent() {
        let gate = SplashSessionGate()
        #expect(!gate.hasStarted)
        #expect(!gate.hasCompleted)
        #expect(gate.begin())
        #expect(!gate.begin())

        gate.complete()
        gate.complete()
        #expect(gate.hasStarted)
        #expect(gate.hasCompleted)
        #expect(!gate.begin())
    }

    @Test @MainActor func interruptedLaunchCannotReplayInTheSameSession() {
        let gate = SplashSessionGate()
        #expect(gate.begin())
        // A disappearing root cancels its task before completion. The claim survives it.
        #expect(!gate.hasCompleted)
        #expect(!gate.begin())
    }

    private func decodeManifest() throws -> SplashFrameManifest {
        let json = """
        {
          "fps": 30,
          "frameCount": 54,
          "durationSeconds": 1.8,
          "canvasWidth": 768,
          "canvasHeight": 768,
          "framesPattern": "frames/%04d.png",
          "startIndex": 0,
          "loop": false,
          "alpha": true,
          "handoffFrame": 53,
          "renderer": "Remotion"
        }
        """
        return try JSONDecoder().decode(SplashFrameManifest.self, from: Data(json.utf8))
    }
}
