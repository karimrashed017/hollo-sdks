import Foundation

// The Hollo HTTP client: no UIKit or SwiftUI, so it can be unit-tested with a
// fake transport. Talks to the SDK API at https://hollo.so/api/v1 with the
// app key and this install's device token.

/** An error from the Hollo API, or from reaching it. */
public struct HolloError: Error, LocalizedError, Equatable, Sendable {
    /** The API's error code, like "plan_required", or "network_error". */
    public let code: String
    public let message: String
    /** The HTTP status, or 0 when the server couldn't be reached. */
    public let status: Int

    public init(code: String, message: String, status: Int) {
        self.code = code
        self.message = message
        self.status = status
    }

    public var errorDescription: String? { message }

    /** Worth retrying later: no connection, or the server had a problem. */
    var isConnectivity: Bool { status == 0 || status >= 500 }

    static let notStarted = HolloError(
        code: "not_started",
        message: "Call Hollo.start(appKey:) before using Hollo.",
        status: 0
    )
}

/** Sends one HTTP request. Swapped for a fake in tests. */
protocol HolloTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HolloTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HolloError(code: "network_error", message: "No HTTP response.", status: 0)
            }
            return (data, http)
        } catch let error as HolloError {
            throw error
        } catch {
            throw HolloError(
                code: "network_error",
                message: "Couldn't reach Hollo. Check the connection.",
                status: 0
            )
        }
    }
}

/** Small strings kept across launches. */
protocol HolloStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func remove(forKey key: String)
}

// The device token lives in UserDefaults, not the Keychain. It's an opaque
// per-install ID that only opens this install's own chat, and the app
// sandbox already protects it. Keychain items outlive an uninstall, which
// would hand a reinstalled app (possibly someone else's, after a resale) the
// old conversation. UserDefaults is declared in PrivacyInfo.xcprivacy (CA92.1).
final class UserDefaultsStorage: HolloStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    func remove(forKey key: String) { defaults.removeObject(forKey: key) }
}

/** Decodes any JSON object, for responses whose body we don't need. */
struct Ignored: Decodable, Sendable {}

