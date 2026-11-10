import XCTest
@testable import GrokNotes

final class ConsentReminderTests: XCTestCase {
    func testDomainOfEmail() {
        XCTAssertEqual(ConsentReminder.domain(of: " Ana@EXAMPLE.COM "), "example.com")
        XCTAssertNil(ConsentReminder.domain(of: "ana"))
        XCTAssertNil(ConsentReminder.domain(of: "@example.com"))
        XCTAssertNil(ConsentReminder.domain(of: "ana@localhost"))
        XCTAssertNil(ConsentReminder.domain(of: "a@b@example.com"))
    }

    func testDomainList() {
        XCTAssertEqual(ConsentReminder.domains(in: "example.com, @Example.org;  nope"), ["example.com", "example.org"])
        XCTAssertEqual(ConsentReminder.domains(in: nil), [])
    }

    func testInternalMeetingNeedsNoReminder() {
        let own: Set<String> = ["example.com"]
        XCTAssertFalse(ConsentReminder.hasExternalAttendees(["ana@example.com", "bo@eng.example.com"], ownDomains: own))
        XCTAssertFalse(ConsentReminder.hasExternalAttendees(["c_123@resource.calendar.google.com"], ownDomains: own))
        XCTAssertFalse(ConsentReminder.hasExternalAttendees([], ownDomains: own))
    }

    func testOutsideAttendeeNeedsReminder() {
        XCTAssertTrue(ConsentReminder.hasExternalAttendees(["ana@example.com", "dana@customer.com"], ownDomains: ["example.com"]))
        XCTAssertTrue(ConsentReminder.hasExternalAttendees(["dana@notexample.com"], ownDomains: ["example.com"]))
    }

    func testUnknownOwnDomainRemindsWheneverThereAreEmails() {
        XCTAssertTrue(ConsentReminder.hasExternalAttendees(["ana@example.com"], ownDomains: []))
        XCTAssertFalse(ConsentReminder.hasExternalAttendees([], ownDomains: []))
        XCTAssertFalse(ConsentReminder.hasExternalAttendees(["not-an-email"], ownDomains: []))
    }
}
