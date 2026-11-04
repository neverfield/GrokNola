import Foundation

extension AppState {
    // MARK: Meeting player

    /// Plays the meeting from a time and keeps going.
    func playMeeting(_ id: UUID, from seconds: Double) {
        guard recordingID != id, let m = meeting(id) else { return }
        if !clips.play(m, from: seconds) {
            banner = "The audio for this meeting is no longer on this Mac."
        }
    }

    func togglePlayback(_ id: UUID) {
        guard recordingID != id, let m = meeting(id), clips.load(m) else { return }
        clips.togglePlayPause()
    }

    func seekPlayback(_ id: UUID, to seconds: Double) {
        guard recordingID != id, let m = meeting(id), clips.load(m) else { return }
        clips.seek(to: seconds)
    }

    func skipPlayback(_ id: UUID, by delta: Double) {
        guard recordingID != id, let m = meeting(id), clips.load(m) else { return }
        clips.skip(delta)
    }

    /// Plays from a chapter's start, or shows it in the transcript when the audio was not kept.
    func openChapter(_ id: UUID, _ chapter: Chapter) {
        if canPlayClips(id) {
            playMeeting(id, from: chapter.start)
        } else {
            focusTranscript(id, at: chapter.start)
        }
    }

    // MARK: Chapters

    /// Splits an older meeting into chapters and takes its topics from them.
    func findChapters(_ id: UUID) async {
        guard let m = meeting(id), !m.utterances.isEmpty, !findingTopics.contains(id) else { return }
        findingTopics.insert(id)
        defer { findingTopics.remove(id) }
        do {
            let client = try XAIClient.fromSettings()
            guard let chapters = try await self.chapters(for: m, client: client) else {
                banner = "Grok could not split this meeting into chapters."
                return
            }
            let topics = Chapters.topics(from: chapters, vocabulary: Topics.vocabulary(from: meetings, excluding: id))
            update(id) {
                $0.chapters = chapters
                if !topics.isEmpty { $0.topics = topics }
            }
            save(id)
        } catch {
            banner = "Grok could not find the chapters: \(error.localizedDescription)"
        }
    }
}
