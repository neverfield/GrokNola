import XCTest
@testable import GrokNotes

final class SpeakerVoteTallyTests: XCTestCase {
    func testGuessThenConfirm() {
        var tally = SpeakerVoteTally()
        tally.vote("s0-0", name: "Dana Kim", attribution: .activeSpeaker)
        XCTAssertNil(tally.evaluate("s0-0"), "one sample is not enough to show a name")

        tally.vote("s0-0", name: "Dana Kim", attribution: .activeSpeaker)
        let guess = tally.evaluate("s0-0")
        XCTAssertEqual(guess?.name, "Dana Kim")
        XCTAssertEqual(guess?.confirmed, false)

        tally.vote("s0-0", name: "Dana Kim", attribution: .activeSpeaker)
        tally.vote("s0-0", name: "Dana Kim", attribution: .activeSpeaker)
        let confirmed = tally.evaluate("s0-0")
        XCTAssertEqual(confirmed?.confirmed, true)
        XCTAssertEqual(confirmed?.attribution, .activeSpeaker)
        XCTAssertEqual(confirmed?.evidence, "Shown as talking in 4 of 4 live samples")
    }

    func testSplitVotesStayAGuess() {
        var tally = SpeakerVoteTally()
        for _ in 0..<4 { tally.vote("s0-0", name: "Dana", attribution: .activeSpeaker) }
        for _ in 0..<2 { tally.vote("s0-0", name: "Bo", attribution: .activeSpeaker) }
        let decision = tally.evaluate("s0-0")
        XCTAssertEqual(decision?.name, "Dana")
        XCTAssertEqual(decision?.confirmed, false, "4 of 6 is below the 70% bar")
    }

    func testConfirmedNameKeepsAMajority() {
        var tally = SpeakerVoteTally()
        for _ in 0..<4 { tally.vote("s0-0", name: "Dana", attribution: .activeSpeaker) }
        XCTAssertEqual(tally.evaluate("s0-0")?.confirmed, true)
        for _ in 0..<2 { tally.vote("s0-0", name: "Bo", attribution: .activeSpeaker) }
        XCTAssertEqual(tally.evaluate("s0-0")?.confirmed, true, "a confirmed name stays while it has 55% or more")
        for _ in 0..<2 { tally.vote("s0-0", name: "Bo", attribution: .activeSpeaker) }
        let contested = tally.evaluate("s0-0")
        XCTAssertNotEqual(contested?.confirmed, true, "an even split is no longer confirmed")
    }

    func testNamesMatchIgnoringCaseAndPreferFullName() {
        var tally = SpeakerVoteTally()
        tally.vote("k", name: "dana", attribution: .activeSpeaker)
        tally.vote("k", name: "DANA", attribution: .activeSpeaker)
        XCTAssertEqual(tally.evaluate("k")?.weight, 2)
    }

    func testPriorConfirmsAndCanBeWithdrawn() {
        var tally = SpeakerVoteTally()
        tally.setPrior("s0-0", name: "Dana Kim", weight: 4, attribution: .onScreen, note: "Only other invitee")
        let decision = tally.evaluate("s0-0")
        XCTAssertEqual(decision?.confirmed, true)
        XCTAssertEqual(decision?.evidence, "Only other invitee")
        tally.clearPrior("s0-0")
        XCTAssertNil(tally.evaluate("s0-0"))
    }

    func testActiveSpeakerOutvotesAWrongPrior() {
        var tally = SpeakerVoteTally()
        tally.setPrior("s0-0", name: "Dana Kim", weight: 4, attribution: .onScreen, note: "Only other invitee")
        for _ in 0..<12 { tally.vote("s0-0", name: "Bo Li", attribution: .activeSpeaker) }
        let decision = tally.evaluate("s0-0")
        XCTAssertEqual(decision?.name, "Bo Li")
        XCTAssertEqual(decision?.confirmed, true)
    }

