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
        XCTAssertTrue(app.descendants(matching: .any)["plan-map-preview"].firstMatch.exists)
        capture("plan-design-\(theme)-\(largeText)", app)
        let layout = XCTAttachment(string: app.debugDescription)
        layout.name = "plan-layout-\(theme)-\(largeText)"
        layout.lifetime = .keepAlways
        add(layout)
        let stop = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan-stop-")).firstMatch
        try reveal(stop, app)
        XCTAssertTrue(stop.isHittable)
        if largeText { capture("plan-stops-accessibility", app) }
        let mapButton = app.buttons["plan-route"]
        for _ in 0..<6 {
            if mapButton.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        try tap(mapButton)
        XCTAssertTrue(app.staticTexts["route-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["map-background"].firstMatch.exists)
        capture("route-map-design-\(theme)-\(largeText)", app)
        let apple = app.buttons["route-open-apple"]
        try reveal(apple, app)
        XCTAssertTrue(apple.isHittable)
        capture("route-actions-\(theme)-\(largeText)", app)
        try tap(app.buttons["walk-back"])
        XCTAssertTrue(app.staticTexts["Твоя прогулка"].waitForExistence(timeout: 5))
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
