import Foundation
import XCTest

/// Network cases use work/seru-state-pack/tests/mascot_mock_server.py on port 18765.
/// The app still uses its normal BackendAPI; only the server response is controlled.
@MainActor
final class MascotStatesUITests: XCTestCase {
    func testEventSearchEmptyCanResetToRealCards() throws {
        let app = demoApp(theme: "dark")
        app.launch()
        defer { app.terminate() }
        try waitForLaunch(app)
        try selectTab("События", in: app)
        try tap(app.buttons["Все"], in: app)
        try require(app.buttons["event-detail-jazz"], in: app)

        let search = element("events-search", in: app)
        try tap(search, in: app)
        search.typeText("zzznomatch\n")
        try require(element("events-mascot-searchEmpty", in: app), in: app)
        XCTAssertEqual(element("events-empty-title", in: app).label, "По этим условиям событий нет")
        XCTAssertFalse(element("events-mascot-emptyBox", in: app).exists)
        XCTAssertFalse(element("events-mascot-calendarEmpty", in: app).exists)
        try wait("exists == false", on: app.keyboards.firstMatch, in: app)
        capture("mascot-events-search-dark", in: app)

        try tap(app.buttons["events-empty-action"], in: app)
        try require(app.buttons["event-detail-jazz"], in: app)
        XCTAssertFalse(element("events-mascot-searchEmpty", in: app).exists)
        XCTAssertTrue((search.value as? String ?? "").isEmpty || search.value as? String == "Поиск событий")
    }

    func testSavedEventsEmptyUsesBoxAndCanReturnToTheFeed() throws {
        let app = demoApp(theme: "light")
        app.launch()
        defer { app.terminate() }
        try waitForLaunch(app)
        try selectTab("События", in: app)
        try setSavedEventsOnly(in: app)

        try require(element("events-mascot-emptyBox", in: app), in: app)
        XCTAssertEqual(element("events-empty-title", in: app).label, "Пока нет сохранённых событий")
        XCTAssertFalse(element("events-mascot-searchEmpty", in: app).exists)
        XCTAssertFalse(element("events-mascot-calendarEmpty", in: app).exists)
        capture("mascot-events-saved-empty-light", in: app)

        try tap(app.buttons["events-empty-action"], in: app)
        try require(app.buttons["event-detail-jazz"], in: app)
        XCTAssertFalse(element("events-mascot-emptyBox", in: app).exists)
    }

    func testSelectedDayWithoutSavedEventsUsesCalendarAndCanRecover() async throws {
        let session = mockSession()
        _ = try await configure("tomorrowOnly", session: session)
        let app = liveApp(session: session, theme: "light")
        app.launch()
        defer { app.terminate() }
        try waitForLaunch(app)
        try selectTab("События", in: app)
        try require(element("events-mascot-calendarEmpty", in: app), in: app)

        try tap(app.buttons["Завтра"], in: app)
        let event = app.buttons["event-detail-mascot:event"]
        try require(event, in: app)
        let save = app.buttons["save-event-mascot:event"]
        try tap(save, in: app)
        try wait("value == %@", value: "Сохранено", on: save, in: app)
        try setSavedEventsOnly(in: app)
        try require(event, in: app)

        try tap(app.buttons["Сегодня"], in: app)
        try require(element("events-mascot-calendarEmpty", in: app), in: app)
        XCTAssertFalse(element("events-mascot-emptyBox", in: app).exists,
                       "A saved event on another date is not an empty saved collection")
        XCTAssertFalse(element("events-mascot-searchEmpty", in: app).exists)
        capture("mascot-events-calendar-saved-other-day-light", in: app)

        try tap(app.buttons["events-empty-action"], in: app)
        try require(event, in: app)
        XCTAssertTrue(app.buttons["Сохранённые"].exists,
                      "Showing all dates must preserve the user's saved-only filter")
    }

