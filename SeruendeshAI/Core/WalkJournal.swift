import Foundation

struct RecommendationContext: Codable, Hashable, Sendable {
    let origin: String
    let duration: Int
    let onlyFree: Bool
    let withKids: Bool
    let originCoordinate: GeoPoint?
}

struct RecommendationSnapshot: Codable, Equatable, Sendable {
    let context: RecommendationContext
    let places: [Place]
    let plan: WalkRoute?
}

struct WalkJournalEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let context: RecommendationContext
    let query: String
    let draft: String
    var draftPhoto: Data?
    var messages: [ChatMessage]
    let places: [Place]
    let plan: WalkRoute?
    let screen: WalkScreen
    var planEdited: Bool? = nil
    var origin: String { context.origin }
    var duration: Int { context.duration }
    var hasContent: Bool { !query.isEmpty || !draft.isEmpty || draftPhoto != nil || !messages.isEmpty || planEdited == true }
}

/// The small index contains no image blobs. Photos live in bounded, atomic sidecar files.
struct WalkJournalStore {
    static let maximumEntries = 20
    static let maximumMessages = 80
    static let maximumPhotoBytes = 24 * 1024 * 1024
    private static let maximumIndexBytes = 4 * 1024 * 1024
    let directory: URL

    static func boundedPhotos(_ entries: [WalkJournalEntry]) -> [WalkJournalEntry] {
        var remaining = maximumPhotoBytes
        func retain(_ photo: Data?) -> Data? {
            guard let photo, photo.count <= min(8 * 1024 * 1024, remaining) else { return nil }
            remaining -= photo.count
            return photo
        }
        return entries.map { value in
            var entry = value
            entry.draftPhoto = retain(value.draftPhoto)
            // Favor the most recent photos within a long conversation.
            entry.messages = value.messages.suffix(maximumMessages).reversed().map { message in
                ChatMessage(id: message.id, role: message.role, text: message.text, showsRoute: message.showsRoute,
                            attachmentData: retain(message.attachmentData), placeIDs: message.placeIDs,
                            routeID: message.routeID, snapshot: message.snapshot)
            }.reversed()
            return entry
        }
    }

    struct State {
        var active: WalkJournalEntry?
        var entries: [WalkJournalEntry]
    }
    private struct Index: Codable {
        let version: Int
        let active: WalkJournalEntry
        let entries: [WalkJournalEntry]
        let photos: [String: String]
    }

    init(defaults: UserDefaults, directory: URL? = nil) {
        if let directory { self.directory = directory; return }
        let key = "seru.journal.storeID"
        let storedID = defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
        let id = storedID ?? UUID()
        if storedID == nil { defaults.set(id.uuidString, forKey: key) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.directory = base.appendingPathComponent("SeruendeshAI/WalkJournal/\(id.uuidString)", isDirectory: true)
    }

    func load() -> State {
        let url = directory.appendingPathComponent("journal.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumIndexBytes,
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data), index.version == 1 else {
            return State(active: nil, entries: [])
        }
        var remaining = Self.maximumPhotoBytes
        func photo(_ key: String) -> Data? {
            guard let name = index.photos[key], UUID(uuidString: name) != nil else { return nil }
            let file = directory.appendingPathComponent(name).appendingPathExtension("photo")
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= min(8 * 1024 * 1024, remaining),
                  let bytes = try? Data(contentsOf: file) else { return nil }
            remaining -= bytes.count
            return bytes
        }
        func restore(_ value: WalkJournalEntry) -> WalkJournalEntry {
            var result = value
            result.draftPhoto = photo("\(value.id)-draft")
            result.messages = value.messages.suffix(Self.maximumMessages).map { message in
                ChatMessage(id: message.id, role: message.role, text: message.text, showsRoute: message.showsRoute,
                            attachmentData: photo(message.id.uuidString), placeIDs: message.placeIDs,
                            routeID: message.routeID, snapshot: message.snapshot)
            }
            return result
        }
        let active = restore(index.active)
        let entries = index.entries.prefix(Self.maximumEntries).map { $0.id == active.id ? active : restore($0) }
        return State(active: active, entries: entries)
    }

    @discardableResult
    func save(active: WalkJournalEntry, entries: [WalkJournalEntry]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var photos: [String: String] = [:]
            var remaining = Self.maximumPhotoBytes
            func storePhoto(_ bytes: Data?, key: String) throws {
                guard photos[key] == nil, let bytes, bytes.count <= min(8 * 1024 * 1024, remaining) else { return }
                // Stable UUID keys ensure repeated draft writes replace a file instead of multiplying it.
                let name = UUID(uuidString: String(key.prefix(36)))?.uuidString ?? active.id.uuidString
                let file = directory.appendingPathComponent(name).appendingPathExtension("photo")
                if (try? Data(contentsOf: file)) != bytes { try bytes.write(to: file, options: .atomic) }
                photos[key] = name
                remaining -= bytes.count
            }
            func strip(_ value: WalkJournalEntry) throws -> WalkJournalEntry {
                var result = value
                try storePhoto(value.draftPhoto, key: "\(value.id)-draft")
                result.draftPhoto = nil
                result.messages = try value.messages.suffix(Self.maximumMessages).map { message in
                    try storePhoto(message.attachmentData, key: message.id.uuidString)
                    return ChatMessage(id: message.id, role: message.role, text: String(message.text.prefix(12_000)),
                                       showsRoute: message.showsRoute, placeIDs: message.placeIDs,
                                       routeID: message.routeID, snapshot: message.snapshot)
                }
                return result
            }
            let cleanActive = try strip(active)
            var unique = Set<UUID>()
            let limited = entries.filter { unique.insert($0.id).inserted }.prefix(Self.maximumEntries)
            var cleanEntries = try limited.map { $0.id == active.id ? cleanActive : try strip($0) }
            var data = try JSONEncoder().encode(Index(version: 1, active: cleanActive, entries: cleanEntries, photos: photos))
            while data.count > Self.maximumIndexBytes && !cleanEntries.isEmpty {
                cleanEntries.removeLast()
                data = try JSONEncoder().encode(Index(version: 1, active: cleanActive, entries: cleanEntries, photos: photos))
            }
            guard data.count <= Self.maximumIndexBytes else { return false }
            try data.write(to: directory.appendingPathComponent("journal.json"), options: .atomic)
            let retained = Set(photos.values.map { "\($0).photo" })
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                where url.pathExtension == "photo" && !retained.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
            return true
        } catch { return false }
    }
}

