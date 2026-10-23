import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SeruCore
#else
@testable import SeruendeshAI
#endif

@Suite(.serialized)
struct BackendAPITests {
    private func client(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> BackendAPI {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BackendAPI(baseURL: URL(string: "https://backend.example")!, session: URLSession(configuration: configuration))
    }

    @Test func recommendationEncodesRoundedOriginAndOnlySelectedFilters() async throws {
        let api = client { request in
            #expect(request.url?.path == "/api/recommend")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try JSONSerialization.jsonObject(with: bodyData(request)) as! [String: Any]
            #expect(body["query"] as? String == "Кофе. Только бесплатные места")
            #expect(body["time_budget_min"] as? Int == 90)
            #expect((body["location"] as? [String: Double])?["lat"] == 51.128)
            #expect((body["location"] as? [String: Double])?["lon"] == 71.43)
            #expect((body["profile"] as? [String: Any])?["with_kids"] as? Bool == true)
            #expect(body["only_free"] == nil)
            #expect(body["weather"] == nil)
            return (200, Data(#"{"summary":"Нашёл","recommendations":[],"ideas":[],"route":null}"#.utf8))
        }
        let response = try await api.recommend(APIRecommendRequest(query: "Кофе", origin: .location(lat: 51.12849, lon: 71.43011, label: "Кенесары 40"), duration: 90, withKids: true, onlyFree: true), photo: nil)
        #expect(response.summary == "Нашёл")
    }

    @Test func omittedDurationLeavesNaturalLanguageBudgetToBackend() throws {
        let data = try JSONEncoder().encode(APIRecommendRequest(query: "Есть час", origin: .landmark("baiterek"), withKids: false, onlyFree: false))
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(body["time_budget_min"] == nil)
        #expect(body["query"] as? String == "Есть час")
        #expect(body["landmark"] as? String == "baiterek")
    }

    @Test func runtimeRecommendationFixtureDecodesNullableFactsAndNetworkGeometry() async throws {
        let fixture = Data(runtimeWalkFixture.utf8)
        let api = client { _ in (200, fixture) }
        let response = try await api.recommend(APIRecommendRequest(query: "Прогулка", origin: .landmark("mega_silk_way"), withKids: false, onlyFree: false), photo: nil)
        #expect(response.recommendations.first?.poiID == "osm:w1460763574")
        #expect(response.recommendations.first?.rating == nil)
        #expect(response.recommendations.first?.cuisine == [])
        #expect(response.recommendations.first?.walkDistanceM == 1330)
        #expect(response.route?.order.count == 2)
        #expect(response.route?.legs.first?.polyline.first?.count == 2)
        #expect(response.usedContext?.timeBudgetMin == 60)
    }

    @Test func relativePhotosResolveAndUnsafeLinksAreDiscarded() async throws {
        let api = client { _ in (200, Data(#"{"recommendations":[{"poi_id":"p1","name":"Парк","photo":{"url":"/cards/park.jpg","author":"Автор","license":"CC BY","page":"javascript:alert(1)"},"website":"file:///etc/passwd"}]}"#.utf8)) }
        let response = try await api.recommend(APIRecommendRequest(query: "Парк", origin: .landmark("baiterek"), withKids: false, onlyFree: false), photo: nil)
        #expect(response.recommendations.first?.photo?.url?.absoluteString == "https://backend.example/cards/park.jpg")
        #expect(response.recommendations.first?.photo?.page == nil)
        #expect(response.recommendations.first?.website == nil)
    }

    @Test func eventsEncodeSearchAndKeepUnknownPriceUnknown() async throws {
        let api = client { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.first { $0.name == "q" }?.value == "джаз & музыка")
            #expect(items.first { $0.name == "price" }?.value == "free")
            #expect(items.first { $0.name == "offset" }?.value == "20")
            return (200, Data(#"{"items":[{"id":"sxodim:1","title":"Джаз","start":"2026-10-24","sessions":["2026-10-24T19:30:00+05:00"],"schedule_kind":"sessions","price_from":null,"image_url":"https://images.example/jazz.jpg","sources":[{"name":"sxodim","url":"https://sxodim.com/astana/event/jazz"}]}],"total":21,"today":"2026-10-21","offset":20,"limit":20}"#.utf8))
        }
        let page = try await api.events(query: "джаз & музыка", price: "free", limit: 20, offset: 20)
        #expect(page.items.first?.priceFrom == nil)
        #expect(page.items.first?.start == "2026-10-24")
        #expect(page.items.first?.sources.first?.url?.host == "sxodim.com")
        #expect(page.total == 21)
    }

    @Test func routePreservesBackendPolylineCoordinateOrder() async throws {
        let api = client { request in
            let body = try JSONSerialization.jsonObject(with: bodyData(request)) as! [String: Any]
            #expect(request.url?.path == "/api/route")
            #expect(body["poi_id"] as? String == "osm:w123")
            #expect(body["landmark"] as? String == "baiterek")
            return (200, Data(#"{"poi_id":"osm:w123","name":"Парк","mode":"walk","distance_m":300,"travel_min":4,"geometry":"network","polyline":[[51.128,71.43],[51.129,71.431]],"origin":{"lat":51.128,"lon":71.43},"origin_source":"landmark","links":{"2gis":"https://2gis.kz/astana/directions"}}"#.utf8))
        }
        let route = try await api.route(poiID: "osm:w123", origin: .landmark("baiterek"))
        #expect(route.polyline.first == [51.128, 71.43])
        #expect(route.geometry == "network")
        #expect(route.links["2gis"]?.host == "2gis.kz")
    }

    @Test func metadataIdeasAndGeocodeDecodeTheirRealEnvelopes() async throws {
        let api = client { request in
            switch request.url?.path {
            case "/api/meta": return (200, Data(#"{"landmarks":[{"key":"baiterek","name":"Байтерек","lat":51.128,"lon":71.43}],"categories":[],"features":{"photo":true,"password_reset_email":false}}"#.utf8))
            case "/api/routes/ideas": return (200, Data(#"{"ideas":[{"key":"green","title":"Зелёная прогулка","emoji":"🌳","total_min":90,"stops":["Парк","Аллея"],"response":{"summary":"Прогулка","recommendations":[]}}]}"#.utf8))
            case "/api/geocode": return (200, Data(#"{"results":[{"label":"Кенесары, 40, Астана","lat":51.166,"lon":71.421,"source":"openstreetmap"}]}"#.utf8))
            default: throw URLError(.badURL)
            }
        }
        #expect(try await api.metadata().features.photo)
        #expect(try await api.routeIdeas(origin: .landmark("baiterek")).first?.response.summary == "Прогулка")
        #expect(try await api.geocode(query: "Кенесары 40").first?.lat == 51.166)
    }

    @Test func photoUsesMultipartAndRejectsOversizeBeforeTransport() async throws {
        let api = client { request in
            #expect(request.url?.path == "/api/recommend/photo")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = bodyData(request)
            #expect(body.range(of: Data("name=\"image\"; filename=\"photo.png\"".utf8)) != nil)
            #expect(body.range(of: Data("Content-Type: image/png".utf8)) != nil)
            return (200, Data(#"{"summary":"По фото","photo_guess":{"recognized":true,"name":"Байтерек","confidence":"high"}}"#.utf8))
        }
        let request = APIRecommendRequest(query: "Что рядом?", origin: .landmark("baiterek"), withKids: false, onlyFree: false)
        let response = try await api.recommend(request, photo: Data([137,80,78,71,13,10,26,10]))
        #expect(response.photoGuess?.recognized == true)
        await #expect(throws: APIError.self) { try await api.recommend(request, photo: Data(count: 8 * 1024 * 1024 + 1)) }
    }

    @Test func statusVariantsBecomeActionableRussianErrors() async throws {
        for (status, json, word) in [(429, #"{"detail":"Too many requests"}"#, "Подожди"), (422, #"{"error":"route_unavailable"}"#, "маршрут"), (503, #"{"error":"photo_unavailable"}"#, "фото")] {
            let api = client { _ in (status, Data(json.utf8)) }
            do { _ = try await api.metadata(); Issue.record("Expected HTTP error") }
            catch { #expect(error.localizedDescription.localizedCaseInsensitiveContains(word)) }
        }
    }

    @Test func offlineAndMalformedResponsesHaveUserFacingErrors() async throws {
        let offline = client { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await offline.metadata(); Issue.record("Expected offline error") }
        catch { #expect(error.localizedDescription.contains("интернет")) }
        let malformed = client { _ in (200, Data("<html>bad gateway</html>".utf8)) }
        await #expect(throws: APIError.self) { try await malformed.metadata() }
    }

    @Test func cancellationIsNeverRewrittenAsNetworkFailure() async throws {
        let api = client { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) { try await api.metadata() }
    }
}

private func bodyData(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

// Captured from main e390a72 docs/api/examples/walk.json; no sibling checkout or live API is required.
private let runtimeWalkFixture = #"""
{"api_version":"1.0","request_id":"ca2d4ac13ffc","lang":"ru","summary":"Мини-маршрут: 25-ти летие Независимости → Аллея мира и согласия. Всего ≈ 56 мин (21 мин в пути + 35 мин на местах).","recommendations":[{"poi_id":"osm:w1460763574","name":"25-ти летие Независимости","category":"attraction","lat":51.093452,"lon":71.417564,"distance_m":864,"travel_min":18,"why":"На территории ЭКСПО вас ждёт мраморная стела высотой около 70 метров, посвящённая 25-летию независимости.","visit_min":[15,15],"what_to_do":"Подойдите к стеле и рассмотрите её 25 граней; затем продолжите прогулку к Аллее мира и согласия.","open_status":"unknown","open_confidence":"none","source":"poi_data","source_url":"https://www.openstreetmap.org/way/1460763574","rating":null,"website":null,"rank":1,"match":0.7,"category_detail":"landmark","category_label":"Достопримечательность","icon":"landmark","walk_distance_m":1330,"travel_mode":"walk","arrival_at":"2026-10-18T15:18:00+05:00","departure_at":"2026-10-18T15:33:00+05:00","visit_suggested_min":15,"leave_by":null,"return_min":0,"opening":{"status":"unknown","confidence":"low","label":"Часы работы неизвестны — уточните перед визитом","raw":null,"source":null,"source_url":null,"check_date":null,"next_change":null},"source_label":"Данные POI","data_sources":["osm"],"popularity":0.0,"features":[],"accessibility":"unknown","badges":[],"event":null,"address":null,"description":"Мраморная стела высотой около 70 м на территории ЭКСПО, открытая 16 декабря 2016 года к 25-летию независимости. Её 25 граней символизируют годы независимости, облицовка выполнена из итальянского мрамора.","description_source":"research","description_url":"https://informburo.kz/novosti/nazarbaev-otkryl-monument-ly-dala-el-na-territorii-ekspo.html","phone":null,"instagram":null,"cuisine":null,"photo":null,"description_attribution":[],"structured_facts":[],"menu_items":[],"prices":[]},{"poi_id":"osm:w1456208624","name":"Аллея мира и согласия","category":"park","lat":51.093812,"lon":71.41695,"distance_m":853,"travel_min":18,"why":"Аллея мира и согласия — парк, который подойдёт для спокойной части прогулки.","visit_min":[20,20],"what_to_do":"Пройдитесь по аллее.","open_status":"unknown","open_confidence":"none","source":"poi_data","source_url":"https://www.openstreetmap.org/way/1456208624","rating":null,"website":null,"rank":2,"match":0.73,"category_detail":"park","category_label":"Парк","icon":"trees","walk_distance_m":1300,"travel_mode":"walk","arrival_at":"2026-10-18T15:36:00+05:00","departure_at":"2026-10-18T15:56:00+05:00","visit_suggested_min":20,"leave_by":null,"return_min":0,"opening":{"status":"always","confidence":"medium","label":"Открытая территория — вход свободный, часов работы нет","raw":null,"source":null,"source_url":null,"check_date":null,"next_change":null},"source_label":"Данные POI","data_sources":["osm"],"popularity":0.0,"features":[],"accessibility":"unknown","badges":[],"event":null,"address":null,"description":"Парк.","description_source":"template","description_url":null,"phone":null,"instagram":null,"cuisine":null,"photo":null,"description_attribution":[],"structured_facts":[],"menu_items":[],"prices":[]}],"service_results":[],"ideas":[],"route":{"order":["osm:w1460763574","osm:w1456208624"],"legs":[{"from_id":"start","to_id":"osm:w1460763574","distance_m":1334,"travel_min":18,"polyline":[[51.08909,71.40733],[51.088358,71.406978],[51.088335,71.407133],[51.088303,71.407292],[51.088262,71.407445],[51.088233,71.407566],[51.088203,71.407668],[51.088135,71.407917],[51.088067,71.408159],[51.087997,71.408401],[51.087967,71.408524],[51.087946,71.408638],[51.087922,71.408889],[51.087892,71.409148],[51.087879,71.409264],[51.087863,71.409394],[51.087841,71.409568],[51.087813,71.409786],[51.087864,71.409897],[51.087879,71.409988],[51.087921,71.410581],[51.08799,71.411438],[51.088044,71.411599],[51.088108,71.411674],[51.088179,71.411683],[51.088261,71.411644],[51.088421,71.411568],[51.088581,71.411491],[51.088718,71.411438],[51.088813,71.411393],[51.088832,71.411588],[51.08885,71.411751],[51.089027,71.411697],[51.089207,71.411659],[51.089375,71.411636],[51.089493,71.411636],[51.089691,71.411644],[51.089758,71.411656],[51.090057,71.411736],[51.09024,71.411812],[51.090382,71.411873],[51.090519,71.411957],[51.090599,71.41201],[51.090765,71.412144],[51.09084,71.412211],[51.090961,71.412331],[51.091053,71.412422],[51.091171,71.41256],[51.09127,71.412682],[51.091408,71.412873],[51.091587,71.413155],[51.091721,71.413376],[51.091881,71.413648],[51.091961,71.413784],[51.092143,71.414075],[51.092543,71.414717],[51.092647,71.41485],[51.092852,71.415102],[51.09303,71.41532],[51.092961,71.415473],[51.092922,71.415771],[51.092926,71.416031],[51.092967,71.416275],[51.093027,71.416508],[51.093136,71.41671],[51.093207,71.416817],[51.09325,71.416878],[51.0933,71.416939],[51.09333,71.417053],[51.093349,71.417145],[51.093357,71.417251],[51.093407,71.417378],[51.093464,71.417351],[51.093552,71.417366],[51.093594,71.41748],[51.093594,71.417603],[51.093559,71.417686],[51.093498,71.417763],[51.09343,71.417732],[51.093395,71.417641],[51.093394,71.417615],[51.093452,71.417564]],"geometry":"network"},{"from_id":"osm:w1460763574","to_id":"osm:w1456208624","distance_m":160,"travel_min":3,"polyline":[[51.093452,71.417564],[51.093394,71.417615],[51.09343,71.417732],[51.093475,71.417778],[51.093559,71.417686],[51.09357,71.417924],[51.093624,71.418007],[51.093661,71.418094],[51.093708,71.418037],[51.093746,71.417961],[51.093769,71.41787],[51.093781,71.41777],[51.093754,71.417633],[51.093708,71.417441],[51.093778,71.417262],[51.093852,71.417086],[51.093812,71.41695]],"geometry":"network"}],"total_min":56,"back_min":0,"fits_budget":true,"returns_to_start":false,"summary":"Мини-маршрут: 25-ти летие Независимости → Аллея мира и согласия. Всего ≈ 56 мин (21 мин в пути + 35 мин на местах)."},"used_context":{"location_source":"landmark","location_label":"Mega Silk Way","radius_m":1757,"time_budget_min":60,"mode":"walk","filters":[],"now":"2026-10-18T15:00:00+05:00","location":{"source":"text_landmark","label":"Mega Silk Way","lat":51.089,"lon":71.407,"precision_m":50},"local_time":"15:00","weekday":"воскресенье","is_holiday":null,"is_dark":false,"weather":{"temperature_c":9.0,"feels_like_c":6.0,"wind_ms":5.0,"precipitation":false,"description":"9°C (ощущается 6°C), ветер 5 м/с","max_outdoor_min":60,"us_aqi":null,"pm2_5":null,"source":"demo override"},"speed_kmh":4.5,"party":"solo","parsed_from_query":{"categories":[],"preferences":["park","garden","landmark","viewpoint","museum"],"avoid":[],"avoid_labels":[],"category_labels":[],"needs":[],"time_budget_min":60,"food_requirements":[],"deadline":null,"deadline_in_min":null,"flight_type":"unknown","deadline_buffer_min":0,"landmark":"Mega Silk Way","night":false,"surprise":false,"parser":"llm+rules (gpt-6-luna)"},"relaxations":[],"funnel":{"total":2271,"within_reach":130,"after_filters":14,"shown":2},"data_sources":["OpenStreetMap (ODbL)","Wikidata (CC0)","Wikipedia (CC BY-SA)","Overture Maps (CDLA)","CityPass Astana (факты со ссылкой)","Ticketon / Sxodim","Open-Meteo (CC BY 4.0)"],"data_built_at":"2026-10-19T09:31:38+00:00","privacy":"Локация округлена до ~100 м, используется только для этого запроса и не сохраняется. В языковую модель координаты не передаются.","ai_check":{"engine":"OpenAI Decisions API · gpt-6-luna","intent":{"with_kids":0.1,"indoor":0.11,"night":0.1,"quiet":0.4,"unusual":0.44,"about_city":1.0},"intent_applied":[],"checked":10,"latency_ms":219,"dropped":[]}},"considered":[],"notes":["Петля с возвращением к старту в это время не помещается, поэтому маршрут в одну сторону: обратно — на такси или ещё одна прогулка."],"disclaimer":"Ответ сформирован ИИ на основе открытых данных (OpenStreetMap, Wikidata/Wikipedia и др.). Часы работы и доступность могут измениться — проверяйте перед визитом.","ai_generated":true,"llm":{"mode":"llm","model":"gpt-6-luna","latency_ms":5024,"usage":{"input_tokens":9183,"output_tokens":323,"cost_usd":0.001746}},"off_topic":false,"navigate_to":null}
"""#
