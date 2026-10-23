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
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    identity

                    journalButton

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Оформление")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ProfileThemeSelector(selection: $app.theme)
                    }

                    if app.usesBackend, app.account.user == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Аккаунт")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Button { accountOpen = true } label: {
                                ProfileActionLabel(title: "Войти или создать аккаунт", symbol: "person.badge.plus")
                            }
                            .buttonStyle(.plain)
                            .disabled(app.account.isRestoring)
                            .accessibilityIdentifier("profile-sign-in")
                        }
                    }

                    if app.account.user != nil {
                        accountActions
                    }

                    if let error = app.account.error {
                        accountError(error)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Divider().overlay(SeruColor.line)
                        DisclosureGroup {
                            Text("Прогулки, фото и избранные места сохраняются между запусками. Журнал остаётся на этом устройстве и не синхронизируется с аккаунтом.")
                                .font(.footnote)
                                .foregroundStyle(SeruColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        } label: {
                            Label("Хранится на устройстве", systemImage: "internaldrive")
                                .font(.subheadline)
                                .foregroundStyle(SeruColor.muted)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("profile-local-storage")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("profile-content")
            .background(SeruColor.background)
            .foregroundStyle(SeruColor.ink)
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SeruColor.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeruColor.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Готово")
                    .accessibilityIdentifier("profile-close")
                    .disabled(app.account.isWorking)
                }
                .sharedBackgroundVisibility(.hidden)
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

    private var displayName: String {
        localName.isEmpty ? (app.account.user?.name ?? "Моя прогулка") : localName
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(SeruColor.field)
                if !localName.isEmpty || app.account.user?.name.isEmpty == false {
                    Text(displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(SeruColor.action)
                } else {
                    Image(systemName: "person")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(SeruColor.action)
                }
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile-user-name")
                if let user = app.account.user {
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(SeruColor.muted)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("profile-user-email")
                }
                Button {
                    editedName = localName
                    nameEditorOpen = true
                } label: {
                    Label(localName.isEmpty ? "Как тебя называть" : "Изменить имя", systemImage: "pencil")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeruColor.action)
                .accessibilityIdentifier("profile-edit-name")
                if app.account.isRestoring {
                    ProgressView("Проверяем аккаунт").font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var journalButton: some View {
        Button { journalOpen = true } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 23, weight: .regular))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Журнал прогулок").font(.headline)
                    Text("Переписка, фото и твои планы")
                        .font(.subheadline)
                        .foregroundStyle(SeruColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(SeruColor.ink)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(SeruColor.field, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-journal")
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Аккаунт")
                .font(.headline)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            Button { accountOpen = true } label: {
                ProfileActionLabel(title: "Сменить пароль", symbol: "key")
            }
            .accessibilityIdentifier("profile-reset-password")
            Button {
                accountActionStarted = true
                Task { @MainActor in _ = await app.account.signOut() }
            } label: {
                HStack {
                    ProfileActionLabel(title: "Выйти из аккаунта", symbol: "rectangle.portrait.and.arrow.right")
                    if app.account.isWorking { ProgressView() }
                }
            }
            .disabled(app.account.isWorking || app.account.isRestoring)
            .accessibilityIdentifier("account-logout")
            Button(role: .destructive) { confirmDeletion = true } label: {
                ProfileActionLabel(title: "Удалить аккаунт", symbol: "trash", isDestructive: true)
            }
            .disabled(app.account.isWorking || app.account.isRestoring)
            .accessibilityIdentifier("account-delete")
        }
        .buttonStyle(.plain)
    }

    private func accountError(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .disabled(app.account.isWorking || app.account.isRestoring)
                .accessibilityIdentifier("account-restore-retry")
            }
        }
    }

    private var nameKey: String { "seru.profile.name." + (app.account.user?.id ?? "guest") }
}

private struct ProfileActionLabel: View {
    let title: String
    let symbol: String
    var isDestructive = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isDestructive ? Color.red : SeruColor.ink)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(.rect)
    }
}

private struct ProfileThemeSelector: View {
    @Binding var selection: AppTheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in option(theme, horizontal: true) }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in option(theme, horizontal: false) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func option(_ theme: AppTheme, horizontal: Bool) -> some View {
        Button { selection = theme } label: {
            Group {
                if horizontal {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: theme)).accessibilityHidden(true)
                        Text(theme.title).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if selection == theme { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                    .font(.body)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: symbol(for: theme))
                            .font(.system(size: 20, weight: .regular))
                            .accessibilityHidden(true)
                        Text(theme == .system ? "Авто" : theme.title)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(selection == theme ? SeruColor.onAction : SeruColor.ink)
            .background(selection == theme ? SeruColor.action : SeruColor.surface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selection == theme ? Color.clear : SeruColor.line, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selection == theme ? .isSelected : [])
        .accessibilityIdentifier("profile-theme-\(theme.rawValue)")
    }

    private func symbol(for theme: AppTheme) -> String {
        switch theme {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
