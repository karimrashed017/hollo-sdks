import Foundation
import Observation
import os

// The SDK's state: the conversation, the unread count, whether a chat is on
// screen, the messages still to send, plus polling. No UIKit here; the Hollo
// namespace wires in presenting and notification permission, so this can be
// unit-tested.

let logger = Logger(subsystem: "so.hollo", category: "Hollo")

@MainActor
@Observable
final class HolloStore {
    static let openPoll: Duration = .seconds(3)
    static let closedPoll: Duration = .seconds(30)

    private(set) var started = false
    private(set) var messages: [HolloMessage] = []
    /** Messages the user wrote that haven't reached the server yet, in order. */
    private(set) var outbox: [OutgoingMessage] = []
    private(set) var unread = 0
    /** The last request couldn't reach Hollo; shows the connection banner. */
    private(set) var offline = false
    /** Who answers, from the dashboard. */
    private(set) var profile = HolloProfile()
    private(set) var push = PushSettings.default
    /** This device sent Hollo a push token. */
    private(set) var pushRegistered = false
    /** The user allowed notifications, so the "we'll notify you" line is true. */
    private(set) var notificationsAllowed = false
    /** Show the in-chat card asking to turn on notifications (F-40). */
    private(set) var askPush = false
    /** How many chat views are on screen; a sheet and an embedded tab can overlap. */
    private(set) var visibleChats = 0

    var isOpen: Bool { visibleChats > 0 }

    // Wired up by Hollo.start, so the store itself needs no UIKit.
    @ObservationIgnored var requestOpen: @MainActor () -> Void = {}
    /** True when the system hasn't asked about notifications yet. */
    @ObservationIgnored var canAskForPush: @MainActor () async -> Bool = { false }
    @ObservationIgnored var askForPush: @MainActor () async -> Void = {}
    @ObservationIgnored var checkNotificationsAllowed: @MainActor () async -> Bool = { false }

    @ObservationIgnored private var client: HolloClient?
    @ObservationIgnored private var polling = true
    @ObservationIgnored private var active = true
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var pushToken: String?
    @ObservationIgnored private var pushSandbox = false
    /**
     * Bumped whenever the conversation is swapped (sign-in, sign-out,
     * erase), so answers to requests made before it are dropped instead of
     * showing one user's messages to another.
     */
    @ObservationIgnored private var epoch = 0

    init() {}

    // MARK: Lifecycle

    func start(client: HolloClient, polling: Bool = true) {
        self.client = client
        self.polling = polling
        epoch += 1
        started = true
        messages = []
        outbox = []
        unread = 0
        offline = false
        // The app delegate may hand over the push token before start runs.
        if let pushToken { registerPush(token: pushToken, sandbox: pushSandbox) }
        restartPolling()
    }

