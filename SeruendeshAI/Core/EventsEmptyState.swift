import Foundation

/// Explains an empty filtered feed after loading and transport failures have been handled.
enum EventsEmptyState: Equatable, Sendable {
    case noSavedEvents
    case noMatches
    case noEventsOnSelectedDay

    static func select(savedOnly: Bool, hasSavedEvents: Bool, query: String,
                       hasCategoryFilter: Bool, freeOnly: Bool) -> Self {
        if savedOnly && !hasSavedEvents { return .noSavedEvents }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasCategoryFilter || freeOnly {
            return .noMatches
        }
        return .noEventsOnSelectedDay
    }
}
