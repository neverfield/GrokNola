import XCTest
@testable import GrokNotes

final class GoogleDriveExportTests: XCTestCase {
    private let work = "GoogleDrive-ana@example.com"
    private let personal = "GoogleDrive-ana@gmail.com"

    func testPinnedMountWinsAndIsNeverReplaced() {
        XCTAssertEqual(GoogleDriveExport.chooseMount(from: [work, personal], pinned: personal, accountEmail: "ana@example.com", companyDomains: []), personal)
        XCTAssertNil(GoogleDriveExport.chooseMount(from: [work], pinned: personal, accountEmail: "ana@example.com", companyDomains: ["example.com"]))
    }

    func testMatchesTheSignedInAccountOrCompanyDomain() {
        XCTAssertEqual(GoogleDriveExport.chooseMount(from: [personal, work], pinned: nil, accountEmail: "ANA@example.com", companyDomains: []), work)
        XCTAssertEqual(GoogleDriveExport.chooseMount(from: [personal, work], pinned: nil, accountEmail: nil, companyDomains: ["example.com"]), work)
    }

    func testDoesNotGuessWithoutAMatch() {
        XCTAssertNil(GoogleDriveExport.chooseMount(from: [personal], pinned: nil, accountEmail: nil, companyDomains: []))
        XCTAssertNil(GoogleDriveExport.chooseMount(from: [personal, work], pinned: nil, accountEmail: "bo@other.com", companyDomains: []))
        let two = [work, "GoogleDrive-bo@example.com"]
        XCTAssertNil(GoogleDriveExport.chooseMount(from: two, pinned: nil, accountEmail: nil, companyDomains: ["example.com"]))
    }

    func testSubfolderAndFolderNames() {
        XCTAssertFalse(GoogleDriveExport.isValidSubfolder(".."))
        XCTAssertFalse(GoogleDriveExport.isValidSubfolder(" . "))
        XCTAssertTrue(GoogleDriveExport.isValidSubfolder("Meeting Notes"))
        XCTAssertEqual(GoogleDriveExport.sanitizePathComponent(".hidden"), "_hidden")
        XCTAssertEqual(GoogleDriveExport.sanitizePathComponent("..config"), "__config")
        XCTAssertEqual(GoogleDriveExport.sanitizePathComponent("..."), "Untitled")
        XCTAssertEqual(GoogleDriveExport.sanitizePathComponent("../../etc"), "__-..-etc")
        XCTAssertEqual(GoogleDriveExport.sanitizePathComponent("Q3 / Planning"), "Q3 - Planning")
    }
}
