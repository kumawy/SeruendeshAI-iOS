import CoreGraphics
import Foundation
import ImageIO
import Observation
import OSLog
import SwiftUI

enum SeruMascotScene: String, CaseIterable, Sendable {
    case emptyBox, calendarEmpty, searchEmpty, postersLoading, greeting, thinking, noPlaces
    case routing, routeBlocked, photoLoading, photoError, connectionError, saved, ready

    var loops: Bool {
        switch self {
        case .greeting, .saved, .ready: false
        default: true
        }
    }

    func resourceDirectory(in root: URL) -> URL {
        let native = root.appendingPathComponent("SeruMotion/\(rawValue)", isDirectory: true)
        if FileManager.default.fileExists(atPath: native.path) { return native }
        // Existing shipped PNG sequences remain usable during an incremental asset update.
        switch self {
        case .emptyBox: return root.appendingPathComponent("SeruEmptyBox", isDirectory: true)
        case .greeting: return root.appendingPathComponent("SeruSplash", isDirectory: true)
        default: return native
        }
    }
}

/// The caller supplies the frame. Only this image subtree updates at the asset's frame rate.
@MainActor
struct SeruMascotAnimation: View {
    let scene: SeruMascotScene
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAppeared = false
    @State private var intersectsViewport = true
    @State private var player = SeruMascotFramePlayer()

    var body: some View {
        ZStack {
            if let image = player.image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Image("SeruMascot").resizable().scaledToFit()
            }
        }
        .transaction { $0.disablesAnimations = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Серу")
        .accessibilityAddTraits(.isImage)
        .onAppear { hasAppeared = true }
        .onDisappear { hasAppeared = false }
        .onGeometryChange(for: Bool.self) { geometry in
            guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else { return true }
            return viewport.intersects(CGRect(origin: .zero, size: geometry.size))
        } action: { intersectsViewport = $0 }
        .task(id: PlaybackRequest(scene: scene, mode: playbackMode)) {
            await player.display(scene: scene, mode: playbackMode)
        }
    }

    private var playbackMode: SeruMascotPlaybackMode {
        guard isActive, hasAppeared, intersectsViewport, scenePhase == .active else { return .inactive }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seru.emptyBox.reduceMotion") { return .poster }
#endif
        return reduceMotion ? .poster : .animate
    }

    private struct PlaybackRequest: Equatable {
        let scene: SeruMascotScene
        let mode: SeruMascotPlaybackMode
    }
}

enum SeruMascotPlaybackMode: Equatable, Sendable {
    case inactive, poster, animate
}

@MainActor
@Observable
final class SeruMascotFramePlayer {
    private(set) var image: CGImage?
    private(set) var frameIndex = 0

    @ObservationIgnored private let resourceRoot: URL?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var currentScene: SeruMascotScene?
    @ObservationIgnored private var finishedOnce = false

    init(resourceRoot: URL? = Bundle.main.resourceURL) {
        self.resourceRoot = resourceRoot
    }

    func display(scene: SeruMascotScene, mode: SeruMascotPlaybackMode) async {
        generation &+= 1
        let playbackGeneration = generation
        if currentScene != scene {
            currentScene = scene
            finishedOnce = false
            frameIndex = 0
            image = nil
        }
        guard mode != .inactive, let resourceRoot else { return }
        if mode == .animate, !scene.loops, finishedOnce { return }
        let directory = scene.resourceDirectory(in: resourceRoot)
        // A task owns its store so an interrupted task cannot clear its replacement's frames.
        let store = SeruMascotFrameStore()
        do {
            if mode == .poster {
                let poster = try await store.poster(in: directory)
                try Task.checkCancellation()
                guard generation == playbackGeneration else { throw CancellationError() }
                image = poster
            } else {
                let manifest = try await store.prepare(directory: directory, loops: scene.loops)
                let clock = ContinuousClock()
                let interval = Duration.seconds(1 / manifest.fps)
                var deadline = clock.now
                var index = 0
                while true {
                    try Task.checkCancellation()
                    let next = try await store.frame(at: index)
                    try Task.checkCancellation()
                    guard generation == playbackGeneration else { throw CancellationError() }
                    image = next
                    frameIndex = index
                    let displayedAt = clock.now
                    // Preserve the dwell of each pose under load instead of skipping to catch up.
                    if deadline.duration(to: displayedAt) > interval / 2 { deadline = displayedAt }
                    try await store.prefetch(from: index)
                    deadline = deadline.advanced(by: interval)
                    try await clock.sleep(until: deadline, tolerance: .milliseconds(1))
                    if !scene.loops, index == manifest.frameCount - 1 {
                        let settled = try await store.frame(at: manifest.settleFrame)
                        try Task.checkCancellation()
                        guard generation == playbackGeneration else { throw CancellationError() }
                        image = settled
                        frameIndex = manifest.settleFrame
                        finishedOnce = true
                        break
                    }
                    index = (index + 1) % manifest.frameCount
                }
            }
        } catch {
            if !Task.isCancelled, generation == playbackGeneration {
                Logger(subsystem: "kz.seruendesh.frontend", category: "SeruMascot")
                    .error("\(scene.rawValue, privacy: .public) fallback: \(String(describing: error), privacy: .public)")
                // The poster remains useful even if the manifest or animated file is damaged.
                let poster = try? await store.poster(in: directory)
                if !Task.isCancelled, generation == playbackGeneration { image = poster }
            }
        }
        // Inactive/cancelled views retain a single still, never the rolling decode cache.
        await store.clear()
    }
}

