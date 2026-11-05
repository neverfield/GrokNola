import Foundation

extension AppState {
    /// Moves a meeting to the trash folder and registers Undo. Recording meetings cannot be deleted.
    func moveToTrash(_ id: UUID, undoManager: UndoManager?) {
        guard id != recordingID, let m = meeting(id) else { return }
        save(id)
        if clips.loadedID == id { clips.stop() }
        do {
            try trash.move(id, from: store.root)
        } catch {
            trash.show(.init(meetingID: id, title: m.title, error: error.localizedDescription))
            return
        }
        meetings.removeAll { $0.id == id }
        clips.invalidate(id)
        if selectedID == id { selectedID = nil }
        undoManager?.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { state.restoreFromTrash(id, undoManager: undoManager) }
        }
        undoManager?.setActionName("Delete Meeting")
        trash.show(.init(meetingID: id, title: m.title))
    }

    /// Puts a trashed meeting back and opens it. Registers Redo.
    func restoreFromTrash(_ id: UUID, undoManager: UndoManager?) {
        guard meeting(id) == nil else { return }
        do {
            try trash.restore(id, to: store.root)
        } catch {
            trash.show(.init(meetingID: id, title: "the meeting", error: "It could not be restored: \(error.localizedDescription)"))
            return
        }
        guard let m = store.load(id) else { return }
        meetings.append(m)
        meetings.sort { $0.startedAt > $1.startedAt }
        clips.invalidate(id)
        openMeeting(id)
        trash.dismiss()
        undoManager?.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { state.moveToTrash(id, undoManager: undoManager) }
        }
        undoManager?.setActionName("Delete Meeting")
    }

    /// The toast's Undo: the same step as Edit > Undo when it is still on top, else a direct restore.
    func undoTrash(_ id: UUID, undoManager: UndoManager?) {
        if let undoManager, undoManager.canUndo, undoManager.undoActionName == "Delete Meeting" {
            undoManager.undo()
        }
        if meeting(id) == nil { restoreFromTrash(id, undoManager: nil) }
    }
}
