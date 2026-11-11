import XCTest
@testable import GrokNotes

final class UsageLedgerTests: XCTestCase {
    private let id = UUID()

    func testOlderLinesWithTitlesDecodeAndAreRewrittenWithout() throws {
        let old = #"{"id":"\#(UUID().uuidString)","date":"2026-01-01T10:00:00Z","meetingID":"\#(id.uuidString)","meetingTitle":"Acme pricing","kind":"notes","model":"grok-4.7","costUSD":0.5,"exact":true}"#
        let entries = UsageLedger.decode(old + "\nnot json\n")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].meetingID, id)
        let rewritten = try XCTUnwrap(UsageLedger.lines(entries).map { String(decoding: $0, as: UTF8.self) })
        XCTAssertFalse(rewritten.contains("meetingTitle"))
        XCTAssertFalse(rewritten.contains("Acme"))
        XCTAssertTrue(rewritten.contains(id.uuidString))
        XCTAssertEqual(UsageLedger.decode(rewritten).first?.costUSD, 0.5)
    }
}
