import Foundation

/// Weighted votes for who each diarized voice is. A name is shown as a guess once it leads, and confirmed
/// once it has enough weight and a clear majority. A confirmed name stays confirmed while it keeps a majority,
/// so one stray vote does not make it flicker.
struct SpeakerVoteTally {
    struct Thresholds {
        /// Weight and share a name needs to be confirmed.
        var confirmWeight = 4.0
        var confirmShare = 0.7
        /// A confirmed name stays confirmed while its share is at least this.
        var keepShare = 0.55
        /// Weight and share a name needs to be shown as a guess.
        var guessWeight = 2.0
        var guessShare = 0.5
    }

    struct Decision: Equatable {
        var name: String
        var confirmed: Bool
        var weight: Double
        /// The leading name's part of all weight for the voice, 0 to 1.
        var share: Double
        var attribution: Attribution
        var evidence: String
    }

    private struct Bucket {
        var name: String
        var weight = 0.0
        var byAttribution: [Attribution: Double] = [:]
        var activeSpeakerSamples = 0
        var notes: [String] = []

        mutating func add(_ weight: Double, _ attribution: Attribution, note: String?) {
            self.weight += weight
            byAttribution[attribution, default: 0] += weight
            if attribution == .activeSpeaker { activeSpeakerSamples += 1 }
            if let note, !notes.contains(note) { notes.append(note) }
        }
    }

    private struct Prior {
        var name: String
        var weight: Double
        var attribution: Attribution
        var note: String
    }

    var thresholds = Thresholds()
    private var votes: [String: [String: Bucket]] = [:]
    private var priors: [String: Prior] = [:]
    private var confirmed: [String: String] = [:]

    init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    mutating func vote(_ key: String, name: String, weight: Double = 1, attribution: Attribution, note: String? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, weight > 0 else { return }
        let slot = name.lowercased()
        var bucket = votes[key]?[slot] ?? Bucket(name: name)
        // A full name replaces a bare first name for the same person.
        if name.count > bucket.name.count { bucket.name = name }
        bucket.add(weight, attribution, note: note)
        votes[key, default: [:]][slot] = bucket
    }

    /// Evidence that holds while a condition does, such as "this is a one-on-one call". Replaces the voice's earlier prior.
    mutating func setPrior(_ key: String, name: String, weight: Double, attribution: Attribution, note: String) {
        priors[key] = Prior(name: name, weight: weight, attribution: attribution, note: note)
    }

    mutating func clearPrior(_ key: String) {
        priors[key] = nil
    }

    /// Folds one voice's votes into another, after the user merged them.
    mutating func merge(_ from: String, into target: String) {
        guard from != target else { return }
        for (slot, bucket) in votes[from] ?? [:] {
            var merged = votes[target]?[slot] ?? Bucket(name: bucket.name)
            merged.weight += bucket.weight
            merged.activeSpeakerSamples += bucket.activeSpeakerSamples
            for (attribution, weight) in bucket.byAttribution { merged.byAttribution[attribution, default: 0] += weight }
            for note in bucket.notes where !merged.notes.contains(note) { merged.notes.append(note) }
            votes[target, default: [:]][slot] = merged
        }
        if priors[target] == nil { priors[target] = priors[from] }
        forget(from)
    }

    mutating func forget(_ key: String) {
        votes[key] = nil
        priors[key] = nil
        confirmed[key] = nil
    }

    func hasVotes(_ key: String) -> Bool {
        votes[key] != nil || priors[key] != nil
    }

