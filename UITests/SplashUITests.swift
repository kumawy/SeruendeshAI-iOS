import Foundation
import UIKit
import XCTest

@MainActor
final class SplashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testColdLaunchRevealsWorkingMainScreenInLightTheme() throws {
        try verifyColdLaunch(theme: "light")
    }

    func testColdLaunchRevealsWorkingMainScreenInDarkTheme() throws {
        try verifyColdLaunch(theme: "dark")
    }

    func testReturningFromBackgroundPreservesSelectedScreenWithoutReplayingSplash() throws {
        let app = makeApp(theme: "dark")
        app.launch()
        defer { app.terminate() }
        try waitForMainScreen(in: app)

        try selectTab(label: "События", symbol: "ticket", in: app)
        let search = app.textFields["Поиск событий"]
        try require(search)
        search.tap()
        search.typeText("Steppe")

        XCUIDevice.shared.press(.home)
        app.activate()

        try require(search)
        XCTAssertEqual(search.value as? String, "Steppe",
                       "Returning to the app must preserve the existing screen state")
        try assertNoSplashAppears(in: app, for: 0.8)
        capture("splash-background-return-preserves-events", in: app)
    }

    func testReduceMotionRevealsInteractiveMainScreen() throws {
        let app = makeApp(theme: "dark", reduceMotion: true)
        app.launch()
        defer { app.terminate() }

        // launch() waits for quiescence; coordinator tests verify the real timing.
        try waitForMainScreen(in: app, timeout: 1)
        capture("splash-reduce-motion-completed", in: app)
        try selectTab(label: "События", symbol: "ticket", in: app)
        try require(app.textFields["Поиск событий"])
    }

    func testMissingArtworkSafelyRevealsMainScreen() throws {
        let app = makeApp(theme: "light", missingAssets: true)
        app.launch()
        defer { app.terminate() }

        try waitForMainScreen(in: app, timeout: 1)
        capture("splash-missing-assets-completed", in: app)
        try selectTab(label: "Избранное", symbol: "heart", in: app)
        try require(element("saved-title", in: app))
    }

    func testLandscapeColdLaunchAndRotationKeepMainScreenInteractiveWithoutReplay() throws {
        let app = makeApp(theme: "dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        try waitForMainScreen(in: app)
        XCTAssertTrue(poll(timeout: 3) { app.frame.width > app.frame.height },
                      "The app must support its configured landscape orientation")
        capture("splash-landscape-completed", in: app)

        try selectTab(label: "События", symbol: "ticket", in: app)
        let search = app.textFields["Поиск событий"]
        try require(search)
        XCTAssertTrue(search.isHittable)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(poll(timeout: 3) { app.frame.height > app.frame.width })
        try require(search)
        XCTAssertTrue(search.isHittable,
                      "Rotation must preserve the selected existing screen and its controls")
        try assertNoSplashAppears(in: app, for: 0.8)
        capture("splash-rotation-preserves-events", in: app)

        try selectTab(label: "Прогулка", symbol: "safari", in: app)
        try waitForMainScreen(in: app)
    }

    func testLargestAccessibilityTextSizeRevealsWorkingMainScreen() throws {
        let baseline = makeApp(theme: "light", contentSizeCategory: .large)
        baseline.launch()
        defer { baseline.terminate() }
        try waitForMainScreen(in: baseline)
        let baselineHeading = element("compact-panel", in: baseline)
        try require(baselineHeading)
        let baselineHeadingHeight = baselineHeading.frame.height
        baseline.terminate()

        let app = makeApp(theme: "light", contentSizeCategory: .accessibilityExtraExtraExtraLarge)
        app.launch()
        defer { app.terminate() }
        try waitForMainScreen(in: app)
        let heading = element("compact-panel", in: app)
        try require(heading)
        XCTAssertGreaterThan(heading.frame.height, baselineHeadingHeight * 1.5,
                             "The native text-size preference must actually enlarge the existing heading")
        XCTAssertTrue(heading.isHittable, "The main heading must remain on screen at the largest text size")
        XCTAssertTrue(app.buttons["panel-handle"].isHittable)
        XCTAssertTrue(app.buttons["composer-filters"].isHittable)
        XCTAssertFalse(element("seru-splash-overlay", in: app).exists)
        capture("splash-accessibility-extra-extra-extra-large-completed", in: app)

        try selectTab(label: "События", symbol: "ticket", in: app)
        try require(app.textFields["Поиск событий"])
        try selectTab(label: "Прогулка", symbol: "safari", in: app)
        try waitForMainScreen(in: app)
        app.buttons["Профиль и настройки"].tap()
        try require(app.navigationBars["Профиль"])
        XCTAssertFalse(element("seru-splash-overlay", in: app).exists)
        capture("splash-accessibility-extra-extra-extra-large-profile", in: app)
    }

    func testColdPasswordResetLinkPresentsExistingFormAfterSplash() throws {
        let app = makeApp(theme: "dark")
        app.terminate()
        let token = "splash-cold-launch-token-123456"
        let url = try XCTUnwrap(URL(string: "seruendesh://reset-password?token=\(token)"))
        app.open(url)
        defer { app.terminate() }

        // open(_:) launches the terminated app and waits for UI quiescence, like launch().
        // The root defers presentation until completion; the existing form must retain the URL token.
        let heading = app.navigationBars["Новый пароль"]
        try require(heading)
        let tokenField = element("account-reset-token", in: app)
        try require(tokenField)
        XCTAssertEqual(tokenField.value as? String, token,
                       "The original reset token must survive launch and the splash handoff")
        XCTAssertTrue(tokenField.isHittable)
        XCTAssertTrue(element("account-password", in: app).isHittable)
        XCTAssertTrue(element("account-password-confirm", in: app).isHittable)
        XCTAssertFalse(element("seru-splash-overlay", in: app).exists)
        capture("splash-cold-password-reset-form", in: app)

        let close = app.navigationBars.buttons["Закрыть"]
        try require(close)
        close.tap()
        try waitForMainScreen(in: app)
        // The synthetic token is never submitted to an account endpoint.
    }

    private func verifyColdLaunch(theme: String) throws {
        let app = makeApp(theme: theme)
        app.launch()
        defer { app.terminate() }

        // XCUIApplication.launch() waits for quiescence and can return after the greeting.
        // Real timing is covered by coordinator tests; video captures verify the crossfade.
        try waitForMainScreen(in: app)
        XCTAssertFalse(element("seru-splash-overlay", in: app).exists)
        capture("splash-complete-\(theme)", in: app)

        try selectTab(label: "События", symbol: "ticket", in: app)
        try require(app.textFields["Поиск событий"])
        try selectTab(label: "Избранное", symbol: "heart", in: app)
        try require(element("saved-title", in: app))
        try selectTab(label: "Прогулка", symbol: "safari", in: app)
        try require(app.buttons["Профиль и настройки"])
        XCTAssertFalse(element("seru-splash-overlay", in: app).exists,
                       "Switching tabs must not restart the splash")
    }

    private func makeApp(
        theme: String,
        reduceMotion: Bool = false,
        missingAssets: Bool = false,
        contentSizeCategory: UIContentSizeCategory? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-seru.dataMode", "demo", "-seru.theme", theme, "-seru.origin", "Байтерек",
            "-seru.journal.storeID", UUID().uuidString,
            "-seru.splash.reduceMotion", reduceMotion ? "YES" : "NO",
            "-seru.splash.missingAssets", missingAssets ? "YES" : "NO"
        ]
        if let contentSizeCategory {
            // UIKit's native preference avoids a test-only override in the production app.
            // The accessibility-size test independently checks that the text really grows.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory.rawValue]
        }
        return app
    }

    private func waitForMainScreen(in app: XCUIApplication, timeout: TimeInterval = 6) throws {
        let overlay = element("seru-splash-overlay", in: app)
        let profile = app.buttons["Профиль и настройки"]
        guard poll(timeout: timeout, until: { !overlay.exists && profile.exists && profile.isHittable }) else {
            capture("splash-completion-failure", in: app)
            XCTFail("The splash must release the existing main screen and its controls")
            throw SplashUIFailure.mainScreenUnavailable
        }
        XCTAssertTrue(element("seru-main-content", in: app).exists)
        try require(app.buttons["panel-handle"])
    }

    private func assertNoSplashAppears(in app: XCUIApplication, for duration: TimeInterval) throws {
        let overlay = element("seru-splash-overlay", in: app)
        guard !poll(timeout: duration, until: { overlay.exists }) else {
            capture("splash-unexpected-replay-failure", in: app)
            XCTFail("The splash may play only once per cold process launch")
            throw SplashUIFailure.unexpectedReplay
        }
    }

    private func selectTab(label: String, symbol: String, in app: XCUIApplication) throws {
        let tab = app.tabBars.buttons[label]
        let button = tab.exists ? tab : app.buttons[symbol]
        try require(button)
        guard poll(timeout: 2, until: { button.isHittable }) else {
            XCTFail("The native tab \(label) must remain interactive after splash completion")
            throw SplashUIFailure.mainScreenUnavailable
        }
        button.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func require(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForExistence(timeout: 3) else {
            XCTFail("Expected existing app control: \(element)", file: file, line: line)
            throw SplashUIFailure.mainScreenUnavailable
        }
    }

    private func poll(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum SplashUIFailure: Error {
        case mainScreenUnavailable
        case unexpectedReplay
    }
}
