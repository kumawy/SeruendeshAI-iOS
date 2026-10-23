import Foundation
import XCTest
import UIKit

@MainActor
final class AccountUITests: XCTestCase {
    func testAccountLifecycleAndPersistentSession() async throws {
        continueAfterFailure = true
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let email = "seru-ios-qa-\(suffix)@example.com"
        let password = "seruqapassword\(suffix)"
        let name = "Проверка iOS"
        // Runs even if registration succeeded on the server but the following UI assertion failed.
        // Cleanup uses the native session first, then independent API credentials if needed.
        addTeardownBlock { [email, password] in
            try await Self.removeDisposableAccount(email: email, password: password)
        }

        try await Self.createDisposableAccount(email: email, password: password, name: name)
        let app = makeApp()
        app.launch()
        defer {
            cleanupVisibleDisposableAccount(email: email, in: app)
            app.terminate()
        }
        try openGuestProfile(app)
        try tap(app.buttons["profile-sign-in"], in: app)
        try require(element("account-email", in: app), in: app)
        capture("account-login-dark", app: app)
        try enter(email, into: "account-email", in: app)
        try enter(password, into: "account-password", in: app)
        try tap(app.buttons["account-submit"], in: app)
        try requireProfile(name: name, email: email, in: app)
        capture("account-profile-dark", app: app)

        let savedID = "ov:aa93675a-1cbe-46"
        try await Self.seedDisposableFavorite(email: email, password: password, poiID: savedID)

        app.terminate()
        app.launch()
        try openProfile(app)
        try requireProfile(name: name, email: email, in: app)
        try tap(app.navigationBars.buttons["Готово"], in: app)
        try selectTab(symbol: "heart", label: "Избранное", in: app)
        try require(app.staticTexts["saved-title"], in: app)
        let syncedFavorite = app.buttons["saved-place-\(savedID)"]
        try require(syncedFavorite, timeout: 30, in: app)
        XCTAssertTrue(syncedFavorite.label.contains("Проверка синхронизации"))
        capture("account-saved-dark", app: app)
        try selectTab(symbol: "safari", label: "Прогулка", in: app)
        try openProfile(app)
        try tap(app.buttons["account-logout"], in: app)
        try requireEnabled(app.buttons["profile-sign-in"], in: app)
        XCTAssertFalse(element("profile-user-email", in: app).exists)
        capture("account-logged-out-dark", app: app)

        try tap(app.buttons["profile-sign-in"], in: app)
        try enter(email, into: "account-email", in: app)
        try enter(password, into: "account-password", in: app)
        try tap(app.buttons["account-submit"], in: app)
        try requireProfile(name: name, email: email, in: app)
        try deleteVisibleOwnedAccount(email: email, in: app)
        XCTAssertFalse(element("profile-user-email", in: app).exists)
    }

    func testNativeRegistrationAndDeletion() async throws {
        continueAfterFailure = true
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let email = "seru-ios-qa-\(suffix)@example.com"
        let password = "seruregister\(suffix)"
        let name = "Новый участник"
        addTeardownBlock { [email, password] in
            try await Self.removeDisposableAccount(email: email, password: password)
        }
        let app = makeApp()
        app.launch()
        defer {
            cleanupVisibleDisposableAccount(email: email, in: app)
            app.terminate()
        }
        try openGuestProfile(app)
        try tap(app.buttons["profile-sign-in"], in: app)
        try tap(app.buttons["account-mode-register"], in: app)
        try enter(name, into: "account-name", in: app)
        try enter(email, into: "account-email", in: app)
        try enter(password, into: "account-password", in: app)
        try enter(password, into: "account-password-confirm", in: app)
        capture("account-register-dark", app: app)
        try tap(app.buttons["account-submit"], in: app)
        try requireProfile(name: name, email: email, in: app)
        guard let verified = try await Self.disposableSession(email: email, password: password) else {
            XCTFail("The newly registered credentials could not sign in independently.")
            throw AccountUIFailure.inputMismatch
        }
        verified.invalidateAndCancel()
        app.terminate()
        app.launch()
        try openProfile(app)
        try requireProfile(name: name, email: email, in: app)
        capture("account-registered-restored-dark", app: app)
        try deleteVisibleOwnedAccount(email: email, in: app)
    }

