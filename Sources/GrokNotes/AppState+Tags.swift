import Foundation

extension AppState {
    // MARK: Meeting tags

    func addTag(_ name: String, to id: UUID) {
        let tag = tagCatalog.register(name, dynamic: false)
        guard !tag.isEmpty, let m = meeting(id), !m.hasTag(tag) else { return }
        update(id) { $0.tags = $0.tagList + [tag] }
        save(id)
    }

    func removeTag(_ name: String, from id: UUID) {
        update(id) { m in
            let remaining = m.tagList.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            m.tags = remaining.isEmpty ? nil : remaining
        }
        save(id)
    }

    func toggleTag(_ name: String, on id: UUID) {
        if meeting(id)?.hasTag(name) == true { removeTag(name, from: id) } else { addTag(name, to: id) }
    }

    func togglePin(_ id: UUID) {
        update(id) { $0.pinned = $0.isPinned ? nil : true }
        save(id)
    }

    // MARK: Catalog edits that touch meetings

    func renameTag(_ tagID: UUID, to newName: String) {
        guard let old = tagCatalog.tags.first(where: { $0.id == tagID })?.name else { return }
        tagCatalog.rename(tagID, to: newName)
        let new = tagCatalog.canonical(newName)
        guard !new.isEmpty, new != old else { return }
        rewriteTags { tags in
            uniqueNames(tags.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 })
        }
    }

    func deleteTag(_ tagID: UUID) {
        guard let name = tagCatalog.tags.first(where: { $0.id == tagID })?.name else { return }
        tagCatalog.remove(tagID)
        rewriteTags { $0.filter { $0.caseInsensitiveCompare(name) != .orderedSame } }
    }

    func usageCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for m in meetings {
            for tag in m.tagList { counts[tag.lowercased(), default: 0] += 1 }
        }
        return counts
    }

    private func rewriteTags(_ transform: ([String]) -> [String]) {
        for m in meetings where !m.tagList.isEmpty {
            let updated = transform(m.tagList)
            guard updated != m.tagList else { continue }
            update(m.id) { $0.tags = updated.isEmpty ? nil : updated }
            save(m.id)
        }
    }

    // MARK: Grok suggestions

    /// Manual "Suggest tags" from the inspector or the context menu.
    func suggestTags(_ id: UUID) async {
        do {
            await applySuggestedTags(id, client: try XAIClient.fromSettings())
        } catch {
            reportError(error)
        }
    }

    /// Adds Grok's tags to the meeting. Never removes a tag. Returns false only when the request failed.
    @discardableResult
    func applySuggestedTags(_ id: UUID, client: XAIClient, reportErrors: Bool = true) async -> Bool {
        let allowNew = Prefs.dynamicTags
        guard let m = meeting(id), !tagCatalog.tagging.contains(id), allowNew || !tagCatalog.tags.isEmpty else { return true }
        tagCatalog.tagging.insert(id)
        defer { tagCatalog.tagging.remove(id) }
        do {
            let suggestion = try await TagSuggester.suggest(
                for: m, catalog: tagCatalog.tags, allowNew: allowNew, myName: Prefs.myName,
                client: client.tracking(.tags, m), model: Prefs.model
            )
            let added = suggestion.existing + suggestion.new.map { tagCatalog.register($0, dynamic: true) }
            guard let current = meeting(id) else { return true }
            let merged = uniqueNames(current.tagList + added)
            if merged != current.tagList {
                update(id) { $0.tags = merged.isEmpty ? nil : merged }
                save(id)
            }
            return true
        } catch {
            if reportErrors { reportError(error, "Grok could not suggest tags.") }
            return false
        }
    }

    // MARK: Backfill

    var untaggedMeetings: [Meeting] {
        meetings.filter { m in
            m.tagList.isEmpty && m.id != recordingID && !processing.contains(m.id)
                && (m.enhancedNotes != nil || !m.userNotes.isEmpty || !m.utterances.isEmpty)
        }
    }

    func estimatedBackfillCost() -> Double {
        untaggedMeetings.reduce(0) { $0 + TagSuggester.estimatedCost(for: $1, catalogSize: tagCatalog.tags.count) }
    }

    /// Tags every untagged meeting, one request at a time.
    func tagAllUntagged() async {
        guard tagCatalog.backfill == nil else { return }
        let client: XAIClient
        do {
            client = try XAIClient.fromSettings()
        } catch {
            reportError(error)
            return
        }
        let ids = untaggedMeetings.map(\.id)
        guard !ids.isEmpty else { return }
        tagCatalog.backfillCancelled = false
        tagCatalog.backfill = TagBackfillProgress(done: 0, total: ids.count)
        defer { tagCatalog.backfill = nil }
        var failures = 0
        for (index, id) in ids.enumerated() {
            if tagCatalog.backfillCancelled { break }
            if await !applySuggestedTags(id, client: client, reportErrors: false) { failures += 1 }
            tagCatalog.backfill = TagBackfillProgress(done: index + 1, total: ids.count)
        }
        if failures > 0 { showBanner("Grok could not tag \(failures) of \(ids.count) meetings.", severity: .warning) }
    }
}
