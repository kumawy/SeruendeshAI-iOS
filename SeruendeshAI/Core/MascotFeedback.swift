import Foundation

/// A short reaction to a completed user action. Each emission has its own identity.
struct MascotFeedback: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case saved
        case ready
        case photoError
    }

    let id: UUID
    let kind: Kind
    let message: String

    init(kind: Kind, message: String, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.message = message
    }
}
