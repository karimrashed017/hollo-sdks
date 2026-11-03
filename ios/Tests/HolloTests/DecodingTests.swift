import SwiftUI
import XCTest
@testable import Hollo

final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDecodesAPollWithCardsProfileAndPushSettings() throws {
        let response = try decode(MessagesResponse.self, """
        {
          "messages": [
            {"id": "m1", "sender": "end_user", "kind": "text", "body": "Hi", "payload": null,
             "created_at": "2026-11-02T10:00:00+00:00"},
            {"id": "m2", "sender": "ai", "kind": "text", "body": "Hello!", "payload": {},
             "created_at": "2026-11-02T10:00:01+00:00"},
            {"id": "m3", "sender": "team", "kind": "review_request", "body": "Enjoying Driftwood?",
             "payload": {"appStoreId": "123456789", "playStorePackage": null, "cta": "Rate it"},
             "created_at": "2026-11-02T10:00:02+00:00"},
            {"id": "m4", "sender": "team", "kind": "offer", "body": "Pro",
             "payload": {"offerId": "o1", "title": "Pro, 50% off", "description": "3 months",
                         "cta": null, "ref": "pro_discount"},
             "created_at": "2026-11-02T10:00:03+00:00"},
            {"id": "m5", "sender": "team", "kind": "link", "body": "Your order",
             "payload": {"linkId": "l1", "label": "Track", "url": null, "screen": "order", "value": "123"},
             "created_at": "2026-11-02T10:00:04+00:00"}
          ],
          "unread": 3,
          "profile": {"name": "Karim", "role": "Founder", "photo": "https://hollo.so/p.png"},
          "push": {"permissionCard": "replies_offers", "notifyLine": false},
          "open": true,
          "branding": false
        }
        """)

        XCTAssertEqual(response.messages.map(\.id), ["m1", "m2", "m3", "m4", "m5"])
        XCTAssertEqual(response.messages[0].sender, .endUser)
        XCTAssertEqual(response.messages[0].payload, [:])
        XCTAssertEqual(response.messages[1].sender, .ai)
        XCTAssertEqual(response.messages[2].payload.text("appStoreId"), "123456789")
        XCTAssertEqual(response.messages[2].payload["playStorePackage"], JSONValue.null)
        XCTAssertTrue(response.messages[3].isCard)
        XCTAssertEqual(response.unread, 3)
        XCTAssertEqual(response.profile?.name, "Karim")
        XCTAssertEqual(response.profile?.photo, URL(string: "https://hollo.so/p.png"))
        XCTAssertNil(response.profile?.welcome)
        XCTAssertEqual(response.push, PushSettings(permissionCard: .repliesOffers, notifyLine: false))
        XCTAssertTrue(response.open)
        XCTAssertFalse(response.branding)

        let strings = HolloStrings.english
        XCTAssertEqual(
            CardContent(response.messages[2], strings: strings),
            CardContent(title: "", text: "Enjoying Driftwood?", button: "Rate it")
        )
        XCTAssertEqual(
            CardContent(response.messages[3], strings: strings),
            CardContent(title: "Pro, 50% off", text: "3 months", button: "See offer")
        )
        XCTAssertEqual(
            CardContent(response.messages[4], strings: strings),
            CardContent(title: "", text: "Your order", button: "Track")
        )
    }

    func testToleratesMissingAndUnknownFields() throws {
        let response = try decode(MessagesResponse.self, """
        {"messages": [{"id": "m1", "sender": "robot", "kind": "poll", "created_at": "t", "extra": 1}]}
        """)
        let message = try XCTUnwrap(response.messages.first)
        XCTAssertEqual(message.sender, .system)
        XCTAssertEqual(message.kind, "poll")
        XCTAssertEqual(message.body, "")
        XCTAssertFalse(message.isCard)
        XCTAssertEqual(response.unread, 0)
        XCTAssertNil(response.profile)
        XCTAssertFalse(response.open)
        XCTAssertTrue(response.branding)
    }

    func testProfileIgnoresEmptyFieldsAndNonHttpsPhotos() throws {
        let profile = try decode(HolloProfile.self, """
        {"name": "", "photo": "http://example.com/p.png", "welcome": "Ask away"}
        """)
        XCTAssertEqual(profile, HolloProfile(welcome: "Ask away"))
    }

    func testPushSettingsFallBackToDefaults() throws {
        let push = try decode(PushSettings.self, #"{"permissionCard": "sometimes"}"#)
        XCTAssertEqual(push, .default)
    }

    func testReviewCardFallsBackToBuiltInWording() {
        let message = HolloMessage(id: "m", sender: .team, kind: "review_request", body: "", createdAt: "t")
        let content = CardContent(message, strings: .english)
        XCTAssertEqual(content.text, HolloStrings.english.reviewText)
        XCTAssertEqual(content.button, "Leave a review")
    }

    func testStringsFollowTheLanguage() {
        XCTAssertEqual(HolloStrings.forLanguage("fr-CA").placeholder, "Message")
        XCTAssertEqual(HolloStrings.forLanguage("de").done, "Fertig")
        XCTAssertEqual(HolloStrings.forLanguage("pt-BR").support, "Suporte")
        XCTAssertEqual(HolloStrings.forLanguage("zz").support, "Support")
        XCTAssertEqual(HolloStrings.forLanguage("ar").layoutDirection, .rightToLeft)
        XCTAssertEqual(HolloStrings.forLanguage("en").layoutDirection, .leftToRight)
    }
}
