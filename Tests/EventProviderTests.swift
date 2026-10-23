import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct EventProviderTests {
    @Test func officialSourcesKeepTheActualEventURL() throws {
        var event = DemoData.events[0]
        event.isLive = true
        event.sourceURL = URL(string: "https://www.sxodim.com/astana/event/music-night?from=app")
        let destination = try #require(EventProviderDestination.forEvent(event))
        #expect(destination.provider == .sxodim)
        #expect(destination.url == event.sourceURL)
        #expect(!destination.isListing)
        #expect(destination.actionTitle == "Открыть на Sxodim")
    }

    @Test func providerNamesInsideOtherHostsNeverBecomeTrustedSources() {
        for source in ["https://ticketon.kz.evil.example/event/123", "https://sxodim.com@evil.example/event/123",
                       "https://evil.example/?source=ticketon.kz", "javascript:alert(1)",
                       "https://ticketon.kz:444/event/123"] {
            var event = DemoData.events[0]
            event.isLive = true
            event.sourceURL = URL(string: source)
            #expect(EventProviderDestination.forEvent(event) == nil)
        }
    }

    @Test func localExamplesAlwaysOpenAListingRatherThanClaimingARealEvent() throws {
        for event in DemoData.events {
            let destination = try #require(EventProviderDestination.forEvent(event))
            #expect(destination.isListing)
            #expect(destination.url == destination.provider.astanaListingURL)
            #expect(destination.actionTitle.hasPrefix("Афиша на "))
        }
        #expect(EventProviderDestination.forEvent(DemoData.events[1])?.provider == .ticketon)
    }

    @Test func oldHTTPProviderURLsAreUpgradedToHTTPS() throws {
        var event = DemoData.events[1]
        event.isLive = true
        event.sourceURL = URL(string: "http://m.ticketon.kz/event/exhibition")
        let destination = try #require(EventProviderDestination.forEvent(event))
        #expect(destination.provider == .ticketon)
        #expect(destination.url.absoluteString == "https://m.ticketon.kz/event/exhibition")
        #expect(!destination.isListing)
    }

    @Test func cityListingAndUnknownSourcesAreNotMislabelledAsEventPages() throws {
        var event = DemoData.events[0]
        event.isLive = true
        event.sourceURL = URL(string: "https://ticketon.kz/astana/")
        #expect(try #require(EventProviderDestination.forEvent(event)).isListing)
        event.sourceURL = URL(string: "https://venue.example/event/summer-jazz")
        #expect(EventProviderDestination.forEvent(event) == nil)
    }
}
