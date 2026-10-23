import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var resetToken: String
    @State private var validationError: String?
    @State private var submitted = false
    @FocusState private var focusedField: Field?

    private enum Mode {
        case signIn, register, requestReset, confirmReset

        var title: String {
            switch self {
            case .signIn: "Вход"
            case .register: "Создать аккаунт"
            case .requestReset: "Сброс пароля"
            case .confirmReset: "Новый пароль"
            }
        }

        var action: String {
            switch self {
            case .signIn: "Войти"
            case .register: "Создать аккаунт"
            case .requestReset: "Отправить ссылку"
            case .confirmReset: "Сохранить пароль"
            }
        }
    }

    private enum Field: Hashable {
        case name, email, password, confirmation, token
    }

    init(resetToken: String? = nil) {
        // A supplied token seeds this form once; edits remain local to the sheet.
        _resetToken = State(initialValue: resetToken ?? "")
        _mode = State(initialValue: resetToken == nil ? .signIn : .confirmReset)
    }

    var body: some View {
        NavigationStack {
            Form {
                credentials
                feedback
                Section {
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            Spacer(minLength: 0)
                            if isBusy { ProgressView().tint(SeruColor.onAction) }
                            Text(mode.action).fontWeight(.semibold)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                    }
                    .foregroundStyle(SeruColor.onAction)
                    .listRowBackground(SeruColor.action)
                    .disabled(isBusy || recoveryUnavailable)
                    .accessibilityIdentifier("account-submit")
                }
                alternatives
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(SeruColor.background)
            .foregroundStyle(SeruColor.ink)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
        }
        .tint(SeruColor.action)
    }

    @ViewBuilder
    private var credentials: some View {
        Section {
            if mode == .register {
                TextField("Имя", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
                    .accessibilityIdentifier("account-name")
            }
            if mode != .confirmReset {
                TextField("Почта", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(mode == .requestReset ? .emailAddress : .username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(mode == .requestReset ? .send : .next)
                    .onSubmit {
                        if mode == .requestReset { submit() }
                        else { focusedField = .password }
                    }
                    .accessibilityIdentifier("account-email")
            } else {
                TextField("Ссылка или код из письма", text: $resetToken, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .token)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .lineLimit(1...3)
                    .privacySensitive()
                    .accessibilityIdentifier("account-reset-token")
            }
            if mode != .requestReset {
                SecureField("Пароль", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(mode == .signIn ? .go : .next)
                    .onSubmit {
                        if mode == .signIn { submit() }
                        else { focusedField = .confirmation }
                    }
                    .accessibilityIdentifier("account-password")
                if mode == .register || mode == .confirmReset {
                    SecureField("Повторите пароль", text: $passwordConfirmation)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .confirmation)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .accessibilityIdentifier("account-password-confirm")
                }
            }
        } footer: {
            switch mode {
            case .register, .confirmReset:
                Text("Не менее 8 символов.")
            case .requestReset:
                Text(recoveryUnavailable
                     ? "Восстановление по почте временно недоступно. Если ссылка у вас уже есть, используйте её ниже."
                     : "Пришлём ссылку для нового пароля, если эта почта зарегистрирована.")
            case .signIn:
                EmptyView()
            }
        }
        .disabled(isBusy)
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = validationError ?? (submitted ? app.account.error : nil) {
            Section {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(message)
                    .accessibilityIdentifier("account-error")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        if submitted, validationError == nil, app.account.error == nil, let notice = app.account.notice {
            Section {
                Label(notice, systemImage: "checkmark.circle")
                    .foregroundStyle(SeruColor.action)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(notice)
                    .accessibilityIdentifier("account-notice")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var alternatives: some View {
        Section {
            switch mode {
            case .signIn:
                Button("Создать аккаунт") { changeMode(.register) }
                    .accessibilityIdentifier("account-mode-register")
                Button("Забыли пароль?") { changeMode(.requestReset) }
                    .accessibilityIdentifier("account-forgot-password")
            case .register:
                Button("Уже есть аккаунт? Войти") { changeMode(.signIn) }
                    .accessibilityIdentifier("account-mode-login")
            case .requestReset:
                Button("Уже есть ссылка?") { changeMode(.confirmReset) }
                Button("Вернуться ко входу") { changeMode(.signIn) }
                    .accessibilityIdentifier("account-mode-login")
            case .confirmReset:
                Button("Запросить новую ссылку") { changeMode(.requestReset) }
                    .accessibilityIdentifier("account-forgot-password")
                Button("Вернуться ко входу") { changeMode(.signIn) }
                    .accessibilityIdentifier("account-mode-login")
            }
        }
        .disabled(isBusy)
    }

    private var isBusy: Bool {
        app.account.isWorking || app.account.isRestoring
    }

    private var recoveryUnavailable: Bool {
        mode == .requestReset && !app.account.passwordResetAvailable
    }

    private func changeMode(_ newMode: Mode) {
        focusedField = nil
        mode = newMode
        validationError = nil
        submitted = false
        password = ""
        passwordConfirmation = ""
    }

    private func submit() {
        guard !isBusy, !recoveryUnavailable else { return }
        validationError = validate()
        guard validationError == nil else { return }
        focusedField = nil
        submitted = true
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            switch mode {
            case .signIn:
                if await app.account.signIn(email: cleanEmail, password: password) { dismiss() }
            case .register:
                if await app.account.register(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: cleanEmail, password: password) { dismiss() }
            case .requestReset:
                _ = await app.account.requestPasswordReset(email: cleanEmail)
            case .confirmReset:
                guard let token = normalizedToken else { return }
                if await app.account.confirmPasswordReset(token: token, password: password) {
                    password = ""
                    passwordConfirmation = ""
                    resetToken = ""
                    dismiss()
                }
            }
        }
    }

    private func validate() -> String? {
        if mode == .register {
            let count = name.trimmingCharacters(in: .whitespacesAndNewlines).count
            if !(2...80).contains(count) { return "Введите имя от 2 до 80 символов." }
        }
        if mode != .confirmReset {
            let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleanEmail.split(separator: "@", omittingEmptySubsequences: false)
            if parts.count != 2 || parts.contains(where: \.isEmpty) || cleanEmail.contains(where: \.isWhitespace) {
                return "Введите почту в формате name@example.com."
            }
        }
        if mode == .confirmReset, normalizedToken == nil { return "Вставьте код или ссылку из письма Серу." }
        if mode == .signIn, password.isEmpty { return "Введите пароль." }
        if mode == .register || mode == .confirmReset {
            if password.count < 8 { return "В пароле должно быть не менее 8 символов." }
            if password != passwordConfirmation { return "Пароли не совпадают." }
        }
        return nil
    }

    private var normalizedToken: String? {
        let value = resetToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 8_192 else { return nil }
        if value.contains("://") {
            guard let url = URL(string: value) else { return nil }
            return PasswordResetLink.token(from: url)
        }
        guard (20...200).contains(value.count),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return nil }
        return value
    }
}