    func testRegistrationValidationAndUnavailableEmailRecovery() throws {
        continueAfterFailure = true
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        try openGuestProfile(app)
        try tap(app.buttons["profile-sign-in"], in: app)
        try tap(app.buttons["account-mode-register"], in: app)
        try enter("Проверка формы", into: "account-name", in: app)
        try enter("form-check@example.com", into: "account-email", in: app)
        try enter("short", into: "account-password", in: app)
        try enter("short", into: "account-password-confirm", in: app)
        try tap(app.buttons["account-submit"], in: app)
        try require(element("account-error", in: app), in: app)
        XCTAssertTrue(element("account-error", in: app).label.contains("не менее 8"), "Validation message: \(element("account-error", in: app).label)")

        try replace("short", with: "LongEnough!123", in: "account-password", app: app)
        try tap(app.buttons["account-submit"], in: app)
        try require(element("account-error", in: app), in: app)
        XCTAssertTrue(element("account-error", in: app).label.contains("не совпадают"), "Validation message: \(element("account-error", in: app).label)")
        capture("account-validation-dark", app: app)

        try tap(app.buttons["account-mode-login"], in: app)
        try tap(app.buttons["account-forgot-password"], in: app)
        try require(app.staticTexts[
            "Восстановление по почте временно недоступно. Если ссылка у вас уже есть, используйте её ниже."
        ], timeout: 30, in: app)
        XCTAssertFalse(app.buttons["account-submit"].isEnabled)
        capture("account-recovery-unavailable-dark", app: app)
        // Never submit a password-reset request in a live test: that endpoint may send email.
        try tap(app.buttons["Уже есть ссылка?"], in: app)
        try require(element("account-reset-token", in: app), in: app)
        try require(element("account-password-confirm", in: app), in: app)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "live", "-seru.theme", "dark", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private func openProfile(_ app: XCUIApplication) throws {
        try tap(app.buttons["Профиль и настройки"], in: app)
        try require(app.navigationBars["Профиль"], in: app)
    }

    private func openGuestProfile(_ app: XCUIApplication) throws {
        try openProfile(app)
        let userEmail = element("profile-user-email", in: app)
        if userEmail.exists {
            let email = userEmail.label
            guard Self.isDisposableEmail(email) else {
                XCTFail("An unexpected account is signed in. Refusing to change or delete it.")
                throw AccountUIFailure.unexpectedAccount
            }
            try deleteVisibleOwnedAccount(email: email, in: app)
        }
        try requireEnabled(app.buttons["profile-sign-in"], in: app)
    }

    private func selectTab(symbol: String, label: String, in app: XCUIApplication) throws {
        let symbolButton = app.buttons[symbol]
        try tap(symbolButton.exists ? symbolButton : app.tabBars.buttons[label], in: app)
    }

    private func deleteVisibleOwnedAccount(email: String, in app: XCUIApplication) throws {
        guard Self.isDisposableEmail(email), element("profile-user-email", in: app).label == email else {
            throw AccountUIFailure.unexpectedAccount
        }
        try tap(app.buttons["account-delete"], in: app)
        let confirmation = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Удалить аккаунт", "account-delete"
        )).firstMatch
        try tap(confirmation, in: app)
        try requireEnabled(app.buttons["profile-sign-in"], in: app)
    }

    private func requireProfile(name: String, email: String, in app: XCUIApplication) throws {
        let emailElement = element("profile-user-email", in: app)
        guard emailElement.waitForExistence(timeout: 35) else {
            let message = element("account-error", in: app).exists ? element("account-error", in: app).label : "No visible account error"
            capture("account-failure", app: app)
            XCTFail("Authentication failed: \(message)")
            throw AccountUIFailure.elementUnavailable
        }
        XCTAssertEqual(element("profile-user-name", in: app).label, name)
        XCTAssertEqual(emailElement.label, email)
        XCTAssertFalse(element("account-error", in: app).exists)
    }

    private func enter(_ text: String, into identifier: String, in app: XCUIApplication) throws {
        let field = element(identifier, in: app)
        try tap(field, in: app)
        let previous = UIPasteboard.general.items
        UIPasteboard.general.string = text
        defer { UIPasteboard.general.items = previous }
        field.press(forDuration: 1.1)
        let selectAll = editMenu(["Select All", "Выбрать все"], in: app)
        if selectAll.exists { selectAll.tap() }
        let paste = editMenu(["Paste", "Вставить"], in: app)
        guard paste.waitForExistence(timeout: 5) else {
            capture("account-paste-unavailable", app: app)
            throw AccountUIFailure.inputMismatch
        }
        paste.tap()
    }

    private func replace(_ oldText: String, with newText: String, in identifier: String, app: XCUIApplication) throws {
        try enter(newText, into: identifier, in: app)
    }

    private func editMenu(_ labels: [String], in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label IN %@", labels)
        let menu = app.menuItems.matching(predicate).firstMatch
        return menu.exists ? menu : app.buttons.matching(predicate).firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func requireEnabled(_ element: XCUIElement, in app: XCUIApplication) throws {
        try require(element, timeout: 35, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        guard XCTWaiter.wait(for: [enabled], timeout: 35) == .completed else {
            capture("account-disabled-element", app: app)
            throw AccountUIFailure.elementUnavailable
        }
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval = 15, in app: XCUIApplication) throws {
        guard element.waitForExistence(timeout: timeout) else {
            capture("account-failure", app: app)
            XCTFail("Expected account UI element: \(element)")
            throw AccountUIFailure.elementUnavailable
        }
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        try require(element, in: app)
        if !element.isHittable {
            for _ in 0..<5 {
                if element.isHittable { break }
                app.swipeUp()
            }
        }
        guard element.isHittable else {
            capture("account-unreachable-element", app: app)
            XCTFail("Account UI element is not reachable: \(element)")
            throw AccountUIFailure.elementUnavailable
        }
        element.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func cleanupVisibleDisposableAccount(email: String, in app: XCUIApplication) {
        guard Self.isDisposableEmail(email) else { return }
        // UI cleanup runs inside the test, before XCTest ends its UI session.
        app.terminate()
        app.launch()
        let profile = app.buttons["Профиль и настройки"]
        guard profile.waitForExistence(timeout: 10) else { return }
        profile.tap()
        let visible = element("profile-user-email", in: app)
        guard visible.waitForExistence(timeout: 2), visible.label == email else { return }
        let deletion = app.buttons["account-delete"]
        guard deletion.waitForExistence(timeout: 10), deletion.isEnabled else { return }
        deletion.tap()
        let confirmation = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Удалить аккаунт", "account-delete"
        )).firstMatch
        guard confirmation.waitForExistence(timeout: 10) else { return }
        confirmation.tap()
        _ = app.buttons["profile-sign-in"].waitForExistence(timeout: 20)
    }

    private static func removeDisposableAccount(email: String, password: String) async throws {
        guard isDisposableEmail(email), let session = try await disposableSession(email: email, password: password) else { return }
        defer { session.invalidateAndCancel() }
        var deletion = URLRequest(url: URL(string: "https://seruendesh.site/api/me")!)
        deletion.httpMethod = "DELETE"
        let (_, deleted) = try await session.data(for: deletion)
        guard (deleted as? HTTPURLResponse)?.statusCode == 204 else {
            XCTFail("Could not delete the disposable test account after the UI test.")
            throw AccountUIFailure.cleanupFailed
        }
    }

    private static func isDisposableEmail(_ email: String) -> Bool {
        email.range(of: "^seru-ios-qa-[a-f0-9]{32}@example\\.com$", options: .regularExpression) != nil
    }

    private static func createDisposableAccount(email: String, password: String, name: String) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://seruendesh.site/api/auth/register")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "email": email, "password": password, "lang": "ru"])
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            XCTFail("Could not create the temporary account for the sign-in test.")
            throw AccountUIFailure.cleanupFailed
        }
    }

    private static func seedDisposableFavorite(email: String, password: String, poiID: String) async throws {
        guard let session = try await disposableSession(email: email, password: password) else {
            throw AccountUIFailure.cleanupFailed
        }
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://seruendesh.site/api/me/saved")!.appendingPathComponent(poiID)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": [
            "name": "Проверка синхронизации",
            "category": "Кофейня",
            "address": "Астана",
            "lat": 51.129,
            "lon": 71.431,
            "why": "Временная запись проверки iOS в тестовом аккаунте."
        ]])
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            XCTFail("Could not save the temporary account's synchronization fixture.")
            throw AccountUIFailure.cleanupFailed
        }
    }

    private static func disposableSession(email: String, password: String) async throws -> URLSession? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        let session = URLSession(configuration: config)
        var login = URLRequest(url: URL(string: "https://seruendesh.site/api/auth/login")!)
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (_, response) = try await session.data(for: login)
        guard let loginResponse = response as? HTTPURLResponse else { throw AccountUIFailure.cleanupFailed }
        // A completed UI deletion leaves no account to clean up; invalid credentials are expected.
        if loginResponse.statusCode == 401 {
            session.invalidateAndCancel()
            return nil
        }
        guard loginResponse.statusCode == 200 else {
            XCTFail("Could not authenticate the disposable test account for cleanup (HTTP \(loginResponse.statusCode)).")
            throw AccountUIFailure.cleanupFailed
        }
        return session
    }

    private enum AccountUIFailure: Error {
        case elementUnavailable, cleanupFailed, unexpectedAccount, inputMismatch
    }
}
