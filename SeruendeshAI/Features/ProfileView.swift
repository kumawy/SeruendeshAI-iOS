import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var accountOpen = false
    @State private var confirmDeletion = false
    @State private var accountActionStarted = false
    @State private var journalOpen = false
    @State private var returnToWalk = false
    @State private var localName = ""
    @State private var nameEditorOpen = false
    @State private var editedName = ""

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarPlaceholder(size: 48).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localName.isEmpty ? (app.account.user?.name ?? "Моя прогулка") : localName)
                                .font(.headline)
                                .accessibilityIdentifier("profile-user-name")
                            if let user = app.account.user {
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(SeruColor.muted)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("profile-user-email")
                            }
                        }
                        Spacer(minLength: 0)
                        if app.account.isRestoring { ProgressView() }
                    }
                    .padding(.vertical, 8)
                    if app.usesBackend, app.account.user == nil {
                        Button("Войти или создать аккаунт") { accountOpen = true }
                            .disabled(app.account.isRestoring)
                            .accessibilityIdentifier("profile-sign-in")
                    }
                    Button("Как тебя называть", systemImage: "pencil") {
                        editedName = localName
                        nameEditorOpen = true
                    }
                    .accessibilityIdentifier("profile-edit-name")
                }
                Section {
                    Button("Журнал прогулок", systemImage: "clock.arrow.circlepath") { journalOpen = true }
                        .accessibilityIdentifier("profile-journal")
                } footer: {
                    Text("Прогулки, фото и избранные места на устройстве сохраняются между запусками. Журнал остаётся на этом устройстве и не синхронизируется с аккаунтом.")
                }
                Section("Оформление") {
                    Picker("Тема", selection: $app.theme) {
                        ForEach(AppTheme.allCases) { theme in Text(theme.title).tag(theme) }
                    }
                }
                if app.account.user != nil {
                    Section {
                        Button("Сменить пароль", systemImage: "key") { accountOpen = true }
                            .accessibilityIdentifier("profile-reset-password")
                        Button {
                            accountActionStarted = true
                            Task { @MainActor in _ = await app.account.signOut() }
                        } label: {
                            HStack {
                                Text("Выйти из аккаунта")
                                Spacer()
                                if app.account.isWorking { ProgressView() }
                            }
                        }
                        .disabled(app.account.isWorking || app.account.isRestoring)
                        .accessibilityIdentifier("account-logout")
                        Button("Удалить аккаунт", role: .destructive) { confirmDeletion = true }
                            .disabled(app.account.isWorking || app.account.isRestoring)
                            .accessibilityIdentifier("account-delete")
                    }
                }
                if let error = app.account.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(error)
                            .accessibilityIdentifier("profile-account-error")
                            .accessibilityAddTraits(.updatesFrequently)
                        if !accountActionStarted {
                            Button("Проверить подключение", systemImage: "arrow.clockwise") {
                                Task { await app.account.restore() }
                            }
                            .disabled(app.account.isWorking || app.account.isRestoring)
                            .accessibilityIdentifier("account-restore-retry")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SeruColor.background)
            .foregroundStyle(SeruColor.ink)
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", systemImage: "checkmark") { dismiss() }
                        .disabled(app.account.isWorking)
                }
            }
            .task(id: app.account.user?.id) {
                localName = UserDefaults.standard.string(forKey: nameKey) ?? ""
            }
            .alert("Как тебя называть?", isPresented: $nameEditorOpen) {
                TextField("Имя", text: $editedName)
                    .textInputAutocapitalization(.words)
                Button("Сохранить") {
                    localName = String(editedName.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(60))
                    UserDefaults.standard.set(localName, forKey: nameKey)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Имя для профиля на этом устройстве. Пустое поле вернёт исходное имя.")
            }
            .confirmationDialog("Удалить аккаунт?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Удалить аккаунт", role: .destructive) {
                    accountActionStarted = true
                    Task { @MainActor in _ = await app.account.deleteAccount() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Аккаунт и сохранённое на сервере избранное будут удалены без возможности восстановления.")
            }
        }
        .tint(SeruColor.action)
        .interactiveDismissDisabled(app.account.isWorking)
        .sheet(isPresented: $accountOpen) {
            AccountView(requestReset: app.account.user != nil)
        }
        .sheet(isPresented: $journalOpen, onDismiss: {
            if returnToWalk { dismiss() }
        }) {
            JournalView(onOpen: { returnToWalk = true })
        }
    }

    private var nameKey: String { "seru.profile.name." + (app.account.user?.id ?? "guest") }
}
