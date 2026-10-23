import Foundation
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

    func select(_ item: PhotosPickerItem?, into app: AppModel) {
        clear()
        app.chatAttachmentData = nil
        guard let item else { return }

        selectedPhoto = item
        isLoading = true
        loadTask = Task { [weak self, weak app] in
            do {
                let data = try await item.loadTransferable(type: Data.self)
                guard !Task.isCancelled, let self, let app else { return }
                defer {
                    self.isLoading = false
                    self.loadTask = nil
                }
                guard let data else {
                    self.selectedPhoto = nil
                    app.emitMascotFeedback(kind: .photoError, message: "Не удалось открыть фото. Выбери другое.")
                    return
                }
                guard let image = UIImage(data: data) else {
                    self.selectedPhoto = nil
                    app.emitMascotFeedback(kind: .photoError, message: "Не удалось открыть фото. Выбери другое.")
                    return
                }
                if app.usesBackend {
                    let scale = min(1, 2048 / max(image.size.width, image.size.height))
                    let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    format.opaque = true
                    let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        UIColor.white.setFill()
                        UIRectFill(CGRect(origin: .zero, size: size))
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    guard let jpeg = normalized.jpegData(compressionQuality: 0.82), jpeg.count <= 8 * 1024 * 1024 else {
                        self.selectedPhoto = nil
                        app.emitMascotFeedback(kind: .photoError, message: "Фото слишком большое. Выбери другое.")
                        return
                    }
                    app.chatAttachmentData = jpeg
                } else { app.chatAttachmentData = data }
            } catch {
                guard !Task.isCancelled, let self, let app else { return }
                self.isLoading = false
                self.selectedPhoto = nil
                self.loadTask = nil
                app.emitMascotFeedback(kind: .photoError, message: "Не удалось открыть фото. Выбери другое.")
            }
        }
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        selectedPhoto = nil
        isLoading = false
    }
}
