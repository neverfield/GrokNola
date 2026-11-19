import XCTest
@testable import GrokNotes

final class RecordingPolicyTests: XCTestCase {
    private let own: Set<String> = ["example.com"]
    private let blocked: Set<String> = ["example.org", "example.net"]

    func testBuildBlockedDomainsReadInfoPlistAndEnvironment() {
        let info: [String: Any] = [RecordingPolicy.buildInfoKey: "example.org, @Example.net"]
        XCTAssertEqual(RecordingPolicy.buildBlocked(info: info, environment: [:]), ["example.org", "example.net"])
        XCTAssertEqual(RecordingPolicy.buildBlocked(info: nil, environment: ["GROKNOLA_BLOCKED_DOMAINS": "a.example b.example"]), ["a.example", "b.example"])
        XCTAssertEqual(RecordingPolicy.buildBlocked(info: nil, environment: [:]), [])
    }

    func testBlockedDomainsMatchSubdomainsOnly() {
        let emails = ["ana@example.com", "bo@Example.org", "cy@eng.example.net", "dee@notexample.org"]
        XCTAssertEqual(RecordingPolicy.blockedDomains(in: emails, blocked: blocked), ["eng.example.net", "example.org"])
        XCTAssertEqual(RecordingPolicy.blockedDomains(in: ["dee@notexample.org"], blocked: blocked), [])
    }

    func testBlockedDomainRefusesInEveryScope() {
        for scope in RecordingScope.allCases {
            let decision = RecordingPolicy.decide(emails: ["ana@example.com", "bo@example.org"], ownDomains: own, blocked: blocked, scope: scope)
            XCTAssertEqual(decision, .refuse(RecordingPolicy.blockedMessage), "\(scope)")
        }
    }

    func testBlockedWinsEvenWhenListedAsOwn() {
        let decision = RecordingPolicy.decide(emails: ["bo@example.org"], ownDomains: ["example.com", "example.org"], blocked: blocked, scope: .any)
        XCTAssertEqual(decision, .refuse(RecordingPolicy.blockedMessage))
    }

    func testInternalOnlyRefusesOutsideInvitees() {
        let decision = RecordingPolicy.decide(emails: ["ana@example.com", "dana@customer.com"], ownDomains: own, blocked: blocked, scope: .internalOnly)
        guard case .refuse(let message) = decision else { return XCTFail("expected refuse") }
        XCTAssertTrue(message.contains("customer.com"))
    }

    func testInternalOnlyAllowsColleaguesAndConfirmsWithoutInvite() {
        XCTAssertEqual(RecordingPolicy.decide(emails: ["ana@eng.example.com"], ownDomains: own, blocked: blocked, scope: .internalOnly), .allow)
        XCTAssertEqual(RecordingPolicy.decide(emails: nil, ownDomains: own, blocked: blocked, scope: .internalOnly), .requireConfirmation)
        XCTAssertEqual(RecordingPolicy.decide(emails: [], ownDomains: own, blocked: blocked, scope: .internalOnly), .requireConfirmation)
    }

    func testInternalOnlyWithoutOwnDomainsRefusesAnyInvitee() {
        guard case .refuse = RecordingPolicy.decide(emails: ["ana@example.com"], ownDomains: [], blocked: blocked, scope: .internalOnly) else {
            return XCTFail("expected refuse")
        }
    }

    func testWarnExternalConfirmsOutsideInvitees() {
        XCTAssertEqual(RecordingPolicy.decide(emails: ["dana@customer.com"], ownDomains: own, blocked: blocked, scope: .warnExternal), .requireConfirmation)
        XCTAssertEqual(RecordingPolicy.decide(emails: ["ana@example.com"], ownDomains: own, blocked: blocked, scope: .warnExternal), .allow)
        XCTAssertEqual(RecordingPolicy.decide(emails: nil, ownDomains: own, blocked: blocked, scope: .warnExternal), .allow)
    }

    func testAnyAllowsOutsideInvitees() {
        XCTAssertEqual(RecordingPolicy.decide(emails: ["dana@customer.com"], ownDomains: own, blocked: blocked, scope: .any), .allow)
    }
}
