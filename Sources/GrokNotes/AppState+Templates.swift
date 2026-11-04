import Foundation

extension AppState {
    // MARK: Summary templates

    func template(for id: UUID) -> SummaryTemplate {
        templateCatalog.resolve(meeting(id)?.templateID)
    }

    func setTemplate(_ templateID: String, for id: UUID) {
        update(id) { $0.templateID = templateID }
        save(id)
    }

    /// The template to offer a regenerate with, when the notes were written with a different one.
    /// Notes from before templates existed count as General meeting.
    func pendingTemplate(for id: UUID) -> SummaryTemplate? {
        guard let m = meeting(id), m.enhancedNotes != nil else { return nil }
        let current = templateCatalog.template(for: m)
        return current.id == (m.notesTemplateID ?? SummaryTemplate.generalID) ? nil : current
    }

    /// Writes notes with the meeting's template. Returns true when the same request also produced topics.
    @discardableResult
    func writeNotes(into m: inout Meeting, client: XAIClient) async throws -> Bool {
        let template = templateCatalog.template(for: m)
        let notes = try await NotesGenerator.enhancedNotes(
            for: m,
            template: template,
            topicVocabulary: Topics.vocabulary(from: meetings, excluding: m.id),
            myName: Prefs.myName,
            client: client.tracking(.notes, m),
            model: Prefs.model
        )
        m.enhancedNotes = notes.markdown
        m.notesTemplateID = template.id
        guard let topics = notes.topics else { return false }
        m.topics = topics
        return true
    }

    func topics(for m: Meeting, client: XAIClient) async throws -> [String] {
        try await NotesGenerator.topics(
            for: m,
            template: templateCatalog.template(for: m),
            topicVocabulary: Topics.vocabulary(from: meetings, excluding: m.id),
            myName: Prefs.myName,
            client: client.tracking(.topics, m),
            model: Prefs.model
        )
    }
}
