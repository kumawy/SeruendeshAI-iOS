import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct SplashModelTests {
    @Test func launchAllowsTheFullMascotWaveBeforeADirectFade() {
        let timing = SplashTiming()
        #expect((1.8...2.0).contains(timing.greetingDuration))
        #expect((2.0...2.3).contains(timing.totalDuration))
    }

    @Test func reducedMotionCompletesWithinAQuarterSecondAndBeforeFullMotion() {
        let timing = SplashTiming()
        let reducedDuration = timing.reducedMotionHold + timing.reducedMotionFade
        #expect(reducedDuration <= 0.25)
        #expect(reducedDuration < timing.totalDuration)
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
        #expect(!gate.hasCompleted)
        #expect(!gate.begin())
    }
}
