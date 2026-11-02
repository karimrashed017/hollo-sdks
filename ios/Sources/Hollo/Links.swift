import Foundation

// Pure helpers for cards and push, kept apart from the UI so they can be
// unit-tested.

enum HolloLinks {
    /** The App Store page to leave a review on, from a review card. */
    static func reviewURL(_ payload: Payload) -> URL? {
        let ios = payload.text("appStoreId").trimmingCharacters(in: .whitespaces)
        let android = payload.text("playStorePackage").trimmingCharacters(in: .whitespaces)
        if !ios.isEmpty, ios.allSatisfy(\.isNumber) {
            // Opens the App Store app straight on the "Write a Review" sheet.
            return URL(string: "itms-apps://itunes.apple.com/app/id\(ios)?action=write-review")
        }
        if !android.isEmpty, let encoded = android.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "https://play.google.com/store/apps/details?id=\(encoded)")
        }
        return nil
    }

    /** What tapping a link card does: open a URL, or one of the app's screens. */
    enum Action: Equatable {
        case url(URL)
        case screen(String, value: String?)
    }

    // Never opened from a card, whatever the server sends.
    private static let blockedSchemes: Set<String> = ["javascript", "data", "file", "vbscript", "blob"]

    static func linkAction(_ payload: Payload) -> Action? {
        let raw = payload.text("url").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
                  !blockedSchemes.contains(scheme)
            else { return nil }
            return .url(url)
        }
        let screen = payload.text("screen")
        guard !screen.isEmpty else { return nil }
        return .screen(screen, value: payload["value"]?.stringValue)
    }

    /** APNs hands over raw bytes; the API wants them as lowercase hex. */
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /** True when a notification's payload has "hollo": true. */
    static func isHolloNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        switch userInfo["hollo"] {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String: return value == "true" || value == "1"
        default: return false
        }
    }

    /**
     * Finds web and email addresses in a message, so they're tappable in the
     * bubble. Phone numbers are left alone: order numbers look like them.
     */
    static func linkified(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return result }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  !blockedSchemes.contains(scheme),
                  let range = Range(match.range, in: text),
                  let attributed = Range(range, in: result)
            else { continue }
            result[attributed].link = url
        }
        return result
    }
}

/** The title, text and button of a card, worked out from the message. */
struct CardContent: Equatable {
    let title: String
    let text: String
    let button: String

    init(title: String, text: String, button: String) {
        self.title = title
        self.text = text
        self.button = button
    }

    init(_ message: HolloMessage, strings: HolloStrings) {
        let p = message.payload
        switch message.kind {
        case "review_request":
            // Review requests carry the team's wording in the user's language.
            title = ""
            text = message.body.isEmpty ? strings.reviewText : message.body
            button = p.text("cta").isEmpty ? strings.leaveReview : p.text("cta")
        case "link":
            title = ""
            text = message.body
            button = p.text("label").isEmpty ? strings.open : p.text("label")
        default:
            title = p.text("title")
            text = p.text("description")
            button = p.text("cta").isEmpty ? strings.seeOffer : p.text("cta")
        }
    }
}
