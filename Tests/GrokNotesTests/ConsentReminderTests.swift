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

    func testExternalDomainsAreDistinctAndSorted() {
        let emails = ["ana@example.com", "dana@customer.com", "eli@Customer.com", "fay@acme.io", "c_1@resource.calendar.google.com"]
        XCTAssertEqual(ConsentReminder.externalDomains(emails, ownDomains: ["example.com"]), ["acme.io", "customer.com"])
        XCTAssertEqual(ConsentReminder.externalDomains(["ana@example.com"], ownDomains: []), ["example.com"])
    }

    func testKnownInternalOnlyNeedsInviteesAndOwnDomains() {
        XCTAssertTrue(ConsentReminder.isKnownInternalOnly(["ana@example.com", "bo@eng.example.com"], ownDomains: ["example.com"]))
        XCTAssertFalse(ConsentReminder.isKnownInternalOnly([], ownDomains: ["example.com"]))
        XCTAssertFalse(ConsentReminder.isKnownInternalOnly(["c_1@resource.calendar.google.com"], ownDomains: ["example.com"]))
        XCTAssertFalse(ConsentReminder.isKnownInternalOnly(["ana@example.com"], ownDomains: []))
        XCTAssertFalse(ConsentReminder.isKnownInternalOnly(["ana@example.com", "dana@customer.com"], ownDomains: ["example.com"]))
    }

    func testConfirmationIsSkippedOnlyForKnownInternalMeetings() {
        XCTAssertTrue(ConsentReminder.needsConfirmation(enabled: true, skipInternalOnly: false, knownInternalOnly: true))
        XCTAssertFalse(ConsentReminder.needsConfirmation(enabled: true, skipInternalOnly: true, knownInternalOnly: true))
        XCTAssertTrue(ConsentReminder.needsConfirmation(enabled: true, skipInternalOnly: true, knownInternalOnly: false))
        XCTAssertFalse(ConsentReminder.needsConfirmation(enabled: false, skipInternalOnly: false, knownInternalOnly: false))
    }

    func testConfirmationDetailNamesOutsideDomains() {
        XCTAssertTrue(ConsentReminder.confirmationDetail(externalDomains: ["acme.io"]).contains("acme.io"))
        let many = (1...7).map { "d\($0).com" }
        let detail = ConsentReminder.confirmationDetail(externalDomains: many)
        XCTAssertTrue(detail.contains("d5.com") && !detail.contains("d6.com") && detail.contains("and 2 more"))
        XCTAssertFalse(ConsentReminder.confirmationDetail(externalDomains: []).contains("outside"))
    }

    func testMeetingWithoutConsentFieldsStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"T","autoTitle":false,"startedAt":"2026-01-01T10:00:00Z","attendees":[],"userNotes":"","utterances":[],"speakers":{},"mode":"named","chat":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let m = try decoder.decode(Meeting.self, from: Data(json.utf8))
        XCTAssertNil(m.consentConfirmedAt)
        XCTAssertNil(m.externalDomains)
    }
}
