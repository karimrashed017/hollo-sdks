import SwiftUI
import UIKit
import UserNotifications

/**
 * Hollo's public API: start Hollo once at launch, then present the chat,
 * identify users, hand over the push token and read the unread count.
 * Everything runs on the main actor, like the UI it drives.
 */
@MainActor
public enum Hollo {
    public static let sdkVersion = "0.1.5"

    static let store = HolloStore()
    private static var observers: [NSObjectProtocol] = []

    // MARK: Setup

    /**
     * Call once when the app starts, as early as possible. It's quick, it
     * doesn't block launch, and it doesn't show or ask the user anything.
     *
     * - Parameter apiURL: only for testing against a local server.
     */
    public static func start(appKey: String, apiURL: URL? = nil) {
        let key = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.hasPrefix("app_") {
            logger.error("Hollo app keys start with app_. Copy yours from the dashboard.")
        }
        let client = HolloClient(
            appKey: key,
            apiURL: apiURL ?? HolloClient.defaultAPIURL,
            info: DeviceInfo.current(language: language)
        )
        store.requestOpen = { present() }
        store.canAskForPush = { await PushPermission.status() == .notDetermined }
        store.askForPush = { await PushPermission.request() }
        store.checkNotificationsAllowed = { await PushPermission.allowed() }
        observeLifecycle()
        store.start(client: client)
    }

    /** How the chat looks. Set it right after `start(appKey:)`. */
    public static var theme = HolloTheme()

    /**
     * The language for the chat's own labels, like "fr" or "pt-BR". Nil
     * follows the device. Set it before `start(appKey:)` for the server to
     * use it too (review card wording, for example).
     */
    public static var language: String?

    // MARK: The chat

    /** Number of replies the user hasn't seen. SwiftUI redraws when it changes. */
    public static var unreadCount: Int { store.unread }

    /** Shows the chat in a sheet over the current screen. */
    public static func present() {
        guard store.started else {
            logger.error("Call Hollo.start(appKey:) before Hollo.present().")
            return
        }
        // A chat is already on screen (embedded, or a sheet): nothing to do.
        guard !store.isOpen else { return }
        Presenter.present()
    }

    /** Closes the chat sheet opened by `present()`. */
    public static func dismiss() {
        Presenter.dismiss()
    }

    // MARK: Users

    /**
     * Links this device to your app's user, so history follows them to
     * every device. Calling it again with the same details does nothing.
     *
     * Pass `identityToken` (an HMAC-SHA256 of `id`, made by your server with
     * the app's identity secret) to mark the user as verified.
     */
    public static func identify(
        id: String, name: String? = nil, email: String? = nil, identityToken: String? = nil
    ) {
        guard store.started else { return logNotStarted("identify") }
        store.identify(id: id, name: name, email: email, identityToken: identityToken)
    }

    /**
     * Clears the user and the local copy of the conversation. History stays
     * in your inbox and comes back when they sign in again.
     */
    public static func signOut() {
        guard store.started else { return logNotStarted("signOut") }
        store.signOut()
    }

    /**
     * Deletes the user's support data from Hollo and the device, for
     * account-deletion flows. It can't be undone. Throws if it fails, so
     * the user can try again.
     */
    public static func eraseUserData() async throws {
        try await store.eraseUserData()
    }

    // MARK: Cards and events

    /** Runs when the user taps an offer card. Show your paywall for `offer.id`. */
    public static var onOffer: ((HolloOffer) -> Void)?

    /**
     * Runs when the user taps a link card that opens one of your screens.
     * Navigate to `link.screen` (with `link.value`, if it has one).
     */
    public static var onLink: ((HolloLink) -> Void)?

    /**
     * Reports something the user did, like "paywall_declined". Automations
     * set up in the dashboard can reply, send an offer or open the chat.
     */
    public static func track(_ event: String) {
        guard store.started else { return logNotStarted("track") }
        store.track(event)
    }

    /** The same as `track(_:)`. */
    public static func log(event: String) {
        track(event)
    }

