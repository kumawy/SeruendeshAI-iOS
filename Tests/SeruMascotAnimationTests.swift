#if !SWIFT_PACKAGE || SERU_MOTION_HARNESS
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SeruendeshAI

@Suite("Shared mascot catalog and bounded decoding", .serialized)
struct SeruMascotAnimationTests {
    // Repeating a one-shot reaction would replay success every time the view becomes active.
    @Test("Only reactions and the greeting stop at their settled pose")
    func scenePlaybackPolicies() {
        #expect(!SeruMascotScene.greeting.loops)
        #expect(!SeruMascotScene.saved.loops)
        #expect(!SeruMascotScene.ready.loops)
        #expect(SeruMascotScene.calendarEmpty.loops)
        #expect(SeruMascotScene.photoError.loops)
        #expect(SeruMascotScene.allCases.count == 14)
    }

    // ImageIO must return a fully composited frame when APNG stores a small changed rectangle.
    @Test("APNG delta frames retain earlier pixels and transparent borders")
    func compositedAPNG() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SeruMascotFrameStore()
        let manifest = try await store.prepare(directory: directory, loops: true)
        #expect(manifest.frameCount == 3)
        let first = try await store.frame(at: 0)
        let second = try await store.frame(at: 1)
        let third = try await store.frame(at: 2)
        #expect(pixel(first, x: 3, y: 3) == [255, 0, 0, 255])
        #expect(pixel(second, x: 3, y: 3) == [255, 0, 0, 255])
        #expect(pixel(second, x: 6, y: 6) == [0, 255, 0, 255])
        #expect(pixel(third, x: 2, y: 2) == [0, 0, 128, 128])
        #expect(pixel(third, x: 6, y: 6) == [0, 0, 0, 0])
        #expect(first.alphaInfo == .premultipliedLast)
        await store.clear()
        #expect(await store.snapshot().cachedFrameCount == 0)
    }

    // A source/count mismatch must fail preparation rather than indexing past ImageIO's frames.
    @Test("Rejects stale APNG manifests and unsafe PNG patterns")
    func invalidResources() async throws {
        let directory = try fixtureDirectory(frameCount: 4)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SeruMascotFrameStore()
        await #expect(throws: SeruMascotFrameError.self) {
            try await store.prepare(directory: directory, loops: true)
        }
        let unsafe = Data(#"{"fps":24,"frameCount":3,"framesPattern":"../%s.png"}"#.utf8)
        #expect(throws: SeruMascotFrameError.self) {
            try JSONDecoder().decode(SeruMascotManifest.self, from: unsafe).validate()
        }
    }

    // Crossing the last-to-first boundary must not retain a complete decoded sequence.
    @Test("Legacy PNG sequences keep a five-frame rolling window across repeated loops")
    func boundedPNGWindow() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("animation.png"))
        let frames = directory.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let source = try #require(CGImageSourceCreateWithData(Self.apngData as CFData, nil))
        for index in 0..<12 {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index % 3, nil))
            let destination = try #require(CGImageDestinationCreateWithURL(
                frames.appendingPathComponent(String(format: "frame_%04d.png", index)) as CFURL,
                "public.png" as CFString, 1, nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
        try Data(#"{"fps":24,"frameCount":12,"width":8,"height":8}"#.utf8)
            .write(to: directory.appendingPathComponent("manifest.json"))
        let store = SeruMascotFrameStore()
        _ = try await store.prepare(directory: directory, loops: true)
        for tick in 0..<36 {
            _ = try await store.frame(at: tick % 12)
            try await store.prefetch(from: tick % 12)
            #expect(await store.snapshot().cachedFrameCount <= 5)
        }
        #expect(await store.snapshot().peakCachedFrameCount == 5)
        #expect(await store.snapshot().decodedFrames >= 36)
        await store.clear()
        #expect(await store.snapshot().cachedFrameCount == 0)
    }

    // A corrupted animation must retain a valid poster instead of leaving the state blank.
    @MainActor
    @Test("Broken animation falls back to its poster and a one-shot does not restart on reactivation")
    func fallbackAndOneShot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try fixtureDirectory(at: root.appendingPathComponent("SeruMotion/saved"))
        let player = SeruMascotFramePlayer(resourceRoot: root)
        await player.display(scene: .saved, mode: .animate)
        #expect(player.frameIndex == 2)
        #expect(player.image != nil)
        await player.display(scene: .saved, mode: .inactive)
        await player.display(scene: .saved, mode: .animate)
        #expect(player.frameIndex == 2)
        let broken = SeruMascotFramePlayer(resourceRoot: root)
        try Data("not a PNG".utf8).write(to: directory.appendingPathComponent("animation.png"))
        await broken.display(scene: .saved, mode: .animate)
        #expect(broken.image != nil)
        #expect(broken.frameIndex == 0)
    }

    // A cancelled loop or an older scene task must never overwrite a newer still.
    @MainActor
    @Test("Stopping or replacing a loop retains the newest scene")
    func cancellationAndReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixtureDirectory(at: root.appendingPathComponent("SeruMotion/thinking"))
        _ = try fixtureDirectory(at: root.appendingPathComponent("SeruMotion/ready"))
        let player = SeruMascotFramePlayer(resourceRoot: root)
        let loop = Task { await player.display(scene: .thinking, mode: .animate) }
        try await Task.sleep(for: .milliseconds(40))
        await player.display(scene: .ready, mode: .poster)
        let newest = try #require(player.image)
        await loop.value
        #expect(player.image === newest)
        let secondLoop = Task { await player.display(scene: .thinking, mode: .animate) }
        try await Task.sleep(for: .milliseconds(40))
        secondLoop.cancel()
        await secondLoop.value
        #expect(player.image != nil)
        let retained = player.image
        await player.display(scene: .thinking, mode: .inactive)
        #expect(player.image === retained)
    }

    #if !SERU_MOTION_HARNESS
    // A missing folder reference or stale scene export must fail on the real app bundle.
    @Test("Every scene has bundled native frames and a poster")
    func bundledScenes() async throws {
        let root = try #require(Bundle.main.resourceURL)
        for scene in SeruMascotScene.allCases {
            let directory = root.appendingPathComponent("SeruMotion/\(scene.rawValue)")
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("poster.png").path))
            let store = SeruMascotFrameStore()
            let manifest = try await store.prepare(directory: directory, loops: scene.loops)
            #expect(manifest.frameCount > 1)
            let image = try await store.frame(at: manifest.frameCount - 1)
            #expect(image.alphaInfo == .premultipliedLast)
            #expect(await store.snapshot().peakCachedFrameCount <= 5)
            await store.clear()
        }
    }
    #endif

    private func fixtureDirectory(at requested: URL? = nil, frameCount: Int = 3) throws -> URL {
        let directory = requested ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.apngData.write(to: directory.appendingPathComponent("animation.png"))
        let source = CGImageSourceCreateWithData(Self.apngData as CFData, nil)!
        let destination = CGImageDestinationCreateWithURL(
            directory.appendingPathComponent("poster.png") as CFURL, "public.png" as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, CGImageSourceCreateImageAtIndex(source, 0, nil)!, nil)
        _ = CGImageDestinationFinalize(destination)
        let manifest = "{\"fps\":60,\"frameCount\":\(frameCount),\"width\":8,\"height\":8}"
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let start = y * image.bytesPerRow + x * 4
        return Array(data[start..<(start + 4)])
    }

    private static let apngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACGFjVEwAAAADAAAAAM7tusAAAAAaZmNUTAAAAAAAAAAIAAAACAAAAAAAAAAAABED6AAAKn2GwAAAABxJREFUeJxjYKAUMMIY/8EIRQIsx0TIBMoVUA4Ae9UCCHSACJIAAAAaZmNUTAAAAAEAAAACAAAAAgAAAAUAAAAFABED6AAAiHuJkwAAABlmZEFUAAAAAnicY2T4z/CfgYGBgQlEgDAAHhgCAkW9OI4AAAAaZmNUTAAAAAMAAAAGAAAABgAAAAEAAAABABED6AAAQm9lagAAAB9mZEFUAAAABHicY2Rg+N/AgAIYwXwmVEEEIF2CdAAAIIMCCKpDNl4AAAAASUVORK5CYII="
    )!
}
#endif
