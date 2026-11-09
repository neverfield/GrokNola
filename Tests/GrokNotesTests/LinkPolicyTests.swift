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
}
