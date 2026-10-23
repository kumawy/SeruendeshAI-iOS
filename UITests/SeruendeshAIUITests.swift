import XCTest

@MainActor
final class SeruendeshAIUITests: XCTestCase {
    func testSavedPlacesAndEmptyChatRemainUsableAtLargestTextSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark",
                                "-seru.saved.places", "()",
                                "-UIPreferredContentSizeCategoryName",
                                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try requireCollapsedPanel(app)
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try require(app.staticTexts["saved-title"])
        verifySavedShowsOnlyPlaces(app)
        try require(app.staticTexts["saved-empty-title"])
        try require(app.descendants(matching: .any)["saved-empty-mascot"])
        let discover = app.buttons["saved-empty-discover"]
        try reveal(discover, app: app)
        let tabBar = app.tabBars.firstMatch
        if discover.frame.maxY > tabBar.frame.minY {
            app.scrollViews["saved-places-content"].swipeUp()
        }
        XCTAssertLessThanOrEqual(discover.frame.maxY, tabBar.frame.minY,
                                 "The entire discovery button must scroll clear of the tab bar")
        capture("saved-largest-text", app: app)

        try tapReachable(discover, app: app)
        XCTAssertTrue(app.tabBars.buttons["Прогулка"].isSelected)
        try openChat(app)
        capture("chat-largest-before-layout-check", app: app)
        try verifyEmptyChatWelcome(app)
        capture("chat-welcome-largest-text", app: app)
        try tapReachable(chatInput(app), app: app)
        chatInput(app).typeText("Кофе по пути")
        try waitForValue("Кофе по пути", on: chatInput(app))
        try require(app.keyboards.firstMatch)
        try verifyNoQuickFilters(app)
        XCTAssertFalse(app.staticTexts.matching(identifier: "user-message").firstMatch.exists,
                       "Editing a draft at the largest text size must not send it")
        XCTAssertTrue(app.buttons["chat-send"].isHittable)
        XCTAssertTrue(app.buttons["composer-filters"].isHittable)
        capture("chat-draft-largest-text", app: app)
    }

    func testEmptyChatDraftCanBeEditedBeforeSending() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "light"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try requireCollapsedPanel(app)
        try openChat(app)
        try verifyEmptyChatWelcome(app)
        try tapReachable(chatInput(app), app: app)
        chatInput(app).typeText("Прогулка у реки")
        try waitForValue("Прогулка у реки", on: chatInput(app))
        try require(app.keyboards.firstMatch)
        XCTAssertFalse(app.staticTexts.matching(identifier: "user-message").firstMatch.exists,
                       "Editing the message must not send it before the send action")
        try require(app.staticTexts["chat-welcome-title"])
        try verifyNoQuickFilters(app)

        chatInput(app).typeText(" вечером")
        try tapReachable(app.buttons["chat-send"], app: app)
        try require(app.staticTexts["Прогулка у реки вечером"])
        try require(app.staticTexts.matching(identifier: "assistant-message").firstMatch)
        XCTAssertFalse(app.staticTexts["chat-welcome-title"].exists,
                       "The centered welcome gives way to the actual conversation")
        capture("chat-draft-edited", app: app)
    }

    func testCenteredEmptyChatWelcomeDark() throws {
        try verifyEmptyChatWelcomeFlow(theme: "dark")
    }

    func testCenteredEmptyChatWelcomeLight() throws {
        try verifyEmptyChatWelcomeFlow(theme: "light")
    }

    func testEmptySavedPlacesDark() throws {
        try verifyEmptySavedPlacesFlow(theme: "dark")
    }

    func testEmptySavedPlacesLight() throws {
        try verifyEmptySavedPlacesFlow(theme: "light")
    }

    func testEmptySavedDiscoveryPreservesConversationAndDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark",
                                "-seru.saved.places", "()"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try requireCollapsedPanel(app)
        try openChat(app)
        try tapReachable(chatInput(app), app: app)
        chatInput(app).typeText("Хочу прогулку у реки")
        try tapReachable(app.buttons["chat-send"], app: app)
        try require(app.staticTexts.matching(identifier: "assistant-message").firstMatch)

        let draft = "А потом зайти за кофе"
        try tapReachable(chatInput(app), app: app)
        chatInput(app).typeText(draft)
        try collapseChat(app)
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try tapReachable(app.buttons["saved-empty-discover"], app: app)
        try waitForValue(draft, on: chatInput(app))
        try openChat(app)
        try require(app.staticTexts.matching(identifier: "assistant-message").firstMatch)
        try require(app.staticTexts["Хочу прогулку у реки"])
        capture("saved-discovery-keeps-chat", app: app)
    }

    func testEventsHaveNoBookmarksAndFavoritesShowsOnlyPlaces() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "light",
                                "-seru.saved.places", "(garden)", "-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        try requireCollapsedPanel(app)
        try tapReachable(app.tabBars.buttons["События"], app: app)
        try tapReachable(app.buttons["event-detail-jazz"], app: app)
        try require(app.navigationBars["Событие"])
        XCTAssertFalse(app.buttons["event-save-jazz"].exists)
        XCTAssertFalse(app.buttons["Сохранить событие"].exists)
        capture("event-without-bookmark", app: app)
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try require(app.buttons["saved-place-garden"])
        verifySavedShowsOnlyPlaces(app)
        capture("saved-only-places", app: app)
    }

    func testSavedPlacesOpenDetailsAndRoutesAndCanBeRemoved() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "light",
                                "-seru.saved.places", "(garden, coffee)"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try requireCollapsedPanel(app)
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try require(app.staticTexts["saved-title"])
        verifySavedShowsOnlyPlaces(app)

        try tapReachable(app.buttons["saved-place-garden"], app: app)
        try require(app.navigationBars["Место"])
        try require(app.buttons["detail-save-garden"])
        try tapReachable(app.navigationBars.buttons["Закрыть"], app: app)

        try tapReachable(app.buttons["saved-place-route-garden"], app: app)
        try require(app.navigationBars["Маршрут"])
        try require(app.staticTexts["route-title"])
        try tapReachable(app.navigationBars.buttons["Закрыть"], app: app)

        try tapReachable(app.buttons["Удалить Бульвар Нуржол с остановкой на кофе из избранного"], app: app)
        XCTAssertFalse(app.buttons["saved-place-coffee"].exists)
        try require(app.buttons["saved-place-garden"])
        XCTAssertFalse(app.staticTexts["saved-empty-title"].exists,
                       "Removing one place must retain the other saved places")
        capture("saved-place-removed", app: app)

        try tapReachable(app.buttons["Удалить Ботанический сад Астаны из избранного"], app: app)
        try require(app.staticTexts["saved-empty-title"])
        XCTAssertFalse(app.buttons["saved-place-garden"].exists)
        try require(app.buttons["saved-empty-discover"])
        capture("saved-last-place-removed", app: app)
    }

    func testChatSettingsRemainAvailableBeforeAndAfterConversation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "light", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try requireCollapsedPanel(app)
        try tapReachable(app.buttons["panel-handle"], app: app)
        try waitForValue("Наполовину", on: app.buttons["panel-handle"])
        try verifyNoQuickFilters(app)
        XCTAssertFalse(app.buttons["close-chat"].exists)
        try require(app.buttons["composer-filters"])

        try tapReachable(chatInput(app), app: app)
        chatInput(app).typeText("Хочу прогулку у реки")
        try tapReachable(app.buttons["chat-send"], app: app)
        try verifyActiveConversation(app)
        capture("chat-conversation-settings", app: app)

        try collapseChat(app)
        try openChat(app)
        try verifyActiveConversation(app)
    }

    func testSheetContentContinuity() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try verifyCompactLaunch(app)
        let handle = app.buttons["panel-handle"]
        let compactY = handle.frame.midY
        let composerY = chatInput(app).frame.midY
        try verifyComposerAnchor(app, expectedY: composerY)

        try tapReachable(handle, app: app)
        try waitForValue("Наполовину", on: handle)
        XCTAssertFalse(compactPanel(app).exists, "The expanded empty chat must not repeat the collapsed heading")
        let mediumY = handle.frame.midY
        try verifyComposerAnchor(app, expectedY: composerY)
        try verifyNoQuickFilters(app)
        capture("sheet-continuity-medium", app: app)

        try tapReachable(handle, app: app)
        try waitForValue("Полностью", on: handle)
        XCTAssertFalse(compactPanel(app).exists, "The expanded empty chat must not repeat the collapsed heading")
        try verifyComposerAnchor(app, expectedY: composerY)
        try verifyNoQuickFilters(app)

        try dragPanelHandle(handle, toY: mediumY, app: app)
        try waitForValue("Наполовину", on: handle)
        XCTAssertFalse(compactPanel(app).exists, "The expanded empty chat must not repeat the collapsed heading")
        try verifyComposerAnchor(app, expectedY: composerY)
        try verifyNoQuickFilters(app)

        try dragPanelHandle(handle, toY: compactY, app: app)
        try requireCollapsedPanel(app)
        try verifyComposerAnchor(app, expectedY: composerY)
    }

    func testBottomSheetDetents() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try verifyCompactLaunch(app)
        let handle = app.buttons["panel-handle"]
        let compactY = handle.frame.midY

        try tapReachable(handle, app: app)
        try waitForValue("Наполовину", on: handle)
        try require(app.buttons["chat-options"])
        let mediumY = handle.frame.midY
        XCTAssertLessThan(mediumY, compactY - 80, "Opening chat should reveal a medium sheet")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Opening the handle must not open the keyboard")
        capture("chat-medium-dark", app: app)

        try tapReachable(handle, app: app)
        try waitForValue("Полностью", on: handle)
        let fullY = handle.frame.midY
        XCTAssertLessThan(fullY, mediumY - 80, "The full sheet should rise above the medium sheet")

        try tapReachable(handle, app: app)
        try waitForValue("Наполовину", on: handle)
        XCTAssertEqual(handle.frame.midY, mediumY, accuracy: 8)

        try dragPanelHandle(handle, toY: fullY, app: app)
        try waitForValue("Полностью", on: handle)
        XCTAssertEqual(handle.frame.midY, fullY, accuracy: 8)
        try dragPanelHandle(handle, toY: mediumY, app: app)
        try waitForValue("Наполовину", on: handle)
        XCTAssertEqual(handle.frame.midY, mediumY, accuracy: 8)
        try dragPanelHandle(handle, toY: compactY, app: app)
        try waitForValue("Свёрнуто", on: handle)
        try requireCollapsedPanel(app)

        let draft = "Прогулка у реки"
        try tapReachable(chatInput(app), app: app)
        try require(app.keyboards.firstMatch)
        try waitForValue("Полностью", on: handle)
        chatInput(app).typeText(draft)
        try waitForValue(draft, on: chatInput(app))
        try collapseChat(app)
        try waitForValue("Свёрнуто", on: handle)
        try requireCollapsedPanel(app)
        try waitForValue(draft, on: chatInput(app))
        try tapReachable(handle, app: app)
        try waitForValue("Наполовину", on: handle)
        try waitForValue(draft, on: chatInput(app))
    }

    func testDarkThemeScreenshots() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", "dark", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try verifyCompactLaunch(app)
        capture("home-collapsed-dark", app: app)

        try tapReachable(app.buttons["Профиль и настройки"], app: app)
        try require(app.navigationBars["Профиль"])
        capture("profile-dark", app: app)
        try tapReachable(app.navigationBars.buttons["Готово"], app: app)

        try openChat(app)
        capture("chat-expanded-dark", app: app)
        try verifyEmptyChatWelcome(app)
        try verifyWalkSettingsPreserveSelections(app)
        try tapReachable(app.buttons["composer-filters"], app: app)
        try require(app.navigationBars["Условия прогулки"])
        capture("walk-filters-dark", app: app)
        try tapReachable(app.navigationBars.buttons["Отмена"], app: app)
        try require(app.buttons["chat-options"])

        try tapReachable(chatInput(app), app: app)
        chatInput(app).typeText("Хочу прогулку рядом")
        try tapReachable(app.buttons["chat-send"], app: app)
        try verifyActiveConversation(app)
        capture("chat-conversation-dark", app: app)

        try openChatMenuItem("chat-nearby", app: app)
        try tapReachable(app.buttons["place-garden"], app: app)
        verifyMainHeaderIsHidden(app)
        try tapReachable(app.buttons["build-route"], app: app)
        try revealHeading(app.staticTexts["route-title"], app: app)
        capture("route-dark", app: app)

        try tapReachable(app.tabBars.buttons["События"], app: app)
        try require(app.textFields["Поиск событий"])
        verifyMainHeaderIsHidden(app)
        capture("events-dark", app: app)
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try require(app.buttons["Подробнее: Ботанический сад Астаны"])
        verifyMainHeaderIsHidden(app)
        capture("saved-dark", app: app)
    }

    func testLocalDiscoveryFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.theme", "light", "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try verifyCompactLaunch(app)
        capture("home-collapsed", app: app)
        try tapReachable(app.buttons["composer-filters"], app: app)
        try selectDuration(120, app: app)
        try tapReachable(app.buttons["walk-settings-apply"], app: app)

        // Entering the compact composer opens the same draft in the expanded chat.
        let draft = "Хочу тихую прогулку рядом"
        let input = chatInput(app)
        try tapReachable(input, app: app)
        try require(app.buttons["chat-options"])
        verifyMainHeaderIsHidden(app)
        try require(app.keyboards.firstMatch)
        chatInput(app).typeText(draft)
        try waitForValue(draft, on: chatInput(app))

        // Closing the panel preserves the unfinished message in both composers.
        try collapseChat(app)
        try requireCollapsedPanel(app)
        try waitForValue(draft, on: chatInput(app))
        try openChat(app)
        try waitForValue(draft, on: chatInput(app))
        capture("chat-expanded", app: app)
        XCTAssertTrue(app.buttons["chat-send"].isEnabled)
        try tapReachable(app.buttons["chat-send"], app: app)

        let reply = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Подобрал места рядом")
        ).firstMatch
        try require(reply)
        try verifyActiveConversation(app)
        capture("chat-conversation-light", app: app)
        try require(app.buttons["chat-show-places"])
        try tapReachable(app.buttons["chat-show-places"], app: app)
        try require(app.buttons["place-garden"])
        capture("results", app: app)

        // Finish with the garden saved, including when the simulator is reused.
        let bookmark = app.buttons["save-garden"]
        try reveal(bookmark, app: app)
        if bookmark.label == "Убрать из избранного" {
            bookmark.tap()
            try waitForLabel("Сохранить место", on: bookmark)
        }
        bookmark.tap()
        try waitForLabel("Убрать из избранного", on: bookmark)

        try tapReachable(app.buttons["place-garden"], app: app)
        try revealHeading(app.staticTexts["Ботанический сад Астаны"], app: app)
        verifyMainHeaderIsHidden(app)
        capture("detail", app: app)
        try tapReachable(app.buttons["build-route"], app: app)
        try revealHeading(app.staticTexts["route-title"], app: app)
        capture("route", app: app)

        try tapReachable(app.buttons["walk-back"], app: app)
        try require(app.staticTexts["Ботанический сад Астаны"])
        try tapReachable(app.buttons["walk-back"], app: app)
        try require(app.buttons["place-garden"])
        try tapReachable(app.buttons["walk-back"], app: app)
        try require(app.buttons["chat-options"])

        try openChatMenuItem("open-plan", app: app)
        try revealHeading(app.staticTexts["Твоя прогулка"], app: app)
        capture("plan", app: app)
        try tapReachable(app.buttons["walk-back"], app: app)
        try require(app.buttons["chat-options"])
        try collapseChat(app)
        try requireCollapsedPanel(app)
        try verifyEvents(app)
        try verifySavedAndProfile(app)
    }

    private func verifyEmptySavedPlacesFlow(theme: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", theme,
                                "-seru.saved.places", "()"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try requireCollapsedPanel(app)
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try require(app.staticTexts["saved-title"])
        try require(app.staticTexts["saved-empty-title"])
        try require(app.descendants(matching: .any)["saved-empty-mascot"])
        verifySavedShowsOnlyPlaces(app)
        XCTAssertFalse(app.buttons["saved-place-garden"].exists)
        XCTAssertFalse(app.staticTexts["Нажмите на сердечко у понравившегося места."].exists)
        XCTAssertFalse(app.staticTexts["Войти для синхронизации"].exists)
        XCTAssertFalse(app.buttons["Войти для синхронизации"].exists)
        XCTAssertFalse(app.staticTexts["Маршруты хранятся на этом устройстве"].exists)
        XCTAssertFalse(app.staticTexts["События хранятся на этом устройстве"].exists)
        try reveal(app.buttons["saved-empty-discover"], app: app)
        capture("saved-empty-\(theme)", app: app)

        try tapReachable(app.buttons["saved-empty-discover"], app: app)
        XCTAssertTrue(app.tabBars.buttons["Прогулка"].isSelected)
        try requireCollapsedPanel(app)
        try require(chatInput(app))
    }

    private func verifySavedShowsOnlyPlaces(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for collection in ["places", "routes", "events"] {
            XCTAssertFalse(app.buttons["saved-collection-\(collection)"].exists,
                           "Favorites should show saved places without collection tabs",
                           file: file, line: line)
        }
        XCTAssertFalse(app.buttons["Посмотреть маршрут"].exists,
                       "Saved route collections must not appear in Favorites",
                       file: file, line: line)
    }

    private func verifyEmptyChatWelcomeFlow(theme: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-seru.dataMode", "demo", "-seru.theme", theme,
                                "-seru.origin", "Байтерек"]
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-seru.journal.storeID", UUID().uuidString]
        app.launch()
        defer { app.terminate() }

        try verifyCompactLaunch(app)
        try openChat(app)
        try verifyEmptyChatWelcome(app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("chat-welcome-\(theme)", app: app)

        try verifyWalkSettingsPreserveSelections(app)
        try verifyEmptyChatWelcome(app)
        try tapReachable(app.buttons["chat-options"], app: app)
        try require(app.buttons["chat-nearby"])
        try require(app.buttons["open-plan"])
        try tapReachable(app.buttons["chat-nearby"], app: app)
        try require(app.buttons["place-garden"])
        try tapReachable(app.buttons["walk-back"], app: app)
        try verifyEmptyChatWelcome(app)
        try tapReachable(chatInput(app), app: app)
        try require(app.keyboards.firstMatch)
        let draft = "Хочу тихую прогулку у реки"
        chatInput(app).typeText(draft)
        try waitForValue(draft, on: chatInput(app))
        try require(app.staticTexts["chat-welcome-title"])
        XCTAssertFalse(app.staticTexts.matching(identifier: "user-message").firstMatch.exists,
                       "The welcome must not send or replace the unfinished draft")
        try verifyNoQuickFilters(app)
        capture("chat-keyboard-\(theme)", app: app)
        try tapReachable(app.buttons["chat-send"], app: app)
        try require(app.staticTexts[draft])
        try verifyActiveConversation(app)
        capture("chat-conversation-\(theme)", app: app)
    }

    private func compactPanel(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "compact-panel").firstMatch
    }

    private func requireCollapsedPanel(_ app: XCUIApplication) throws {
        try waitForValue("Свёрнуто", on: app.buttons["panel-handle"])
        try require(compactPanel(app))
    }

    private func chatInput(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
    }

    private func verifyCompactLaunch(_ app: XCUIApplication) throws {
        try requireCollapsedPanel(app)
        try require(app.buttons["Профиль и настройки"])
        XCTAssertFalse(app.images["brand-logo"].exists, "The main app bar has no brand mark")
        try require(chatInput(app))
        try require(app.buttons["chat-send"])
        try require(app.buttons["composer-filters"])
        XCTAssertFalse(app.buttons["Голосовой ввод"].exists, "Filters replace the microphone action")
        XCTAssertFalse(app.buttons["chat-send"].isEnabled, "An empty message must not be sent")
        XCTAssertFalse(app.buttons["close-chat"].exists, "The chat has no separate collapse arrow")
        try waitForValue("Свёрнуто", on: app.buttons["panel-handle"])
        try waitForLabel("Развернуть панель", on: app.buttons["panel-handle"])
    }

    private func openChat(_ app: XCUIApplication) throws {
        let handle = app.buttons["panel-handle"]
        try tapReachable(handle, app: app)
        try require(app.buttons["chat-options"])
        try require(chatInput(app))
        if handle.value as? String != "Полностью" {
            try waitForValue("Наполовину", on: handle)
            try tapReachable(handle, app: app)
        }
        try waitForValue("Полностью", on: handle)
        XCTAssertFalse(app.buttons["close-chat"].exists, "The sheet closes through its handle or map")
        verifyMainHeaderIsHidden(app)
        XCTAssertFalse(app.buttons["Центрировать карту"].exists,
                       "Map controls must not appear behind the expanded chat")
        try waitForLabel("Свернуть панель", on: app.buttons["panel-handle"])
    }

    private func collapseChat(_ app: XCUIApplication) throws {
        let handle = app.buttons["panel-handle"]
        try require(handle)
        if handle.value as? String == "Свёрнуто" { return }

        if app.keyboards.firstMatch.exists {
            // Dragging the handle dismisses the keyboard and returns to the medium sheet.
            let lowerY = min(handle.frame.midY + 180, app.frame.height * 0.55)
            try dragPanelHandle(handle, toY: lowerY, app: app)
            try waitForValue("Наполовину", on: handle)
        } else if handle.value as? String == "Полностью" {
            try tapReachable(handle, app: app)
            try waitForValue("Наполовину", on: handle)
        }

        try require(app.descendants(matching: .any)["map-background"].firstMatch)
        let mapY = min(200, handle.frame.minY - 40)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 30, dy: mapY)).tap()
        try requireCollapsedPanel(app)
    }

    private func dragPanelHandle(_ handle: XCUIElement, toY y: CGFloat, app: XCUIApplication) throws {
        try require(handle)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: handle.frame.midX, dy: y))
        start.press(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow,
                    thenHoldForDuration: 0.3)
    }

    private func selectDuration(_ value: Int, app: XCUIApplication) throws {
        try tapReachable(app.buttons["walk-duration"], app: app)
        try tapReachable(app.buttons["\(value) мин"], app: app)
    }

    private func verifyWalkSettingsPreserveSelections(_ app: XCUIApplication) throws {
        try verifyNoQuickFilters(app)
        let filters = app.buttons["composer-filters"]
        try tapReachable(filters, app: app)
        try require(app.navigationBars["Условия прогулки"])
        try selectDuration(30, app: app)
        try setWalkFreeOnly(true, app: app)
        try tapReachable(app.buttons["walk-settings-apply"], app: app)
        try require(app.buttons["chat-options"])

        try tapReachable(filters, app: app)
        try require(app.navigationBars["Условия прогулки"])
        XCTAssertTrue(app.buttons["walk-duration"].label.contains("30 мин"),
                      "The composer settings must retain the applied duration")
        try waitForValue("1", on: walkFreeOnly(app))
        try selectDuration(120, app: app)
        try setWalkFreeOnly(false, app: app)
        try tapReachable(app.buttons["walk-settings-apply"], app: app)

        try tapReachable(filters, app: app)
        try require(app.navigationBars["Условия прогулки"])
        XCTAssertTrue(app.buttons["walk-duration"].label.contains("120 мин"))
        try waitForValue("0", on: walkFreeOnly(app))
        try tapReachable(app.navigationBars.buttons["Отмена"], app: app)
        try require(app.buttons["chat-options"])
        try verifyNoQuickFilters(app)
        verifyMainHeaderIsHidden(app)
    }

    private func walkFreeOnly(_ app: XCUIApplication) -> XCUIElement {
        let row = app.switches["Бесплатные места"]
        return row.switches.firstMatch.exists ? row.switches.firstMatch : row
    }

    private func setWalkFreeOnly(_ enabled: Bool, app: XCUIApplication) throws {
        let control = walkFreeOnly(app)
        try require(control)
        let expected = enabled ? "1" : "0"
        if control.value as? String != expected {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        try waitForValue(expected, on: control)
    }

    private func verifyNoQuickFilters(_ app: XCUIApplication) throws {
        for identifier in ["chat-quick-filters", "chat-duration-filter", "chat-origin-filter",
                           "chat-free-filter", "chat-kids-filter"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists,
                           "Quick filter chips must not occupy the space above the composer")
        }
        for identifier in ["chat-suggestion-nearby", "chat-suggestion-river", "chat-suggestion-coffee"] {
            XCTAssertFalse(app.buttons[identifier].exists,
                           "The empty welcome should not display the removed starter suggestions")
        }
        try require(app.buttons["composer-filters"])
        try require(chatInput(app))
    }

    private func verifyEmptyChatWelcome(_ app: XCUIApplication) throws {
        let welcome = app.descendants(matching: .any).matching(identifier: "chat-welcome").firstMatch
        let title = app.staticTexts["chat-welcome-title"]
        let mascot = app.images["chat-welcome-mascot"]
        let menu = app.buttons["chat-options"]
        let composer = chatInput(app)
        try require(welcome)
        try require(title)
        try require(mascot)
        try require(menu)
        try require(composer)
        XCTAssertEqual(title.label, "Куда сегодня пойдём?")
        XCTAssertFalse(compactPanel(app).exists, "The empty chat must not duplicate the collapsed heading")
        XCTAssertFalse(app.staticTexts["Серу"].exists, "The central mascot replaces the left-aligned Seru row")
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: app.frame.width * 0.04,
                       "The welcome question should be centered horizontally")
        XCTAssertEqual(mascot.frame.midX, title.frame.midX, accuracy: app.frame.width * 0.04)
        XCTAssertLessThanOrEqual(mascot.frame.maxY, title.frame.minY,
                                 "Seru should sit above the centered question")
        XCTAssertGreaterThanOrEqual(welcome.frame.minY, menu.frame.maxY)
        XCTAssertLessThanOrEqual(welcome.frame.maxY, composer.frame.minY)
        let context = app.buttons["chat-current-conditions"]
        let headingBottom = context.exists ? context.frame.maxY : menu.frame.maxY
        let availableHeight = composer.frame.minY - headingBottom
        let center = (composer.frame.minY + headingBottom) / 2
        XCTAssertEqual(welcome.frame.midY, center, accuracy: availableHeight / 6,
                       "The welcome content should occupy the center of the available conversation area")
        XCTAssertGreaterThan(menu.frame.midX, title.frame.midX,
                             "The chat menu must remain reachable at the trailing edge")
        XCTAssertTrue(menu.isHittable)
        try verifyNoQuickFilters(app)
        try require(app.buttons["Прикрепить фото"])
        XCTAssertTrue(app.buttons["Прикрепить фото"].isEnabled)
    }

    private func verifyActiveConversation(_ app: XCUIApplication) throws {
        let reply = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Подобрал места рядом")
        ).firstMatch
        try require(reply)
        try require(app.staticTexts.matching(identifier: "assistant-message").firstMatch)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "chat-quick-filters").firstMatch.exists,
                       "Quick filters disappear once the conversation starts")
        XCTAssertFalse(app.buttons["chat-duration-filter"].exists)
        XCTAssertFalse(app.buttons["chat-free-filter"].exists)
        XCTAssertFalse(app.buttons["close-chat"].exists)

        let filters = app.buttons["composer-filters"]
        try require(filters)
        XCTAssertEqual(filters.label, "Фильтры прогулки")
        try tapReachable(filters, app: app)
        try require(app.navigationBars["Условия прогулки"])
        try require(app.buttons["walk-duration"])
        try tapReachable(app.navigationBars.buttons["Отмена"], app: app)
        try require(reply)
        try require(app.staticTexts.matching(identifier: "assistant-message").firstMatch)
        XCTAssertFalse(app.buttons["chat-duration-filter"].exists,
                       "Returning from settings must preserve the active conversation")
    }

    private func verifyComposerAnchor(_ app: XCUIApplication, expectedY: CGFloat) throws {
        let input = chatInput(app)
        let send = app.buttons["chat-send"]
        try require(input)
        try require(send)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-input").count, 1,
                       "The sheet should have one persistent composer")
        XCTAssertEqual(input.frame.midY, expectedY, accuracy: 3,
                       "Changing sheet height must keep the composer anchored above navigation")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let navigationTop = app.tabBars.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 0 }
            .map { $0.frame.minY }.min()
        guard let navigationTop else {
            XCTFail("Expected native bottom navigation")
            throw SmokeFailure.elementUnavailable
        }
        XCTAssertLessThanOrEqual(max(input.frame.maxY, send.frame.maxY) + 8, navigationTop,
                                 "The composer must stay clear of bottom navigation")
    }

    private func verifyMainHeaderIsHidden(_ app: XCUIApplication) {
        XCTAssertFalse(app.images["brand-logo"].exists)
    }

    private func openChatMenuItem(_ identifier: String, app: XCUIApplication) throws {
        try tapReachable(app.buttons["chat-options"], app: app)
        let item = app.buttons[identifier]
        try require(item)
        try tapReachable(item, app: app)
    }

    private func verifyEvents(_ app: XCUIApplication) throws {
        try tapReachable(app.tabBars.buttons["События"], app: app)
        let search = app.textFields["Поиск событий"]
        try require(search)
        verifyMainHeaderIsHidden(app)
        capture("events", app: app)

        search.tap()
        search.typeText("Steppe Art\n")
        try require(eventCount(1, app: app))
        try tapReachable(app.buttons["Очистить поиск"], app: app)

        search.tap()
        search.typeText("zzznomatch\n")
        try require(app.staticTexts["По этим условиям событий нет"])
        try require(eventCount(0, app: app))
        try tapReachable(app.buttons["Очистить поиск"], app: app)

        try tapReachable(app.buttons["Фильтры событий"], app: app)
        let freeOnly = app.switches["Только бесплатные"]
        try require(freeOnly)
        let freeOnlyControl = freeOnly.switches.firstMatch.exists ? freeOnly.switches.firstMatch : freeOnly
        freeOnlyControl.tap()
        let isEnabled = NSPredicate(format: "value == %@", "1")
        let firstToggle = XCTNSPredicateExpectation(predicate: isEnabled, object: freeOnlyControl)
        if XCTWaiter.wait(for: [firstToggle], timeout: 3) != .completed {
            // A Form row can expose the switch trait while its center misses the control.
            freeOnly.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let enabledToggle = XCTNSPredicateExpectation(predicate: isEnabled, object: freeOnlyControl)
        guard XCTWaiter.wait(for: [enabledToggle], timeout: 5) == .completed else {
            XCTFail("Expected free-only switch value 1, received \(String(describing: freeOnlyControl.value))")
            throw SmokeFailure.elementUnavailable
        }
        try tapReachable(app.navigationBars.buttons["Готово"], app: app)
        try require(eventCount(1, app: app))
    }

    private func verifySavedAndProfile(_ app: XCUIApplication) throws {
        try tapReachable(app.tabBars.buttons["Избранное"], app: app)
        try require(app.buttons["Подробнее: Ботанический сад Астаны"])
        verifyMainHeaderIsHidden(app)
        capture("saved", app: app)

        try tapReachable(app.tabBars.buttons["Прогулка"], app: app)
        try requireCollapsedPanel(app)
        try tapReachable(app.buttons["Профиль и настройки"], app: app)
        try require(app.navigationBars["Профиль"])
        try require(app.staticTexts["Тема"])
        capture("profile", app: app)
        try tapReachable(app.navigationBars.buttons["Готово"], app: app)
        try requireCollapsedPanel(app)
    }

    private func eventCount(_ count: Int, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Событий найдено: \(count)")
        ).firstMatch
    }

    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Expected element: \(element)", file: file, line: line)
            throw SmokeFailure.elementUnavailable
        }
    }

    private func tapReachable(
        _ element: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try reveal(element, app: app, file: file, line: line)
        element.tap()
    }

    private func reveal(
        _ element: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if element.waitForExistence(timeout: 2), element.isHittable { return }

        let handle = app.buttons["panel-handle"]
        if handle.exists, handle.isHittable, handle.label == "Развернуть панель" {
            handle.tap()
        }

        // Scroll the native container rather than relying on screen coordinates.
        let scrollView = scrollingContainer(app)
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            guard let scrollView else { break }
            scrollView.swipeUp()
        }
        guard element.exists, element.isHittable else {
            XCTFail("Element could not be reached by scrolling: \(element)", file: file, line: line)
            throw SmokeFailure.elementUnavailable
        }
    }

    private func scrollingContainer(_ app: XCUIApplication) -> XCUIElement? {
        // Select the largest visible vertical content area.
        app.scrollViews.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && $0.frame.height > 80 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private func waitForValue(_ value: String, on element: XCUIElement) throws {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: 5) == .completed else {
            XCTFail("Expected draft ‘\(value)’, received ‘\(String(describing: element.value))’")
            throw SmokeFailure.elementUnavailable
        }
    }

    private func waitForLabel(_ label: String, on element: XCUIElement) throws {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: 5) == .completed else {
            XCTFail("Expected label ‘\(label)’, received ‘\(element.label)’")
            throw SmokeFailure.elementUnavailable
        }
    }

    private func revealHeading(_ heading: XCUIElement, app: XCUIApplication) throws {
        try require(heading)
        let scrollView = scrollingContainer(app)
        for _ in 0..<8 {
            if heading.isHittable { return }
            guard let scrollView else { break }
            scrollView.swipeDown()
        }
        guard heading.isHittable else {
            XCTFail("Screen heading was not visible: \(heading)")
            throw SmokeFailure.elementUnavailable
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum SmokeFailure: Error {
        case elementUnavailable
    }
}
