import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ChatPhotoProcessingError: Error, Equatable {
    case unreadable
    case tooLarge
}

actor ChatPhotoProcessor {
    static let shared = ChatPhotoProcessor()

    /// Actor isolation keeps ImageIO decoding and JPEG encoding away from the main actor.
    func normalize(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        let image = try Self.downsample(data, maxPixelSize: 2048)
        try Task.checkCancellation()

        // JPEG has no alpha. Give transparent PNG/HEIC artwork a predictable white matte.
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ChatPhotoProcessingError.unreadable
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else { throw ChatPhotoProcessingError.unreadable }

        for quality in [0.82, 0.70, 0.58] {
            try Task.checkCancellation()
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ChatPhotoProcessingError.unreadable
            }
            CGImageDestinationAddImage(destination, flattened,
                                       [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ChatPhotoProcessingError.unreadable }
            try Task.checkCancellation()
            if result.length <= 8 * 1024 * 1024 { return result as Data }
        }
        throw ChatPhotoProcessingError.tooLarge
    }

    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) throws -> CGImage {
        try Task.checkCancellation()
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ChatPhotoProcessingError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(2048, max(1, maxPixelSize)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ChatPhotoProcessingError.unreadable
        }
        try Task.checkCancellation()
        return image
    }
}

#if canImport(UIKit)
import Observation
import PhotosUI
import SwiftUI

/// Owned above the walk panel so photo transfers survive its compact/chat transition.
@MainActor
@Observable
final class ChatAttachmentLoader {
    private(set) var selectedPhoto: PhotosPickerItem?
    private(set) var isLoading = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var selectionID = UUID()

    func select(_ item: PhotosPickerItem?, into app: AppModel) {
        clear()
        app.chatAttachmentData = nil
        guard let item else { return }

        selectedPhoto = item
        isLoading = true
        let requestID = selectionID
        loadTask = Task { [weak self, weak app] in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ChatPhotoProcessingError.unreadable
                }
                try Task.checkCancellation()
                let normalized = try await ChatPhotoProcessor.shared.normalize(data)
                guard !Task.isCancelled, let self, let app, self.selectionID == requestID else { return }
                app.chatAttachmentData = normalized
                self.isLoading = false
                self.loadTask = nil
            } catch {
                guard !Task.isCancelled, let self, let app, self.selectionID == requestID else { return }
                self.isLoading = false
                self.selectedPhoto = nil
                self.loadTask = nil
                let message = error as? ChatPhotoProcessingError == .tooLarge
                    ? "Фото слишком большое. Выбери другое."
                    : "Не удалось открыть фото. Выбери другое."
                app.emitMascotFeedback(kind: .photoError, message: message)
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    func clear() {
        selectionID = UUID()
        loadTask?.cancel()
        loadTask = nil
        selectedPhoto = nil
        isLoading = false
    }
}
#endif
