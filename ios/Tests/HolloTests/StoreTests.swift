import XCTest
@testable import Hollo

@MainActor
final class StoreTests: XCTestCase {
    private func makeStore(_ server: FakeServer) -> HolloStore {
        let storage = MemoryStorage()
        storage.set("hdt_saved", forKey: "hollo.deviceToken.\(testAppKey)")
        let store = HolloStore()
        store.start(client: makeClient(server, storage: storage), polling: false)
        return store
    }

    func testKeepsMessagesWrittenOfflineAndSendsThemOnceBack() async {
        let server = FakeServer([
            "GET /messages": { _ in throw offlineError },
            "POST /messages": { _ in throw offlineError },
        ])
        let store = makeStore(server)

        await store.send("Hello?").value
        XCTAssertEqual(store.outbox.map(\.body), ["Hello?"])
        XCTAssertEqual(store.outbox.first?.state, .waiting)
        XCTAssertTrue(store.offline)

        server.route("GET /messages") { _ in (200, ["messages": [Any](), "unread": 0]) }
        server.route("POST /messages") { call in
            (201, ["message": messageJSON("m1", sender: "end_user", at: "2026-11-02T10:00:00+00:00",
                                          body: call.body?["body"] as? String ?? "")])
        }
        await store.refresh()

        XCTAssertTrue(store.outbox.isEmpty)
        XCTAssertFalse(store.offline)
        XCTAssertEqual(store.messages.map(\.body), ["Hello?"])
    }

    func testMarksARefusedMessageFailedAndRetriesIt() async {
        let server = FakeServer([
            "POST /messages": { _ in (400, ["error": ["code": "empty_message", "message": "body is required."]]) },
        ])
        let store = makeStore(server)

        await store.send("Hi").value
        let item = try? XCTUnwrap(store.outbox.first)
        XCTAssertEqual(item?.state, .failed)
        XCTAssertFalse(store.offline)

        server.route("POST /messages") { _ in
            (201, ["message": messageJSON("m1", sender: "end_user", at: "2026-11-02T10:00:00+00:00")])
        }
        if let item { await store.retry(item.id).value }
        XCTAssertTrue(store.outbox.isEmpty)
        XCTAssertEqual(store.messages.count, 1)
    }

    func testMergesPollsInTimeOrderWithoutDuplicates() async {
        let server = FakeServer([
            "GET /messages": { _ in
                (200, ["messages": [
                    messageJSON("b", at: "2026-11-02T10:00:02+00:00"),
                    messageJSON("a", at: "2026-11-02T10:00:01+00:00"),
                ], "unread": 2])
            },
        ])
        let store = makeStore(server)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.messages.map(\.id), ["a", "b"])
        XCTAssertEqual(store.unread, 2)
        // The poll asks only for messages after the newest one.
        XCTAssertEqual(server.calls.last?.query, "after=2026-11-02T10%3A00%3A02%2B00%3A00")
    }

    func testOpeningTheChatClearsUnread() async {
        let server = FakeServer([
            "GET /messages": { _ in (200, ["messages": [messageJSON("a", at: "t1")], "unread": 1]) },
            "POST /read": { _ in (200, ["unread": 0]) },
        ])
        let store = makeStore(server)
        await store.refresh()
        XCTAssertEqual(store.unread, 1)

        store.chatAppeared()
        XCTAssertTrue(store.isOpen)
        XCTAssertEqual(store.unread, 0)
        store.chatDisappeared()
        XCTAssertFalse(store.isOpen)
    }

    func testAnAutomationCanOpenTheChat() async {
        let server = FakeServer([
            "GET /messages": { _ in (200, ["messages": [Any](), "unread": 0, "open": true]) },
        ])
        let store = makeStore(server)
        var opened = 0
        store.requestOpen = { opened += 1 }
        await store.refresh()
        XCTAssertEqual(opened, 1)
    }

    func testSignOutStartsAFreshAnonymousChat() async {
        let server = FakeServer([
            "GET /messages": { call in
                call.header("authorization") == "Bearer hdt_saved"
                    ? (200, ["messages": [messageJSON("old", at: "t1")], "unread": 0])
                    : (200, ["messages": [Any](), "unread": 0])
            },
            "POST /devices": { _ in (201, ["deviceToken": "hdt_fresh_device_token_value"]) },
        ])
        let store = makeStore(server)
        await store.refresh()
        XCTAssertEqual(store.messages.map(\.id), ["old"])

        store.signOut()
        await store.settle()

        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(server.calls.last?.header("authorization"), "Bearer hdt_fresh_device_token_value")
    }

    func testShowsThePushCardAfterTheFirstMessageOnlyOnce() async {
        let server = FakeServer([
            "GET /messages": { _ in
                (200, ["messages": [Any](), "unread": 0,
                       "push": ["permissionCard": "replies", "notifyLine": true]])
            },
            "POST /messages": { _ in
                (201, ["message": messageJSON("m1", sender: "end_user", at: "t1")])
            },
        ])
        let store = makeStore(server)
        store.canAskForPush = { true }
        var asked = 0
        store.askForPush = { asked += 1 }
        await store.refresh()

        await store.send("Hi").value
        XCTAssertTrue(store.askPush)

        await store.answerPushCard(accept: true)
        XCTAssertFalse(store.askPush)
        XCTAssertEqual(asked, 1)
    }
}
