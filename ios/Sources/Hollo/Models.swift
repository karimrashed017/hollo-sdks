import Foundation

// What the SDK API sends and receives. Decoding is lenient on purpose: a new
// field or message kind on the server must never break a shipped app.

/** An offer card the user tapped. `id` is the ID you set in the dashboard. */
public struct HolloOffer: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/**
 * A link card that opens one of your app's screens. `screen` is the name you
 * gave it in the dashboard, `value` its optional value (an order number, say).
 */
public struct HolloLink: Hashable, Sendable {
    public let screen: String
    public let value: String?

    public init(screen: String, value: String?) {
        self.screen = screen
        self.value = value
    }
}

/** Any JSON value, for card payloads whose fields vary by kind. */
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

typealias Payload = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    /** The string at key, or "" (cards treat missing and empty the same). */
    func text(_ key: String) -> String {
        self[key]?.stringValue ?? ""
    }
}

struct HolloMessage: Decodable, Identifiable, Hashable, Sendable {
    enum Sender: String, Sendable {
        case endUser = "end_user"
        case team
        case ai
        case system
    }

    let id: String
    let sender: Sender
    /** "text", "review_request", "offer", "link", or something newer. */
    let kind: String
    let body: String
    /** Card details for review_request, offer and link messages. */
    let payload: Payload
    /** ISO time from the server; also the cursor for the next poll. */
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, sender, kind, body, payload
        case createdAt = "created_at"
    }

    init(
        id: String, sender: Sender, kind: String = "text", body: String,
        payload: Payload = [:], createdAt: String
    ) {
        self.id = id
        self.sender = sender
        self.kind = kind
        self.body = body
        self.payload = payload
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let sender = try c.decodeIfPresent(String.self, forKey: .sender) ?? ""
        self.sender = Sender(rawValue: sender) ?? .system
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        payload = (try? c.decodeIfPresent(Payload.self, forKey: .payload)) ?? [:]
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    var isCard: Bool {
        kind == "review_request" || kind == "offer" || kind == "link"
    }
}

/**
 * Who answers, set on the app's page in the dashboard: a name, a short role,
 * a photo URL and the welcome line. Every field is optional.
 */
struct HolloProfile: Decodable, Hashable, Sendable {
    var name: String?
    var role: String?
    var photo: URL?
    var welcome: String?

    init(name: String? = nil, role: String? = nil, photo: URL? = nil, welcome: String? = nil) {
        self.name = name
        self.role = role
        self.photo = photo
        self.welcome = welcome
    }

    enum CodingKeys: String, CodingKey { case name, role, photo, welcome }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func pick(_ key: CodingKeys) -> String? {
            guard let value = try? c.decodeIfPresent(String.self, forKey: key), !value.isEmpty
            else { return nil }
            return value
        }
        name = pick(.name)
        role = pick(.role)
        welcome = pick(.welcome)
        // The server only sends https uploads; check on the way in too.
        photo = pick(.photo).flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil }
    }
}

/** Push options from the dashboard. */
struct PushSettings: Decodable, Hashable, Sendable {
    enum PermissionCard: String, Sendable {
        case off
        case replies
        case repliesOffers = "replies_offers"
    }

    var permissionCard: PermissionCard
    var notifyLine: Bool

    static let `default` = PushSettings(permissionCard: .off, notifyLine: true)

    init(permissionCard: PermissionCard, notifyLine: Bool) {
        self.permissionCard = permissionCard
        self.notifyLine = notifyLine
    }

    enum CodingKeys: String, CodingKey { case permissionCard, notifyLine }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let card = (try? c.decodeIfPresent(String.self, forKey: .permissionCard)) ?? nil
        permissionCard = card.flatMap(PermissionCard.init(rawValue:)) ?? .off
        notifyLine = ((try? c.decodeIfPresent(Bool.self, forKey: .notifyLine)) ?? nil) ?? true
    }
}

