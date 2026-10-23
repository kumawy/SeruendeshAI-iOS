import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct EventsEmptyStateTests {
    @Test func unfilteredFeedUsesCalendarRecovery() {
        #expect(EventsEmptyState.select(query: "",
                                        hasCategoryFilter: false, freeOnly: false) == .noEventsOnSelectedDay)
    }

    @Test(arguments: ["Джаз", "  Джаз\n"])
    func queryEmptinessOffersFilterRecovery(_ query: String) {
        #expect(EventsEmptyState.select(query: query,
                                        hasCategoryFilter: false, freeOnly: false) == .noMatches)
    }

    @Test func categoryAndPriceFiltersOfferFilterRecovery() {
        #expect(EventsEmptyState.select(query: "",
                                        hasCategoryFilter: true, freeOnly: false) == .noMatches)
        #expect(EventsEmptyState.select(query: "",
                                        hasCategoryFilter: false, freeOnly: true) == .noMatches)
    }

    @Test func whitespaceQueryKeepsCalendarRecovery() {
        #expect(EventsEmptyState.select(query: " \n ",
                                        hasCategoryFilter: false, freeOnly: false) == .noEventsOnSelectedDay)
    }
}
