#if !SWIFT_PACKAGE
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SeruendeshAI

@MainActor
@Suite("Bundled mascot frame playback", .serialized)
struct MascotFramePlayerTests {
    // A missing frame, stale source manifest, or lost PNG alpha breaks this contract.
    @Test("All 54 original transparent frames are bundled and decoded at their source size")
    func originalFrameResources() async throws {
        let player = MascotFramePlayer()
        try await player.prepare()
        let manifest = try #require(player.manifest)
        #expect(manifest.frameCount == 54)
        #expect(manifest.fps == 30)
        #expect(manifest.handoffFrame == 53)
        #expect(player.frameIndex == 0)
        let image = try #require(player.image)
        #expect(image.width == 768)
        #expect(image.height == 768)
        #expect(image.alphaInfo == .premultipliedLast)
        for index in 0..<54 {
            let name = String(format: "%04d", index)
            let url = try #require(Bundle.main.url(
                forResource: name, withExtension: "png", subdirectory: "SeruSplash/frames"
            ))
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect(properties[kCGImagePropertyPixelWidth] as? Int == 768)
            #expect(properties[kCGImagePropertyPixelHeight] as? Int == 768)
            #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
        }
        await player.release()
    }

    // Skipping frames, dropping frame 0053's dwell, or keeping all decoded PNGs fails here.
    @Test("Plays every frame once, retains final pose, and releases its bounded decode cache")
    func completePlaybackAndRelease() async throws {
        let player = MascotFramePlayer()
        try await player.prepare()
        let prepared = await player.metricsSnapshot()
        #expect(prepared.cachedFrameCount == 5)
        let clock = ContinuousClock()
        let start = clock.now
        try await player.play()
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .seconds(1.8))
        #expect(player.frameIndex == 53)
        #expect(player.image != nil)
        let finished = await player.metricsSnapshot()
        #expect(finished.framesDisplayed == 54)
        #expect(finished.decodedFrames == 54)
        #expect(finished.peakCachedFrameCount <= 5)
        #expect(finished.cachedFrameCount == 0)
        await player.release()
        #expect(player.image == nil)
        #expect(await player.metricsSnapshot().cachedFrameCount == 0)
    }

    // Ignoring the configured wave duration would keep this run at the original 1.8 seconds.
    @Test("An explicit duration retimes all original frames and preserves the final handoff")
    func configuredPlaybackDuration() async throws {
        let player = MascotFramePlayer()
        try await player.prepare()
        try await player.play(duration: 0.27)
        let finished = await player.metricsSnapshot()
        #expect(finished.framesDisplayed == 54)
        #expect(finished.decodedFrames == 54)
        #expect(player.frameIndex == 53)
        #expect(player.image != nil)
        #expect(finished.playbackDurationSeconds >= 0.27)
        #expect(finished.playbackDurationSeconds < 1.8)
        #expect(finished.peakCachedFrameCount <= 5)
        #expect(finished.cachedFrameCount == 0)
        await player.release()
    }

    // Non-finite input must not reach Duration conversion or consume the one-shot playback claim.
    @Test("Invalid configured durations are rejected before any frame is played")
    func invalidConfiguredPlaybackDuration() async throws {
        let player = MascotFramePlayer()
        try await player.prepare()
        for invalid in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
            do {
                try await player.play(duration: invalid)
                Issue.record("A playback duration must be positive and finite")
            } catch MascotFramePlayerError.invalidDuration {
                #expect(player.frameIndex == 0)
                #expect(player.image != nil)
                #expect(await player.metricsSnapshot().framesDisplayed == 0)
            }
        }
        await player.release()
    }

    // A typo in bundle integration must fail preparation instead of producing a blank splash.
    @Test("Missing resource directory produces a readable preparation error")
    func missingResource() async {
        let player = MascotFramePlayer(resourceDirectory: "MissingSeruSplashFixture")
        do {
            try await player.prepare()
            Issue.record("Preparation must reject a missing manifest")
        } catch {
            #expect(error.localizedDescription.contains("manifest.json"))
            #expect(player.image == nil)
            #expect(await player.metricsSnapshot().cachedFrameCount == 0)
        }
    }

    // Background interruption must stop playback and release image memory.
    @Test("Cancellation releases every retained frame")
    func cancellation() async throws {
        let player = MascotFramePlayer()
        try await player.prepare()
        let playback = Task { try await player.play() }
        try await Task.sleep(for: .milliseconds(80))
        playback.cancel()
        do {
            try await playback.value
            Issue.record("Cancelled playback must throw CancellationError")
        } catch is CancellationError {
            #expect(player.image == nil)
            #expect(await player.metricsSnapshot().cachedFrameCount == 0)
        }
    }
}
#endif