/**
 * Chat colours and title set in the dashboard, applied over the app's
 * `HolloTheme` so the look changes without an app release. Every field is
 * optional, and anything malformed is dropped instead of failing the poll.
 */
struct RemoteTheme: Decodable, Hashable, Sendable {
    /** A colour for light mode, dark mode or both, as 0xRRGGBB. */
    struct Pair: Hashable, Sendable {
        var light: UInt32?
        var dark: UInt32?

        init(light: UInt32? = nil, dark: UInt32? = nil) {
            self.light = light
            self.dark = dark
        }
    }

    enum Scheme: String, Sendable {
        case light, dark, system
    }

    /** Outgoing bubbles, the send button and filled buttons. */
    var accent: Pair?
    /** Text and icons on accent surfaces. */
    var onAccent: Pair?
    var background: Pair?
    /** Bubbles from the team and the AI. */
    var incoming: Pair?
    var incomingText: Pair?
    var colorScheme: Scheme?
    var title: String?

    init(
        accent: Pair? = nil, onAccent: Pair? = nil, background: Pair? = nil,
        incoming: Pair? = nil, incomingText: Pair? = nil,
        colorScheme: Scheme? = nil, title: String? = nil
    ) {
        self.accent = accent
        self.onAccent = onAccent
        self.background = background
        self.incoming = incoming
        self.incomingText = incomingText
        self.colorScheme = colorScheme
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case accent, onAccent, background, incoming, incomingText, colorScheme, title
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func pair(_ key: CodingKeys) -> Pair? {
            guard let raw = try? c.decodeIfPresent(Payload.self, forKey: key) else { return nil }
            let pair = Pair(
                light: raw["light"]?.stringValue.flatMap(Self.hex),
                dark: raw["dark"]?.stringValue.flatMap(Self.hex)
            )
            return pair.light == nil && pair.dark == nil ? nil : pair
        }
        accent = pair(.accent)
        onAccent = pair(.onAccent)
        background = pair(.background)
        incoming = pair(.incoming)
        incomingText = pair(.incomingText)
        let scheme = try? c.decodeIfPresent(String.self, forKey: .colorScheme)
        colorScheme = scheme.flatMap(Scheme.init(rawValue:))
        let title = (try? c.decodeIfPresent(String.self, forKey: .title))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) }
    }

    /** "#RRGGBB" as 0xRRGGBB; anything else is nil. */
    static func hex(_ value: String) -> UInt32? {
        guard value.count == 7, value.hasPrefix("#") else { return nil }
        let digits = value.dropFirst()
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

/** GET /messages. */
struct MessagesResponse: Decodable, Sendable {
    let messages: [HolloMessage]
    let unread: Int
    let profile: HolloProfile?
    let push: PushSettings?
    /** Dashboard colours and title. Servers before SDK 0.1.4 leave it out. */
    let theme: RemoteTheme?
    /** An automation asked to open the chat. */
    let open: Bool
    /** Show "Runs on Hollo" under the composer. Missing means yes. */
    let branding: Bool

    enum CodingKeys: String, CodingKey { case messages, unread, profile, push, theme, open, branding }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decodeIfPresent([HolloMessage].self, forKey: .messages) ?? []
        unread = try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0
        profile = try? c.decodeIfPresent(HolloProfile.self, forKey: .profile)
        push = try? c.decodeIfPresent(PushSettings.self, forKey: .push)
        theme = try? c.decodeIfPresent(RemoteTheme.self, forKey: .theme)
        open = (try? c.decodeIfPresent(Bool.self, forKey: .open)) ?? false
        branding = (try? c.decodeIfPresent(Bool.self, forKey: .branding)) ?? true
    }
}

/** A message the user wrote that hasn't reached the server yet. */
struct OutgoingMessage: Identifiable, Hashable, Sendable {
    enum State: Sendable {
        /** On its way. */
        case sending
        /** No connection; sent automatically once it's back. */
        case waiting
        /** The server refused it; the user can tap to retry. */
        case failed
    }

    let id: UUID
    let body: String
    var state: State
}