/// New exports use animation.png (APNG), poster.png and manifest.json. Required metadata:
/// fps, frameCount; width/height, posterFrame and settleFrame are validated when supplied.
/// Legacy PNG sequences use framesPattern + startIndex (the two original patterns are supported).
struct SeruMascotManifest: Decodable, Sendable {
    let fps: Double
    let frameCount: Int
    let width: Int?
    let height: Int?
    let posterFrame: Int
    let settleFrame: Int
    let framesPattern: String
    let startIndex: Int

    private enum CodingKeys: String, CodingKey {
        case fps, frameCount, width, height, canvasWidth, canvasHeight
        case posterFrame, handoffFrame, settleFrame, framesPattern, startIndex
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fps = try values.decode(Double.self, forKey: .fps)
        frameCount = try values.decode(Int.self, forKey: .frameCount)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
            ?? values.decodeIfPresent(Int.self, forKey: .canvasWidth)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
            ?? values.decodeIfPresent(Int.self, forKey: .canvasHeight)
        let handoff = try values.decodeIfPresent(Int.self, forKey: .handoffFrame)
        posterFrame = try values.decodeIfPresent(Int.self, forKey: .posterFrame) ?? handoff ?? 0
        settleFrame = try values.decodeIfPresent(Int.self, forKey: .settleFrame) ?? handoff ?? (frameCount - 1)
        framesPattern = try values.decodeIfPresent(String.self, forKey: .framesPattern) ?? "frames/frame_%04d.png"
        startIndex = try values.decodeIfPresent(Int.self, forKey: .startIndex) ?? 0
    }

    func validate() throws {
        guard fps.isFinite, (1...60).contains(fps), (1...3_600).contains(frameCount),
              (0..<frameCount).contains(posterFrame), (0..<frameCount).contains(settleFrame),
              (0...999_999).contains(startIndex),
              width.map({ (1...2_048).contains($0) }) ?? true,
              height.map({ (1...2_048).contains($0) }) ?? true,
              ["frames/frame_%04d.png", "frames/%04d.png"].contains(framesPattern) else {
            throw SeruMascotFrameError.invalidManifest
        }
    }

    func frameURL(at index: Int, in directory: URL) -> URL {
        let name = framesPattern.replacingOccurrences(of: "%04d", with: String(format: "%04d", index + startIndex))
        return directory.appendingPathComponent(name)
    }
}

enum SeruMascotFrameError: Error {
    case missingResource, invalidManifest, invalidImage, frameCountMismatch
}

