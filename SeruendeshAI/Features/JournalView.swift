import SwiftUI

struct JournalView: View {
    var onOpen: () -> Void = {}
    @Environment(AppModel.self) private var app
    @Environment(ChatAttachmentLoader.self) private var attachmentLoader
    @Environment(\.dismiss) private var dismiss
    @State private var entryToDelete: WalkJournalEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Новая прогулка", systemImage: "plus") {
                        attachmentLoader.clear()
                        app.startNewWalk()
                        dismiss()
                        onOpen()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("journal-new-walk")
                }
                if app.journalEntries.isEmpty {
                    ContentUnavailableView("Пока пусто", systemImage: "clock.arrow.circlepath",
                                           description: Text("Здесь появятся твои прогулки и переписка с Серу."))
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("journal-empty")
                } else {
                    Section {
                        ForEach(app.journalEntries) { entry in
                            Button {
                                attachmentLoader.clear()
                                app.restoreJournalEntry(id: entry.id)
                                dismiss()
                                onOpen()
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(entry.title).font(.headline).foregroundStyle(SeruColor.ink)
                                        .lineLimit(3)
                                    Text("\(entry.origin) · \(entry.duration) мин")
                                        .font(.subheadline).foregroundStyle(SeruColor.muted)
                                    Text(entry.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                                        .font(.caption).foregroundStyle(SeruColor.muted)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("journal-entry-\(entry.id)")
                            .swipeActions {
                                Button("Удалить", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                            }
                            .contextMenu {
                                Button("Удалить из журнала", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                            }
                        }
                    } footer: {
                        Text("На этом устройстве хранятся до 20 прогулок и 80 сообщений в каждой. Старые фото удаляются при заполнении хранилища.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SeruColor.background)
            .navigationTitle("Журнал")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Удалить прогулку из журнала?", isPresented: Binding(
                get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Удалить прогулку", role: .destructive) {
                    if let entryToDelete {
                        attachmentLoader.clear()
                        app.deleteJournalEntry(id: entryToDelete.id)
                    }
                    entryToDelete = nil
                }
                Button("Отмена", role: .cancel) { entryToDelete = nil }
            } message: {
                Text("Переписка и фото этой прогулки будут удалены с устройства.")
            }
        }
        .tint(SeruColor.action)
    }
}
