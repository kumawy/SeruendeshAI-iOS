import XCTest

@MainActor
final class SavedMascotUITests: XCTestCase {
    func testEmptyBoxKeepsAnimatingAcrossLoopAndTabChanges() async throws {
        let app = makeApp(theme: "light")
        app.launch()
        defer { app.terminate() }
        let mascot = try openFavorites(app)
        try await Task.sleep(for: .seconds(1))
        let first = mascot.screenshot()
        attach(first, name: "empty-box-native-first")
        try await Task.sleep(for: .seconds(1.15))
        let second = mascot.screenshot()
        attach(second, name: "empty-box-native-shake")
        XCTAssertNotEqual(first.pngRepresentation, second.pngRepresentation,
                          "The mascot must animate after its initial assets have loaded")
        try await Task.sleep(for: .seconds(5.8))
        let nextLoop = mascot.screenshot()
        attach(nextLoop, name: "empty-box-native-next-loop")
        XCTAssertNotEqual(second.pngRepresentation, nextLoop.pngRepresentation,
                          "The frame player must continue beyond one six-second cycle")
        attach(app.screenshot(), name: "empty-box-native-light")

        app.tabBars.buttons["События"].tap()
        XCTAssertTrue(app.tabBars.buttons["События"].isSelected)
        let resumed = try openFavorites(app)
        try await Task.sleep(for: .seconds(0.8))
        let resumedFirst = resumed.screenshot().pngRepresentation
        try await Task.sleep(for: .seconds(0.65))
        XCTAssertNotEqual(resumedFirst, resumed.screenshot().pngRepresentation,
                          "Playback must resume when Favorites becomes visible again")
        app.buttons["saved-empty-discover"].tap()
        XCTAssertTrue(app.tabBars.buttons["Прогулка"].isSelected)
    }

    func testEmptyBoxReduceMotionKeepsPosterStill() async throws {
        let app = makeApp(theme: "dark")
        app.launchArguments += ["-seru.emptyBox.reduceMotion"]
        app.launch()
        defer { app.terminate() }
        let mascot = try openFavorites(app)
        try await Task.sleep(for: .seconds(0.8))
        let first = mascot.screenshot()
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(first.pngRepresentation, mascot.screenshot().pngRepresentation,
                       "Reduce Motion must display a stable poster")
        attach(first, name: "empty-box-reduce-motion-poster")
        attach(app.screenshot(), name: "empty-box-native-dark")
        app.buttons["saved-empty-discover"].tap()
        XCTAssertTrue(app.tabBars.buttons["Прогулка"].isSelected)
    }

    private func makeApp(theme: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", theme,
                                "-seru.saved.places", "()"]
        return app
    }

    private func openFavorites(_ app: XCUIApplication) throws -> XCUIElement {
        let splash = app.descendants(matching: .any)["seru-splash-overlay"].firstMatch
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: splash)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 12), .completed)
        let tab = app.tabBars.buttons["Избранное"]
        XCTAssertTrue(tab.waitForExistence(timeout: 12))
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 8), .completed)
        tab.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let mascot = app.descendants(matching: .any)["saved-empty-mascot"].firstMatch
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saved-empty-discover"].isHittable)
        return mascot
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
