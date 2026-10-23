import CoreGraphics
import Foundation
import ImageIO
import Observation

struct MascotPlaybackMetrics: Sendable {
    var framesDisplayed = 0
    var decodedFrames = 0
    var peakCachedFrameCount = 0
    var cachedFrameCount = 0
    var lateFrames = 0
    var playbackDurationSeconds = 0.0
}

enum MascotFramePlayerError: LocalizedError {
    case missingResource(String)
    case invalidImage(String)
    case unprepared
    case alreadyPlayed
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .missingResource(let path): "Splash resource is missing: \(path)"
        case .invalidImage(let path): "Splash PNG could not be decoded with its expected RGBA dimensions: \(path)"
        case .unprepared: "Prepare the splash frames before playback."
        case .alreadyPlayed: "The splash frame sequence has already played."
        case .invalidDuration: "Splash playback duration must be positive and finite."
        }
    }
}

/// Owns only the currently displayed image; decoding and the five-frame window live off the main actor.
@MainActor
@Observable
final class MascotFramePlayer {
    private(set) var image: CGImage?
    private(set) var frameIndex = 0
    private(set) var manifest: SplashFrameManifest?
    private(set) var metrics = MascotPlaybackMetrics()

    @ObservationIgnored private let resourceRoot: URL?
    @ObservationIgnored private let resourceDirectory: String
    @ObservationIgnored private var store: MascotFrameStore?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var hasPlayed = false

    init(bundle: Bundle = .main, resourceDirectory: String = "SeruSplash") {
        resourceRoot = bundle.resourceURL
        self.resourceDirectory = resourceDirectory
    }

    /// Reduced Motion requests only the settled handoff image; normal playback preloads frames 0000...0004.
    func prepare(handoffOnly: Bool = false) async throws {
        await release()
        manifest = nil
        metrics = MascotPlaybackMetrics()
        hasPlayed = false
        let preparationGeneration = generation
        guard let resourceRoot else {
            throw MascotFramePlayerError.missingResource("\(resourceDirectory)/manifest.json")
        }
        let newStore = MascotFrameStore()
        store = newStore
        do {
            let prepared = try await newStore.prepare(
                directory: resourceRoot.appendingPathComponent(resourceDirectory, isDirectory: true),
                handoffOnly: handoffOnly
            )
            try Task.checkCancellation()
            guard preparationGeneration == generation else { throw CancellationError() }
            manifest = prepared.manifest
            frameIndex = prepared.index
            image = prepared.image
            metrics = await metricsSnapshot()
        } catch {
            await newStore.clear()
            if preparationGeneration == generation {
                image = nil
                store = nil
            }
            throw error
        }
    }

    /// Absolute clock deadlines avoid accumulating relative-sleep drift. Under load the sequence extends,
    /// preserving each source frame's dwell instead of skipping frames to catch up.
    func play(duration: Double? = nil) async throws {
        guard let store, let manifest else { throw MascotFramePlayerError.unprepared }
        guard !hasPlayed else { throw MascotFramePlayerError.alreadyPlayed }
        let playbackDuration = duration ?? manifest.durationSeconds
        guard playbackDuration.isFinite, playbackDuration > 0 else {
            throw MascotFramePlayerError.invalidDuration
        }
        hasPlayed = true
        let playbackGeneration = generation
        let clock = ContinuousClock()
        let started = clock.now
        let interval = Duration.seconds(playbackDuration / Double(manifest.frameCount))
        var deadline = started
        metrics.framesDisplayed = 0
        metrics.lateFrames = 0
        do {
            for index in 0..<manifest.frameCount {
                try Task.checkCancellation()
                try await clock.sleep(until: deadline, tolerance: .zero)
                let next = try await store.frame(at: index)
                try Task.checkCancellation()
                guard playbackGeneration == generation else { throw CancellationError() }
                let displayedAt = clock.now
                if deadline.duration(to: displayedAt) > interval / 2 {
                    metrics.lateFrames += 1
                    deadline = displayedAt
                }
                frameIndex = index
                image = next
                metrics.framesDisplayed += 1
                // Publish first, then replace the old cache slot. This never retains six distinct frames.
                try await store.prefetch(from: index)
                deadline = deadline.advanced(by: interval)
                if index == manifest.handoffFrame {
                    deadline = max(deadline, displayedAt.advanced(by: interval))
                }
            }
            // Frame 0053 receives a full frame interval (1/30 s by default), then a coordinator display refresh.
            try await clock.sleep(until: deadline, tolerance: .zero)
            try Task.checkCancellation()
            guard playbackGeneration == generation else { throw CancellationError() }
            metrics.playbackDurationSeconds = Self.seconds(started.duration(to: clock.now))
            await store.clear()
            metrics = await metricsSnapshot()
        } catch {
            await store.clear()
            if playbackGeneration == generation {
                image = nil
                metrics = await metricsSnapshot()
            }
            throw error
        }
    }

