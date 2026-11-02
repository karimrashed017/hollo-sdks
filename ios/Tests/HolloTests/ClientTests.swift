import XCTest
@testable import Hollo

final class ClientTests: XCTestCase {
    func testRegistersOnceThenSendsTheDeviceTokenOnEveryCall() async throws {
        var registrations = 0
        let server = FakeServer([
            "POST /devices": { call in
                registrations += 1
                XCTAssertEqual(call.body?["platform"] as? String, "ios")
                XCTAssertNil(call.header("authorization"))
                return (201, ["deviceToken": "hdt_first_token_value_1234", "userId": "u1"])
            },
            "GET /messages": { _ in (200, ["messages": [Any](), "unread": 0]) },
        ])
        let client = makeClient(server)

        _ = try await client.messages(after: nil)
        _ = try await client.messages(after: nil)

        XCTAssertEqual(registrations, 1)
        let last = try XCTUnwrap(server.calls.last)
        XCTAssertEqual(last.header("x-hollo-app-key"), testAppKey)
        XCTAssertEqual(last.header("authorization"), "Bearer hdt_first_token_value_1234")
    }

    func testConcurrentFirstCallsShareOneRegistration() async throws {
        let server = FakeServer([
            "POST /devices": { _ in (201, ["deviceToken": "hdt_shared_token_value_123"]) },
            "GET /messages": { _ in (200, ["messages": [Any](), "unread": 0]) },
        ])
        let client = makeClient(server)
        async let a = client.messages(after: nil)
        async let b = client.messages(after: nil)
        _ = try await (a, b)
        XCTAssertEqual(server.calls.filter { $0.path == "/devices" }.count, 1)
    }

    func testReusesATokenSavedByAnEarlierLaunch() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let server = FakeServer([
            "GET /messages": { _ in (200, ["messages": [Any](), "unread": 2]) },
        ])
        let response = try await makeClient(server, storage: storage).messages(after: nil)
        XCTAssertEqual(response.unread, 2)
        XCTAssertEqual(server.calls.first?.header("authorization"), "Bearer hdt_saved")
    }

    func testRegistersAgainWhenTheServerHasForgottenTheDevice() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_old", forKey: "hollo.deviceToken.\(testAppKey)")
        storage.set("someone", forKey: "hollo.identity.\(testAppKey)")
        let server = FakeServer([
            "GET /messages": { call in
                call.header("authorization") == "Bearer hdt_old"
                    ? (401, ["error": ["code": "invalid_device", "message": "Unknown"]])
                    : (200, ["messages": [Any](), "unread": 0])
            },
            "POST /devices": { _ in (201, ["deviceToken": "hdt_new"]) },
        ])
        _ = try await makeClient(server, storage: storage).messages(after: nil)
        XCTAssertEqual(storage.string(forKey: "hollo.deviceToken.\(testAppKey)"), "hdt_new")
        // The new device is anonymous, so identify must run again.
        XCTAssertNil(storage.string(forKey: "hollo.identity.\(testAppKey)"))
        XCTAssertEqual(server.calls.map(\.path), ["/messages", "/devices", "/messages"])
    }

    func testRetriesInvalidDeviceOnlyOnce() async throws {
        let server = FakeServer([
            "GET /messages": { _ in (401, ["error": ["code": "invalid_device", "message": "Unknown"]]) },
            "POST /devices": { _ in (201, ["deviceToken": "hdt_new"]) },
        ])
        do {
            _ = try await makeClient(server).messages(after: nil)
            XCTFail("Expected an error")
        } catch let error as HolloError {
            XCTAssertEqual(error.code, "invalid_device")
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertEqual(server.calls.filter { $0.path == "/messages" }.count, 2)
    }

    func testSurfacesAMissingPlanAsAClearError() async throws {
        let server = FakeServer([
            "POST /devices": { _ in (402, ["error": ["code": "plan_required", "message": "No plan"]]) },
        ])
        do {
            _ = try await makeClient(server).messages(after: nil)
            XCTFail("Expected an error")
        } catch let error as HolloError {
            XCTAssertEqual(error, HolloError(code: "plan_required", message: "No plan", status: 402))
            XCTAssertFalse(error.isConnectivity)
        }
    }

    func testMapsAServerErrorWithoutABody() async throws {
        let server = FakeServer([
            "POST /devices": { _ in (503, [:]) },
        ])
        do {
            _ = try await makeClient(server).messages(after: nil)
            XCTFail("Expected an error")
        } catch let error as HolloError {
            XCTAssertEqual(error.code, "network_error")
            XCTAssertEqual(error.status, 503)
            XCTAssertTrue(error.isConnectivity)
        }
    }

    func testPassesTransportFailuresThrough() async throws {
        let server = FakeServer(["POST /devices": { _ in throw offlineError }])
        do {
            _ = try await makeClient(server).messages(after: nil)
            XCTFail("Expected an error")
        } catch let error as HolloError {
            XCTAssertEqual(error.status, 0)
            XCTAssertTrue(error.isConnectivity)
        }
    }

    func testEncodesThePollCursorLikeEncodeURIComponent() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let server = FakeServer(["GET /messages": { _ in (200, ["messages": [Any](), "unread": 0]) }])
        _ = try await makeClient(server, storage: storage).messages(after: "2026-11-02T10:00:00.5+00:00")
        XCTAssertEqual(server.calls.first?.query, "after=2026-11-02T10%3A00%3A00.5%2B00%3A00")
    }

    func testIdentifySkipsDetailsItAlreadySent() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let server = FakeServer(["POST /identify": { _ in (200, ["userId": "u1"]) }])
        let client = makeClient(server, storage: storage)

        let first = try await client.identify(id: "42", name: "Ada", email: nil)
        let again = try await client.identify(id: "42", name: "Ada", email: nil)
        let changed = try await client.identify(id: "42", name: "Ada L", email: nil)

        XCTAssertTrue(first)
        XCTAssertFalse(again)
        XCTAssertTrue(changed)
        XCTAssertEqual(server.calls.count, 2)
        XCTAssertEqual(server.calls.first?.body?["id"] as? String, "42")
        XCTAssertNil(server.calls.first?.body?["email"])
    }

    func testSendsThePushTokenForAPNs() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let server = FakeServer(["POST /push": { _ in (200, ["ok": true]) }])
        let client = makeClient(server, storage: storage)

        try await client.registerPush(token: "0aff", sandbox: true)
        try await client.registerPush(token: nil, sandbox: false)

        let calls = server.calls
        XCTAssertEqual(calls[0].body?["token"] as? String, "0aff")
        XCTAssertEqual(calls[0].body?["provider"] as? String, "apns")
        XCTAssertEqual(calls[0].body?["sandbox"] as? Bool, true)
        XCTAssertTrue(calls[1].body?["token"] is NSNull)
    }

    func testEraseForgetsTheDevice() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let server = FakeServer(["DELETE /user": { _ in (200, ["deleted": true]) }])
        try await makeClient(server, storage: storage).eraseUserData()
        XCTAssertNil(storage.string(forKey: "hollo.deviceToken.\(testAppKey)"))
    }

    func testEventReturnsWhetherToOpenTheChat() async throws {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let server = FakeServer(["POST /events": { _ in (200, ["open": true]) }])
        let open = try await makeClient(server, storage: storage).event(name: "paywall_declined")
        XCTAssertTrue(open)
        XCTAssertEqual(server.calls.first?.body?["name"] as? String, "paywall_declined")
    }
}
