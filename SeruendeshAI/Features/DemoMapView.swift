import SwiftUI

/// Place data remains local. Apple supplies the base map independently of the app backend.
struct DemoMapView: View {
    let screen: WalkScreen
    let visibleHeight: CGFloat
    var showsContent = true
    var onBackgroundTap: () -> Void = {}

    var body: some View {
        LiveMapView(screen: screen, visibleHeight: visibleHeight, showsContent: showsContent,
                    onBackgroundTap: onBackgroundTap)
    }
}
