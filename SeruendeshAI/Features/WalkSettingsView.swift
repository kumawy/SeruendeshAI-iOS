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
        app.landmarks.map(\.name)
    }
    private var durations: [Int] {
        Array(Set(Array(stride(from: 15, through: 240, by: 15)) + [app.duration])).sorted()
    }
    private var selectedOrigin: String {
        let custom = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? origin : custom
    }
    private var canApply: Bool { app.usesBackend || landmarks.contains(selectedOrigin) }
    private var summary: String {
        ([selectedOrigin, "до \(duration) мин"] + (withKids ? ["с ребёнком"] : []) + (onlyFree ? ["бесплатные места"] : [])).joined(separator: " · ")
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
                                    SeruMenuLabel(title: landmark, symbol: "mappin.circle")
                                    Spacer()
                                    if origin == landmark && address.isEmpty {
                                        Image(systemName: "checkmark").font(.system(size: 17)).foregroundStyle(SeruColor.action)
                                    }
                                }
                                .frame(minHeight: 44)
                                .foregroundStyle(SeruColor.ink)
                            }
                            .accessibilityAddTraits(origin == landmark && address.isEmpty ? .isSelected : [])
                        }
                    }
                    Section("Или укажи свой адрес") {
                        TextField("Адрес или ориентир в Астане", text: $address)
                    }
                } else {
                    Section("Сколько времени есть?") {
                        Picker("Длительность", selection: $duration) {
                            ForEach(durations, id: \.self) { Text("\($0) мин").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("walk-duration")
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
                Section {
                    Text(kind == .origin ? "Начнём от \(selectedOrigin)." : summary)
                        .font(.subheadline)
                        .foregroundStyle(SeruColor.muted)
                        .accessibilityIdentifier("walk-settings-summary")
                } footer: {
                    if !canApply {
                        Text("Для расчёта выбери ориентир из списка.")
                    } else if kind == .filters && app.isResponding {
                        Text("Новые условия отменят текущий подбор. Его можно повторить с выбранными условиями.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SeruColor.background)
            .navigationTitle(kind == .origin ? "Откуда начнём?" : "Условия прогулки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryAction(title: kind == .origin ? "Начать отсюда" : "Применить") { apply() }
                    .disabled(!canApply)
                    .opacity(canApply ? 1 : 0.5)
                    .accessibilityIdentifier("walk-settings-apply")
                    .padding(16).background(.bar)
            }
        }
        .tint(SeruColor.action)
        .onAppear { duration = app.duration; origin = app.origin; onlyFree = app.onlyFree; withKids = app.withKids }
    }

    private func apply() {
        if kind == .origin {
            app.saveOrigin(selectedOrigin)
        } else {
            app.duration = duration
            app.onlyFree = onlyFree
            app.withKids = withKids
            app.saveOrigin(selectedOrigin)
            if app.screen != .chat { app.showResults() }
        }
        dismiss()
    }
}
