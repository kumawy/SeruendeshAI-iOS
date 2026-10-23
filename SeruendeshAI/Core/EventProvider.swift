import Foundation

enum EventProvider: String, Equatable, Sendable {
    case sxodim, ticketon

    var title: String {
        switch self {
        case .sxodim: "Sxodim"
        case .ticketon: "Ticketon"
        }
    }

    var astanaListingURL: URL {
        // Both are official, city-specific listings, not invented event pages.
        switch self {
        case .sxodim: URL(string: "https://sxodim.com/astana")!
        case .ticketon: URL(string: "https://ticketon.kz/astana")!
        }
    }

    static func recognizing(_ url: URL) -> EventProvider? {
        guard let host = url.host?.lowercased() else { return nil }
        switch host {
        case "sxodim.com", "www.sxodim.com": return .sxodim
        case "ticketon.kz", "www.ticketon.kz", "m.ticketon.kz": return .ticketon
        default: return nil
        }
    }
}

struct EventProviderDestination: Equatable, Sendable {
    let provider: EventProvider
    let url: URL
    let isListing: Bool

    var actionTitle: String {
        isListing ? "Афиша на \(provider.title)" : "Открыть на \(provider.title)"
    }

    static func forEvent(_ event: CityEvent) -> EventProviderDestination? {
        guard let source = validatedWebURL(event.sourceURL),
              let provider = EventProvider.recognizing(source) else { return nil }
        // Local examples are illustrative. They must never masquerade as a provider's publication.
        guard event.isLive else {
            return EventProviderDestination(provider: provider, url: provider.astanaListingURL, isListing: true)
        }
        let components = source.path.lowercased().split(separator: "/")
        let cityListings: Set<String> = ["astana", "almaty", "shymkent", "karaganda", "aktau", "atyrau"]
        let isListing = components.isEmpty || (components.count == 1 && cityListings.contains(String(components[0])))
        return EventProviderDestination(provider: provider, url: source, isListing: isListing)
    }

    static func validatedWebURL(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { return nil }
        components.scheme = "https"
        return components.url
    }
}
