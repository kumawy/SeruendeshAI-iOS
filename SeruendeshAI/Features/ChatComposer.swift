import SwiftUI
import PhotosUI

struct ChatComposer: View {
    var focusOnAppear: Bool = false
    var focusDismissal: Int = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    var onEditing: () -> Void = {}
    var onSent: () -> Void = {}
    var onFilters: () -> Void = {}
    var mascotActive: Bool = true

    @Environment(AppModel.self) private var app
    @Environment(ChatAttachmentLoader.self) private var attachmentLoader
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool

    private var hasContent: Bool {
        !app.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.chatAttachmentData != nil
    }

    var body: some View {
        @Bindable var app = app
        let isLoading = attachmentLoader.isLoading
        VStack(spacing: 7) {
            if let photoData = app.chatAttachmentData {
                attachmentPreview(photoData)
            }
            HStack(alignment: .bottom, spacing: 5) {
                PhotosPicker(selection: Binding(
                    get: { attachmentLoader.selectedPhoto },
                    set: { attachmentLoader.select($0, into: app) }
                ), matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .opacity(isLoading ? 0 : 1)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .overlay {
                    if isLoading {
                        SeruMascotAnimation(scene: .photoLoading,
                                            isActive: mascotActive && app.tab == .walk && scenePhase == .active)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                            .accessibilityIdentifier("photo-loading-mascot")
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(attachmentLoader.isLoading ? "Загрузка фото" : "Прикрепить фото")

                TextField("Напиши Серу…", text: $app.chatDraft,
                          prompt: Text("Напиши Серу…").foregroundStyle(SeruColor.muted), axis: .vertical)
                    .font(.system(.subheadline, design: .default))
                    .lineLimit(1...(typeSize.isAccessibilitySize && focused ? 2 : 4))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("chat-input")

                Button {
                    focused = false
                    onFilters()
                } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Фильтры прогулки")
                .accessibilityIdentifier("composer-filters")

                Button(action: send) {
                    Image("SendPlane")
                        .renderingMode(.template)
                        .resizable().scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(SeruColor.onAction)
                        .frame(width: 44, height: 44)
                        .background(SeruColor.action, in: Circle())
                }
                .disabled(!hasContent || app.isResponding || attachmentLoader.isLoading)
                .opacity(hasContent && !app.isResponding && !attachmentLoader.isLoading ? 1 : 0.5)
                .accessibilityLabel("Отправить сообщение")
                .accessibilityIdentifier("chat-send")
            }
            .buttonStyle(.plain)
            .font(.system(size: 20))
            .foregroundStyle(SeruColor.ink)
            .padding(6)
            .background(SeruColor.field, in: RoundedRectangle(cornerRadius: 28))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(SeruColor.surface)
        .task(id: focusOnAppear) {
            if focusOnAppear { focused = true }
        }
        .onChange(of: focusDismissal) { _, _ in focused = false }
        .onChange(of: focused) { _, value in
            if value { onEditing() }
            onFocusChange(value)
        }
        .onDisappear { onFocusChange(false) }
    }

    private func attachmentPreview(_ data: Data) -> some View {
        HStack(spacing: 10) {
            ChatPhotoAttachment(data: data, maxPixelSize: 240)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer()
            Button {
                app.chatAttachmentData = nil
                attachmentLoader.clear()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Убрать фото")
        }
        .foregroundStyle(SeruColor.muted)
    }

    private func send() {
        guard !attachmentLoader.isLoading, app.sendChatDraft() else { return }
        attachmentLoader.clear()
        focused = false
        onSent()
    }
}
