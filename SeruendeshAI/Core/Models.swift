import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case walk, events, saved
    var id: Self { self }
    var title: String {
        switch self { case .walk: "Прогулка"; case .events: "События"; case .saved: "Избранное" }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self { case .system: "Как на устройстве"; case .light: "Светлая"; case .dark: "Тёмная" }
    }
}

enum WalkScreen: Hashable {
    case home, results, detail(String), route(String), plan, chat
    var isMap: Bool { self != .chat }
}

struct GeoPoint: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct StartLandmark: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let coordinate: GeoPoint
}

struct Place: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let category: String
    let subtitle: String
    let imageAsset: String
    let travelMinutes: Int
    let visitMinutes: Int
    let distance: String
    let hours: String
    let rating: String
    let reason: String
    let symbol: String
    let isFree: Bool
    let isChildFriendly: Bool
    var isLive = false
    var coordinate: GeoPoint? = nil
    var imageURL: URL? = nil
    var imageCredit: String? = nil
    var imageSourceURL: URL? = nil
    var sourceURL: URL? = nil
    var websiteURL: URL? = nil
    var descriptionCredit: String? = nil
}

struct CityEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let venue: String
    let dateLabel: String
    let time: String
    let price: String
    let imageAsset: String
    let category: String
    let travelMinutes: Int
    let isTomorrow: Bool
    let isFree: Bool
    let description: String
    var isLive = false
    var imageURL: URL? = nil
    var sourceURL: URL? = nil
    var startDate: Date? = nil
    var endDate: Date? = nil
    var sessionDates: [Date] = []
}

struct WalkRoute: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let duration: Int
    let distance: String
    let placeIDs: [String]
    var isLive = false
    var legs: [WalkLeg] = []
    var originLabel: String? = nil
    var originCoordinate: GeoPoint? = nil
}

struct WalkLeg: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(fromID)>\(toID)" }
    let fromID: String
    let toID: String
    let travelMinutes: Int
    let distanceMeters: Int
    let points: [GeoPoint]
    let geometry: String
}

struct RoutePreview: Hashable, Sendable {
    let placeID: String
    let travelMinutes: Int
    let distanceMeters: Int
    let points: [GeoPoint]
    let geometry: String
    let origin: GeoPoint?
    let originLabel: String
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let showsRoute: Bool
    let attachmentData: Data?
    let placeIDs: [String]
    let routeID: String?
    init(role: Role, text: String, showsRoute: Bool = false, attachmentData: Data? = nil,
         placeIDs: [String] = [], routeID: String? = nil) {
        id = UUID(); self.role = role; self.text = text; self.showsRoute = showsRoute
        self.attachmentData = attachmentData
        self.placeIDs = placeIDs; self.routeID = routeID
    }
}

enum DemoData {
    static let places: [Place] = [
        Place(id: "garden", name: "Ботанический сад Астаны", category: "Парк & природа", subtitle: "Есильский район · Парк & Оранжерея", imageAsset: "results-asset-001", travelMinutes: 12, visitMinutes: 35, distance: "1.4 км", hours: "До 23:00", rating: "4.9", reason: "Тихие аллеи, вечерняя подсветка мостиков и кофе у центрального входа. Хороший вариант для неспешной прогулки вдали от городского шума.", symbol: "tree.fill", isFree: true, isChildFriendly: true),
        Place(id: "coffee", name: "Бульвар Нуржол & Кофейня Sensily", category: "Архитектура & кофе", subtitle: "Бульвар Нуржол · Кофе & Выпечка", imageAsset: "results-asset-002", travelMinutes: 6, visitMinutes: 25, distance: "650 м", hours: "До 22:00", rating: "4.8", reason: "Уютная остановка на кофе и зелёные аллеи Нуржола. Можно взять напиток с собой и продолжить прогулку по левобережью.", symbol: "cup.and.saucer.fill", isFree: false, isChildFriendly: false),
        Place(id: "park", name: "Парк Влюблённых и вид на Хан Шатыр", category: "Панорама", subtitle: "Пешеходная зона · Вид на Хан Шатыр", imageAsset: "results-asset-003", travelMinutes: 16, visitMinutes: 30, distance: "2.1 км", hours: "Круглосуточно", rating: "4.7", reason: "Открытые виды на город, зелёные дорожки и скамейки для отдыха. Здесь приятно встретить закат и немного замедлиться.", symbol: "sun.horizon.fill", isFree: true, isChildFriendly: true),
        Place(id: "baiterek", name: "Монумент Байтерек", category: "Символ столицы", subtitle: "Бульвар Нуржол · Площадь Байтерека", imageAsset: "plan-asset-001", travelMinutes: 0, visitMinutes: 15, distance: "Вы здесь", hours: "Часы уточняй", rating: "4.9", reason: "Начни с площади у Байтерека и посмотри на город с новой стороны. Отсюда удобно отправиться по зелёным аллеям Нуржола.", symbol: "flag.fill", isFree: true, isChildFriendly: true),
        Place(id: "river", name: "Набережная реки Ишим (Арбат)", category: "Променад", subtitle: "Пешеходная зона · Вид на мост", imageAsset: "saved-asset-002", travelMinutes: 26, visitMinutes: 30, distance: "2.1 км", hours: "Круглосуточно", rating: "4.7", reason: "Прогулка вдоль Ишима с панорамой мостов и спокойными местами для отдыха у воды.", symbol: "water.waves", isFree: true, isChildFriendly: true)
    ]

    static let routes: [WalkRoute] = [
        WalkRoute(id: "green-heart", name: "Зелёное сердце левобережья", subtitle: "Байтерек · Нуржол · Ботанический сад", duration: 90, distance: "3.2 км", placeIDs: ["baiterek", "coffee", "garden"]),
        WalkRoute(id: "evening-river", name: "Огни Бульвара", subtitle: "Вечерний Нуржол с подсветкой к Акорде", duration: 45, distance: "3.4 км", placeIDs: ["baiterek", "park"])
    ]
    static let featuredRoute = routes[0]

    static let events: [CityEvent] = [
        CityEvent(id: "jazz", title: "Летний джаз на набережной Ишима", venue: "Амфитеатр парка «Астана»", dateLabel: "Сегодня", time: "19:30", price: "Бесплатно", imageAsset: "events-asset-000", category: "Музыка", travelMinutes: 18, isTomorrow: false, isFree: true, description: "Вечерний променад вдоль Ишима под живую музыку. Открытая сцена, летний воздух и джазовые импровизации."),
        CityEvent(id: "sculpture", title: "Выставка современной скульптуры Steppe Art", venue: "Национальный музей РК", dateLabel: "Сегодня", time: "до 21:00", price: "1 500 ₸", imageAsset: "events-asset-001", category: "Выставки", travelMinutes: 25, isTomorrow: false, isFree: false, description: "Современная пластика и новые взгляды на степной ландшафт в экспозиции Национального музея."),
        CityEvent(id: "stars", title: "Астрономический вечер под открытым небом", venue: "Ботанический сад", dateLabel: "Завтра", time: "21:00", price: "Бесплатно", imageAsset: "events-asset-002", category: "Наука", travelMinutes: 12, isTomorrow: true, isFree: true, description: "Посмотри на вечернее небо и узнай больше о созвездиях. Маршрут проходит через оранжерею.")
    ]
}
