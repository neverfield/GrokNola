import XCTest
@testable import GrokNotes

final class SettingsMigrationTests: XCTestCase {
    func testCopiesOnlySettingsMissingFromTheNewDomain() {
        let legacy: [String: Any] = ["keepAudio": true, "companyDomains": "example.com", "recordingScope": "any"]
        let current: [String: Any] = ["recordingScope": "internalOnly"]
        let missing = SettingsMigration.missing(legacy: legacy, current: current)
        XCTAssertEqual(Set(missing.keys), ["keepAudio", "companyDomains"])
        XCTAssertEqual(missing["companyDomains"] as? String, "example.com")
    }

    func testNeverCopiesTheDoneMarker() {
        XCTAssertTrue(SettingsMigration.missing(legacy: [SettingsMigration.doneKey: true], current: [:]).isEmpty)
    }
}
