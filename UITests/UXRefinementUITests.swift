import XCTest

@MainActor
final class UXRefinementUITests: XCTestCase {
    func testJournalArchivesRestoresAndSurvivesRelaunch() throws {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        try openChat(app)
        let input = app.descendants(matching: .any)["chat-input"].firstMatch
        input.tap()
        input.typeText("Тихая прогулка")
        app.buttons["chat-send"].tap()
        XCTAssertTrue(app.staticTexts["assistant-message"].firstMatch.waitForExistence(timeout: 8))
        try tap(app.buttons["chat-journal"])
        XCTAssertTrue(app.navigationBars["Журнал"].waitForExistence(timeout: 5))
        try tap(app.buttons["journal-new-walk"])
        try openChat(app)
        XCTAssertTrue(app.staticTexts["chat-welcome-title"].waitForExistence(timeout: 5))
        try tap(app.buttons["chat-journal"])
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journal-entry-")).firstMatch
        try tap(entry)
        XCTAssertTrue(app.staticTexts["Тихая прогулка"].waitForExistence(timeout: 5))
        input.tap()
        input.typeText("А потом кофе")
        capture("journal-restored-chat", app)
        app.terminate()
        app.launch()
        try openChat(app)
        XCTAssertTrue(app.staticTexts["Тихая прогулка"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "А потом кофе")
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat-recommendation-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let layout = XCTAttachment(string: app.debugDescription)
        layout.name = "journal-layout-hierarchy"
        layout.lifetime = .keepAlways
        add(layout)
        capture("journal-cold-restore", app)
        XCTAssertGreaterThanOrEqual(card.frame.minX, app.frame.minX + 14)
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX - 14)
    }

    func testRemovingFavoriteCanBeUndoneAndProfileHasJournal() throws {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        try tap(app.tabBars.buttons["Избранное"])
        try tap(app.buttons["Удалить Ботанический сад Астаны из избранного"])
        XCTAssertFalse(app.buttons["saved-place-garden"].exists)
        try tap(app.buttons["saved-undo"])
        XCTAssertTrue(app.buttons["saved-place-garden"].waitForExistence(timeout: 4))
        try tap(app.buttons["saved-sign-in"])
        XCTAssertTrue(app.navigationBars["Профиль"].waitForExistence(timeout: 5))
        try tap(app.buttons["profile-journal"])
        XCTAssertTrue(app.navigationBars["Журнал"].waitForExistence(timeout: 5))
        capture("profile-journal-empty", app)
        try tap(app.buttons["journal-new-walk"])
        XCTAssertTrue(app.tabBars.buttons["Прогулка"].isSelected)
        XCTAssertFalse(app.navigationBars["Профиль"].exists)
    }

    func testEventsProfileDatesAndProviderLinkWithoutSaveOrCalendar() throws {
        try verifyEventProvider(theme: "dark")
    }

    func testEventsProviderLinkLight() throws {
        try verifyEventProvider(theme: "light")
    }

    private func verifyEventProvider(theme: String) throws {
        let app = makeApp(theme: theme)
        app.launch()
        defer { app.terminate() }
        try tap(app.tabBars.buttons["События"])
        try tap(app.buttons["events-profile"])
        XCTAssertTrue(app.navigationBars["Профиль"].waitForExistence(timeout: 5))
        try tap(app.navigationBars.buttons["Готово"])
        try tap(app.buttons["Выбрать дату"])
        XCTAssertTrue(app.datePickers["events-date-picker"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["events-date-picker"].exists)
        try tap(app.navigationBars.buttons["Закрыть"])
        XCTAssertTrue(app.buttons["Выбрать дату"].waitForExistence(timeout: 5))
        capture("event-guide-feed-\(theme)", app)
        try tap(app.buttons["event-detail-jazz"])
        XCTAssertTrue(app.navigationBars["Событие"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["event-save-jazz"].exists)
        XCTAssertTrue(app.buttons["event-venue-map"].exists)
        capture("event-improved-detail", app)
        XCTAssertFalse(app.buttons["event-add-calendar"].exists)
        let provider = app.descendants(matching: .any)["event-provider-link-jazz"].firstMatch
        for _ in 0..<4 {
            if provider.exists && provider.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(provider.exists && provider.isHittable)
        XCTAssertTrue(provider.label.contains("Sxodim"))
        capture("event-provider-action", app)
    }

    func testPlanStopEditorCanRemoveTheOnlyStop() throws {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        try openChat(app)
        try tap(app.buttons["open-current-plan"])
        try tap(app.buttons["plan-edit-stops"])
        XCTAssertTrue(app.navigationBars["Остановки"].waitForExistence(timeout: 5))
        capture("plan-stop-editor", app)
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan-remove-")).firstMatch
        try tap(remove)
        try tap(app.navigationBars.buttons["Готово"])
        XCTAssertTrue(app.staticTexts["В плане пока нет остановок"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plan-open-full-route"].exists)
        capture("plan-after-stop-removal", app)
    }

    private func makeApp(theme: String = "dark") -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", theme,
                                "-seru.origin", "Байтерек", "-seru.saved.places", "(garden)",
                                "-seru.journal.storeID", UUID().uuidString]
        return app
    }

    private func openChat(_ app: XCUIApplication) throws {
        let handle = app.buttons["panel-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 8))
        for _ in 0..<2 {
            if handle.value as? String == "Полностью" { break }
            try tap(handle)
        }
        XCTAssertTrue(app.buttons["chat-options"].waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed, file: file, line: line)
        element.tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
