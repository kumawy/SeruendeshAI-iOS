import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct EventPresentationTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func liveEvent(sessions: [String] = [], start: String? = nil, end: String? = nil,
                           time: String = "") -> CityEvent {
        var event = CityEvent(id: "sessions", title: "Вечер музыки", venue: "Зал № 1", dateLabel: "",
                              time: time, price: "", imageAsset: "", category: "Музыка", travelMinutes: 0,
                              isTomorrow: false, isFree: false, description: "Живая музыка")
        event.isLive = true
        event.sessionDates = sessions.map(date)
        event.startDate = start.map(date)
        event.endDate = end.map(date)
        return event
    }

    @Test func selectedDateCardUsesThatSessionsTimeRatherThanFirstSession() {
        let event = liveEvent(sessions: ["2026-10-24T14:30:00Z", "2026-10-25T16:00:00Z"])
        let now = date("2026-10-24T12:00:00Z")
        #expect(EventPresentation.cardDate(event, day: .date, selectedDate: date("2026-10-25T08:00:00Z"), now: now)
                == "25 окт. · 21:00")
    }

    @Test func allDatesCardUsesUpcomingSessionWhenEarlierOneHasPassed() {
        let event = liveEvent(sessions: ["2026-10-24T05:00:00Z", "2026-10-24T14:30:00Z"])
        let now = date("2026-10-24T12:00:00Z")
        #expect(EventPresentation.cardDate(event, day: .all, selectedDate: now, now: now) == "Сегодня · 19:30")
    }

    @Test func sessionListSortsAndDeduplicatesActualTimes() {
        let event = liveEvent(sessions: ["2026-10-25T16:00:00Z", "2026-10-24T14:30:00Z", "2026-10-25T16:00:00Z"])
        let now = date("2026-10-24T12:00:00Z")
        #expect(EventPresentation.sessions(event, now: now) == [date("2026-10-24T14:30:00Z"), date("2026-10-25T16:00:00Z")])
        #expect(EventPresentation.sessionLabel(date("2026-10-25T16:00:00Z")) == "25 октября 2026 · 21:00")
    }

    @Test func todayAndTomorrowUseAlmatyMidnightAsTimeMovesForward() {
        let event = liveEvent(sessions: ["2026-10-25T02:00:00Z"])
        let before = date("2026-10-24T18:59:00Z")
        let after = date("2026-10-24T19:01:00Z")
        #expect(!EventPresentation.matchesDay(event, day: .today, selectedDate: before, now: before))
        #expect(EventPresentation.matchesDay(event, day: .tomorrow, selectedDate: before, now: before))
        #expect(EventPresentation.matchesDay(event, day: .today, selectedDate: after, now: after))
        #expect(!EventPresentation.matchesDay(event, day: .tomorrow, selectedDate: after, now: after))
        #expect(EventPresentation.nextDayChange(after: before) == date("2026-10-24T19:00:00Z"))
    }

    @Test func saturdayAndSundayFiltersUseCurrentOrNextWeekend() {
        let event = liveEvent(sessions: ["2026-10-25T16:00:00Z", "2026-10-31T12:00:00Z"])
        let sunday = date("2026-10-25T07:00:00Z")
        let monday = date("2026-10-26T07:00:00Z")
        #expect(EventPresentation.matchesDay(event, day: .weekend, selectedDate: sunday, now: sunday))
        #expect(EventPresentation.cardDate(event, day: .weekend, selectedDate: monday, now: monday) == "31 окт. · 17:00")
    }

    @Test func rangedDateOnlyEventIncludesItsLastDayWithoutInventingSessionTimes() {
        let event = liveEvent(start: "2026-10-24T19:00:00Z", end: "2026-10-27T19:00:00Z")
        let selected = date("2026-10-28T06:00:00Z")
        #expect(EventPresentation.matchesDay(event, day: .date, selectedDate: selected, now: selected))
        #expect(EventPresentation.cardDate(event, day: .date, selectedDate: selected, now: selected) == "28 окт.")
        #expect(EventPresentation.sessions(event, now: selected).isEmpty)
    }

    @Test func localFixtureExactStartCanBeExportedButClosingTimeIsNotAStart() {
        let now = date("2026-10-24T07:00:00Z")
        #expect(EventPresentation.sessions(DemoData.events[0], now: now) == [date("2026-10-24T14:30:00Z")])
        #expect(EventPresentation.sessions(DemoData.events[1], now: now).isEmpty)
        #expect(EventPresentation.cardDate(DemoData.events[1], day: .today, selectedDate: now, now: now) == "Сегодня · до 21:00")
    }

    @Test(arguments: [(1, "сеанс"), (2, "сеанса"), (5, "сеансов"), (11, "сеансов"), (21, "сеанс"), (24, "сеанса"), (112, "сеансов")])
    func russianSessionCountsUseCorrectForms(_ count: Int, _ word: String) {
        #expect(EventPresentation.sessionCount(count) == "\(count) \(word)")
    }

    @Test func calendarDraftPreservesChosenSessionAndExplainsUnknownEnd() throws {
        let event = liveEvent(sessions: ["2026-10-24T14:30:00Z", "2026-10-25T16:00:00Z"], end: "2026-11-05T19:00:00Z")
        let start = date("2026-10-25T16:00:00Z")
        let draft = try #require(EventPresentation.calendarDraft(event, session: start, now: date("2026-10-24T12:00:00Z")))
        #expect(draft.start == start)
        #expect(draft.end == date("2026-10-25T17:00:00Z"))
        #expect(!draft.isAllDay)
        #expect(draft.notes.contains("Время окончания не указано"))
        #expect(draft.location == "Зал № 1")
    }

    @Test func calendarDraftForDateOnlyRangeUsesExclusiveEndDay() throws {
        let event = liveEvent(start: "2026-10-24T19:00:00Z", end: "2026-10-27T19:00:00Z")
        let draft = try #require(EventPresentation.calendarDraft(event, now: date("2026-10-24T07:00:00Z")))
        #expect(draft.isAllDay)
        #expect(draft.start == date("2026-10-24T19:00:00Z"))
        #expect(draft.end == date("2026-10-28T19:00:00Z"))
    }

    @Test func calendarDraftCannotInventDateForUndatedLiveEvent() {
        let event = liveEvent()
        #expect(EventPresentation.calendarDraft(event, now: date("2026-10-24T07:00:00Z")) == nil)
    }

    @Test func venueLinkOpensSearchForCorrectCityAndCannotClaimTurnByTurnDirections() throws {
        let local = try #require(EventPresentation.venueURL(DemoData.events[0]))
        let localComponents = try #require(URLComponents(url: local, resolvingAgainstBaseURL: false))
        #expect(localComponents.host == "maps.apple.com")
        #expect(localComponents.queryItems?.first(where: { $0.name == "q" })?.value == "Амфитеатр парка «Астана», Астана")
        #expect(localComponents.queryItems?.contains(where: { $0.name == "daddr" }) == false)
        let live = try #require(EventPresentation.venueURL(liveEvent()))
        #expect(URLComponents(url: live, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Зал № 1, Астана")
    }
}
