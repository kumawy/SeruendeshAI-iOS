import SwiftUI

/// Compatibility wrapper preserves the saved empty-state accessibility contract.
@MainActor
struct SavedMascotAnimation: View {
    var isActive = true

    var body: some View {
        SeruMascotAnimation(scene: .emptyBox, isActive: isActive)
            .accessibilityIdentifier("saved-empty-mascot")
    }
}