/// Decoding runs off the main actor. ImageIO's source cache is disabled, and at most five
/// fully decompressed RGBA images are retained by this store, including a loop boundary.
actor SeruMascotFrameStore {
    private let capacity = 5
    private var manifest: SeruMascotManifest?
    private var directory: URL?
    private var animatedSource: CGImageSource?
    private var loops = true
    private var cache: [Int: CGImage] = [:]
    private var decodedFrames = 0
    private var peakCachedFrameCount = 0

    struct Snapshot: Sendable {
        let decodedFrames: Int
        let peakCachedFrameCount: Int
        let cachedFrameCount: Int
    }

    func prepare(directory: URL, loops: Bool) throws -> SeruMascotManifest {
        clear()
        try Task.checkCancellation()
        let metadata = try Self.readManifest(in: directory)
        try metadata.validate()
        let animatedURL = directory.appendingPathComponent("animation.png")
        if FileManager.default.fileExists(atPath: animatedURL.path) {
            guard let source = CGImageSourceCreateWithURL(animatedURL as CFURL, Self.sourceOptions) else {
                throw SeruMascotFrameError.invalidImage
            }
            guard CGImageSourceGetCount(source) == metadata.frameCount else {
                throw SeruMascotFrameError.frameCountMismatch
            }
            animatedSource = source
        } else {
            for index in 0..<metadata.frameCount {
                try Task.checkCancellation()
                guard FileManager.default.fileExists(atPath: metadata.frameURL(at: index, in: directory).path) else {
                    throw SeruMascotFrameError.missingResource
                }
            }
        }
        manifest = metadata
        self.directory = directory
        self.loops = loops
        try prefetch(from: 0)
        return metadata
    }

    func poster(in directory: URL) throws -> CGImage {
        try Task.checkCancellation()
        let posterURL = directory.appendingPathComponent("poster.png")
        if FileManager.default.fileExists(atPath: posterURL.path) { return try Self.decode(posterURL) }
        let metadata = try Self.readManifest(in: directory)
        try metadata.validate()
        let animationURL = directory.appendingPathComponent("animation.png")
        if FileManager.default.fileExists(atPath: animationURL.path),
           let source = CGImageSourceCreateWithURL(animationURL as CFURL, Self.sourceOptions),
           CGImageSourceGetCount(source) == metadata.frameCount {
            return try Self.decode(source: source, index: metadata.posterFrame, manifest: metadata)
        }
        return try Self.decode(metadata.frameURL(at: metadata.posterFrame, in: directory))
    }

    func frame(at index: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard let manifest, let directory, (0..<manifest.frameCount).contains(index) else {
            throw SeruMascotFrameError.missingResource
        }
        trim(from: index)
        if let image = cache[index] { return image }
        let image: CGImage
        if let animatedSource {
            image = try Self.decode(source: animatedSource, index: index, manifest: manifest)
        } else {
            image = try Self.decode(manifest.frameURL(at: index, in: directory), manifest: manifest)
        }
        cache[index] = image
        decodedFrames += 1
        peakCachedFrameCount = max(peakCachedFrameCount, cache.count)
        return image
    }

    func prefetch(from index: Int) throws {
        guard let manifest else { throw SeruMascotFrameError.missingResource }
        trim(from: index)
        for offset in 0..<min(capacity, manifest.frameCount) {
            try Task.checkCancellation()
            let next = index + offset
            if !loops, next >= manifest.frameCount { break }
            let wrapped = next % manifest.frameCount
            // frame(at:) trims relative to its argument, so populate through a separate decoder.
            if cache[wrapped] == nil {
                guard let directory else { throw SeruMascotFrameError.missingResource }
                let image: CGImage
                if let animatedSource {
                    image = try Self.decode(source: animatedSource, index: wrapped, manifest: manifest)
                } else {
                    image = try Self.decode(manifest.frameURL(at: wrapped, in: directory), manifest: manifest)
                }
                cache[wrapped] = image
                decodedFrames += 1
                peakCachedFrameCount = max(peakCachedFrameCount, cache.count)
            }
        }
    }

    func clear() {
        cache.removeAll(keepingCapacity: false)
        animatedSource = nil
        manifest = nil
        directory = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(decodedFrames: decodedFrames, peakCachedFrameCount: peakCachedFrameCount, cachedFrameCount: cache.count)
    }

    private func trim(from index: Int) {
        guard let manifest else { return }
        cache = cache.filter {
            let distance = loops ? ($0.key - index + manifest.frameCount) % manifest.frameCount : $0.key - index
            return (0..<capacity).contains(distance)
        }
    }

    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    private static func readManifest(in directory: URL) throws -> SeruMascotManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw SeruMascotFrameError.missingResource }
        return try JSONDecoder().decode(SeruMascotManifest.self, from: Data(contentsOf: url))
    }

    private static func decode(_ url: URL, manifest: SeruMascotManifest? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw SeruMascotFrameError.invalidImage
        }
        return try decode(source: source, index: 0, manifest: manifest)
    }

    private static func decode(source: CGImageSource, index: Int, manifest: SeruMascotManifest?) throws -> CGImage {
        try autoreleasepool {
            guard let sourceImage = CGImageSourceCreateImageAtIndex(source, index, sourceOptions),
                  (1...2_048).contains(sourceImage.width), (1...2_048).contains(sourceImage.height),
                  manifest?.width.map({ $0 == sourceImage.width }) ?? true,
                  manifest?.height.map({ $0 == sourceImage.height }) ?? true,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: sourceImage.width, height: sourceImage.height,
                    bitsPerComponent: 8, bytesPerRow: sourceImage.width * 4, space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw SeruMascotFrameError.invalidImage
            }
            context.setBlendMode(.copy)
            context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
            guard let image = context.makeImage() else { throw SeruMascotFrameError.invalidImage }
            return image
        }
    }
}
