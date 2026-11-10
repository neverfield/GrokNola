import XCTest
@testable import GrokNotes

final class KeytermTests: XCTestCase {
    func testKeytermsAreThisMeetingsInviteesAndYou() {
        let terms = AppState.transcriptionKeyterms(attendees: ["Ana Ruiz", "ana ruiz", "Bo"], myName: "Dana Lee")
        XCTAssertEqual(terms, ["Ana Ruiz", "Bo", "Dana Lee"])
    }

    func testKeytermsAreCapped() {
        let long = String(repeating: "a", count: AppState.maxKeytermLength + 1)
        let many = (0..<100).map { "Person \($0)" }
        let terms = AppState.transcriptionKeyterms(attendees: [long] + many, myName: "Dana")
        XCTAssertEqual(terms.count, AppState.maxKeyterms)
        XCTAssertFalse(terms.contains(long))
    }
}
