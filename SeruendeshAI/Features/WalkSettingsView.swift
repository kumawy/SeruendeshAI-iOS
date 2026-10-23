import SwiftUI

enum WalkSettingsSheet: String, Identifiable {
    case origin, filters
    var id: String { rawValue }
}

struct WalkSettingsView: View {
    let kind: WalkSettingsSheet
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var duration = 60
    @State private var origin = "Байтерек"
    @State private var onlyFree = false
    @State private var withKids = false
    @State private var address = ""
    private var landmarks: [String] {
        app.usesBackend ? app.landmarks.map(\.name) : ["Байтерек", "Ботанический сад", "Хан Шатыр", "ЭКСПО", "Mega Silk Way", "Набережная Ишима"]
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .origin {
                    Section("Выбери точку старта") {
                        ForEach(landmarks, id: \.self) { landmark in
                            Button {
                                origin = landmark
                                address = ""
                            } label: {
                                HStack {
                                    Label(landmark, systemImage: "mappin.circle")
                                    Spacer()
                                    if origin == landmark { Image(systemName: "checkmark").foregroundStyle(SeruColor.action) }
                                }.foregroundStyle(SeruColor.ink)
                            }
                        }
                    }
                    Section {
                        TextField("Адрес или ориентир в Астане", text: $address)
                    } header: {
                        Text("Или укажи свой адрес")
                    }
                } else {
                    Section("Сколько времени есть?") {
                        Picker("Длительность", selection: $duration) {
                            Text("30 мин").tag(30)
                            Text("60 мин").tag(60)
                            Text("120 мин").tag(120)
                        }.pickerStyle(.segmented)
                    }
                    Section("Пожелания") {
                        Toggle("С ребёнком", isOn: $withKids)
                        Toggle("Бесплатные места", isOn: $onlyFree)
                    }
                    Section("Точка старта") {
                        Picker("Откуда начнём?", selection: Binding(
                            get: { origin },
                            set: { origin = $0; address = "" }
                        )) {
                            if !landmarks.contains(origin) { Text(origin).tag(origin) }
                            ForEach(landmarks, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Адрес или ориентир в Астане", text: $address)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SeruColor.background)
            .navigationTitle(kind == .origin ? "Откуда начнём?" : "Условия прогулки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить", systemImage: "checkmark") { apply() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryAction(title: kind == .origin ? "Начать отсюда" : app.screen == .chat ? "Применить" : "Показать места") { apply() }
                    .padding(16).background(.bar)
            }
        }
        .tint(SeruColor.action)
        .onAppear { duration = app.duration; origin = app.origin; onlyFree = app.onlyFree; withKids = app.withKids }
    }

    private func apply() {
        if kind == .origin {
            app.saveOrigin(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? origin : address.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            app.duration = duration; app.onlyFree = onlyFree; app.withKids = withKids
            app.saveOrigin(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? origin : address.trimmingCharacters(in: .whitespacesAndNewlines))
            if app.screen != .chat { app.showResults() }
        }
        dismiss()
    }
}
