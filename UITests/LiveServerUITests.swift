import XCTest

@MainActor
final class LiveServerUITests: XCTestCase {
    func testPublicEventsAndLiveRecommendation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "live", "-seru.theme", "dark", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        try tap(app.tabBars.buttons["События"], in: app)
        try require(element("events-search", in: app), in: app)
        try tap(app.buttons["Все"], in: app)
        let event = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "event-detail-")
        ).firstMatch
        try require(event, timeout: 30, in: app)
        XCTAssertFalse(String(event.identifier.dropFirst("event-detail-".count)).isEmpty)
        capture("live-events-dark", app: app)

        try tap(app.tabBars.buttons["Прогулка"], in: app)
        let input = element("chat-input", in: app)
        try tap(input, in: app)
        try require(app.keyboards.firstMatch, in: app)
        input.typeText("Хочу кофе рядом с Байтереком")
        try tap(app.buttons["chat-send"], in: app)

        // A server failure should end the wait immediately instead of looking like a slow answer.
        let response = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["assistant-message", "response-error"])
        ).firstMatch
        try require(response, timeout: 110, in: app)
        XCTAssertFalse(element("response-error", in: app).exists, "The live recommendation request failed")
        let assistant = app.staticTexts.matching(identifier: "assistant-message").firstMatch
        try require(assistant, in: app)
        let answer = assistant.label.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(answer.isEmpty, "The backend should supply an answer or clarification")
        XCTAssertNotEqual(answer, "Подобрал места рядом с Байтерек. Посмотри на карте.")
        XCTAssertNotEqual(answer, "Подходящих мест нет. Увеличь время или измени фильтры.")
        record("live-assistant-response", text: answer)
        capture("live-chat-dark", app: app)

        let showPlaces = app.buttons["chat-show-places"]
        guard showPlaces.exists else {
            // Availability changes with opening hours and weather. A real clarification is valid.
            record("live-no-recommendations", text: answer)
            XCTAssertFalse(app.buttons["place-garden"].exists)
            XCTAssertFalse(app.buttons["place-coffee"].exists)
            return
        }

        try tap(showPlaces, in: app)
        let place = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "place-")
        ).firstMatch
        try require(place, timeout: 30, in: app)
        XCTAssertFalse(["place-garden", "place-coffee", "place-river"].contains(place.identifier),
                       "The live response must not fall back to demo place identifiers")
        record("live-recommended-place", text: place.identifier + "\n" + place.label)
        capture("live-results-dark", app: app)

        try tap(place, in: app)
        try tap(app.buttons["build-route"], in: app)
        let routeState = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["route-loaded", "route-error"])
        ).firstMatch
        try require(routeState, timeout: 60, in: app)

        let loaded = element("route-loaded", in: app)
        if loaded.exists {
            XCTAssertFalse(loaded.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "A loaded live route should expose its metrics")
            record("live-route-metrics", text: loaded.label)
        } else {
            try require(element("route-error", in: app), in: app)
            try require(app.staticTexts["Не удалось построить маршрут"], in: app)
            try require(app.buttons["Повторить"], in: app)
            record("live-route-unavailable", text: element("route-error", in: app).label)
        }
        capture("live-route-dark", app: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval = 15,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard element.waitForExistence(timeout: timeout) else {
            capture("live-failure", app: app)
            XCTFail("Expected live UI element: \(element)", file: file, line: line)
            throw LiveSmokeFailure.elementUnavailable
        }
    }

    private func tap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try require(element, in: app, file: file, line: line)
        if !element.isHittable {
            let handle = app.buttons["panel-handle"]
            if handle.exists, handle.isHittable, handle.value as? String != "Полностью" {
                handle.tap()
            }
            for _ in 0..<6 {
                if element.isHittable { break }
                guard let scroll = app.scrollViews.allElementsBoundByIndex
                    .filter({ $0.exists && $0.isHittable && $0.frame.height > 80 })
                    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
                else { break }
                scroll.swipeUp()
            }
        }
        guard element.isHittable else {
            capture("live-unreachable-element", app: app)
            XCTFail("Live UI element is not reachable: \(element)", file: file, line: line)
            throw LiveSmokeFailure.elementUnavailable
        }
        element.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func record(_ name: String, text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum LiveSmokeFailure: Error {
        case elementUnavailable
    }
}
