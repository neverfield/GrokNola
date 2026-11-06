import SwiftUI

extension AppState {
    /// The enhanced notes as editable Markdown. Edits save a moment after typing stops.
    func enhancedNotesBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.meeting(id)?.enhancedNotes ?? "" },
            set: { value in
                guard self.meeting(id)?.enhancedNotes != value else { return }
                self.update(id) {
                    $0.enhancedNotes = value
                    $0.markNotesEdited()
                }
                self.scheduleSave(id)
            }
        )
    }

    /// Checks or unchecks the checkbox on one line of the enhanced notes.
    func toggleNotesCheckbox(_ id: UUID, line: Int) {
        guard !processing.contains(id), let notes = meeting(id)?.enhancedNotes,
              let updated = NotesMarkdown.togglingCheckbox(atLine: line, in: notes) else { return }
        update(id) {
            $0.enhancedNotes = updated
            $0.markNotesEdited()
        }
        save(id)
    }

    /// "Name: what they said" for the transcript line a citation points at, shortened for a tooltip.
    func transcriptQuote(_ id: UUID, at seconds: Double) -> String? {
        guard let m = meeting(id),
              let i = Citations.index(at: seconds, in: m.utterances, start: \.start, end: \.end) else { return nil }
        let u = m.utterances[i]
        let text = u.text.count > 220 ? String(u.text.prefix(220)) + "…" : u.text
        return "\(m.displayName(for: u.speakerKey, myName: Prefs.myName)): \(text)"
    }
}
