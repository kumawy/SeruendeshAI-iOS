import SwiftUI
import Observation
import OSLog
import QuartzCore

@MainActor @Observable
final class SplashCoordinator {
    private(set) var phase: SplashPhase = .preparing
    private(set) var spiralProgress = 0.0
    private(set) var expansionProgress = 0.0
    private(set) var revealProgress = 0.0
    private(set) var isShortFade = false
    let timing: SplashTiming
    let player: MascotFramePlayer
    let usesMetal: Bool
    private let gate: SplashSessionGate
    private var sequence: Task<Void, Never>?
    private let logger = Logger(subsystem: "kz.seruendesh.frontend", category: "Splash")

    init(timing: SplashTiming = SplashTiming(), gate: SplashSessionGate = .shared,
         player: MascotFramePlayer? = nil) {
        self.timing = timing
        self.gate = gate
        #if DEBUG
        let missing = UserDefaults.standard.bool(forKey: "seru.splash.missingAssets")
        #else
        let missing = false
        #endif
        self.player = player ?? MascotFramePlayer(resourceDirectory: missing ? "MissingSplashFixture" : "SeruSplash")
        usesMetal = SpiralCollapseView.metalIsAvailable()
        if gate.hasStarted { phase = .done; revealProgress = 1 }
    }

    var isComplete: Bool { phase == .done }

    func start(reduceMotion: Bool) {
        guard sequence == nil, !isComplete else { return }
        guard gate.begin() else {
            // Another root may have claimed launch after this object was made.
            phase = .done
            revealProgress = 1
            return
        }
        sequence = Task { [weak self] in
            guard let self else { return }
            do {
                if reduceMotion {
                    try await player.prepare(handoffOnly: true)
                    phase = .wave
                    try await Task.sleep(for: .seconds(timing.reducedMotionHold))
                    try await shortFade()
                } else {
                    try await player.prepare()
                    phase = .wave
                    try await player.play(duration: timing.waveDuration)
                    // play() holds 0053 for its full source interval. Waiting for
                    // a real display refresh makes the shader handoff explicit.
                    try await SplashDisplayRefresh.wait()
                    try Task.checkCancellation()
                    phase = .spiral
                    // The shader authors its own accelerating pull and twist.
                    withAnimation(.linear(duration: timing.spiralDuration)) { spiralProgress = 1 }
                    try await Task.sleep(for: .seconds(timing.spiralDuration))
                    try Task.checkCancellation()
                    phase = .expand
                    withAnimation(.timingCurve(0.30, 0.18, 0.30, 1, duration: timing.expandDuration)) { expansionProgress = 1 }
                    try await Task.sleep(for: .seconds(timing.expandDuration))
                    try await SplashDisplayRefresh.wait()
                    try Task.checkCancellation()
                    phase = .reveal
                    withAnimation(.easeInOut(duration: timing.revealDuration)) { revealProgress = 1 }
                    try await Task.sleep(for: .seconds(timing.revealDuration))
                    try await SplashDisplayRefresh.wait()
                }
                try Task.checkCancellation()
                await finish()
            } catch is CancellationError {
                await player.release()
            } catch {
                logger.error("Splash assets unavailable; revealing existing root: \(String(describing: error), privacy: .public)")
                do { try await shortFade(); await finish() } catch { await player.release() }
            }
        }
    }

    func reduceMotionChanged() {
        guard !isComplete else { return }
        sequence?.cancel()
        sequence = Task { [weak self] in
            guard let self else { return }
            do { try await shortFade(); await finish() } catch { await player.release() }
        }
    }

    func cancel() {
        sequence?.cancel()
        sequence = nil
        gate.complete()
        phase = .done
        revealProgress = 1
        Task { await player.release() }
    }

    private func shortFade() async throws {
        isShortFade = true
        phase = .reveal
        withAnimation(.easeOut(duration: timing.reducedMotionFade)) { revealProgress = 1 }
        try await Task.sleep(for: .seconds(timing.reducedMotionFade))
        try Task.checkCancellation()
    }

    private func finish() async {
        let metrics = await player.metricsSnapshot()
        await player.release()
        gate.complete()
        phase = .done
        revealProgress = 1
        sequence = nil
        logger.notice("Splash completed: frames=\(metrics.framesDisplayed) decoded=\(metrics.decodedFrames) peakCache=\(metrics.peakCachedFrameCount) late=\(metrics.lateFrames) waveSeconds=\(metrics.playbackDurationSeconds) metal=\(self.usesMetal); resources released")
    }
}

@MainActor
private final class SplashDisplayRefresh: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Error>?

    static func wait() async throws {
        let refresh = SplashDisplayRefresh()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                refresh.continuation = continuation
                let link = CADisplayLink(target: refresh, selector: #selector(tick))
                refresh.link = link
                link.add(to: .main, forMode: .common)
            }
        } onCancel: { Task { @MainActor in refresh.complete(CancellationError()) } }
    }

    @objc private func tick() { complete(nil) }
    private func complete(_ error: Error?) {
        link?.invalidate(); link = nil
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