    func testMergeFoldsVotes() {
        var tally = SpeakerVoteTally()
        for _ in 0..<2 { tally.vote("s0-0", name: "Dana", attribution: .activeSpeaker) }
        for _ in 0..<2 { tally.vote("s1-0", name: "Dana", attribution: .activeSpeaker) }
        tally.merge("s1-0", into: "s0-0")
        XCTAssertEqual(tally.evaluate("s0-0")?.confirmed, true)
        XCTAssertFalse(tally.hasVotes("s1-0"))
    }
}

final class SelfIntroductionTests: XCTestCase {
    private let people = ["Dana Kim", "Priya Natarajan", "Andrew Parsons"]

    func testListedFirstName() {
        let intro = LiveSpeakerIdentifier.selfIntroduction(in: "Hi everyone, this is Dana from finance.", candidates: people, myName: "Andrew George")
        XCTAssertEqual(intro?.name, "Dana Kim")
        XCTAssertEqual(intro?.listed, true)
    }

    func testMyNameIsAcceptsUnlistedNames() {
        let intro = LiveSpeakerIdentifier.selfIntroduction(in: "Sure, my name is Tomasz and I run support", candidates: people, myName: "Andrew George")
        XCTAssertEqual(intro?.name, "Tomasz")
        XCTAssertEqual(intro?.listed, false)
    }

    func testIgnoresPhrasesThatAreNotIntroductions() {
        for text in ["I'm good, thanks", "This is Great", "this is Dana's doc", "I'm Sorry about that", "It's Monday already"] {
            XCTAssertNil(LiveSpeakerIdentifier.selfIntroduction(in: text, candidates: people, myName: "Andrew George"), text)
        }
    }

    func testNeverNamesTheUser() {
        XCTAssertNil(LiveSpeakerIdentifier.selfIntroduction(in: "Hey, this is Andrew.", candidates: people + ["Andrew George"], myName: "Andrew George"))
    }

    func testNameHere() {
        XCTAssertEqual(LiveSpeakerIdentifier.selfIntroduction(in: "Priya here, sorry I'm late", candidates: people, myName: "")?.name, "Priya Natarajan")
    }
}

final class CarryNamesTests: XCTestCase {
    private func meeting(_ utterances: [Utterance], _ speakers: [String: SpeakerInfo]) -> Meeting {
        var m = Meeting(title: "t", autoTitle: false, startedAt: Date())
        for u in utterances { m.insert(u) }
        m.speakers = speakers
        return m
    }

    private func u(_ key: String, _ start: Double, _ end: Double) -> Utterance {
        Utterance(source: .system, speakerKey: key, start: start, end: end, text: "words")
    }

    func testLiveNamesCarryToReDiarizedVoices() {
        let live = meeting(
            [u("s0-0", 0, 10), u("s0-1", 10, 20), u("s1-0", 30, 40)],
            [
                "s0-0": SpeakerInfo(name: "Dana Kim", attribution: .activeSpeaker, confidence: 0.9, evidence: "x", identifiedLiveAt: 4),
                "s0-1": SpeakerInfo(name: "Bo Li", attribution: .manual, confidence: 1),
                "s1-0": SpeakerInfo(name: "Dana Kim", attribution: .activeSpeaker, confidence: 0.8, identifiedLiveAt: 33),
            ]
        )
        var batch = meeting([u("r0", 0.5, 9.5), u("r1", 10.2, 19.8), u("r0", 30.1, 39.9), u("r2", 50, 55)], [:])
        SpeakerResolver.carryNames(from: live, into: &batch)
        XCTAssertEqual(batch.speakers["r0"]?.name, "Dana Kim")
        XCTAssertEqual(batch.speakers["r0"]?.identifiedLiveAt, 4)
        XCTAssertEqual(batch.speakers["r1"]?.name, "Bo Li")
        XCTAssertEqual(batch.speakers["r1"]?.attribution, .manual)
        XCTAssertNil(batch.speakers["r2"], "a voice that was never heard live gets no name")
    }

