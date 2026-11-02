import XCTest
@testable import Hollo

final class LinksTests: XCTestCase {
    func testOpensTheAppStoreReviewSheet() {
        let payload: Payload = ["appStoreId": .string("123456789"), "playStorePackage": .string("com.example.app")]
        XCTAssertEqual(
            HolloLinks.reviewURL(payload)?.absoluteString,
            "itms-apps://itunes.apple.com/app/id123456789?action=write-review"
        )
    }

    func testFallsBackToGooglePlayOnTheWeb() {
        XCTAssertEqual(
            HolloLinks.reviewURL(["playStorePackage": .string("com.example.app")])?.absoluteString,
            "https://play.google.com/store/apps/details?id=com.example.app"
        )
    }

    func testNoReviewLinkWithoutStoreIDs() {
        XCTAssertNil(HolloLinks.reviewURL([:]))
        XCTAssertNil(HolloLinks.reviewURL(["appStoreId": .null]))
    }

    func testLinkCardOpensAURL() {
        XCTAssertEqual(
            HolloLinks.linkAction(["url": .string(" https://example.com/help ")]),
            .url(URL(string: "https://example.com/help")!)
        )
        XCTAssertEqual(
            HolloLinks.linkAction(["url": .string("whatsapp://send?phone=123")]),
            .url(URL(string: "whatsapp://send?phone=123")!)
        )
    }

    func testLinkCardOpensAScreenWithItsValue() {
        XCTAssertEqual(
            HolloLinks.linkAction(["url": .null, "screen": .string("order"), "value": .string("123")]),
            .screen("order", value: "123")
        )
        XCTAssertEqual(
            HolloLinks.linkAction(["screen": .string("settings"), "value": .null]),
            .screen("settings", value: nil)
        )
    }

    func testRefusesScriptsAndEmptyCards() {
        XCTAssertNil(HolloLinks.linkAction(["url": .string("javascript:alert(1)")]))
        XCTAssertNil(HolloLinks.linkAction(["url": .string("JavaScript:alert(1)")]))
        XCTAssertNil(HolloLinks.linkAction(["url": .string("file:///etc/passwd")]))
        XCTAssertNil(HolloLinks.linkAction([:]))
    }

    func testHexEncodesThePushToken() {
        let token = Data([0x00, 0x0A, 0xFF, 0x10, 0xab])
        XCTAssertEqual(HolloLinks.hex(token), "000aff10ab")
        XCTAssertEqual(HolloLinks.hex(Data()), "")
    }

    func testRecognisesHolloNotifications() {
        XCTAssertTrue(HolloLinks.isHolloNotification(["hollo": "true", "conversationId": "c1"]))
        XCTAssertTrue(HolloLinks.isHolloNotification(["hollo": true]))
        XCTAssertTrue(HolloLinks.isHolloNotification(["hollo": NSNumber(value: 1)]))
        XCTAssertFalse(HolloLinks.isHolloNotification(["hollo": "false"]))
        XCTAssertFalse(HolloLinks.isHolloNotification(["aps": ["alert": "Hi"]]))
    }

    func testMakesWebAddressesTappable() {
        let text = HolloLinks.linkified("See https://hollo.so/docs for more")
        let links = text.runs.compactMap { $0.link }
        XCTAssertEqual(links, [URL(string: "https://hollo.so/docs")!])
        XCTAssertEqual(String(text.characters), "See https://hollo.so/docs for more")
    }
}
