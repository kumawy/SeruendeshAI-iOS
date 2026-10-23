import CoreGraphics
import CryptoKit
import Foundation

actor ChatPhotoPreviewCache {
    static let shared = ChatPhotoPreviewCache()

    private struct Key: Hashable {
        let digest: Data
        let maxPixelSize: Int
    }
    private struct Entry {
        let image: CGImage
        let byteCount: Int
    }
    private let countLimit: Int
    private let byteLimit: Int
    private var entries: [Key: Entry] = [:]
    private var recentKeys: [Key] = []
    private var byteCount = 0

    init(countLimit: Int = 24, byteLimit: Int = 24 * 1024 * 1024) {
        self.countLimit = max(0, countLimit)
        self.byteLimit = max(0, byteLimit)
    }

    func preview(data: Data, maxPixelSize: Int) throws -> CGImage {
        try Task.checkCancellation()
        let pixelSize = min(2048, max(1, maxPixelSize))
        // Keys retain a fixed-size digest instead of duplicating the source attachment bytes.
        let key = Key(digest: Data(SHA256.hash(data: data)), maxPixelSize: pixelSize)
        if let entry = entries[key] {
            recentKeys.removeAll { $0 == key }
            recentKeys.append(key)
            return entry.image
        }
        let image = try ChatPhotoProcessor.downsample(data, maxPixelSize: pixelSize)
        let cost = image.bytesPerRow * image.height
        guard countLimit > 0, cost <= byteLimit else { return image }
        while entries.count >= countLimit || byteCount + cost > byteLimit {
            let oldest = recentKeys.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) { byteCount -= removed.byteCount }
        }
        entries[key] = Entry(image: image, byteCount: cost)
        recentKeys.append(key)
        byteCount += cost
        return image
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Caller supplies its frame and clipping shape; decoding is shared between composer and chat.
struct ChatPhotoAttachment: View {
    let data: Data
    var maxPixelSize = 660
    @State private var showsViewer = false

    var body: some View {
        Button { showsViewer = true } label: {
            ChatPhotoThumbnail(data: data, maxPixelSize: maxPixelSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Открыть фото")
        .accessibilityHint("Просмотр и увеличение прикреплённого фото")
        .accessibilityIdentifier("chat-photo-open")
        .fullScreenCover(isPresented: $showsViewer) { ChatPhotoViewer(data: data) }
    }
}

struct ChatPhotoThumbnail: View {
    let data: Data
    var maxPixelSize = 660
    @State private var image: CGImage?
    @State private var failed = false

    private struct Request: Equatable {
        let data: Data
        let pixelSize: Int
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay {
                        if failed { Image(systemName: "photo").foregroundStyle(.secondary) }
                        else { ProgressView() }
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: Request(data: data, pixelSize: maxPixelSize)) {
            image = nil
            failed = false
            do {
                let decoded = try await ChatPhotoPreviewCache.shared.preview(data: data, maxPixelSize: maxPixelSize)
                try Task.checkCancellation()
                image = decoded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

struct ChatPhotoViewer: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var failed = false
    @State private var resetID = 0
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    ChatPhotoZoomCanvas(image: image, resetID: resetID, reduceMotion: reduceMotion)
                        .accessibilityIdentifier("chat-photo-zoom")
                } else if failed {
                    ContentUnavailableView("Не удалось открыть фото", systemImage: "photo")
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle("Фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        guard let image else { return }
                        UIPasteboard.general.image = UIImage(cgImage: image)
                        copied = true
                        AccessibilityNotification.Announcement("Фото скопировано").post()
                    } label: {
                        Label(copied ? "Фото скопировано" : "Скопировать фото", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(image == nil)
                    .accessibilityIdentifier("chat-photo-copy")
                    Button { resetID += 1 } label: {
                        Label("Сбросить масштаб", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(image == nil)
                    .accessibilityIdentifier("chat-photo-reset")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("chat-photo-close")
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .task(id: data) {
                image = nil
                failed = false
                do {
                    let decoded = try await ChatPhotoPreviewCache.shared.preview(data: data, maxPixelSize: 2048)
                    try Task.checkCancellation()
                    image = decoded
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// UIScrollView supplies native pinch zoom, panning, and double-tap focus without custom drag math.
private struct ChatPhotoZoomCanvas: UIViewRepresentable {
    let image: CGImage
    let resetID: Int
    let reduceMotion: Bool

    func makeUIView(context: Context) -> ChatPhotoZoomScrollView {
        let view = ChatPhotoZoomScrollView()
        view.setImage(image)
        view.resetID = resetID
        view.reduceMotion = reduceMotion
        return view
    }

    func updateUIView(_ view: ChatPhotoZoomScrollView, context: Context) {
        view.setImage(image)
        view.reduceMotion = reduceMotion
        if view.resetID != resetID {
            view.resetID = resetID
            view.setZoomScale(view.minimumZoomScale, animated: !reduceMotion)
        }
    }
}

private final class ChatPhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let photoView = UIImageView()
    private var sourceImage: CGImage?
    private var fittedSize: CGSize = .zero
    var resetID = 0
    var reduceMotion = false

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        photoView.contentMode = .scaleAspectFit
        photoView.isAccessibilityElement = true
        photoView.accessibilityLabel = "Фото"
        photoView.accessibilityHint = "Доступны действия увеличения и сброса масштаба."
        photoView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Увеличить", target: self, selector: #selector(increasePhotoZoom)),
            UIAccessibilityCustomAction(name: "Сбросить масштаб", target: self, selector: #selector(resetPhotoZoom))
        ]
        addSubview(photoView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { nil }

    func setImage(_ image: CGImage) {
        guard sourceImage !== image else { return }
        sourceImage = image
        // The CGImage was already decoded on the cache actor; this only wraps it for display.
        photoView.image = UIImage(cgImage: image)
        fittedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize, bounds.width > 0, bounds.height > 0, let sourceImage {
            fittedSize = bounds.size
            setZoomScale(minimumZoomScale, animated: false)
            let fit = min(bounds.width / CGFloat(sourceImage.width), bounds.height / CGFloat(sourceImage.height))
            let size = CGSize(width: CGFloat(sourceImage.width) * fit, height: CGFloat(sourceImage.height) * fit)
            photoView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        centerPhoto()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photoView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }

    private func centerPhoto() {
        photoView.center = CGPoint(x: max(bounds.width, contentSize.width) / 2,
                                   y: max(bounds.height, contentSize.height) / 2)
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: !reduceMotion)
        } else {
            let scale: CGFloat = 2.5
            let point = gesture.location(in: photoView)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: !reduceMotion)
        }
    }

    @objc private func increasePhotoZoom() -> Bool {
        setZoomScale(min(maximumZoomScale, zoomScale + 1), animated: !reduceMotion)
        return true
    }

    @objc private func resetPhotoZoom() -> Bool {
        setZoomScale(minimumZoomScale, animated: !reduceMotion)
        return true
    }
}
#endif
