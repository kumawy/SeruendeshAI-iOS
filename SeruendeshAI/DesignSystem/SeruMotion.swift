import SwiftUI

/// Short native transitions for changes of state. Spatial motion is optional;
/// Reduce Motion keeps feedback through a small crossfade instead.
enum SeruMotion {
    static func panel(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)
    }

    static func scroll(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    static func feedback(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.12 : 0.18)
    }
}

struct SeruMenuLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).font(.system(size: 17))
        }
    }
}

enum SeruText {
    static func placeCount(_ count: Int) -> String {
        let remainder = abs(count) % 100
        let noun: String
        if (11...14).contains(remainder) {
            noun = "мест"
        } else {
            switch remainder % 10 {
            case 1: noun = "место"
            case 2...4: noun = "места"
            default: noun = "мест"
            }
        }
        return "\(count) \(noun)"
    }
}
