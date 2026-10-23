#if !SWIFT_PACKAGE
import Foundation
import Testing
@testable import SeruendeshAI

@MainActor @Suite(.serialized)
struct SplashCoordinatorTests {
    @Test func compiledShaderIsActuallyInTheApplicationBundle() {
        #expect(SpiralCollapseView.metalIsAvailable())
    }

    @Test func reduceMotionDecodesOnlyHandoffAndReleasesEverything() async throws {
        var timing = SplashTiming()
        timing.reducedMotionHold = 0.01
        timing.reducedMotionFade = 0.01
        let gate = SplashSessionGate()
        let coordinator = SplashCoordinator(timing: timing, gate: gate)
        coordinator.start(reduceMotion: true)
        try await waitUntilDone(coordinator)
        #expect(gate.hasCompleted)
        #expect(coordinator.player.image == nil)
        let metrics = await coordinator.player.metricsSnapshot()
        #expect(metrics.decodedFrames == 1)
        #expect(metrics.peakCachedFrameCount == 1)
        #expect(metrics.cachedFrameCount == 0)
    }

    @Test func missingBundleSafelyUnblocksTheMountedRoot() async throws {
        var timing = SplashTiming()
        timing.reducedMotionFade = 0.01
        let player = MascotFramePlayer(resourceDirectory: "MissingSplashCoordinatorFixture")
        let coordinator = SplashCoordinator(timing: timing, gate: SplashSessionGate(), player: player)
        coordinator.start(reduceMotion: false)
        try await waitUntilDone(coordinator)
        #expect(coordinator.isShortFade)
        #expect(coordinator.player.image == nil)
    }

    @Test func cancellationCannotRestartSplashInTheSameProcessSession() async throws {
        let gate = SplashSessionGate()
        let first = SplashCoordinator(gate: gate)
        first.start(reduceMotion: false)
        first.cancel()
        try await Task.sleep(for: .milliseconds(50))
        let replacement = SplashCoordinator(gate: gate)
        replacement.start(reduceMotion: false)
        #expect(first.isComplete)
        #expect(first.player.image == nil)
        #expect(replacement.isComplete)
        #expect(replacement.player.image == nil)
        #expect(gate.hasStarted && gate.hasCompleted)
    }

    @Test func overlappingRootCreationCannotLeaveAnUnclaimedOverlay() {
        let gate = SplashSessionGate()
        let first = SplashCoordinator(gate: gate)
        let overlapping = SplashCoordinator(gate: gate)
        first.start(reduceMotion: false)
        overlapping.start(reduceMotion: false)
        #expect(overlapping.isComplete)
        #expect(overlapping.revealProgress == 1)
        first.cancel()
    }

    private func waitUntilDone(_ coordinator: SplashCoordinator) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !coordinator.isComplete && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.isComplete)
    }
}
#endif