    func testMixedOverlapIsNotCarried() {
        let live = meeting(
            [u("s0-0", 0, 5), u("s0-1", 5, 10)],
            [
                "s0-0": SpeakerInfo(name: "Dana", attribution: .activeSpeaker),
                "s0-1": SpeakerInfo(name: "Bo", attribution: .activeSpeaker),
            ]
        )
        var batch = meeting([u("r0", 0, 10)], [:])
        SpeakerResolver.carryNames(from: live, into: &batch)
        XCTAssertNil(batch.speakers["r0"])
    }

    func testGuessesAreNotCarried() {
        let live = meeting([u("s0-0", 0, 10)], ["s0-0": SpeakerInfo(name: "Dana", attribution: .activeSpeaker, provisional: true)])
        var batch = meeting([u("r0", 0, 10)], [:])
        SpeakerResolver.carryNames(from: live, into: &batch)
        XCTAssertNil(batch.speakers["r0"])
    }

    func testLiveMergesCarryThroughReDiarization() {
        var live = meeting(
            [u("s0-0", 0, 10), u("s0-0", 10, 20)],
            ["s0-0": SpeakerInfo(name: "Dana Kim", attribution: .manual, confidence: 1)]
        )
        live.mergeSpeaker("s0-1", into: "s0-0")
        var batch = meeting([u("r0", 0, 10), u("r1", 10, 20)], [:])
        SpeakerResolver.carryNames(from: live, into: &batch)
        SpeakerResolver.carryMerges(from: live, into: &batch)
        XCTAssertEqual(Set(batch.utterances.map(\.speakerKey)), ["r0"])
        XCTAssertEqual(batch.speakers["r0"]?.name, "Dana Kim")
    }

    func testBatchVotesDoNotClobberALiveNameWithWeakEvidence() {
        var m = meeting(
            [u("r0", 0, 10)],
            ["r0": SpeakerInfo(name: "Dana", attribution: .activeSpeaker, confidence: 0.9, identifiedLiveAt: 3)]
        )
        let weak = (0..<4).map { ActiveSpeakerMonitor.Sample(time: Double($0) * 2 + 1, speaking: ["Bo"]) }
        SpeakerResolver.applyActiveSpeakerVotes(to: &m, samples: weak)
        XCTAssertEqual(m.speakers["r0"]?.name, "Dana")

        let strong = (0..<8).map { ActiveSpeakerMonitor.Sample(time: Double($0) + 1, speaking: ["Bo"]) }
        SpeakerResolver.applyActiveSpeakerVotes(to: &m, samples: strong)
        XCTAssertEqual(m.speakers["r0"]?.name, "Bo")
    }
}

@MainActor
final class LiveSpeakerIdentifierTests: XCTestCase {
    private func identifier(attendees: [String]) -> (LiveSpeakerIdentifier, () -> [String: SpeakerInfo]) {
        let id = LiveSpeakerIdentifier(
            config: .init(myName: "Andrew George", attendees: attendees, knownPeople: [], appName: "Zoom", useVision: false),
            monitor: nil, snapshotter: nil, meeting: { nil }
        )
        var latest: [String: SpeakerInfo] = [:]
        id.onChange = { latest = $0 }
        return (id, { latest })
    }