    /// Called when the overlay finishes or is interrupted; playback metrics remain available for diagnostics.
    func release() async {
        generation += 1
        image = nil
        let previousStore = store
        store = nil
        if let previousStore {
            let snapshot = await previousStore.snapshot()
            metrics.decodedFrames = snapshot.decodedFrames
            metrics.peakCachedFrameCount = snapshot.peakCachedFrameCount
            await previousStore.clear()
        }
        metrics.cachedFrameCount = 0
    }

    func metricsSnapshot() async -> MascotPlaybackMetrics {
        var result = metrics
        if let store {
            let snapshot = await store.snapshot()
            result.decodedFrames = snapshot.decodedFrames
            result.peakCachedFrameCount = snapshot.peakCachedFrameCount
            result.cachedFrameCount = snapshot.cachedFrameCount
        }
        return result
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

private actor MascotFrameStore {
    private let capacity = 5
    private var frameURLs: [URL] = []
    private var manifest: SplashFrameManifest?
    private var cache: [Int: CGImage] = [:]
    private var decodedFrames = 0
    private var peakCachedFrameCount = 0

    struct Prepared: Sendable {
        let manifest: SplashFrameManifest
        let index: Int
        let image: CGImage
    }

    struct Snapshot: Sendable {
        let decodedFrames: Int
        let peakCachedFrameCount: Int
        let cachedFrameCount: Int
    }

    func prepare(directory: URL, handoffOnly: Bool) throws -> Prepared {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw MascotFramePlayerError.missingResource(manifestURL.path)
        }
        let decodedManifest = try JSONDecoder().decode(SplashFrameManifest.self, from: Data(contentsOf: manifestURL))
        try decodedManifest.validate()
        var urls: [URL] = []
        urls.reserveCapacity(decodedManifest.frameCount)
        for index in 0..<decodedManifest.frameCount {
            let frameName = try decodedManifest.frameName(at: index)
            let relativePath = frameName.contains("/") ? frameName : "frames/\(frameName)"
            let url = directory.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw MascotFramePlayerError.missingResource(url.path)
            }
            urls.append(url)
        }
        manifest = decodedManifest
        frameURLs = urls
        let index = handoffOnly ? decodedManifest.handoffFrame : 0
        let firstImage = try frame(at: index)
        if !handoffOnly { try prefetch(from: index) }
        return Prepared(manifest: decodedManifest, index: index, image: firstImage)
    }

    func frame(at index: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard frameURLs.indices.contains(index), let manifest else { throw MascotFramePlayerError.unprepared }
        // Remove old frames before decoding so the actor never exceeds five RGBA buffers.
        cache = cache.filter { $0.key >= index && $0.key < index + capacity }
        if let image = cache[index] { return image }
        let image = try Self.decode(url: frameURLs[index], manifest: manifest)
        cache[index] = image
        decodedFrames += 1
        peakCachedFrameCount = max(peakCachedFrameCount, cache.count)
        return image
    }

    func prefetch(from index: Int) throws {
        guard let manifest else { throw MascotFramePlayerError.unprepared }
        cache = cache.filter { $0.key >= index && $0.key < index + capacity }
        for next in index..<min(index + capacity, frameURLs.count) where cache[next] == nil {
            try Task.checkCancellation()
            cache[next] = try Self.decode(url: frameURLs[next], manifest: manifest)
            decodedFrames += 1
            peakCachedFrameCount = max(peakCachedFrameCount, cache.count)
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(decodedFrames: decodedFrames, peakCachedFrameCount: peakCachedFrameCount, cachedFrameCount: cache.count)
    }

    func clear() {
        cache.removeAll(keepingCapacity: false)
        frameURLs.removeAll(keepingCapacity: false)
        manifest = nil
    }

    private static func decode(url: URL, manifest: SplashFrameManifest) throws -> CGImage {
        try autoreleasepool {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, options),
                  image.width == manifest.canvasWidth, image.height == manifest.canvasHeight,
                  [.premultipliedFirst, .premultipliedLast, .first, .last].contains(image.alphaInfo),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw MascotFramePlayerError.invalidImage(url.path)
            }
            // Drawing here forces the PNG inflate and alpha premultiplication on the store's executor.
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let decoded = context.makeImage() else { throw MascotFramePlayerError.invalidImage(url.path) }
            return decoded
        }
    }
}
