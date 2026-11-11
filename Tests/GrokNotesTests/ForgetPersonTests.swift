import XCTest
@testable import GrokNotes

final class ForgetPersonTests: XCTestCase {
    private func meeting() -> Meeting {
        var m = Meeting(title: "Sync", autoTitle: false, startedAt: Date())
        m.utterances = [
            Utterance(source: .system, speakerKey: "r0", start: 0, end: 1, text: "Thanks, Dana Ruiz."),
            Utterance(source: .system, speakerKey: "r1", start: 1, end: 2, text: "Sure."),
            Utterance(source: .mic, speakerKey: Meeting.meKey, start: 2, end: 3, text: "Hi."),
        ]
        m.speakers = [
            "r0": SpeakerInfo(name: "Dana Ruiz", attribution: .manual, confidence: 1, evidence: "set"),
            "r1": SpeakerInfo(name: "Eli", attribution: .inferred, confidence: 0.8, evidence: nil),
            Meeting.meKey: SpeakerInfo(name: nil, attribution: .me),
        ]
        m.mode = .named
        return m
    }

    func testClearsMatchingSpeakersButKeepsTranscriptText() {
        var m = meeting()
        let text = m.utterances.map(\.text)
        XCTAssertEqual(m.forgetSpeaker(named: "  dana ruiz "), 1)
        XCTAssertNil(m.speakers["r0"]?.name)
        XCTAssertEqual(m.speakers["r0"]?.attribution, .unknown)
        XCTAssertNil(m.speakers["r0"]?.evidence)
        XCTAssertEqual(m.speakers["r1"]?.name, "Eli")
        XCTAssertEqual(m.utterances.map(\.text), text)
        XCTAssertEqual(m.mode, .named)
    }

    func testModeFallsBackWhenNoNamedSpeakerIsLeft() {
        var m = meeting()
        m.forgetSpeaker(named: "Dana Ruiz")
        m.forgetSpeaker(named: "ELI")
        XCTAssertEqual(m.mode, .meThem)
    }

    func testYourOwnKeyStaysYou() {
        var m = meeting()
        m.speakers[Meeting.meKey] = SpeakerInfo(name: "Ana", attribution: .manual)
        m.forgetSpeaker(named: "ana")
        XCTAssertEqual(m.speakers[Meeting.meKey]?.attribution, .me)
        XCTAssertNil(m.speakers[Meeting.meKey]?.name)
    }

    func testNoMatchOrBlankNameChangesNothing() {
        var m = meeting()
        XCTAssertEqual(m.forgetSpeaker(named: "Dan"), 0)
        XCTAssertEqual(m.forgetSpeaker(named: "   "), 0)
        XCTAssertEqual(m.speakers["r0"]?.name, "Dana Ruiz")
    }

    func testRemovesFromRememberedPeopleIgnoringCase() {
        XCTAssertEqual(Prefs.removing(" dana ruiz", from: ["Dana Ruiz", "Eli", "dana ruiz"]), ["Eli"])
        XCTAssertEqual(Prefs.removing("Zed", from: ["Eli"]), ["Eli"])
    }
}
