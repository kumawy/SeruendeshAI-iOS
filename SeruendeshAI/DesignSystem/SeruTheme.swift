import SwiftUI

enum SeruColor {
    static let background = adaptive("F7F5F0", "161717")
    static let surface = adaptive("FFFFFF", "1D1E1E")
    static let field = adaptive("EDEAE5", "282929")
    static let assistantBubble = adaptive("F7F5F0", "1D1E1E")
    static let forest = adaptive("23583F", "23583F")
    static let action = adaptive("23583F", "A5C4B3")
    static let onAction = adaptive("FFFFFF", "161717")
    static let lime = adaptive("E5EDE5", "303B35")
    static let ink = adaptive("202322", "F2F1ED")
    static let muted = adaptive("5E625F", "B0B3AF")
    static let line = adaptive("DDDAD3", "393B3A")

    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: String) {
        let n = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        self.init(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
}

struct FigmaIcon: View {
    let screen: String
    let index: Int
    var size: CGFloat = 18
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(String(format: "%@-asset-%03d", screen, index))
            .resizable().scaledToFit().frame(width: size, height: size)
            .saturation(scheme == .dark ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

struct PrimaryAction: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol, !typeSize.isAccessibilitySize { Image(systemName: symbol) }
                Text(title).fontWeight(.semibold).multilineTextAlignment(.center)
            }
            .font(.system(.body, design: .default))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 12)
            .foregroundStyle(SeruColor.onAction)
            .background(SeruColor.action, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(SeruPressStyle())
    }
}

struct TagPill: View {
    let title: String
    var symbol: String? = nil
    var highlighted = false
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.system(.caption, design: .default, weight: .medium))
        .foregroundStyle(SeruColor.ink)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(highlighted ? SeruColor.lime.opacity(0.45) : SeruColor.field, in: Capsule())
    }
}

struct PlaceThumbnail: View {
    let place: Place
    var size: CGFloat = 76
    var body: some View {
        PlaceArtwork(place: place)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.title2, design: .default, weight: .semibold)).foregroundStyle(SeruColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle { Text(subtitle).font(.system(.caption, design: .default)).foregroundStyle(SeruColor.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SeruCardModifier: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.background(SeruColor.surface, in: RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func seruCard(radius: CGFloat = 20) -> some View { modifier(SeruCardModifier(radius: radius)) }
}

struct GlassCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(SeruColor.action)
        .accessibilityLabel(label)
    }
}

struct AppBrandHeader: View {
    var onProfile: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            ProfileButton(action: onProfile)
        }
        .padding(.horizontal, 20).frame(height: 58)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.8), location: 0.35),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
        }
    }
}

struct ProfileButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(SeruColor.ink)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Профиль и настройки")
    }
}

struct AvatarPlaceholder: View {
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: "person")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(SeruColor.muted)
            .accessibilityHidden(true)
    }
}

struct SavePlaceButton: View {
    let place: Place
    @Environment(AppModel.self) private var app
    var body: some View {
        Button { app.toggleSaved(place) } label: {
            Image(systemName: app.isSaved(place) ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(app.isSaved(place) ? Color.red : SeruColor.muted)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: app.isSaved(place))
        .disabled(app.account.user != nil && app.account.isShowingCachedData)
        .accessibilityLabel(app.isSaved(place) ? "Убрать из избранного" : "Сохранить место")
        .accessibilityIdentifier("save-\(place.id)")
    }
}

struct SeruPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