    /// The current name for a voice, or nil when no name leads clearly enough to show.
    mutating func evaluate(_ key: String) -> Decision? {
        var buckets = votes[key] ?? [:]
        if let prior = priors[key] {
            let slot = prior.name.lowercased()
            var bucket = buckets[slot] ?? Bucket(name: prior.name)
            bucket.add(prior.weight, prior.attribution, note: prior.note)
            buckets[slot] = bucket
        }
        let total = buckets.values.reduce(0) { $0 + $1.weight }
        guard total > 0, let (slot, leader) = buckets.max(by: { $0.value.weight < $1.value.weight }) else {
            confirmed[key] = nil
            return nil
        }
        let share = leader.weight / total
        let wasConfirmed = confirmed[key] == slot
        let isConfirmed = (leader.weight >= thresholds.confirmWeight && share >= thresholds.confirmShare)
            || (wasConfirmed && share >= thresholds.keepShare)
        confirmed[key] = isConfirmed ? slot : nil
        guard isConfirmed || (leader.weight >= thresholds.guessWeight && share >= thresholds.guessShare) else { return nil }

        let attribution = leader.byAttribution.max(by: { $0.value < $1.value })?.key ?? .inferred
        var evidence: [String] = []
        if leader.activeSpeakerSamples > 0 {
            let all = buckets.values.reduce(0) { $0 + $1.activeSpeakerSamples }
            evidence.append("Shown as talking in \(leader.activeSpeakerSamples) of \(all) live samples")
        }
        evidence += leader.notes
        return Decision(
            name: leader.name,
            confirmed: isConfirmed,
            weight: leader.weight,
            share: share,
            attribution: attribution,
            evidence: evidence.joined(separator: "; ")
        )
    }
}

/// Names remote voices while the meeting is recorded, instead of only after it ends.
///
/// Evidence, as votes in a `SpeakerVoteTally`:
/// - The meeting app's "who is talking" indicator, polled once a second by `ActiveSpeakerMonitor`, matched to the
///   diarized voice whose words cover that moment. One vote per sample.
/// - A self-introduction in what the voice said ("Hi, this is Dana"), strongest when the name is an invitee.
/// - A one-on-one call: one other invitee and one remote voice per connection.
/// - Now and then, Grok reading the call-window snapshots for a voice that is still unnamed, at most once a minute.
///
/// It reports names through `onChange`. The caller keeps names the user set.
@MainActor
final class LiveSpeakerIdentifier {
    /// Enough state to put live naming back how it was before a speaker merge was undone.
    struct UndoSnapshot {
        var tally: SpeakerVoteTally
        var speech: [String: (first: Double, seconds: Double)]
        var pending: [Utterance]
        var firstNamedAt: [String: Double]
        var published: [String: SpeakerInfo]
        var lastCountedSample: [String: Double]
    }

    struct Config {
        var myName: String
        /// Calendar invitees, without the user.
        var attendees: [String]
        /// Names a self-introduction is matched against: invitees and people from past meetings.
        var knownPeople: [String]
        var appName: String?
        /// Ask Grok about the call-window snapshots for voices that stay unnamed.
        var useVision: Bool
    }

    static let introWeight = 3.0
    static let unlistedIntroWeight = 2.0
    static let soleParticipantWeight = 4.0
    static let visionInterval: Double = 60
    static let maxVisionRequests = 8
    /// A voice must have talked this long, and been heard this long ago, before Grok is asked about it.
    static let visionMinSpeech: Double = 6
    static let visionMinAge: Double = 30

    /// Every voice that currently has a name, confirmed or not. Called on the main actor when it changes.
    var onChange: (([String: SpeakerInfo]) -> Void)?

    private let config: Config
    private let monitor: ActiveSpeakerMonitor?
    private weak var snapshotter: WindowSnapshotter?
    private let meeting: () -> Meeting?
    private var tally = SpeakerVoteTally()

    private var sampleCursor = 0
    private var soloSamples: [ActiveSpeakerMonitor.Sample] = []
    private var latestSampleTime = -Double.infinity
    private var shownNames: [String: Int] = [:]
    private var pending: [Utterance] = []
    private var lastCountedSample: [String: Double] = [:]

    private var speech: [String: (first: Double, seconds: Double)] = [:]
    private var firstNamedAt: [String: Double] = [:]
    private var published: [String: SpeakerInfo] = [:]
    private var now: Double = 0

