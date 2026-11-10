import XCTest
@testable import GrokNotes

final class CallWindowTests: XCTestCase {
    private let zoom = "us.zoom.xos"
    private let slack = "com.tinyspeck.slackmacgap"
    private let teams = "com.microsoft.teams2"
    private let chrome = "com.google.Chrome"

    func testKnownCallWindowTitles() {
        XCTAssertEqual(MeetingDetector.isCallWindowTitle("Zoom Meeting", bundleID: zoom, isBrowser: false), true)
        XCTAssertEqual(MeetingDetector.isCallWindowTitle("Zoom Workplace", bundleID: zoom, isBrowser: false), false)
        XCTAssertEqual(MeetingDetector.isCallWindowTitle("Huddle with Ana", bundleID: slack, isBrowser: false), true)
        XCTAssertEqual(MeetingDetector.isCallWindowTitle("Slack | general", bundleID: slack, isBrowser: false), false)
        XCTAssertEqual(MeetingDetector.isCallWindowTitle("Meet - abc-defg-hij", bundleID: chrome, isBrowser: true), true)
        XCTAssertEqual(MeetingDetector.isCallWindowTitle("Inbox - Gmail", bundleID: chrome, isBrowser: true), false)
        XCTAssertNil(MeetingDetector.isCallWindowTitle("Meeting with Ana", bundleID: teams, isBrowser: false))
    }

    func testMonitorScansOnlyCallWindowsWhenTheTitleIsKnown() {
        XCTAssertTrue(ActiveSpeakerMonitor.shouldScan(windowTitle: "Zoom Meeting", bundleID: zoom, isBrowser: false))
        XCTAssertFalse(ActiveSpeakerMonitor.shouldScan(windowTitle: "Zoom Workplace", bundleID: zoom, isBrowser: false))
        XCTAssertFalse(ActiveSpeakerMonitor.shouldScan(windowTitle: nil, bundleID: slack, isBrowser: false))
        XCTAssertFalse(ActiveSpeakerMonitor.shouldScan(windowTitle: nil, bundleID: chrome, isBrowser: true))
        XCTAssertTrue(ActiveSpeakerMonitor.shouldScan(windowTitle: "Chat | Microsoft Teams", bundleID: teams, isBrowser: false))
        XCTAssertTrue(ActiveSpeakerMonitor.shouldScan(windowTitle: nil, bundleID: teams, isBrowser: false))
    }
}
