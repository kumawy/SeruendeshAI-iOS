#if !SWIFT_PACKAGE
import Foundation
import Testing
@testable import SeruendeshAI

@MainActor
struct LivePresentationTests {
    @Test func astanaMapLinksRetainServerCoordinatesAndRouteOrigin() throws {
        let start = GeoPoint(latitude: 51.128, longitude: 71.430)
        let destination = GeoPoint(latitude: 51.129, longitude: 71.431)
        let twoGIS = try #require(LiveMapLink.url(provider: .twoGIS, destination: "Парк", coordinate: destination,
                                                origin: "Байтерек", originCoordinate: start))
        #expect(twoGIS.path.hasPrefix("/astana/directions/points/"))
        #expect(twoGIS.path.contains("71.43,51.128|71.431,51.129"))
        let yandex = try #require(LiveMapLink.url(provider: .yandex, destination: "Парк", coordinate: destination))
        #expect(yandex.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "maps/163/astana")
        let apple = try #require(LiveMapLink.url(provider: .apple, destination: "Парк", coordinate: nil))
        #expect(URLComponents(url: apple, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "daddr" })?.value == "Парк, Астана")
    }
}
#endif