    private var visionTask: Task<Void, Never>?
    private var lastVisionAt = -Double.infinity
    private var visionTriedAt: [String: Double] = [:]
    private var visionRequests = 0
    private var stopped = false

    init(config: Config, monitor: ActiveSpeakerMonitor?, snapshotter: WindowSnapshotter?, meeting: @escaping () -> Meeting?) {
        self.config = config
        self.monitor = monitor
        self.snapshotter = config.useVision ? snapshotter : nil
        self.meeting = meeting
    }

    /// Names that were only guesses when recording stopped, as extra candidates for naming after the meeting.
    var guessedNames: [String] {
        published.values.filter(\.isProvisional).compactMap(\.name)
    }

    /// A finished utterance from the call audio.
    func heard(_ u: Utterance) {
        guard !stopped, u.speakerKey != Meeting.meKey else { return }
        now = max(now, u.end)
        var spoken = speech[u.speakerKey] ?? (u.start, 0)
        spoken.seconds += max(0, u.end - u.start)
        speech[u.speakerKey] = spoken

        if let intro = Self.selfIntroduction(in: u.text, candidates: config.attendees + config.knownPeople + Array(shownNames.keys), myName: config.myName) {
            tally.vote(
                u.speakerKey, name: intro.name,
                weight: intro.listed ? Self.introWeight : Self.unlistedIntroWeight,
                attribution: .inferred,
                note: "Introduced themselves: \"\(Self.excerpt(u.text))\""
            )
        }
        if monitor != nil { pending.append(u) }
        refreshSoleParticipant()
        publish()
    }

    /// Called once a second with the meeting time.
    func tick(at time: Double) {
        guard !stopped else { return }
        now = max(now, time)
        pullSamples()
        countPendingVotes(force: false)
        refreshSoleParticipant()
        publish()
        askVisionIfNeeded()
    }

