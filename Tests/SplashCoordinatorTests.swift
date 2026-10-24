import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@MainActor @Suite(.serialized)
struct SplashCoordinatorTests {
    // The full wave remains visible, with no spiral or network wait after it.
    @Test func ordinaryLaunchKeepsTheGreetingVisibleThenReleasesTheMountedRoot() async throws {
        let gate = SplashSessionGate()
        let coordinator = SplashCoordinator(gate: gate)
        coordinator.start(reduceMotion: false)
        #expect(coordinator.phase == .greeting)
        #expect(gate.hasStarted && !gate.hasCompleted)

        try await Task.sleep(for: .milliseconds(1_550))
        #expect(coordinator.phase == .greeting)
        try await waitUntilDone(coordinator, timeout: 1.15)
        #expect(gate.hasCompleted)
        #expect(coordinator.revealProgress == 1)
    }

    @Test func reducedMotionReleasesTheRootWithoutAFullGreetingHold() async throws {
        let coordinator = SplashCoordinator(gate: SplashSessionGate())
        coordinator.start(reduceMotion: true)
        #expect(coordinator.usesReducedMotion)

        try await waitUntilDone(coordinator, timeout: 0.25)
    }

    @Test func missingArtworkReleasesTheRootImmediately() {
        let gate = SplashSessionGate()
        let coordinator = SplashCoordinator(gate: gate)
        coordinator.start(reduceMotion: false, artworkAvailable: false)
        #expect(coordinator.isComplete)
        #expect(coordinator.revealProgress == 1)
        #expect(gate.hasStarted && gate.hasCompleted)
    }

    @Test func enablingReducedMotionInterruptsTheGreetingWithAShortFade() async throws {
        var timing = SplashTiming()
        timing.greetingDuration = 5
        let coordinator = SplashCoordinator(timing: timing, gate: SplashSessionGate())
        coordinator.start(reduceMotion: false)
        coordinator.reduceMotionChanged()
        #expect(coordinator.usesReducedMotion)
        #expect(coordinator.phase == .reveal)

        try await waitUntilDone(coordinator, timeout: 0.25)
    }

    @Test func cancellationCannotRestartSplashInTheSameProcessSession() async throws {
        let gate = SplashSessionGate()
        let first = SplashCoordinator(gate: gate)
        first.start(reduceMotion: false)
        first.cancel()
        let replacement = SplashCoordinator(gate: gate)
        replacement.start(reduceMotion: false)
        #expect(first.isComplete)
        #expect(replacement.isComplete)
        #expect(gate.hasStarted && gate.hasCompleted)
        // A cancelled sleep must not later put the old root back into its reveal phase.
        try await Task.sleep(for: .milliseconds(30))
        #expect(first.phase == .done)
    }

    @Test func cancellingBeforePresentationAlsoPreventsReplay() {
        let gate = SplashSessionGate()
        let first = SplashCoordinator(gate: gate)
        first.cancel()
        let replacement = SplashCoordinator(gate: gate)
        replacement.start(reduceMotion: false)
        #expect(replacement.isComplete)
    }

    @Test func changingReduceMotionBeforeStartDoesNotLaunchAnUnclaimedSequence() {
        let gate = SplashSessionGate()
        let coordinator = SplashCoordinator(gate: gate)
        coordinator.reduceMotionChanged()
        #expect(coordinator.phase == .preparing)
        #expect(!gate.hasStarted)
        coordinator.start(reduceMotion: true)
        #expect(gate.hasStarted)
        coordinator.cancel()
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

    @Test func repeatedStartDoesNotExtendTheGreetingDeadline() async throws {
        var timing = SplashTiming()
        timing.greetingDuration = 0.08
        timing.revealDuration = 0.02
        let coordinator = SplashCoordinator(timing: timing, gate: SplashSessionGate())
        coordinator.start(reduceMotion: false)
        try await Task.sleep(for: .milliseconds(60))
        coordinator.start(reduceMotion: false)
        try await waitUntilDone(coordinator, timeout: 0.08)
    }

    private func waitUntilDone(_ coordinator: SplashCoordinator, timeout: Double) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !coordinator.isComplete && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(coordinator.isComplete)
    }
}
