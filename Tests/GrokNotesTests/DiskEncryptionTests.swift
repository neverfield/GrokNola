import XCTest
@testable import GrokNotes

final class DiskEncryptionTests: XCTestCase {
    func testParsesFdesetupStatus() {
        XCTAssertEqual(DiskEncryption.parseFdesetup("FileVault is On.\n"), true)
        XCTAssertEqual(DiskEncryption.parseFdesetup("FileVault is On.\nEncryption in progress: Percent completed = 40\n"), true)
        XCTAssertEqual(DiskEncryption.parseFdesetup("FileVault is Off.\n"), false)
        XCTAssertNil(DiskEncryption.parseFdesetup(""))
    }

    func testPilotRefusesUnlessFileVaultIsConfirmedOn() {
        XCTAssertEqual(DiskEncryption.decide(encrypted: true, pilot: true), .ok)
        XCTAssertEqual(DiskEncryption.decide(encrypted: false, pilot: true), .refuse(DiskEncryption.pilotRefusal))
        XCTAssertEqual(DiskEncryption.decide(encrypted: nil, pilot: true), .refuse(DiskEncryption.pilotRefusal))
    }

    func testOtherBuildsOnlyWarn() {
        XCTAssertEqual(DiskEncryption.decide(encrypted: true, pilot: false), .ok)
        XCTAssertEqual(DiskEncryption.decide(encrypted: false, pilot: false), .warn(DiskEncryption.offWarning))
        XCTAssertEqual(DiskEncryption.decide(encrypted: nil, pilot: false), .warn(DiskEncryption.unknownWarning))
    }
}