    /** Tells Hollo whether the user pays, for automation audiences and the AI. */
    public static func setSubscriber(_ isSubscriber: Bool) {
        guard store.started else { return logNotStarted("setSubscriber") }
        store.setSubscriber(isSubscriber)
    }

    // MARK: Push

    /**
     * Hands Hollo the APNs device token, from
     * `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
     * Call it at every launch; Apple may change the token at any time.
     *
     * - Parameter sandbox: whether the token is for APNs' development
     *   server. Defaults to true in Debug builds and false otherwise; pass it
     *   when that guess is wrong (a Release build signed for development).
     */
    public static func registerPush(deviceToken: Data, sandbox: Bool? = nil) {
        store.registerPush(token: HolloLinks.hex(deviceToken), sandbox: sandbox ?? isDebugBuild)
    }

    /** Stops Hollo notifications on this device, for an in-app "notifications off" switch. */
    public static func unregisterPush() {
        store.registerPush(token: nil, sandbox: isDebugBuild)
    }

    /**
     * Pass the response when the user taps a notification. Returns true and
     * opens the chat if it was Hollo's, so your own notifications still
     * reach your code.
     */
    @discardableResult
    public static func handle(notification response: UNNotificationResponse) -> Bool {
        handleNotification(response.notification.request.content.userInfo)
    }

    /** The same check as `handle(notification:)`, for a notification's `userInfo`. */
    @discardableResult
    public static func handleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard HolloLinks.isHolloNotification(userInfo) else { return false }
        present()
        return true
    }

    // MARK: Internals

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static func logNotStarted(_ call: String) {
        logger.error("Call Hollo.start(appKey:) before Hollo.\(call, privacy: .public)().")
    }

    /** Polls only while the app is in the foreground. */
    private static func observeLifecycle() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { store.setActive(false) }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { store.setActive(true) }
            },
        ]
    }

    /** What tapping a card's button does. */
    static func tapCard(_ message: HolloMessage) {
        switch message.kind {
        case "review_request":
            if let url = HolloLinks.reviewURL(message.payload) {
                UIApplication.shared.open(url)
            }
        case "link":
            openLink(message)
        default:
            let offer = HolloOffer(id: message.payload.text("ref"), title: message.payload.text("title"))
            // Close the sheet first, so the app can present its paywall.
            Presenter.closeThen { onOffer?(offer) }
        }
    }

    /** Links open a URL themselves; screens go to the app's onLink handler. */
    private static func openLink(_ message: HolloMessage) {
        switch HolloLinks.linkAction(message.payload) {
        case .url(let url)?:
            Task {
                let opened = await UIApplication.shared.open(url)
                store.linkTapped(messageId: message.id, opened: opened)
            }
        case .screen(let screen, value: let value)?:
            guard let onLink else {
                store.linkTapped(messageId: message.id, opened: false)
                return
            }
            Presenter.closeThen { onLink(HolloLink(screen: screen, value: value)) }
            store.linkTapped(messageId: message.id, opened: true)
        case nil:
            store.linkTapped(messageId: message.id, opened: false)
        }
    }
}

/** Notification permission, for the in-chat card (F-40). */
enum PushPermission {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func allowed() async -> Bool {
        switch await status() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /** Shows the system prompt; if allowed, the app delegate gets a token. */
    @MainActor
    static func request() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}

/** Model, OS, app and SDK version, language: sent once when the device registers. */
enum DeviceInfo {
    @MainActor
    static func current(language: String?) -> [String: String] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return [
            "os": "iOS \(UIDevice.current.systemVersion)",
            "model": model(),
            "app": "\(version) (\(build))",
            // Review requests and other team messages use it to pick wording.
            "language": language ?? Locale.preferredLanguages.first ?? "en",
            "sdk": "ios \(Hollo.sdkVersion)",
        ]
    }

    /** Like "iPhone16,1"; the simulator reports the model it's simulating. */
    static func model() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
