import Foundation
import Observation

enum SplashPhase: String, Sendable {
    case preparing, greeting, reveal, done
}

struct SplashTiming: Sendable {
    var greetingDuration = 1.8
    var revealDuration = 0.25
    var reducedMotionHold = 0.02
    var reducedMotionFade = 0.12

    var totalDuration: Double { greetingDuration + revealDuration }
}

@MainActor
final class SplashSessionGate {
    static let shared = SplashSessionGate()
    private(set) var hasStarted = false
    private(set) var hasCompleted = false

    /// The claim survives interruption or a recreated root during this process.
    func begin() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }

    func complete() {
        hasStarted = true
        hasCompleted = true
    }
}

/// Owns presentation timing only. The real root mounts immediately and does not
/// depend on artwork decoding, account restoration, or backend readiness here.
@MainActor @Observable
final class SplashCoordinator {
    private(set) var phase: SplashPhase = .preparing
    private(set) var usesReducedMotion = false
    let timing: SplashTiming
    @ObservationIgnored private let gate: SplashSessionGate
    @ObservationIgnored private var sequence: Task<Void, Never>?

    init(timing: SplashTiming = SplashTiming(), gate: SplashSessionGate = .shared) {
        self.timing = timing
        self.gate = gate
        if gate.hasStarted { phase = .done }
    }

    var isComplete: Bool { phase == .done }
    var revealProgress: Double { phase == .reveal || isComplete ? 1 : 0 }
    var fadeDuration: Double { usesReducedMotion ? timing.reducedMotionFade : timing.revealDuration }

    func start(reduceMotion: Bool, artworkAvailable: Bool = true) {
        guard sequence == nil, !isComplete else { return }
        guard gate.begin() else {
            phase = .done
            return
        }
        guard artworkAvailable else {
            finish()
            return
        }
        usesReducedMotion = reduceMotion
        phase = .greeting
        let hold = reduceMotion ? timing.reducedMotionHold : timing.greetingDuration
        let started = ContinuousClock.now
        let greetingDeadline = started.advanced(by: .seconds(hold))
        let completionDeadline = greetingDeadline.advanced(by: .seconds(fadeDuration))
        sequence = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(until: greetingDeadline, clock: .continuous)
                try await reveal(until: completionDeadline)
                finish()
            } catch is CancellationError {
                // The owner of the interruption chooses either a short fade or
                // immediate completion; a cancelled task never changes its state.
            } catch {
                finish()
            }
        }
    }

    func reduceMotionChanged() {
        guard sequence != nil, !isComplete else { return }
        sequence?.cancel()
        usesReducedMotion = true
        phase = .reveal
        sequence = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(timing.reducedMotionFade))
                try Task.checkCancellation()
                finish()
            } catch is CancellationError {
            } catch {
                finish()
            }
        }
    }

    /// Backgrounding or removing this presentation unblocks the mounted root.
    /// Foregrounding preserves its navigation and never replays the greeting.
    func cancel() {
        sequence?.cancel()
        finish()
    }

    private func reveal(until deadline: ContinuousClock.Instant) async throws {
        try Task.checkCancellation()
        phase = .reveal
        try await Task.sleep(until: deadline, clock: .continuous)
        try Task.checkCancellation()
    }

    private func finish() {
        gate.complete()
        phase = .done
        sequence = nil
    }
}