    func testEventsLoadingAndServerFailurePreserveReasonAndRetry() async throws {
        let session = mockSession()
        _ = try await configure("hold", session: session)
        let app = liveApp(session: session, theme: "dark")
        app.launch()
        defer { app.terminate() }
        try waitForLaunch(app)
        try selectTab("События", in: app)

        try require(element("events-mascot-postersLoading", in: app), in: app)
        XCTAssertFalse(element("events-empty-title", in: app).exists)
        XCTAssertFalse(element("events-count", in: app).exists,
                       "A pending first request does not establish a zero event count")
        capture("mascot-events-loading-dark", in: app)

        _ = try await configure("failure", session: session)
        try require(element("events-mascot-connectionError", in: app), in: app)
        let reason = element("events-error", in: app)
        XCTAssertEqual(reason.label, "Сервер временно недоступен. Попробуй чуть позже.")
        XCTAssertFalse(element("events-mascot-postersLoading", in: app).exists)
        XCTAssertFalse(element("events-empty-title", in: app).exists)
        XCTAssertFalse(element("events-count", in: app).exists,
                       "A failed first request must not present an empty result count")
        capture("mascot-events-server-error-dark", in: app)

        _ = try await configure("success", session: session)
        XCTAssertTrue(reason.exists, "Changing the server does not fabricate a successful UI result")
        try tap(app.buttons["events-retry"], in: app)
        try require(app.buttons["event-detail-mascot:event"], in: app)
        XCTAssertFalse(element("events-error", in: app).exists)
        XCTAssertFalse(element("events-mascot-connectionError", in: app).exists)
        let state = try await serverState(session: session)
        XCTAssertGreaterThanOrEqual(state.eventRequests, 2,
                                    "The retry must perform another actual backend request")
        capture("mascot-events-retry-recovered-dark", in: app)
    }

    func testSavingAnEventShowsReactionAndRemovalRestoresTheHeart() throws {
        let app = demoApp(theme: "light")
        app.launch()
        defer { app.terminate() }
        try waitForLaunch(app)
        try selectTab("События", in: app)
        let save = app.buttons["save-event-jazz"]
        try require(save, in: app)
        XCTAssertEqual(save.value as? String, "Не сохранено")

        try tap(save, in: app)
        let reaction = element("mascot-feedback-saved", in: app)
        try require(reaction, timeout: 2, in: app)
        XCTAssertTrue(reaction.label.contains("Событие сохранено"))
        XCTAssertTrue(save.isHittable, "The reaction must not block the event controls")
        capture("mascot-event-saved-reaction-light", in: app)

        save.tap()
        try wait("value == %@", value: "Не сохранено", on: save, in: app)
        try wait("exists == false", on: reaction, timeout: 2, in: app)
        XCTAssertTrue(save.isHittable)
    }

    func testGreetingAndComposerDraftSurviveSheetAndDetentChanges() throws {
        let app = demoApp(theme: "dark")
        app.launch()
        defer { app.terminate() }
        try waitForLaunch(app)
        try selectTab("Прогулка", in: app)
        let handle = app.buttons["panel-handle"]
        try tap(handle, in: app)
        try wait("value == %@", value: "Наполовину", on: handle, in: app)
        try tap(handle, in: app)
        try wait("value == %@", value: "Полностью", on: handle, in: app)
        try require(element("chat-welcome-mascot", in: app), in: app)
        XCTAssertEqual(element("chat-welcome-title", in: app).label, "Куда сегодня хотите?")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-input").count, 1)
        capture("mascot-chat-greeting-dark", in: app)

        let input = element("chat-input", in: app)
        let draft = "Прогулка у реки"
        try tap(input, in: app)
        input.typeText(draft)
        try wait("value == %@", value: draft, on: input, in: app)
        try tap(app.buttons["composer-filters"], in: app)
        try require(app.navigationBars["Условия прогулки"], in: app)
        try tap(app.navigationBars.buttons["Отмена"], in: app)
        try wait("value == %@", value: draft, on: input, in: app)
        try wait("exists == false", on: app.keyboards.firstMatch, in: app)

        try tap(handle, in: app)
        try wait("value == %@", value: "Наполовину", on: handle, in: app)
        XCTAssertEqual(input.value as? String, draft)
        try tap(handle, in: app)
        try wait("value == %@", value: "Полностью", on: handle, in: app)
        XCTAssertEqual(input.value as? String, draft)
        try tap(input, in: app)
        let insertion = " вечером"
        input.typeText(insertion)
        try wait("value CONTAINS %@", value: insertion, on: input, in: app)
        let editedDraft = try XCTUnwrap(input.value as? String)
        XCTAssertEqual(editedDraft.replacingOccurrences(of: insertion, with: ""), draft,
                       "Editing at the tapped caret must preserve the complete existing draft")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-input").count, 1)
        XCTAssertFalse(element("user-message", in: app).exists)
        try require(element("chat-welcome-title", in: app), in: app)
        XCTAssertTrue(app.buttons["chat-send"].isEnabled)
        capture("mascot-chat-preserved-draft-dark", in: app)
    }

