import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct EventsEmptyStateTests {
    @Test func noSavedEventsTakesPriorityOverOtherFilters() {
        #expect(EventsEmptyState.select(savedOnly: true, hasSavedEvents: false, query: "Джаз",
                                        hasCategoryFilter: true, freeOnly: true) == .noSavedEvents)
    }

    @Test func savedEventsOnAnotherDateRemainACalendarEmptyState() {
        #expect(EventsEmptyState.select(savedOnly: true, hasSavedEvents: true, query: "",
                                        hasCategoryFilter: false, freeOnly: false) == .noEventsOnSelectedDay)
    }

    @Test(arguments: ["Джаз", "  Джаз\n"])
    func aQueryThatHidesExistingSavedEventsUsesSearchEmpty(_ query: String) {
        #expect(EventsEmptyState.select(savedOnly: true, hasSavedEvents: true, query: query,
                                        hasCategoryFilter: false, freeOnly: false) == .noMatches)
    }

    @Test func categoryAndPriceFiltersUseSearchEmpty() {
        #expect(EventsEmptyState.select(savedOnly: false, hasSavedEvents: true, query: "",
                                        hasCategoryFilter: true, freeOnly: false) == .noMatches)
        #expect(EventsEmptyState.select(savedOnly: true, hasSavedEvents: true, query: "",
                                        hasCategoryFilter: false, freeOnly: true) == .noMatches)
    }

    @Test func ordinaryCalendarEmptinessDoesNotDependOnHavingSavedEvents() {
        #expect(EventsEmptyState.select(savedOnly: false, hasSavedEvents: false, query: "",
                                        hasCategoryFilter: false, freeOnly: false) == .noEventsOnSelectedDay)
        #expect(EventsEmptyState.select(savedOnly: false, hasSavedEvents: true, query: " \n ",
                                        hasCategoryFilter: false, freeOnly: false) == .noEventsOnSelectedDay)
    }

    @Test func unsavedSearchDoesNotImplyAnEmptySavedCollection() {
        #expect(EventsEmptyState.select(savedOnly: false, hasSavedEvents: false, query: "Концерт",
                                        hasCategoryFilter: false, freeOnly: false) == .noMatches)
    }
}
