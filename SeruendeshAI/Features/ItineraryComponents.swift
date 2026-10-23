import AVFoundation
import SwiftUI
import Observation

struct ItineraryMetric: View {
    let screen: String
    let index: Int
    let text: String

    private var symbol: String {
        switch (screen, index) {
        case ("detail", 11), ("plan", 13): "figure.walk"
        case ("plan", 14): "mappin.and.ellipse"
        default: "clock"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SeruColor.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SeruColor.field, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct ItineraryActionLabel: View {
    let title: String
    let screen: String
    let index: Int
    var selected = false

    private var symbol: String {
        switch (screen, index) {
        case ("detail", 22): selected ? "heart.fill" : "heart"
        case ("detail", 23), ("route", 16), ("route-dark", 16): "square.and.arrow.up"
        case ("plan", 22): "arrow.up.right"
        default: "info.circle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline)
            Text(title)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SeruColor.ink)
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 8)
        .background(SeruColor.field, in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}

@MainActor @Observable
final class ItineraryAudioGuide: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isPlaying = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String) {
        if isPlaying {
            stop()
        } else {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            isPlaying = true
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isPlaying = false }
    }
}
