import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

struct MapLinksTests {
    private let start = GeoPoint(latitude: 51.128, longitude: 71.430)
    private let coffee = GeoPoint(latitude: 51.129, longitude: 71.431)
    private let garden = GeoPoint(latitude: 51.130, longitude: 71.432)

    private func place(_ id: String, _ name: String, _ point: GeoPoint?) -> Place {
        var value = Place(id: id, name: name, category: "Парк", subtitle: "", imageAsset: "", travelMinutes: 0,
                          visitMinutes: 15, distance: "", hours: "", rating: "", reason: "", symbol: "tree", isFree: true,
                          isChildFriendly: true)
        value.coordinate = point
        return value
    }

    @Test func fullAppleWalkRetainsEveryStopInOrder() throws {
        let url = try #require(MapLinks.orderedWalk(origin: "Байтерек", originCoordinate: start,
            places: [place("coffee", "Кофе", coffee), place("garden", "Сад", garden), place("end", "Финиш", start)]))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "maps.apple.com")
        #expect(components.path == "/directions")
        #expect(components.queryItems?.filter { $0.name == "waypoint" }.compactMap(\.value) == ["51.129,71.431", "51.13,71.432"])
        #expect(components.queryItems?.first { $0.name == "destination" }?.value == "51.128,71.43")
        #expect(components.queryItems?.first { $0.name == "source" }?.value == "51.128,71.43")
        #expect(components.queryItems?.first { $0.name == "mode" }?.value == "walking")
    }

    @Test func returnWalkUsesStartAsDestinationAndKeepsFinalVisitAsWaypoint() throws {
        let url = try #require(MapLinks.orderedWalk(origin: "Байтерек", originCoordinate: start,
            places: [place("coffee", "Кофе", coffee), place("garden", "Сад", garden)], returnsToStart: true))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "waypoint" }.compactMap(\.value) == ["51.129,71.431", "51.13,71.432"])
        #expect(items.first { $0.name == "destination" }?.value == "51.128,71.43")
    }

    @Test func missingCoordinateKeepsNamedStopInsteadOfSilentlyDroppingIt() throws {
        let url = try #require(MapLinks.orderedWalk(origin: "Байтерек", originCoordinate: start,
            places: [place("unknown", "Кафе & сад", nil), place("garden", "Сад", garden)]))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "waypoint" }?.value == "Кафе & сад, Астана")
        #expect(MapLinks.orderedWalk(origin: "", originCoordinate: nil, places: [place("garden", "Сад", garden)]) == nil)
        #expect(MapLinks.orderedWalk(origin: "Байтерек", originCoordinate: start, places: []) == nil)
    }

    @Test func twoGISExplicitlyRequestsWalkingAndPreservesCoordinateOrder() throws {
        let url = try #require(MapLinks.destinationRoute(provider: .twoGIS, destination: "Сад", coordinate: garden,
                                                        origin: "Байтерек", originCoordinate: start))
        #expect(url.path == "/astana/directions/tab/pedestrian/points/71.43,51.128|71.432,51.13")
    }

    @Test func yandexActionOpensDestinationWithoutInventingARoute() throws {
        let url = try #require(MapLinks.destinationRoute(provider: .yandex, destination: "Сад", coordinate: garden,
                                                        origin: "Байтерек", originCoordinate: start))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "pt" }?.value == "71.432,51.13")
        #expect(components.queryItems?.contains { $0.name == "rtext" } == false)
        #expect(ExternalMapProvider.yandex.actionTitle(hasRoute: true) == "Открыть место в Яндекс Картах")
    }

    @Test func malformedCoordinateFallsBackToEncodedPlaceName() throws {
        let url = try #require(MapLinks.place(provider: .apple, destination: "Кафе & сад", coordinate: GeoPoint(latitude: .nan, longitude: 71)))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/place")
        #expect(components.queryItems?.first { $0.name == "address" }?.value == "Кафе & сад, Астана")
        #expect(components.queryItems?.contains { $0.name == "coordinate" } == false)
    }

    @Test func sharingUnknownDurationDoesNotInventZeroMinutes() {
        let route = WalkRoute(id: "walk", name: "Путь", subtitle: "", duration: 0, distance: "", placeIDs: ["garden"])
        let text = MapLinks.shareRoute(route, places: [place("garden", "Сад", garden)])
        #expect(!text.contains("0 мин"))
        #expect(text.contains("Сад"))
    }

    @Test func sharingRouteCarriesOrderedStopsAndNavigableLinks() {
        var route = WalkRoute(id: "walk", name: "Моя прогулка", subtitle: "", duration: 50, distance: "2 км", placeIDs: ["coffee", "garden"])
        route.originLabel = "Байтерек"; route.originCoordinate = start
        let text = MapLinks.shareRoute(route, places: [place("garden", "Сад", garden), place("coffee", "Кофе", coffee)])
        #expect(text.contains("1. Кофе\nhttps://maps.apple.com/place?"))
        #expect(text.contains("2. Сад\nhttps://maps.apple.com/place?"))
        #expect(text.contains("https://maps.apple.com/directions?"))
        #expect(text.contains("Старт: Байтерек"))
    }
}
