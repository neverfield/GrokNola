import XCTest
@testable import GrokNotes

final class PilotBuildTests: XCTestCase {
    func testInfoPlistKeyTurnsPilotOn() {
        XCTAssertTrue(PilotBuild.isPilot(info: [PilotBuild.infoKey: true], environment: [:]))
        XCTAssertFalse(PilotBuild.isPilot(info: [PilotBuild.infoKey: false], environment: [:]))
        XCTAssertFalse(PilotBuild.isPilot(info: [PilotBuild.infoKey: "true"], environment: [:]))
        XCTAssertFalse(PilotBuild.isPilot(info: nil, environment: [:]))
    }

    func testEnvironmentCanOnlyTurnPilotOn() {
        XCTAssertTrue(PilotBuild.isPilot(info: nil, environment: ["GROKNOLA_PILOT": "1"]))
        XCTAssertTrue(PilotBuild.isPilot(info: [PilotBuild.infoKey: true], environment: ["GROKNOLA_PILOT": "0"]))
        XCTAssertFalse(PilotBuild.isPilot(info: nil, environment: ["GROKNOLA_PILOT": "0"]))
    }
}