    /** The app went to the background: stop polling until it's back. */
    func setActive(_ active: Bool) {
        self.active = active
        if active {
            restartPolling()
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func chatAppeared() {
        visibleChats += 1
        if visibleChats == 1 { openChanged() }
    }

    func chatDisappeared() {
        visibleChats = max(0, visibleChats - 1)
        if visibleChats == 0 { openChanged() }
    }

    private func openChanged() {
        if isOpen {
            unread = 0
            if let client { Task { try? await client.markRead() } }
            Task { notificationsAllowed = await checkNotificationsAllowed() }
        }
        restartPolling()
    }

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = nil
        guard client != nil, active else { return }
        guard polling else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay = self.isOpen ? Self.openPoll : Self.closedPoll
                try? await Task.sleep(for: delay)
            }
        }
    }

    // MARK: Polling

    /** Fetches new messages, then sends anything waiting in the outbox. */
    func refresh() async {
        guard client != nil else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            guard let client else { return }
            let epoch = self.epoch
            do {
                let response = try await client.messages(after: messages.last?.createdAt)
                guard epoch == self.epoch else { continue }
                apply(response)
                offline = false
            } catch {
                guard epoch == self.epoch else { continue }
                offline = (error as? HolloError)?.isConnectivity ?? true
            }
            if !offline { await flushOutbox() }
        } while refreshAgain
    }

    private func apply(_ response: MessagesResponse) {
        if let profile = response.profile, profile != self.profile { self.profile = profile }
        if let push = response.push, push != self.push { self.push = push }
        merge(response.messages)
        if isOpen {
            if response.unread > 0, let client { Task { try? await client.markRead() } }
            unread = 0
        } else {
            unread = response.unread
        }
        if response.open && !isOpen { requestOpen() }
    }

    /** Adds messages we don't have yet, keeping them in time order. */
    private func merge(_ incoming: [HolloMessage]) {
        let known = Set(messages.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        var all = messages + fresh
        // Server times share one ISO format, so text order is time order.
        // A poll and a send can land out of order; the sort puts them right.
        if zip(all, all.dropFirst()).contains(where: { $0.createdAt > $1.createdAt }) {
            all = all.enumerated()
                .sorted { ($0.element.createdAt, $0.offset) < ($1.element.createdAt, $1.offset) }
                .map(\.element)
        }
        messages = all
    }

    // MARK: Sending

    /**
     * Queues a message and sends it. Without a connection it waits in the
     * outbox and goes out with the next successful poll, while the app is open.
     */
    @discardableResult
    func send(_ text: String) -> Task<Void, Never> {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !body.isEmpty else { return Task {} }
        outbox.append(OutgoingMessage(id: UUID(), body: body, state: .sending))
        return Task { await flushOutbox() }
    }

    /** The user tapped a failed message. */
    @discardableResult
    func retry(_ id: UUID) -> Task<Void, Never> {
        if let index = outbox.firstIndex(where: { $0.id == id }) {
            outbox[index].state = .sending
        }
        return Task { await flushOutbox() }
    }

    func flushOutbox() async {
        guard !flushing, let client else { return }
        flushing = true
        defer { flushing = false }
        let epoch = self.epoch
        while let index = outbox.firstIndex(where: { $0.state != .failed }) {
            let item = outbox[index]
            outbox[index].state = .sending
            let first = !messages.contains { $0.sender == .endUser }
            do {
                let message = try await client.send(item.body)
                // It reached the server either way, so never send it twice.
                outbox.removeAll { $0.id == item.id }
                guard epoch == self.epoch else { return }
                merge([message])
                offline = false
                if first { await maybeAskForPush() }
            } catch {
                guard epoch == self.epoch else {
                    if let i = outbox.firstIndex(where: { $0.id == item.id }) { outbox[i].state = .waiting }
                    return
                }
                let connectivity = (error as? HolloError)?.isConnectivity ?? true
                if let i = outbox.firstIndex(where: { $0.id == item.id }) {
                    outbox[i].state = connectivity ? .waiting : .failed
                }
                if connectivity {
                    // Keep the order: the rest wait for the connection too.
                    offline = true
                    for i in outbox.indices where outbox[i].state == .sending {
                        outbox[i].state = .waiting
                    }
                    return
                }
                logger.error("Hollo couldn't send a message: \((error as? HolloError)?.code ?? "unknown", privacy: .public)")
            }
        }
    }

    // MARK: Push

    /** Saves the push token, or nil when the user turns notifications off. */
    func registerPush(token: String?, sandbox: Bool) {
        pushToken = token
        pushSandbox = sandbox
        pushRegistered = token != nil
        askPush = false
        enqueue { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                try await client.registerPush(token: token, sandbox: sandbox)
            } catch {
                logger.error("Hollo couldn't save the push token: \((error as? HolloError)?.code ?? "unknown", privacy: .public)")
            }
        }
    }

    /** Just after the first message: the moment a reply is worth waiting for. */
    private func maybeAskForPush() async {
        guard push.permissionCard != .off, !askPush, let client else { return }
        if await client.flag("pushAsked") { return }
        // "Never shows if the app already asked": the system remembers that.
        guard await canAskForPush() else { return }
        askPush = true
    }

    /** The user answered the card. Either way it never shows again. */
    func answerPushCard(accept: Bool) async {
        askPush = false
        await client?.setFlag("pushAsked")
        guard accept else { return }
        await askForPush()
        notificationsAllowed = await checkNotificationsAllowed()
    }

    // MARK: Users

    func identify(id: String, name: String?, email: String?) {
        enqueue { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                if try await client.identify(id: id, name: name, email: email) {
                    // The device may now belong to a user with history.
                    await self.reload(clearOutbox: false)
                }
            } catch {
                logger.error("Hollo couldn't identify the user: \((error as? HolloError)?.code ?? "unknown", privacy: .public)")
            }
        }
    }

    /** Signing out starts a fresh anonymous chat; history stays on the server. */
    func signOut() {
        enqueue { [weak self] in
            guard let self, let client = self.client else { return }
            await client.forgetDevice()
            await self.reload(clearOutbox: true)
        }
    }

    /** Deletes this user's support data (App Store account-deletion rules). */
    func eraseUserData() async throws {
        guard let client else { throw HolloError.notStarted }
        let previous = queue
        let work = Task { [weak self] in
            await previous?.value
            try await client.eraseUserData()
            await self?.reload(clearOutbox: true)
        }
        queue = Task { _ = try? await work.value }
        try await work.value
    }

    /** Reports an event; automations may open the chat in response. */
    func track(_ name: String) {
        enqueue { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                if try await client.event(name: name), !self.isOpen {
                    self.requestOpen()
                } else {
                    await self.refresh()
                }
            } catch {
                logger.error("Hollo couldn't track an event: \((error as? HolloError)?.code ?? "unknown", privacy: .public)")
            }
        }
    }

    func setSubscriber(_ subscriber: Bool) {
        enqueue { [weak self] in
            guard let client = self?.client else { return }
            _ = try? await client.event(subscriber: subscriber)
        }
    }

    /** Reports a link card tap for the dashboard's counts. Never throws. */
    func linkTapped(messageId: String, opened: Bool) {
        guard let client else { return }
        Task { try? await client.linkTapped(messageId: messageId, opened: opened) }
    }

    /** Runs work after everything queued before it, so calls keep their order. */
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    /** Waits for queued identify, sign-out and push calls. For tests. */
    func settle() async {
        await queue?.value
    }

    private func reload(clearOutbox: Bool) async {
        epoch += 1
        messages = []
        unread = 0
        askPush = false
        if clearOutbox { outbox = [] }
        // A new device on the server needs the push token again.
        if let pushToken, let client {
            try? await client.registerPush(token: pushToken, sandbox: pushSandbox)
        }
        await refresh()
    }
}