    func undoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            tally: tally,
            speech: speech,
            pending: pending,
            firstNamedAt: firstNamedAt,
            published: published,
            lastCountedSample: lastCountedSample
        )
    }

    func restore(_ snapshot: UndoSnapshot) {
        tally = snapshot.tally
        speech = snapshot.speech
        pending = snapshot.pending
        firstNamedAt = snapshot.firstNamedAt
        lastCountedSample = snapshot.lastCountedSample
        published = [:]
        publish()
    }

    /// The user merged one voice into another. A voice merged into you is dropped; you are never named here.
    func merge(_ from: String, into target: String) {
        guard from != target else { return }
        if target == Meeting.meKey {
            tally.forget(from)
            speech[from] = nil
            pending.removeAll { $0.speakerKey == from }
            firstNamedAt[from] = nil
            publish()
            return
        }
        tally.merge(from, into: target)
        if let moved = speech.removeValue(forKey: from) {
            speech[target] = speech[target].map { (min($0.first, moved.first), $0.seconds + moved.seconds) } ?? moved
        }
        for i in pending.indices where pending[i].speakerKey == from { pending[i].speakerKey = target }
        firstNamedAt[from] = nil
        publish()
    }

    /// Counts the last votes and stops. Names already reported stay with the caller.
    func finish() {
        guard !stopped else { return }
        pullSamples()
        countPendingVotes(force: true)
        publish()
        stopped = true
        visionTask?.cancel()
        visionTask = nil
    }

    // MARK: Active speaker

    private func pullSamples() {
        guard let monitor else { return }
        let (samples, next) = monitor.samples(from: sampleCursor)
        sampleCursor = next
        for sample in samples {
            latestSampleTime = max(latestSampleTime, sample.time)
            for name in sample.speaking { shownNames[name, default: 0] += 1 }
            if sample.speaking.count == 1 { soloSamples.append(sample) }
        }
        // Keep enough history for utterances that arrive late.
        let horizon = min(pending.map(\.start).min() ?? latestSampleTime, latestSampleTime) - 5
        if let firstKept = soloSamples.firstIndex(where: { $0.time >= horizon }) {
            if firstKept > 0 { soloSamples.removeFirst(firstKept) }
        } else {
            soloSamples.removeAll()
        }
    }

    /// Votes for each utterance once the samples around it have come in. `force` counts the rest at the end.
    private func countPendingVotes(force: Bool) {
        var waiting: [Utterance] = []
        for u in pending {
            guard force || u.end + 1 <= latestSampleTime else {
                // Without samples for a long time, the monitor is not seeing the call.
                if now - u.end < 30 { waiting.append(u) }
                continue
            }
            let after = lastCountedSample[u.speakerKey] ?? -Double.infinity
            for sample in soloSamples where sample.time > after && sample.time >= u.start - 0.5 && sample.time <= u.end + 1 {
                tally.vote(u.speakerKey, name: sample.speaking[0], attribution: .activeSpeaker)
                lastCountedSample[u.speakerKey] = max(lastCountedSample[u.speakerKey] ?? sample.time, sample.time)
            }
        }
        pending = waiting
        if force { pending = [] }
    }

    // MARK: One-on-one calls

    /// With one other invitee and one remote voice per connection, every remote voice is that invitee.
    /// The prior is withdrawn as soon as a second voice or a second name shows up.
    private func refreshSoleParticipant() {
        let invitees = uniqueNames(config.attendees.filter { !SpeakerResolver.isLikelyUser($0, myName: config.myName) })
        let shown = shownNames.filter { $0.value >= 3 }.map(\.key)
        var sole: (name: String, note: String)?
        if invitees.count == 1 {
            let other = shown.contains { name in
                let n = name.lowercased(), invitee = invitees[0].lowercased()
                return n != invitee && !invitee.hasPrefix(n + " ") && !n.hasPrefix(invitee + " ")
            }
            if !other { sole = (invitees[0], "Only other invitee") }
        } else if invitees.isEmpty, shown.count == 1 {
            sole = (shown[0], "Only other participant shown in the call")
        }
        let voices = speech.filter { $0.value.seconds >= 3 }.map(\.key)
        let byConnection = Dictionary(grouping: voices, by: Self.connection(of:))
        let oneVoice = byConnection.values.allSatisfy { $0.count <= 1 }
        for key in speech.keys {
            if let sole, oneVoice {
                tally.setPrior(key, name: sole.name, weight: Self.soleParticipantWeight, attribution: .onScreen, note: sole.note)
            } else {
                tally.clearPrior(key)
            }
        }
    }

    /// Live keys look like `s<connection>-<speaker>`. Speaker numbers restart on each connection.
    nonisolated static func connection(of key: String) -> String {
        guard let dash = key.firstIndex(of: "-") else { return key }
        return String(key[..<dash])
    }

    // MARK: Vision

    private func askVisionIfNeeded() {
        guard visionTask == nil, let snapshotter, visionRequests < Self.maxVisionRequests,
              now - lastVisionAt >= Self.visionInterval
        else { return }
        let waiting = speech.filter { key, spoken in
            !(published[key].map { !$0.isProvisional } ?? false)
                && spoken.seconds >= Self.visionMinSpeech
                && now - spoken.first >= Self.visionMinAge
                && now - (visionTriedAt[key] ?? -Double.infinity) >= 2 * Self.visionInterval
        }
        guard let key = waiting.max(by: { $0.value.seconds < $1.value.seconds })?.key,
              let m = meeting(), let client = try? XAIClient.fromSettings()
        else { return }
        let frames = SpeakerResolver.pickFrames(for: key, in: m, from: snapshotter.frames, limit: 2)
        guard !frames.isEmpty else { return }
        lastVisionAt = now
        visionTriedAt[key] = now
        visionRequests += 1
        let config = config
        let tracked = client.tracking(.vision, m)
        visionTask = Task { [weak self] in
            let result = try? await SpeakerResolver.identifyLive(
                key: key, frames: frames, appName: config.appName, myName: config.myName, client: tracked, model: Prefs.model
            )
            guard let self else { return }
            self.visionTask = nil
            guard !self.stopped, !Task.isCancelled, let result, result.confidence >= 0.7 else { return }
            self.tally.vote(
                key, name: result.name,
                weight: result.confidence >= 0.8 ? 4 : 3,
                attribution: .onScreen,
                note: result.evidence.map { "Call window: \($0)" } ?? "Highlighted in the call window"
            )
            self.publish()
        }
    }

    // MARK: Output

    private func publish() {
        var next: [String: SpeakerInfo] = [:]
        for key in speech.keys where tally.hasVotes(key) {
            guard let decision = tally.evaluate(key) else { continue }
            let at = firstNamedAt[key] ?? now
            firstNamedAt[key] = at
            next[key] = SpeakerInfo(
                name: decision.name,
                attribution: decision.attribution,
                confidence: (decision.share * 100).rounded() / 100,
                evidence: decision.evidence,
                provisional: decision.confirmed ? nil : true,
                identifiedLiveAt: at
            )
        }
        guard next != published else { return }
        published = next
        onChange?(next)
    }

    // MARK: Self-introductions

    nonisolated private static let introPatterns: [(regex: NSRegularExpression, needsListed: Bool)] = [
        (#"\b(?i:my name is|my name's)\s+(\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)?)"#, false),
        (#"\b(?i:this is|it's|it is)\s+(\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)?)(?=\s*(?:$|[,.!]|\s(?i:here|speaking|from|with|on)\b))"#, true),
        (#"\b(?i:i'm|i’m|i am)\s+(\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)?)"#, true),
        (#"^(?:(?i:hi|hey|hello)[,!]?\s+)?(\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)?)\s+(?i:here)\b"#, true),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    nonisolated private static let notNames: Set<String> = [
        "just", "not", "so", "the", "going", "sorry", "good", "fine", "here", "back", "sure", "really", "okay", "ok",
        "happy", "glad", "excited", "trying", "looking", "thinking", "also", "still", "actually", "on", "in", "with",
    ]

    /// A name the speaker gave for themselves, and whether it matched a listed person.
    /// "This is", "I'm", and "<name> here" count only for listed names; "my name is" counts for any name.
    nonisolated static func selfIntroduction(in text: String, candidates: [String], myName: String) -> (name: String, listed: Bool)? {
        let range = NSRange(text.startIndex..., in: text)
        for (regex, needsListed) in introPatterns {
            for match in regex.matches(in: text, range: range) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                let captured = String(text[r]).trimmingCharacters(in: .punctuationCharacters)
                if captured.hasSuffix("'s") || captured.hasSuffix("’s") { continue }
                // "This is Dana Kim" or "this is Dana Can you hear me": try the longer name, then the first word.
                let words = captured.split(separator: " ").map(String.init)
                for spoken in words.count > 1 ? [captured, words[0]] : [captured] {
                    guard !notNames.contains(spoken.lowercased()), !SpeakerResolver.isLikelyUser(spoken, myName: myName) else { continue }
                    if let listed = listedName(spoken, in: candidates) {
                        guard !SpeakerResolver.isLikelyUser(listed, myName: myName) else { continue }
                        return (listed, true)
                    }
                    if !needsListed, spoken == captured { return (spoken, false) }
                }
            }
        }
        return nil
    }

    /// The listed person a spoken name refers to: the full name, or a first name only one listed person has.
    nonisolated private static func listedName(_ spoken: String, in candidates: [String]) -> String? {
        let s = spoken.lowercased()
        let people = uniqueNames(candidates)
        if let exact = people.first(where: { $0.lowercased() == s }) { return exact }
        let byFirst = people.filter { $0.lowercased().split(separator: " ").first.map(String.init) == s }
        return byFirst.count == 1 ? byFirst[0] : nil
    }

    private static func excerpt(_ text: String) -> String {
        text.count <= 80 ? text : String(text.prefix(77)) + "…"
    }
}