    func testOneOnOneCallIsNamedRightAway() {
        let (id, names) = identifier(attendees: ["Dana Kim"])
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 1, end: 5, text: "Hello, can you hear me?"))
        XCTAssertEqual(names()["s0-0"]?.name, "Dana Kim")
        XCTAssertEqual(names()["s0-0"]?.isProvisional, false)
        XCTAssertEqual(names()["s0-0"]?.identifiedLiveAt, 5)
        // Reconnecting restarts numbering; the same single voice keeps the name.
        id.heard(Utterance(source: .system, speakerKey: "s1-0", start: 40, end: 45, text: "Back again."))
        XCTAssertEqual(names()["s1-0"]?.name, "Dana Kim")
    }

    func testSecondVoiceWithdrawsTheOneOnOneGuess() {
        let (id, names) = identifier(attendees: ["Dana Kim"])
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 1, end: 5, text: "Hello there."))
        id.heard(Utterance(source: .system, speakerKey: "s0-1", start: 6, end: 10, text: "Hi, this is Priya, I joined late."))
        XCTAssertNil(names()["s0-0"])
        XCTAssertNil(names()["s0-1"], "Priya is not listed, so \"this is\" alone does not name her")
    }

    func testMergedVoicesShareEvidence() {
        let (id, names) = identifier(attendees: ["Dana Kim", "Priya Natarajan"])
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 1, end: 5, text: "Hi all, this is Priya."))
        id.heard(Utterance(source: .system, speakerKey: "s0-2", start: 9, end: 12, text: "Priya here, one more thing."))
        XCTAssertEqual(names()["s0-2"]?.isProvisional, true)
        id.merge("s0-2", into: "s0-0")
        XCTAssertNil(names()["s0-2"])
        XCTAssertEqual(names()["s0-0"]?.name, "Priya Natarajan")
        XCTAssertEqual(names()["s0-0"]?.isProvisional, false)
    }

    func testRestoreUndoSnapshotAfterMerge() {
        let (id, names) = identifier(attendees: ["Dana Kim", "Priya Natarajan"])
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 1, end: 5, text: "Hi all, this is Priya."))
        id.heard(Utterance(source: .system, speakerKey: "s0-2", start: 9, end: 12, text: "Priya here, one more thing."))
        let snap = id.undoSnapshot()
        id.merge("s0-2", into: "s0-0")
        XCTAssertNil(names()["s0-2"])
        id.restore(snap)
        XCTAssertEqual(names()["s0-2"]?.name, "Priya Natarajan")
        XCTAssertEqual(names()["s0-0"]?.name, "Priya Natarajan")
        XCTAssertEqual(names()["s0-0"]?.isProvisional, true)
        XCTAssertEqual(names()["s0-2"]?.isProvisional, true)
    }

    func testVoiceMergedIntoMeIsNeverNamed() {
        let (id, names) = identifier(attendees: ["Dana Kim", "Priya Natarajan"])
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 1, end: 5, text: "Hi all, this is Priya."))
        id.merge("s0-0", into: Meeting.meKey)
        XCTAssertTrue(names().isEmpty)
    }

    func testListedIntroductionIsAGuess() {
        let (id, names) = identifier(attendees: ["Dana Kim", "Priya Natarajan"])
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 1, end: 5, text: "Hi all, this is Priya."))
        XCTAssertEqual(names()["s0-0"]?.name, "Priya Natarajan")
        XCTAssertEqual(names()["s0-0"]?.isProvisional, true)
        id.heard(Utterance(source: .system, speakerKey: "s0-0", start: 30, end: 33, text: "Priya here again."))
        XCTAssertEqual(names()["s0-0"]?.isProvisional, false)
    }
}

final class BackwardCompatibleDecodingTests: XCTestCase {
    func testSpeakerInfoWithoutNewFieldsDecodes() throws {
        let json = #"{"name":"Dana","attribution":"activeSpeaker","confidence":0.8,"evidence":"x"}"#
        let info = try JSONDecoder().decode(SpeakerInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.name, "Dana")
        XCTAssertNil(info.provisional)
        XCTAssertNil(info.identifiedLiveAt)
        XCTAssertFalse(info.isProvisional)
    }

    /// Reads, never writes, the meetings on this Mac.
    func testExistingMeetingsStillDecode() throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes/Meetings", isDirectory: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var checked = 0
        for dir in dirs {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meeting.json")) else { continue }
            XCTAssertNoThrow(try decoder.decode(Meeting.self, from: data), dir.lastPathComponent)
            checked += 1
        }
        print("Decoded \(checked) existing meeting.json files")
    }
}
