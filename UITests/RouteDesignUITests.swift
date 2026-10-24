import XCTest

@MainActor
final class RouteDesignUITests: XCTestCase {
    func testPlanAndMapDark() throws { try verifyPlan(theme: "dark") }
    func testPlanAndMapLight() throws { try verifyPlan(theme: "light") }
    func testPlanWithAccessibilityText() throws { try verifyPlan(theme: "dark", largeText: true) }

    private func verifyPlan(theme: String, largeText: Bool = false) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", theme,
                                "-seru.origin", "Байтерек", "-seru.journal.storeID", UUID().uuidString]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        defer { app.terminate() }
        try tap(app.buttons["panel-handle"])
        try tap(app.buttons["panel-handle"])
        capture("chat-toolbar-\(theme)-\(largeText)", app)
        try tap(app.buttons["open-current-plan"])
        XCTAssertTrue(app.staticTexts["Твоя прогулка"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["map-background"].firstMatch.exists)
        capture("unified-plan-\(theme)-\(largeText)", app)
        let toggle = app.buttons["plan-toggle-view"]
        if !largeText { try tap(toggle) }
        let stop = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan-stop-")).firstMatch
        try reveal(stop, app)
        XCTAssertTrue(stop.isHittable)
        capture("unified-stops-\(theme)-\(largeText)", app)
        if theme == "dark" && !largeText {
            try tap(stop)
            XCTAssertTrue(app.buttons["build-route"].waitForExistence(timeout: 5))
            try tap(app.buttons["walk-back"])
            XCTAssertEqual(toggle.label, "Показать карту прогулки", "Returning from a stop must preserve the expanded list")
        }
        XCTAssertFalse(app.staticTexts["route-title"].exists, "Viewing stops must not push a duplicate route screen")
        try tap(toggle)
        XCTAssertTrue(app.descendants(matching: .any)["map-background"].firstMatch.exists)
        capture("unified-map-\(theme)-\(largeText)", app)
        try tap(toggle)
        let apple = app.buttons["plan-open-full-route"]
        try reveal(apple, app)
        XCTAssertTrue(apple.isHittable)
        capture("route-actions-\(theme)-\(largeText)", app)
        try tap(app.buttons["walk-back"])
        XCTAssertTrue(app.buttons["chat-options"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func tap(_ element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed)
        element.tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
