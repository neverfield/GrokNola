import Foundation

/// Who said which lines before a merge or a move, so Undo can put them back without touching lines
/// that arrived since, while recording.
struct SpeakerEdit {
    var keys: [UUID: String]
    var speakers: [String: SpeakerInfo]
    var mode: AttributionMode
    var speakerAliases: [String: String]?
    var speakersEditedAt: Date?

    init(_ m: Meeting, lines ids: Set<UUID>) {
        keys = Dictionary(uniqueKeysWithValues: m.utterances.filter { ids.contains($0.id) }.map { ($0.id, $0.speakerKey) })
        speakers = m.speakers
        mode = m.mode
        speakerAliases = m.speakerAliases
        speakersEditedAt = m.speakersEditedAt
    }
}

extension AppState {
    static let mergeSpeakersActionName = "Merge Speakers"
    static let moveLineActionName = "Move Line"

    /// Speakers can change except while the after-meeting steps rewrite the transcript.
    func canEditSpeakers(_ id: UUID) -> Bool {
        !processing.contains(id)
    }

    /// Gives every line of `from` to `target`. Your own lines always stay yours, so merging Me into
    /// someone merges them into Me instead.
    func mergeSpeakers(from: String, into target: String, in id: UUID, undoManager: UndoManager?) {
        let (from, target) = from == Meeting.meKey ? (target, from) : (from, target)
        guard from != target, canEditSpeakers(id), let m = meeting(id) else { return }
        let fromName = m.displayName(for: from, myName: Prefs.myName)
        let lines = Set(m.utterances.filter { $0.speakerKey == from }.map(\.id))
        let before = SpeakerEdit(m, lines: lines)
        update(id) { m in
            m.mergeSpeaker(from, into: target)
            m.refreshAttributionMode()
            if m.enhancedNotes != nil { m.speakersEditedAt = Date() }
        }
        liveSpeakersMerged(from: from, into: target, in: id)
        save(id)
        registerSpeakerUndo(id, restoring: before, actionName: Self.mergeSpeakersActionName, undoManager: undoManager)
        let targetName = meeting(id)?.displayName(for: target, myName: Prefs.myName) ?? target
        offerRegenerateAfterSpeakerEdit(id, message: "Merged \(fromName) into \(targetName).", undoManager: undoManager)
    }

    /// Gives the lines of one transcript block to another speaker.
    func reassignBlock(_ lineIDs: Set<UUID>, to key: String, in id: UUID, undoManager: UndoManager?) {
        guard !lineIDs.isEmpty, canEditSpeakers(id), let m = meeting(id) else { return }
        let before = SpeakerEdit(m, lines: lineIDs)
        update(id) { m in
            m.reassignUtterances(ids: lineIDs, to: key)
            m.refreshAttributionMode()
            if m.enhancedNotes != nil { m.speakersEditedAt = Date() }
        }
        save(id)
        registerSpeakerUndo(id, restoring: before, actionName: Self.moveLineActionName, undoManager: undoManager)
        let name = meeting(id)?.displayName(for: key, myName: Prefs.myName) ?? key
        offerRegenerateAfterSpeakerEdit(id, message: "Moved the lines to \(name).", undoManager: undoManager)
    }

    /// Notes Grok already wrote name the old speakers, so offer to write them again.
    private func offerRegenerateAfterSpeakerEdit(_ id: UUID, message: String, undoManager: UndoManager?) {
        guard let m = meeting(id), m.enhancedNotes != nil, recordingID != id else {
            showBanner(message, severity: .info)
            return
        }
        showBanner(
            "\(message) The notes still use the old speakers.",
            severity: .info,
            action: BannerItem.Action(label: "Regenerate notes") { [weak self] in self?.requestRegenerate(id, undoManager: undoManager) },
            autoDismiss: 12
        )
    }

    private func registerSpeakerUndo(_ id: UUID, restoring edit: SpeakerEdit, actionName: String, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { state.apply(edit, to: id, actionName: actionName, undoManager: undoManager) }
        }
        undoManager?.setActionName(actionName)
    }

    /// Restores a speaker edit and registers the opposite change, so Undo and Redo swap between them.
    private func apply(_ edit: SpeakerEdit, to id: UUID, actionName: String, undoManager: UndoManager?) {
        guard canEditSpeakers(id), let m = meeting(id) else { return }
        let inverse = SpeakerEdit(m, lines: Set(edit.keys.keys))
        update(id) { m in
            for i in m.utterances.indices {
                if let key = edit.keys[m.utterances[i].id] { m.utterances[i].speakerKey = key }
            }
            m.speakers.merge(edit.speakers) { _, saved in saved }
            m.mode = edit.mode
            m.speakerAliases = edit.speakerAliases
            m.speakersEditedAt = edit.speakersEditedAt
        }
        save(id)
        registerSpeakerUndo(id, restoring: inverse, actionName: actionName, undoManager: undoManager)
    }
}