    private func demoApp(theme: String) -> XCUIApplication {
        makeApp(mode: "demo", theme: theme)
    }

    private func liveApp(session: MockSession, theme: String) -> XCUIApplication {
        let app = makeApp(mode: "live", theme: theme)
        app.launchEnvironment["SERU_API_BASE_URL"] = session.appURL.absoluteString
        return app
    }

    private func makeApp(mode: String, theme: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", mode, "-seru.theme", theme,
                                "-seru.origin", "Байтерек", "-seru.saved.places", "()",
                                "-seruendesh.savedEventIDs", "|"]
        return app
    }

    private func waitForLaunch(_ app: XCUIApplication) throws {
        try wait("exists == false", on: element("seru-splash-overlay", in: app), timeout: 15, in: app)
        try wait("hittable == true", on: app.tabBars.buttons["События"], timeout: 12, in: app)
    }

    private func selectTab(_ title: String, in app: XCUIApplication) throws {
        let tab = app.tabBars.buttons[title]
        try tap(tab, in: app)
        try wait("selected == true", on: tab, in: app)
    }

    private func setSavedEventsOnly(in app: XCUIApplication) throws {
        try tap(app.buttons["events-filters"], in: app)
        try require(app.navigationBars["Фильтры событий"], in: app)
        let row = app.switches["events-saved-filter"]
        try require(row, in: app)
        let control = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        if control.value as? String != "1" {
            try wait("hittable == true", on: control, in: app)
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        try wait("value == %@", value: "1", on: control, in: app)
        try tap(app.navigationBars.buttons["Готово"], in: app)
        try wait("exists == false", on: app.navigationBars["Фильтры событий"], in: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval = 8, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard element.waitForExistence(timeout: timeout) else {
            capture("mascot-state-missing", in: app)
            XCTFail("Expected UI element: \(element)", file: file, line: line)
            throw UIStateFailure.elementUnavailable
        }
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication,
                     file: StaticString = #filePath, line: UInt = #line) throws {
        try require(element, in: app, file: file, line: line)
        try wait("hittable == true", on: element, in: app, file: file, line: line)
        element.tap()
    }

    private func wait(_ predicate: String, value: String? = nil, on element: XCUIElement,
                      timeout: TimeInterval = 8, in app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        let condition = value.map { NSPredicate(format: predicate, $0) } ?? NSPredicate(format: predicate)
        let expectation = XCTNSPredicateExpectation(predicate: condition, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            capture("mascot-state-wait-failed", in: app)
            XCTFail("Expected \(predicate) for \(element)", file: file, line: line)
            throw UIStateFailure.elementUnavailable
        }
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct MockSession {
        let root: URL
        let token = UUID().uuidString
        var appURL: URL { root.appendingPathComponent(token) }
        var controlURL: URL { root.appendingPathComponent("__control").appendingPathComponent(token) }
    }

    private struct MockState: Decodable {
        let eventRequests: Int
    }

    private func mockSession() -> MockSession {
        let configured = ProcessInfo.processInfo.environment["SERU_MASCOT_MOCK_BASE_URL"]
        return MockSession(root: URL(string: configured ?? "http://127.0.0.1:18765")!)
    }

    private func configure(_ mode: String, session: MockSession) async throws -> MockState {
        var request = URLRequest(url: session.controlURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
        return try await controlResponse(request)
    }

    private func serverState(session: MockSession) async throws -> MockState {
        try await controlResponse(URLRequest(url: session.controlURL, timeoutInterval: 5))
    }

    private func controlResponse(_ request: URLRequest) async throws -> MockState {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            XCTFail("Start mascot_mock_server.py before running the two network state UI tests")
            throw UIStateFailure.mockServerUnavailable
        }
        return try JSONDecoder().decode(MockState.self, from: data)
    }

    private enum UIStateFailure: Error {
        case elementUnavailable
        case mockServerUnavailable
    }
}
