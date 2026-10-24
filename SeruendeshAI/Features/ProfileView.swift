import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var accountOpen = false
    @State private var confirmDeletion = false
    @State private var accountActionStarted = false
    @State private var journalOpen = false
    @State private var returnToWalk = false
    @State private var localName = ""
    @State private var nameEditorOpen = false
    @State private var editedName = ""
    @State private var photoCreditsOpen = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    identity

                    journalButton

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Оформление")
                            .font(.subheadline)
                            .foregroundStyle(SeruColor.muted)
                            .accessibilityAddTraits(.isHeader)
                        ProfileThemeSelector(selection: $app.theme)
                    }

                    if app.usesBackend, app.account.user == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Аккаунт")
                                .font(.subheadline)
                                .foregroundStyle(SeruColor.muted)
                                .accessibilityAddTraits(.isHeader)
                            Button { accountOpen = true } label: {
                                ProfileActionLabel(title: "Войти или создать аккаунт", showsChevron: true)
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

                    Text("Журнал, фотографии и избранные места хранятся на этом устройстве. Они сохраняются между запусками и не синхронизируются с аккаунтом.")
                        .font(.footnote)
                        .foregroundStyle(SeruColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile-local-storage")

                    Button { photoCreditsOpen = true } label: {
                        ProfileActionLabel(title: "Фотографии", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile-photo-credits")
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("profile-content")
            .accessibilityValue(colorScheme == .dark ? "Тёмная тема" : "Светлая тема")
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
        .preferredColorScheme(app.theme == .system ? nil : app.theme == .dark ? .dark : .light)
        .interactiveDismissDisabled(app.account.isWorking)
        .sheet(isPresented: $accountOpen) {
            AccountView(requestReset: app.account.user != nil)
        }
        .sheet(isPresented: $journalOpen, onDismiss: {
            if returnToWalk { dismiss() }
        }) {
            JournalView(onOpen: { returnToWalk = true })
        }
        .sheet(isPresented: $photoCreditsOpen) {
            PhotoCreditsView()
        }
    }

    private var displayName: String {
        localName.isEmpty ? (app.account.user?.name ?? "Гость") : localName
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(SeruColor.surface)
                if !localName.isEmpty || app.account.user?.name.isEmpty == false {
                    Text(displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                        .font(.title3.weight(.medium))
                        .foregroundStyle(SeruColor.ink)
                } else {
                    Image(systemName: "person")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(SeruColor.muted)
                }
            }
            .frame(width: 52, height: 52)
            .overlay(Circle().strokeBorder(SeruColor.line, lineWidth: 1))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
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
                    Text(localName.isEmpty ? "Добавить имя" : "Изменить имя")
                        .font(.subheadline)
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
        VStack(spacing: 0) {
            Divider().overlay(SeruColor.line)
            Button { journalOpen = true } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Журнал прогулок").font(.body.weight(.medium))
                        Text("Переписка, фото и планы")
                            .font(.footnote)
                            .foregroundStyle(SeruColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeruColor.muted)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(SeruColor.ink)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-journal")
            Divider().overlay(SeruColor.line)
        }
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Аккаунт")
                .font(.subheadline)
                .foregroundStyle(SeruColor.muted)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
            Button { accountOpen = true } label: {
                ProfileActionLabel(title: "Сменить пароль", showsChevron: true)
            }
            .accessibilityIdentifier("profile-reset-password")
            Divider().overlay(SeruColor.line)
            Button {
                accountActionStarted = true
                Task { @MainActor in _ = await app.account.signOut() }
            } label: {
                HStack {
                    ProfileActionLabel(title: "Выйти из аккаунта")
                    if app.account.isWorking { ProgressView() }
                }
            }
            .disabled(app.account.isWorking || app.account.isRestoring)
            .accessibilityIdentifier("account-logout")
            Divider().overlay(SeruColor.line)
            Button(role: .destructive) { confirmDeletion = true } label: {
                ProfileActionLabel(title: "Удалить аккаунт", isDestructive: true)
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
    var showsChevron = false
    var isDestructive = false

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeruColor.muted)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isDestructive ? Color.red : SeruColor.ink)
        .padding(.vertical, 12)
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
                VStack(spacing: 0) {
                    ForEach(AppTheme.allCases) { theme in
                        accessibleOption(theme)
                        if theme != AppTheme.allCases.last {
                            Divider().overlay(SeruColor.line)
                        }
                    }
                }
            } else {
                Picker("Тема", selection: $selection) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme == .system ? "Авто" : theme.title)
                            .tag(theme)
                            .accessibilityIdentifier("profile-theme-\(theme.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .frame(minHeight: 44)
                .accessibilityIdentifier("profile-theme-picker")
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func accessibleOption(_ theme: AppTheme) -> some View {
        Button { selection = theme } label: {
            HStack(spacing: 16) {
                Text(theme.title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if selection == theme {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SeruColor.action)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(SeruColor.ink)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selection == theme ? .isSelected : [])
        .accessibilityIdentifier("profile-theme-\(theme.rawValue)")
    }
}
