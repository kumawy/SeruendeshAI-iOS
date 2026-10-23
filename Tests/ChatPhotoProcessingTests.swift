#if !SWIFT_PACKAGE || SERU_PHOTO_HARNESS
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SeruendeshAI

struct ChatPhotoProcessingTests {
    // Returning original local bytes would retain a 4000px PNG and bypass the upload/storage budget.
    @Test func normalizesLargePhotosToBoundedJPEG() async throws {
        let input = try fixture(width: 4000, height: 3000)
        let output = try await ChatPhotoProcessor.shared.normalize(input)
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(image.width == 2048)
        #expect(image.height == 1536)
        #expect(output.count <= 8 * 1024 * 1024)
    }

    // Small attachments should retain their dimensions rather than growing to the thumbnail limit.
    @Test func smallPhotosAreNotUpscaled() async throws {
        let output = try await ChatPhotoProcessor.shared.normalize(fixture(width: 32, height: 20))
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 32)
        #expect(image.height == 20)
    }

    // Dropping EXIF orientation before applying it would rotate portrait photos sideways.
    @Test func appliesOrientationBeforeDiscardingMetadata() async throws {
        let input = try fixture(width: 40, height: 20, type: UTType.jpeg.identifier, orientation: 6)
        let output = try await ChatPhotoProcessor.shared.normalize(input)
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 20)
        #expect(image.height == 40)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect((properties?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    // JPEG cannot store alpha; transparent artwork should have a white rather than black matte.
    @Test func transparentPixelsBecomeWhite() async throws {
        let output = try await ChatPhotoProcessor.shared.normalize(fixture(width: 16, height: 16, transparent: true))
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        #expect(bytes[0] >= 250 && bytes[1] >= 250 && bytes[2] >= 250)
    }

    @Test func unreadableDataCannotBecomeAnAttachment() async {
        await #expect(throws: ChatPhotoProcessingError.unreadable) {
            try await ChatPhotoProcessor.shared.normalize(Data("not a photo".utf8))
        }
    }

    @Test func cancelledProcessingCannotReturnPhotoData() async throws {
        let input = try fixture(width: 16, height: 16)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChatPhotoProcessor.shared.normalize(input)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // A bounded preview must be reused for equal bytes and evicted after its LRU budget is exceeded.
    @Test func previewsDownsampleReuseAndEvictDecodedImages() async throws {
        let cache = ChatPhotoPreviewCache(countLimit: 2, byteLimit: 8 * 1024 * 1024)
        let firstData = try fixture(width: 1000, height: 500)
        let secondData = try fixture(width: 40, height: 20)
        let thirdData = try fixture(width: 48, height: 24)
        let first = try await cache.preview(data: firstData, maxPixelSize: 200)
        #expect(first.width == 200)
        #expect(first.height == 100)
        let repeated = try await cache.preview(data: firstData, maxPixelSize: 200)
        #expect(first === repeated)
        _ = try await cache.preview(data: secondData, maxPixelSize: 200)
        _ = try await cache.preview(data: thirdData, maxPixelSize: 200)
        let reloaded = try await cache.preview(data: firstData, maxPixelSize: 200)
        #expect(first !== reloaded)
    }

    @Test func oversizePreviewIsNotRetainedBeyondTheByteBudget() async throws {
        let cache = ChatPhotoPreviewCache(countLimit: 2, byteLimit: 1_000)
        let data = try fixture(width: 100, height: 100)
        let first = try await cache.preview(data: data, maxPixelSize: 100)
        let second = try await cache.preview(data: data, maxPixelSize: 100)
        #expect(first !== second)
    }

    private func fixture(width: Int, height: Int, type: String = UTType.png.identifier,
                         orientation: Int = 1, transparent: Bool = false) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !transparent {
            context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
#endif
