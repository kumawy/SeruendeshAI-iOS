import XCTest

@MainActor
final class ProfilePolishUITests: XCTestCase {
    func testProfileNameAndThemePersistWithReachableJournalAndClose() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark",
                                "-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try openProfile(app)
        let close = app.navigationBars.buttons["Готово"]
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        XCTAssertTrue(app.buttons["profile-journal"].isHittable)
        capture("profile-refined-dark", app)

        try tap(app.buttons["profile-edit-name"])
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        let oldName = nameField.value as? String ?? ""
        if oldName != "Имя" {
            nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count))
        }
        nameField.typeText("Алина")
        try tap(app.alerts.buttons["Сохранить"])
        XCTAssertEqual(app.staticTexts["profile-user-name"].label, "Алина")

        try tap(app.buttons["profile-theme-light"])
        XCTAssertTrue(app.buttons["profile-theme-light"].isSelected)
        capture("profile-refined-light", app)
        try tap(close)
        try tap(app.buttons["saved-sign-in"])
        XCTAssertEqual(app.staticTexts["profile-user-name"].label, "Алина")
        XCTAssertTrue(app.buttons["profile-theme-light"].isSelected)

        app.terminate()
        if let index = app.launchArguments.firstIndex(of: "-seru.theme") {
            app.launchArguments.removeSubrange(index...index + 1)
        }
        app.launch()
        try openProfile(app)
        XCTAssertEqual(app.staticTexts["profile-user-name"].label, "Алина")
        XCTAssertTrue(app.buttons["profile-theme-light"].isSelected)

        // Leave the guest name as it was before this simulator test.
        try tap(app.buttons["profile-edit-name"])
        let restoredField = app.alerts.textFields.firstMatch
        XCTAssertTrue(restoredField.waitForExistence(timeout: 3))
        restoredField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Алина".count))
        if oldName != "Имя" { restoredField.typeText(oldName) }
        try tap(app.alerts.buttons["Сохранить"])
        try tap(app.buttons["profile-theme-dark"])
    }

    func testProfileRemainsReadableAtLargestTextSize() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                "-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        try openProfile(app)
        XCTAssertTrue(app.buttons["profile-journal"].isHittable)
        XCTAssertTrue(app.navigationBars.buttons["Готово"].isHittable)
        let theme = app.buttons["profile-theme-light"]
        for _ in 0..<4 {
            if theme.exists && theme.isHittable { break }
            app.scrollViews["profile-content"].swipeUp()
        }
        try tap(theme)
        XCTAssertTrue(theme.isSelected)
        XCTAssertGreaterThanOrEqual(theme.frame.height, 44)
        capture("profile-refined-accessibility", app)
        try tap(app.navigationBars.buttons["Готово"])
    }

    private func openProfile(_ app: XCUIApplication) throws {
        try tap(app.tabBars.buttons["Избранное"])
        try tap(app.buttons["saved-sign-in"])
        XCTAssertTrue(app.navigationBars["Профиль"].waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, file: file, line: line)
        element.tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
