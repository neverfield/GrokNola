import Foundation

extension AppState {
    /// Checks or unchecks one action item in the meeting's notes.
    func setActionItem(_ item: Insights.ActionItem, done: Bool) {
        guard !processing.contains(item.meetingID), let notes = meeting(item.meetingID)?.enhancedNotes else { return }
        guard let updated = Insights.setting(item, done: done, in: notes) else {
            showBanner("That action item changed since the list was loaded. Open the meeting to edit it.", severity: .warning)
            return
        }
        update(item.meetingID) {
            $0.enhancedNotes = updated
            $0.markNotesEdited()
        }
        save(item.meetingID)
    }

    /// Opens a meeting on its transcript at a time, for citations clicked outside the meeting view.
    func openTranscript(_ id: UUID, at seconds: Double) {
        openMeeting(id)
        Task { @MainActor [weak self] in
            // The meeting view switches tabs on a change of focus, so set it once that view exists.
            try? await Task.sleep(for: .milliseconds(150))
            self?.focusTranscript(id, at: seconds)
        }
    }

    func askFromHome(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        openLibraryChat()
        Task { await askLibrary(q) }
    }
}
