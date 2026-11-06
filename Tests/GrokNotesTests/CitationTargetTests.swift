import XCTest
@testable import GrokNotes

final class CitationTargetTests: XCTestCase {
    private typealias Span = (start: Double, end: Double)

    private func index(_ seconds: Double, _ spans: [Span]) -> Int? {
        Citations.index(at: seconds, in: spans, start: { $0.start }, end: { $0.end })
    }

    func testPicksTheSpanThatContainsTheTime() {
        let spans: [Span] = [(0, 4.5), (5.2, 9), (10, 14)]
        XCTAssertEqual(index(0, spans), 0)
        XCTAssertEqual(index(7, spans), 1)
        XCTAssertEqual(index(13, spans), 2)
    }

    func testAllowsOneSecondOfRounding() {
        XCTAssertEqual(index(5, [(0, 5.5), (5.6, 9)]), 1, "a line at 5.6s is cited as [0:05]")
    }

    func testAfterAPausePicksTheNearerSpan() {
        let spans: [Span] = [(600, 605), (640, 650)]
        XCTAssertEqual(index(630, spans), 1, "the next line is closer than the one before the pause")
        XCTAssertEqual(index(610, spans), 0)
    }

    func testBeforeTheFirstAndAfterTheLast() {
        let spans: [Span] = [(30, 40), (50, 60)]
        XCTAssertEqual(index(0, spans), 0)
        XCTAssertEqual(index(500, spans), 1)
        XCTAssertNil(index(10, []))
    }
}
