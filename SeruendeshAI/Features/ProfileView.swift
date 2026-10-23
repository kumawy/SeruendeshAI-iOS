import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var accountOpen = false
    @State private var confirmDeletion = false
    @State private var accountActionStarted = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarPlaceholder(size: 48).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.account.user?.name ?? "Моя прогулка")
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
                }
                Section("Оформление") {
                    Picker("Тема", selection: $app.theme) {
                        ForEach(AppTheme.allCases) { theme in Text(theme.title).tag(theme) }
                    }
                }
                if app.account.user != nil {
                    Section {
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
            AccountView()
        }
    }
}
