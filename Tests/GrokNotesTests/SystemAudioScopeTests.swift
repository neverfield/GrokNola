import XCTest
@testable import GrokNotes

final class SystemAudioScopeTests: XCTestCase {
    func testIncludesTheMeetingAppAndItsHelpersOnly() {
        let chrome = MeetingDetector.App(bundleID: "com.google.Chrome", name: "Google Meet", pid: 42, isBrowser: true)
        XCTAssertTrue(SystemAudioCapture.belongsToMeetingApp(bundleID: "com.google.Chrome", pid: 42, app: chrome))
        XCTAssertTrue(SystemAudioCapture.belongsToMeetingApp(bundleID: "com.google.Chrome.helper", pid: 77, app: chrome))
        XCTAssertFalse(SystemAudioCapture.belongsToMeetingApp(bundleID: "com.google.Chromecast", pid: 79, app: chrome))
        XCTAssertFalse(SystemAudioCapture.belongsToMeetingApp(bundleID: "com.spotify.client", pid: 80, app: chrome))
    }
}
