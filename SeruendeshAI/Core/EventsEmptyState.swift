import Foundation

/// Explains an empty filtered feed after loading and transport failures have been handled.
enum EventsEmptyState: Equatable, Sendable {
    case noMatches
    case noEventsOnSelectedDay

    static func select(query: String, hasCategoryFilter: Bool, freeOnly: Bool) -> Self {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasCategoryFilter || freeOnly {
            return .noMatches
        }
        return .noEventsOnSelectedDay
    }
}
