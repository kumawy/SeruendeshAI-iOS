import SwiftUI
import EventKit
import EventKitUI

/// EventKitUI owns the final save. The app only prepares an editable draft.
struct EventCalendarEditor: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let draft: EventCalendarDraft
    let completion: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.location = draft.location
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.timeZone = EventPresentation.calendar.timeZone
        event.notes = draft.notes
        event.url = draft.url
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        controller.view.accessibilityIdentifier = "event-calendar-editor"
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let parent: EventCalendarEditor
        init(parent: EventCalendarEditor) { self.parent = parent }

        nonisolated func eventEditViewController(_ controller: EKEventEditViewController,
                                                 didCompleteWith action: EKEventEditViewAction) {
            let saved = action == .saved
            Task { @MainActor [weak self] in
                guard let self else { return }
                parent.completion(saved)
                parent.dismiss()
            }
        }
    }
}
