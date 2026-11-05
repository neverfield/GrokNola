import Foundation

/// The enhanced notes and what goes with them, saved before a regenerate so it can be undone.
struct NotesVersion {
    var enhancedNotes: String?
    var generatedNotes: String?
    var notesEditedAt: Date?
    var notesTemplateID: String?
    var speakersEditedAt: Date?
    /// Rough notes to put back, applied only while the rough notes still read `ifUserNotes`.
    var userNotes: String?
    var ifUserNotes: String?

    init(_ m: Meeting) {
        enhancedNotes = m.enhancedNotes
        generatedNotes = m.generatedNotes
        notesEditedAt = m.notesEditedAt
        notesTemplateID = m.notesTemplateID
        speakersEditedAt = m.speakersEditedAt
    }
}

/// The one regenerate per meeting that Undo regenerate can take back this session.
struct RegenerateUndo {
    var previous: NotesVersion
    /// The notes the regenerate wrote. Undo does nothing once they have changed.
    var regenerated: String?
}

extension AppState {
    static let regenerateActionName = "Regenerate Notes"

    /// Regenerates, or first asks what to do when the user edited the enhanced notes since Grok wrote them.
    func requestRegenerate(_ id: UUID, undoManager: UndoManager?) {
        guard let m = meeting(id), !processing.contains(id) else { return }
        if m.hasEditedNotes {
            regenerateConfirmation = id
        } else {
            Task { await regenerateNotes(id, undoManager: undoManager) }
        }
    }

    /// The answer to the edited-notes question. With `saveEdits`, the edited notes go into the rough notes
    /// first, so the new notes keep their changes.
    func confirmRegenerate(_ id: UUID, saveEdits: Bool, undoManager: UndoManager?) {
        regenerateConfirmation = nil
        guard let m = meeting(id), !processing.contains(id) else { return }
        var previous = NotesVersion(m)
        if saveEdits {
            var updated = m
            updated.saveEditedNotesToUserNotes()
            previous.userNotes = m.userNotes
            previous.ifUserNotes = updated.userNotes
            update(id) { $0.userNotes = updated.userNotes }
            save(id)
        }
        Task { await regenerateNotes(id, undoManager: undoManager, previous: previous) }
    }

    /// Registers Edit > Undo and shows a banner with Undo regenerate, when notes were replaced.
    func offerUndoRegenerate(_ id: UUID, before: NotesVersion, undoManager: UndoManager?) {
        guard let m = meeting(id), let old = before.enhancedNotes, !old.isEmpty, old != m.enhancedNotes else { return }
        regenerateUndo[id] = RegenerateUndo(previous: before, regenerated: m.enhancedNotes)
        registerNotesUndo(id, restoring: before, undoManager: undoManager)
        showBanner(
            "Regenerated the notes for \"\(m.title)\".",
            severity: .info,
            action: BannerItem.Action(label: "Undo regenerate") { [weak self] in self?.undoRegenerate(id, undoManager: undoManager) },
            autoDismiss: 12
        )
    }

    /// Puts back the notes from before the last regenerate. Does nothing once the new notes were changed.
    func undoRegenerate(_ id: UUID, undoManager: UndoManager?) {
        guard let entry = regenerateUndo[id], !processing.contains(id), meeting(id)?.enhancedNotes == entry.regenerated else { return }
        if let undoManager, undoManager.canUndo, undoManager.undoActionName == Self.regenerateActionName {
            undoManager.undo()
        } else {
            apply(entry.previous, to: id, undoManager: undoManager)
        }
        regenerateUndo[id] = nil
    }

    private func registerNotesUndo(_ id: UUID, restoring version: NotesVersion, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { state.apply(version, to: id, undoManager: undoManager) }
        }
        undoManager?.setActionName(Self.regenerateActionName)
    }

    /// Restores a saved version and registers the opposite change, so Undo and Redo swap between them.
    private func apply(_ version: NotesVersion, to id: UUID, undoManager: UndoManager?) {
        guard let m = meeting(id), !processing.contains(id) else { return }
        var inverse = NotesVersion(m)
        let restoreRough = version.userNotes != nil && m.userNotes == version.ifUserNotes
        if restoreRough {
            inverse.userNotes = m.userNotes
            inverse.ifUserNotes = version.userNotes
        }
        update(id) {
            $0.enhancedNotes = version.enhancedNotes
            $0.generatedNotes = version.generatedNotes
            $0.notesEditedAt = version.notesEditedAt
            $0.notesTemplateID = version.notesTemplateID
            $0.speakersEditedAt = version.speakersEditedAt
            if restoreRough, let rough = version.userNotes { $0.userNotes = rough }
        }
        save(id)
        registerNotesUndo(id, restoring: inverse, undoManager: undoManager)
    }
}
