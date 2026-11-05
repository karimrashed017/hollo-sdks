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

    func testDecodesPhotoLinksLeniently() throws {
        let response = try decode(MessagesResponse.self, """
        {"messages": [
          {"id": "m1", "sender": "end_user", "kind": "image", "body": "The error",
           "payload": {"photos": ["ws/c/a.jpg", "ws/c/b.jpg"]},
           "photos": ["https://storage.hollo.so/a.jpg?token=1", "https://storage.hollo.so/b.jpg?token=2"],
           "created_at": "t1"},
          {"id": "m2", "sender": "team", "kind": "image", "body": "",
           "photos": ["http://example.com/x.jpg", 42, null, "https://storage.hollo.so/c.jpg"],
           "created_at": "t2"},
          {"id": "m3", "sender": "team", "kind": "image", "body": "", "photos": "nope", "created_at": "t3"},
          {"id": "m4", "sender": "team", "kind": "text", "body": "Hi", "created_at": "t4"}
        ]}
        """)
        XCTAssertEqual(response.messages.map(\.id), ["m1", "m2", "m3", "m4"])
        XCTAssertEqual(response.messages[0].photos, [
            URL(string: "https://storage.hollo.so/a.jpg?token=1")!,
            URL(string: "https://storage.hollo.so/b.jpg?token=2")!,
        ])
        XCTAssertEqual(response.messages[0].body, "The error")
        XCTAssertFalse(response.messages[0].isCard)
        // Only the https string survives; a bad entry never drops the message.
        XCTAssertEqual(response.messages[1].photos, [URL(string: "https://storage.hollo.so/c.jpg")!])
        XCTAssertEqual(response.messages[2].photos, [])
        // Older servers and text messages have no photos field.
        XCTAssertEqual(response.messages[3].photos, [])
    }

    func testProfileIgnoresEmptyFieldsAndNonHttpsPhotos() throws {
        let profile = try decode(HolloProfile.self, """
        {"name": "", "photo": "http://example.com/p.png", "welcome": "Ask away"}
        """)
        XCTAssertEqual(profile, HolloProfile(welcome: "Ask away"))
    }

    func testDecodesAFullTheme() throws {
        let response = try decode(MessagesResponse.self, """
        {"messages": [], "theme": {
          "accent": {"light": "#FF5500", "dark": "#ffaa77"},
          "onAccent": {"light": "#FFFFFF", "dark": "#000000"},
          "background": {"light": "#FAFAFA", "dark": "#101010"},
          "incoming": {"light": "#EEEEEE", "dark": "#222222"},
          "incomingText": {"light": "#111111", "dark": "#F0F0F0"},
          "colorScheme": "dark",
          "title": "  Driftwood help  "
        }}
        """)
        let theme = try XCTUnwrap(response.theme)
        XCTAssertEqual(theme.accent, RemoteTheme.Pair(light: 0xFF5500, dark: 0xFFAA77))
        XCTAssertEqual(theme.onAccent, RemoteTheme.Pair(light: 0xFFFFFF, dark: 0x000000))
        XCTAssertEqual(theme.background, RemoteTheme.Pair(light: 0xFAFAFA, dark: 0x101010))
        XCTAssertEqual(theme.incoming, RemoteTheme.Pair(light: 0xEEEEEE, dark: 0x222222))
        XCTAssertEqual(theme.incomingText, RemoteTheme.Pair(light: 0x111111, dark: 0xF0F0F0))
        XCTAssertEqual(theme.colorScheme, .dark)
        XCTAssertEqual(theme.title, "Driftwood help")
        XCTAssertEqual(ChatStyle.scheme(remote: theme, local: .light, system: .light), .dark)
        XCTAssertEqual(ChatStyle(HolloTheme(), remote: theme, scheme: .dark).title, "Driftwood help")
    }

    func testPartialThemeKeepsTheAppsOwnValues() throws {
        let theme = try decode(RemoteTheme.self, """
        {"accent": {"dark": "#123456"}, "colorScheme": "system"}
        """)
        XCTAssertEqual(theme, RemoteTheme(accent: RemoteTheme.Pair(dark: 0x123456), colorScheme: .system))
        // Only the dark half is set, so light mode keeps the app's accent.
        XCTAssertEqual(theme.accent?.hex(dark: true), 0x123456)
        XCTAssertNil(theme.accent?.hex(dark: false))
        XCTAssertEqual(ChatStyle.scheme(remote: theme, local: .dark, system: .light), .dark)
        XCTAssertEqual(ChatStyle.scheme(remote: theme, local: nil, system: .light), .light)
        XCTAssertEqual(ChatStyle(HolloTheme(title: "Help"), remote: theme).title, "Help")
    }

    func testMalformedThemeValuesAreDropped() throws {
        let theme = try decode(RemoteTheme.self, """
        {"accent": "#FF5500", "onAccent": {"light": "#FFF", "dark": 12},
         "background": {"light": "#GG0000", "dark": "#00000080"}, "incoming": null,
         "incomingText": {"light": "#+12345"}, "colorScheme": "sepia", "title": "   "}
        """)
        XCTAssertEqual(theme, RemoteTheme())

        // A theme that isn't an object never breaks the poll.
        let response = try decode(MessagesResponse.self, #"{"messages": [], "theme": "blue", "unread": 2}"#)
        XCTAssertNil(response.theme)
        XCTAssertEqual(response.unread, 2)
        XCTAssertNil(try decode(MessagesResponse.self, #"{"messages": []}"#).theme)
        XCTAssertEqual(ChatStyle.scheme(remote: RemoteTheme(), local: nil, system: .dark), .dark)
    }

    func testDecodesAnActionConfirmCard() throws {
        let response = try decode(MessagesResponse.self, """
        {"messages": [
          {"id": "m1", "sender": "ai", "kind": "action_confirm", "body": "Restore your streak to 41 days?",
           "payload": {"confirmationId": "6f1c2a9e-0b3d-4c55-9a77-2e8f0d1b4c3a", "title": "Restore lost streak",
                       "summary": "Restore your streak to 41 days",
                       "inputs": [{"label": "Streak days", "value": "41"}, {"label": "Bonus", "value": 2}],
                       "risk": "low", "status": "pending", "expiresAt": "2026-11-05T12:00:00.000Z"},
           "created_at": "t1"}
        ]}
        """)
        let message = try XCTUnwrap(response.messages.first)
        XCTAssertTrue(message.isActionConfirm)
        // It has its own card, so the one-button card never draws it.
        XCTAssertFalse(message.isCard)
        XCTAssertEqual(message.sender, .ai)

        let card = ActionConfirm(message.payload)
        XCTAssertEqual(card.confirmationId, "6f1c2a9e-0b3d-4c55-9a77-2e8f0d1b4c3a")
        XCTAssertEqual(card.title, "Restore lost streak")
        XCTAssertEqual(card.summary, "Restore your streak to 41 days")
        XCTAssertEqual(card.inputs, [
            ActionConfirm.Input(label: "Streak days", value: "41"),
            ActionConfirm.Input(label: "Bonus", value: "2"),
        ])
        XCTAssertEqual(card.risk, "low")
        XCTAssertEqual(card.expiresAt, Date(timeIntervalSince1970: 1_793_880_000))
        XCTAssertEqual(ActionConfirmCard.line(card.inputs[0]), "Streak days: 41")

        let before = Date(timeIntervalSince1970: 1_793_879_999)
        let after = Date(timeIntervalSince1970: 1_793_880_001)
        XCTAssertEqual(card.state(now: before), .pending)
        XCTAssertEqual(card.state(now: after), .expired)
        // What the user did on this device wins over the payload.
        XCTAssertEqual(card.state(progress: .sending, now: after), .pending)
        XCTAssertEqual(card.state(progress: .failed, now: before), .pending)
        XCTAssertEqual(card.state(progress: .done(.cancelled), now: before), .cancelled)
        XCTAssertEqual(card.state(progress: .done(.unavailable), now: before), .unavailable)
    }

    func testActionConfirmCardShowsTheServersStatus() {
        func card(_ payload: Payload) -> ActionConfirm { ActionConfirm(payload) }
        let id: JSONValue = .string("6f1c2a9e-0b3d-4c55-9a77-2e8f0d1b4c3a")
        XCTAssertEqual(card(["confirmationId": id, "status": .string("confirmed")]).state(), .confirmed)
        XCTAssertEqual(card(["confirmationId": id, "status": .string("cancelled")]).state(), .cancelled)
        // A status newer than the SDK never offers buttons.
        XCTAssertEqual(card(["confirmationId": id, "status": .string("running")]).state(), .unavailable)
        // Without an expiry the card waits; an expiry without fractions still reads.
        XCTAssertEqual(card(["confirmationId": id]).state(), .pending)
        XCTAssertEqual(
            card(["expiresAt": .string("2026-11-05T12:00:00+00:00")]).expiresAt,
            Date(timeIntervalSince1970: 1_793_880_000)
        )
    }

    func testActionConfirmToleratesMissingAndOddFields() throws {
        let response = try decode(MessagesResponse.self, """
        {"messages": [
          {"id": "m1", "sender": "ai", "kind": "action_confirm", "body": "Confirm the change?", "created_at": "t1"},
          {"id": "m2", "sender": "ai", "kind": "action_confirm", "body": "",
           "payload": {"confirmationId": 7, "title": null, "inputs": [{"label": "Days"}, "x", {"value": true}, {}],
                       "status": null, "expiresAt": "soon"},
           "created_at": "t2"},
          {"id": "m3", "sender": "ai", "kind": "action_confirm", "body": "", "payload": {"inputs": {"a": 1}},
           "created_at": "t3"}
        ]}
        """)
        XCTAssertEqual(response.messages.map(\.id), ["m1", "m2", "m3"])

        let empty = ActionConfirm(response.messages[0].payload)
        XCTAssertEqual(empty.title, "")
        XCTAssertEqual(empty.inputs, [])
        XCTAssertNil(empty.expiresAt)
        // Nothing to answer without an ID.
        XCTAssertEqual(empty.state(), .unavailable)

        let odd = ActionConfirm(response.messages[1].payload)
        XCTAssertEqual(odd.confirmationId, "")
        XCTAssertEqual(odd.inputs, [
            ActionConfirm.Input(label: "Days", value: ""),
            ActionConfirm.Input(label: "", value: "true"),
        ])
        XCTAssertNil(odd.expiresAt)
        XCTAssertEqual(ActionConfirmCard.line(odd.inputs[0]), "Days")
        XCTAssertEqual(ActionConfirmCard.line(odd.inputs[1]), "true")

        XCTAssertEqual(ActionConfirm(response.messages[2].payload).inputs, [])
    }

    func testActionConfirmLabelsAreTranslated() {
        XCTAssertEqual(HolloStrings.english.confirm, "Confirm")
        XCTAssertEqual(HolloStrings.english.noLongerAvailable, "No longer available")
        XCTAssertEqual(HolloStrings.forLanguage("fr").cancel, "Annuler")
        XCTAssertEqual(HolloStrings.forLanguage("de").expired, "Abgelaufen")
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
        XCTAssertEqual(HolloStrings.english.photoLabel(2, of: 3), "Photo 2 of 3")
        XCTAssertEqual(HolloStrings.english.photoLabel(1, of: 1), "Photo")
        XCTAssertEqual(HolloStrings.forLanguage("de").photoLabel(1, of: 2), "Foto 1 von 2")
    }
}