/// Geometry is a local estimate, never an assertion about a surveyed street route.
enum WalkPlanner {
    static func plan(places: [Place], context: RecommendationContext, id: String = UUID().uuidString) -> WalkRoute? {
        var stops: [Place] = []
        var legs: [WalkLeg] = []
        var total = 0
        var previous = context.originCoordinate
        var previousID = "start"
        var seen = Set<String>()
        for place in places where seen.insert(place.id).inserted && (!context.onlyFree || place.isFree) && (!context.withKids || place.isChildFriendly) {
            let meters: Int
            let travel: Int
            if let start = previous, let end = place.coordinate {
                meters = estimatedDistance(from: start, to: end)
                travel = Int(ceil(Double(meters) / 75))
            } else {
                // Per-place travel is the only available estimate when a server omitted coordinates.
                travel = max(0, place.travelMinutes)
                meters = travel * 75
            }
            let nextTotal = total + travel + max(0, place.visitMinutes)
            guard nextTotal <= context.duration else { continue }
            legs.append(WalkLeg(fromID: previousID, toID: place.id, travelMinutes: travel,
                                distanceMeters: meters, points: [previous, place.coordinate].compactMap { $0 }, geometry: "estimate"))
            stops.append(place); total = nextTotal; previous = place.coordinate; previousID = place.id
        }
        guard !stops.isEmpty else { return nil }
        var route = WalkRoute(id: id, name: "Твоя прогулка", subtitle: stops.map(\.name).joined(separator: " · "),
                              duration: total, distance: BackendMapping.distance(legs.reduce(0) { $0 + $1.distanceMeters }), placeIDs: stops.map(\.id))
        route.isLive = stops.contains(where: \.isLive)
        route.legs = legs; route.originLabel = context.origin; route.originCoordinate = context.originCoordinate
        route.returnsToStart = false; route.fitsBudget = total <= context.duration
        if let start = context.originCoordinate, let end = stops.last?.coordinate {
            route.returnMinutes = Int(ceil(Double(estimatedDistance(from: end, to: start)) / 75))
        }
        return route
    }

    static func estimatedDistance(from start: GeoPoint, to end: GeoPoint) -> Int {
        let radians = Double.pi / 180
        let dLat = (end.latitude - start.latitude) * radians
        let dLon = (end.longitude - start.longitude) * radians
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(start.latitude * radians) * cos(end.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        let direct = 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return Int((direct * 1.25).rounded())
    }
}
