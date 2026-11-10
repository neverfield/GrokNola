import XCTest
@testable import GrokNotes

final class EchoFilterTests: XCTestCase {
    private func mic(_ text: String, _ start: Double, _ end: Double) -> Utterance {
        Utterance(source: .mic, speakerKey: Meeting.meKey, start: start, end: end, text: text)
    }

    private func system(_ text: String, _ start: Double, _ end: Double) -> Utterance {
        Utterance(source: .system, speakerKey: "s0-0", start: start, end: end, text: text)
    }

    func testDropsAnEchoOfOverlappingCallAudio() {
        let them = system("So the launch moves to Thursday because the build is not ready.", 10, 14)
        let echo = mic("so the launch moves to thursday because the build isn't ready", 10.3, 14.2)
        XCTAssertEqual(EchoFilter.echoIDs(in: [them, echo]), [echo.id])
    }

    func testDropsAnEchoWithTranscriptionErrors() {
        let them = system("We should ship the beta to the design partners next week.", 20, 24)
        let echo = mic("we should ship a beta to design partners next weak", 20.2, 24.1)
        XCTAssertTrue(EchoFilter.isEcho(echo, system: [them]))
    }

    func testDropsAnEchoSplitAcrossTwoCallLines() {
        let first = system("Can everyone see my screen?", 30, 31.5)
        let second = system("I am sharing the roadmap now.", 31.6, 33)
        let echo = mic("can everyone see my screen I am sharing the roadmap now", 30.2, 33.1)
        XCTAssertTrue(EchoFilter.isEcho(echo, system: [first, second]))
    }

    func testKeepsTheSameWordsAtADifferentTime() {
        let them = system("So the launch moves to Thursday because the build is not ready.", 10, 14)
        let later = mic("so the launch moves to thursday because the build is not ready", 30, 34)
        XCTAssertTrue(EchoFilter.echoIDs(in: [them, later]).isEmpty)
    }

    func testKeepsAReplyThatQuotesTheCall() {
        let them = system("Is the launch on Thursday?", 10, 11.5)
        let reply = mic("no I don't think the launch can be on Thursday at all", 12, 15)
        XCTAssertFalse(EchoFilter.isEcho(reply, system: [them]))
    }

    func testKeepsOwnSpeechThatOverlapsCallAudio() {
        let them = system("Let's move on to the budget review for next quarter.", 10, 13)
        let mine = mic("sorry before that can we talk about hiring", 11, 13.5)
        XCTAssertFalse(EchoFilter.isEcho(mine, system: [them]))
    }

    func testShortLinesNeedTheSameWordsAtTheSameMoment() {
        let them = system("Yeah.", 10, 10.4)
        XCTAssertTrue(EchoFilter.isEcho(mic("yeah", 10.2, 10.6), system: [them]))
        // Two people saying "yeah" a couple of seconds apart both stay.
        XCTAssertFalse(EchoFilter.isEcho(mic("yeah", 11.8, 12.2), system: [them]))
        XCTAssertFalse(EchoFilter.isEcho(mic("okay", 10.2, 10.6), system: [them]))
    }

    func testShortLineInsideALongerCallLineStays() {
        let them = system("Yeah, I think that works for the team.", 10, 13)
        XCTAssertFalse(EchoFilter.isEcho(mic("yeah", 10.1, 10.4), system: [them]))
    }

    func testMediumLinesNeedNearlyEveryWord() {
        let them = system("Sounds good to me.", 10, 11)
        XCTAssertTrue(EchoFilter.isEcho(mic("sounds good to me", 10.1, 11.1), system: [them]))
        XCTAssertFalse(EchoFilter.isEcho(mic("that sounds good", 10.1, 11.1), system: [them]))
    }

    func testIgnoresMicLinesWithoutCallAudio() {
        let mine = mic("let me share my screen", 5, 7)
        XCTAssertTrue(EchoFilter.echoIDs(in: [mine]).isEmpty)
    }

    func testInterimTextAgainstRecentCallAudio() {
        XCTAssertTrue(EchoFilter.isEchoText("the build is not ready", of: "so the launch moves to Thursday because the build is not ready"))
        XCTAssertFalse(EchoFilter.isEchoText("yeah", of: "yeah"))
        XCTAssertFalse(EchoFilter.isEchoText("can we talk about hiring", of: "let's move on to the budget review"))
    }

    func testNormalizedWords() {
        XCTAssertEqual(EchoFilter.normalizedWords("Yeah, it's   READY."), ["yeah", "its", "ready"])
    }
}
