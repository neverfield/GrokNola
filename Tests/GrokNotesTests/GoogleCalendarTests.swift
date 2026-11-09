import XCTest
@testable import GrokNotes

final class GoogleOAuthTests: XCTestCase {
    func testChallengeMatchesRFC7636Example() {
        XCTAssertEqual(
            OAuthPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testRandomStringsAreUnreservedAndUnique() {
        let a = OAuthPKCE.randomString(), b = OAuthPKCE.randomString()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isLetter || $0.isNumber || "-_".contains($0) })
    }

    func testCallbackReturnsTheCodeWhenStateMatches() throws {
        let code = try OAuthPKCE.code(fromCallbackQuery: "state=abc&code=4%2F0Ab_xyz&scope=email", expectedState: "abc")
        XCTAssertEqual(code, "4/0Ab_xyz")
    }

    func testCallbackRejectsWrongStateMissingCodeAndDenial() {
        XCTAssertThrowsError(try OAuthPKCE.code(fromCallbackQuery: "state=other&code=c", expectedState: "abc"))
        XCTAssertThrowsError(try OAuthPKCE.code(fromCallbackQuery: "state=abc", expectedState: "abc"))
        XCTAssertThrowsError(try OAuthPKCE.code(fromCallbackQuery: "error=access_denied&state=abc", expectedState: "abc")) { error in
            XCTAssertEqual(error.localizedDescription, "Google access was not allowed.")
        }
    }

    func testEmailFromIDToken() {
        let payload = OAuthPKCE.base64URL(Data(#"{"email":"dana@example.com","sub":"1"}"#.utf8))
        XCTAssertEqual(OAuthPKCE.email(fromIDToken: "e30.\(payload).sig"), "dana@example.com")
        XCTAssertNil(OAuthPKCE.email(fromIDToken: "not-a-token"))
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(OAuthPKCE.formEncode(["b": "x y", "a": "1/2+3"]), "a=1%2F2%2B3&b=x%20y")
    }
}

final class GoogleEventsTests: XCTestCase {
    private let fixture = #"""
    {
      "summary": "dana@example.com",
      "timeZone": "America/Los_Angeles",
      "items": [
        {
          "id": "timed",
          "summary": "Pricing sync",
          "start": {"dateTime": "2026-11-09T10:00:00-08:00"},
          "end": {"dateTime": "2026-11-09T10:30:00-08:00"},
          "attendees": [
            {"email": "dana@example.com", "self": true, "responseStatus": "accepted"},
            {"email": "yemi.a@example.com", "displayName": "Yemi A", "responseStatus": "accepted"}
          ],
          "organizer": {"email": "yemi.a@example.com", "displayName": "Yemi A"},
          "hangoutLink": "https://meet.google.com/abc-defg-hij"
        },
        {
          "id": "allday",
          "summary": "Offsite",
          "start": {"date": "2026-11-10"},
          "end": {"date": "2026-11-11"}
        },
        {
          "id": "declined",
          "summary": "Skip me",
          "start": {"dateTime": "2026-11-09T12:00:00-08:00"},
          "end": {"dateTime": "2026-11-09T13:00:00-08:00"},
          "attendees": [{"email": "dana@example.com", "self": true, "responseStatus": "declined"}]
        },
        {
          "id": "cancelled",
          "status": "cancelled",
          "start": {"dateTime": "2026-11-09T14:00:00-08:00"}
        },
        {
          "id": "zoom",
          "summary": "",
          "start": {"dateTime": "2026-11-09T15:00:00-08:00"},
          "end": {"dateTime": "2026-11-09T15:30:00-08:00"},
          "conferenceData": {"entryPoints": [
            {"entryPointType": "phone", "uri": "tel:+1-555-0100"},
            {"entryPointType": "video", "uri": "https://example.zoom.us/j/123"}
          ]}
        },
        {"id": "broken", "summary": "No start"}
      ]
    }
    """#

    func testMapsTimedAllDayAndConferenceEventsAndSkipsTheRest() throws {
        let page = try GoogleEvents.parse(Data(fixture.utf8))
        XCTAssertEqual(page.summary, "dana@example.com")
        XCTAssertEqual(page.events.map(\.id), ["timed", "zoom", "allday"])

        let timed = try XCTUnwrap(page.events.first { $0.id == "timed" })
        XCTAssertEqual(timed.title, "Pricing sync")
        XCTAssertEqual(timed.end.timeIntervalSince(timed.start), 1800)
        XCTAssertEqual(timed.attendeeNames, ["Yemi A"], "your own attendee entry is left out")
        XCTAssertEqual(timed.meetingAppName, "Google Meet")
        XCTAssertEqual(timed.organizer?.name, "Yemi A")

        let allDay = try XCTUnwrap(page.events.first { $0.id == "allday" })
        XCTAssertTrue(allDay.allDay)
        XCTAssertEqual(allDay.end.timeIntervalSince(allDay.start), 86_400)

        let zoom = try XCTUnwrap(page.events.first { $0.id == "zoom" })
        XCTAssertEqual(zoom.title, "Untitled event")
        XCTAssertEqual(zoom.conferenceURL?.absoluteString, "https://example.zoom.us/j/123")
        XCTAssertEqual(zoom.meetingAppName, "Zoom")
    }
}
