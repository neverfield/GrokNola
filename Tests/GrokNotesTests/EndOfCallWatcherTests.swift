import XCTest
@testable import GrokNotes

final class EndOfCallWatcherTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    private func check(
        _ w: inout EndOfCallWatcher,
        _ seconds: Double,
        spoke: Double = 0,
        window: Bool? = nil,
        eventEnd: Double? = nil
    ) -> EndOfCallWatcher.Event? {
        w.check(now: at(seconds), lastSpeech: at(spoke), callWindowOpen: window, appName: "Zoom", eventEnd: eventEnd.map(at))
    }

    func testAsksAfterSilenceThenStopsWhenUnanswered() {
        var w = EndOfCallWatcher(silence: 300)
        XCTAssertNil(check(&w, 299))
        guard case .ask(let prompt)? = check(&w, 300) else { return XCTFail("expected a prompt") }
        XCTAssertEqual(prompt.reason, .silence(minutes: 5))
        XCTAssertNil(check(&w, 419))
        XCTAssertEqual(check(&w, 420), .stop)
    }

    func testSpeechWithdrawsThePrompt() {
        var w = EndOfCallWatcher(silence: 300)
        guard case .ask? = check(&w, 300) else { return XCTFail("expected a prompt") }
        XCTAssertEqual(check(&w, 330, spoke: 329), .withdraw)
        XCTAssertNil(w.prompt)
    }

    func testClosedCallWindowAsksOnlyAfterItWasOpen() {
        var w = EndOfCallWatcher(silence: 300)
        XCTAssertNil(check(&w, 3, spoke: 3, window: false))
        XCTAssertNil(check(&w, 6, spoke: 6, window: false))
        XCTAssertNil(check(&w, 9, spoke: 9, window: true))
        XCTAssertNil(check(&w, 12, spoke: 12, window: false))
        guard case .ask(let prompt)? = check(&w, 15, spoke: 12, window: false) else { return XCTFail("expected a prompt") }
        XCTAssertEqual(prompt.reason, .callWindowClosed(appName: "Zoom"))
        XCTAssertEqual(check(&w, 18, spoke: 12, window: true), .withdraw)
    }

    func testKeepRecordingSnoozesAndWindowAsksOnce() {
        var w = EndOfCallWatcher(silence: 3600)
        _ = check(&w, 3, spoke: 3, window: true)
        _ = check(&w, 6, spoke: 6, window: false)
        guard case .ask? = check(&w, 9, spoke: 9, window: false) else { return XCTFail("expected a prompt") }
        w.keepRecording(now: at(10))
        XCTAssertNil(check(&w, 700, spoke: 700, window: false))
    }

    func testWithdrawAsksAgainWithoutSnooze() {
        var w = EndOfCallWatcher(silence: 300)
        guard case .ask? = check(&w, 300) else { return XCTFail("expected a prompt") }
        w.withdraw()
        XCTAssertNil(w.prompt)
        guard case .ask? = check(&w, 301) else { return XCTFail("expected a new prompt") }
    }

    func testCalendarEndAsksOnceTheCallIsQuiet() {
        var w = EndOfCallWatcher(silence: 3600)
        XCTAssertNil(check(&w, 1000, spoke: 990, eventEnd: 600))
        guard case .ask(let prompt)? = check(&w, 1110, spoke: 990, eventEnd: 600) else { return XCTFail("expected a prompt") }
        XCTAssertEqual(prompt.reason, .calendarEnded)
    }
}