actor HolloClient {
    static let defaultAPIURL = URL(string: "https://hollo.so/api/v1")!

    let appKey: String
    private let apiURL: String
    private let info: [String: String]
    private let transport: HolloTransport
    private let storage: HolloStorage
    private var token: String?
    private var registration: Task<String, Error>?

    init(
        appKey: String,
        apiURL: URL = HolloClient.defaultAPIURL,
        info: [String: String] = [:],
        transport: HolloTransport = URLSessionTransport(),
        storage: HolloStorage = UserDefaultsStorage()
    ) {
        self.appKey = appKey
        var base = apiURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        self.apiURL = base
        self.info = info
        self.transport = transport
        self.storage = storage
    }

    // MARK: Keys

    private var tokenKey: String { "hollo.deviceToken.\(appKey)" }
    private var identityKey: String { "hollo.identity.\(appKey)" }
    private func flagKey(_ name: String) -> String { "hollo.\(name).\(appKey)" }

    // MARK: Device token

    /** The device token, registering this install the first time. */
    func deviceToken() async throws -> String {
        if let token { return token }
        if let saved = storage.string(forKey: tokenKey) {
            token = saved
            return saved
        }
        // Concurrent first calls share one registration.
        if let registration { return try await registration.value }
        let task = Task { try await self.register() }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func register() async throws -> String {
        struct Registered: Decodable { let deviceToken: String }
        let body: JSONValue = .object([
            "platform": .string("ios"),
            "info": .object(info.mapValues { .string($0) }),
        ])
        let result: Registered = try await call("/devices", method: "POST", body: body, auth: false)
        storage.set(result.deviceToken, forKey: tokenKey)
        token = result.deviceToken
        return result.deviceToken
    }

    /** Drops the device token, so the next call registers a fresh device. */
    func forgetDevice() {
        token = nil
        registration?.cancel()
        registration = nil
        storage.remove(forKey: tokenKey)
        // A new device is anonymous, so identify has to run again.
        storage.remove(forKey: identityKey)
    }

    // MARK: Requests

    /// The server's error body: { "error": { "code", "message" } }.
    private struct APIFailure: Decodable {
        struct Detail: Decodable { let code: String?; let message: String? }
        let error: Detail?
    }

    func call<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: JSONValue? = nil,
        auth: Bool = true,
        retried: Bool = false
    ) async throws -> T {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(appKey, forHTTPHeaderField: "x-hollo-app-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if auth {
            let token = try await deviceToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }

        let (data, response) = try await transport.send(request)

        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIFailure.self, from: data))?.error
            let code = detail?.code ?? "network_error"
            // The server forgot this device (its data was erased, say):
            // register again, once.
            if code == "invalid_device" && auth && !retried {
                forgetDevice()
                return try await call(path, method: method, query: query, body: body, auth: auth, retried: true)
            }
            throw HolloError(
                code: code,
                message: detail?.message ?? "Request failed (\(response.statusCode)).",
                status: response.statusCode
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw HolloError(
                code: "invalid_response",
                message: "Hollo sent a response this SDK can't read.",
                status: response.statusCode
            )
        }
    }

    private func url(_ path: String, query: [String: String]) throws -> URL {
        var string = apiURL + path
        if !query.isEmpty {
            // Encode everything but unreserved characters, like JavaScript's
            // encodeURIComponent: a "+" in a timestamp must not become a space.
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            string += "?" + query.sorted { $0.key < $1.key }.map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }.joined(separator: "&")
        }
        guard let url = URL(string: string) else {
            throw HolloError(code: "invalid_url", message: "Bad API URL: \(apiURL)", status: 0)
        }
        return url
    }

    // MARK: Endpoints

    /**
     * Links this device to the app's own user. Returns false without a
     * request when the same details were already sent from this device.
     */
    func identify(
        id: String, name: String?, email: String?, identityToken: String? = nil
    ) async throws -> Bool {
        // The token is in the fingerprint so adding one later still sends it.
        let fingerprint = [id, name ?? "", email ?? "", identityToken ?? ""]
            .joined(separator: "\u{1F}")
        if storage.string(forKey: identityKey) == fingerprint { return false }
        var body: [String: JSONValue] = ["id": .string(id)]
        if let name, !name.isEmpty { body["name"] = .string(name) }
        if let email, !email.isEmpty { body["email"] = .string(email) }
        if let identityToken, !identityToken.isEmpty { body["token"] = .string(identityToken) }
        let _: Ignored = try await call("/identify", method: "POST", body: .object(body))
        storage.set(fingerprint, forKey: identityKey)
        return true
    }

    func messages(after: String?) async throws -> MessagesResponse {
        try await call("/messages", query: after.map { ["after": $0] } ?? [:])
    }

    func send(_ text: String) async throws -> HolloMessage {
        struct Sent: Decodable { let message: HolloMessage }
        let sent: Sent = try await call("/messages", method: "POST", body: .object(["body": .string(text)]))
        return sent.message
    }

    /** Counts a link card tap; opened is false when nothing could open it. */
    func linkTapped(messageId: String, opened: Bool) async throws {
        let _: Ignored = try await call(
            "/links/tap", method: "POST",
            body: .object(["messageId": .string(messageId), "opened": .bool(opened)])
        )
    }

    /** Reports an event or the subscription status. True: open the chat now. */
    func event(name: String? = nil, subscriber: Bool? = nil) async throws -> Bool {
        struct Result: Decodable { let open: Bool? }
        var body: [String: JSONValue] = [:]
        if let name { body["name"] = .string(name) }
        if let subscriber { body["subscriber"] = .bool(subscriber) }
        let result: Result = try await call("/events", method: "POST", body: .object(body))
        return result.open ?? false
    }

    /** Saves the hex APNs token, or nil to stop notifications. */
    func registerPush(token: String?, sandbox: Bool) async throws {
        let _: Ignored = try await call(
            "/push", method: "POST",
            body: .object([
                "token": token.map { .string($0) } ?? .null,
                "provider": .string("apns"),
                "sandbox": .bool(sandbox),
            ])
        )
    }

    func markRead() async throws {
        let _: Ignored = try await call("/read", method: "POST")
    }

    /** Deletes this user's support data on the server, then on the device. */
    func eraseUserData() async throws {
        let _: Ignored = try await call("/user", method: "DELETE")
        forgetDevice()
    }

    // MARK: Flags

    /** Small flags kept beside the device token, like "asked for push". */
    func flag(_ name: String) -> Bool {
        storage.string(forKey: flagKey(name)) != nil
    }

    func setFlag(_ name: String) {
        storage.set("1", forKey: flagKey(name))
    }
}
