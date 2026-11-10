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

    func testSnapshotsNeedACallTitledWindow() {
        let zoomApp = MeetingDetector.App(bundleID: zoom, name: "Zoom", pid: 1, isBrowser: false)
        let teamsApp = MeetingDetector.App(bundleID: teams, name: "Microsoft Teams", pid: 2, isBrowser: false)
        let meet = MeetingDetector.App(bundleID: chrome, name: "Google Meet", pid: 3, isBrowser: true)
        XCTAssertTrue(WindowSnapshotter.isCallWindow(title: "Zoom Meeting", app: zoomApp))
        XCTAssertFalse(WindowSnapshotter.isCallWindow(title: "Zoom Workplace", app: zoomApp))
        XCTAssertFalse(WindowSnapshotter.isCallWindow(title: nil, app: zoomApp))
        XCTAssertFalse(WindowSnapshotter.isCallWindow(title: "Meeting with Ana | Microsoft Teams", app: teamsApp))
        XCTAssertFalse(WindowSnapshotter.isCallWindow(title: "Call", app: teamsApp))
        XCTAssertTrue(WindowSnapshotter.isCallWindow(title: "Meet - abc-defg-hij", app: meet))
        XCTAssertFalse(WindowSnapshotter.isCallWindow(title: "Calendar - Meeting", app: meet))
    }
}
