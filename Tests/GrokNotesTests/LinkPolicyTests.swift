import XCTest
@testable import GrokNotes

final class LinkPolicyTests: XCTestCase {
    func testAllowsWebMailAndInAppLinks() {
        for link in ["https://example.com/a", "mailto:dana@example.com", "groknotes://meeting/\(UUID().uuidString)"] {
            XCTAssertTrue(LinkPolicy.isAllowed(URL(string: link)!), link)
        }
    }

    func testRejectsOtherSchemes() {
        let links = [
            "file:///etc/passwd",
            "smb://evil.example/share",
            "tel:+15555550100",
            "x-apple.systempreferences:com.apple.preference.security",
            "javascript:alert(1)",
        ]
        for link in links {
            XCTAssertFalse(LinkPolicy.isAllowed(URL(string: link)!), link)
        }
    }

    func testDestinationShowsTheRealHostOrRecipient() {
        XCTAssertEqual(LinkPolicy.destination(URL(string: "https://docs.example.com/a?b=1")!), "docs.example.com")
        XCTAssertEqual(LinkPolicy.destination(URL(string: "https://example.com@evil.example/login")!), "evil.example")
        XCTAssertEqual(LinkPolicy.destination(URL(string: "mailto:dana@example.com?subject=Hi")!), "dana@example.com")
        XCTAssertEqual(LinkPolicy.destination(URL(string: "mailto:?subject=Hi")!), "no recipient")
    }

    func testLongAddressesAreFlagged() {
        XCTAssertFalse(LinkPolicy.carriesLotsOfData(URL(string: "https://example.com/page?id=42")!))
        let longQuery = "https://example.com/?q=" + String(repeating: "a", count: 101)
        XCTAssertTrue(LinkPolicy.carriesLotsOfData(URL(string: longQuery)!))
        let longPath = "https://example.com/" + String(repeating: "p", count: 200)
        XCTAssertTrue(LinkPolicy.carriesLotsOfData(URL(string: longPath)!))
    }

    func testMailLinksLoseBodyAndCopies() {
        let url = URL(string: "mailto:dana@example.com?subject=Follow%20up&body=Secret%20notes&CC=a@b.com&bcc=c@d.com")!
        XCTAssertEqual(LinkPolicy.cleanedMail(url).absoluteString, "mailto:dana@example.com?subject=Follow%20up")
        XCTAssertEqual(LinkPolicy.cleanedMail(URL(string: "mailto:dana@example.com?body=x")!).absoluteString, "mailto:dana@example.com")
        let web = URL(string: "https://example.com/?body=x")!
        XCTAssertEqual(LinkPolicy.cleanedMail(web), web)
    }
}
