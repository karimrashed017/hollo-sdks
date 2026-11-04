import Foundation
@testable import Hollo

/** Keeps strings in memory instead of UserDefaults. */
final class MemoryStorage: HolloStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: String] = [:]

    func string(forKey key: String) -> String? {
        lock.withLock { data[key] }
    }

    func set(_ value: String, forKey key: String) {
        lock.withLock { data[key] = value }
    }

    func remove(forKey key: String) {
        lock.withLock { _ = data.removeValue(forKey: key) }
    }
}

/** A recorded request, with its JSON body decoded and the raw bytes kept. */
struct Call {
    let method: String
    let path: String
    let query: String?
    let headers: [String: String]
    let body: [String: Any]?
    let data: Data?

    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

/** A fake SDK API that answers by "METHOD /path". */
final class FakeServer: HolloTransport, @unchecked Sendable {
    typealias Route = (Call) throws -> (Int, [String: Any])

    private let lock = NSLock()
    private var routes: [String: Route]
    private var recorded: [Call] = []

    init(_ routes: [String: Route]) {
        self.routes = routes
    }

    var calls: [Call] { lock.withLock { recorded } }

    func route(_ key: String, _ route: @escaping Route) {
        lock.withLock { routes[key] = route }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path.replacingOccurrences(of: "/api/v1", with: "")
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let call = Call(
            method: request.httpMethod ?? "GET",
            path: path,
            query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body,
            data: request.httpBody
        )
        let route: Route? = lock.withLock {
            recorded.append(call)
            return routes["\(call.method) \(path)"]
        }
        guard let route else {
            throw HolloError(code: "network_error", message: "No route for \(call.method) \(path)", status: 0)
        }
        let (status, json) = try route(call)
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

let testAppKey = "app_" + String(repeating: "a", count: 32)

func makeClient(_ server: FakeServer, storage: MemoryStorage = MemoryStorage()) -> HolloClient {
    HolloClient(appKey: testAppKey, info: ["sdk": "ios test"], transport: server, storage: storage)
}

func messageJSON(_ id: String, sender: String = "team", at time: String, body: String = "Hi") -> [String: Any] {
    ["id": id, "sender": sender, "kind": "text", "body": body, "payload": NSNull(), "created_at": time]
}

/** A photo message as the server returns it, with signed links. */
func photoMessageJSON(_ id: String, at time: String, body: String = "", photos: [String]) -> [String: Any] {
    [
        "id": id, "sender": "end_user", "kind": "image", "body": body,
        "payload": ["photos": photos.map { "ws/conv/\($0).jpg" }], "created_at": time,
        "photos": photos.map { "https://storage.hollo.so/signed/\($0).jpg?token=t" },
    ]
}

let offlineError = HolloError(code: "network_error", message: "Offline", status: 0)
