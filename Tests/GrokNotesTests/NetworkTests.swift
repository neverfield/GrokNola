import XCTest
@testable import GrokNotes

final class NetworkTests: XCTestCase {
    func testSessionKeepsNothingAndNeedsModernTLS() {
        let config = Network.session.configuration
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.tlsMinimumSupportedProtocolVersion, .TLSv12)
        XCTAssertNil(config.urlCredentialStorage)
    }
}
