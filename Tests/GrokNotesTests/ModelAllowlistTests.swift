import XCTest
@testable import GrokNotes

final class ModelAllowlistTests: XCTestCase {
    func testOnlyListedModelsAreUsed() {
        for id in Prefs.notesModels {
            XCTAssertEqual(Prefs.allowedModel(id), id)
        }
        XCTAssertEqual(Prefs.allowedModel(" grok-4.6 "), "grok-4.6")
        XCTAssertEqual(Prefs.allowedModel("some-other-model"), Prefs.defaultModel)
        XCTAssertEqual(Prefs.allowedModel(""), Prefs.defaultModel)
        XCTAssertEqual(Prefs.allowedModel(nil), Prefs.defaultModel)
    }
}
