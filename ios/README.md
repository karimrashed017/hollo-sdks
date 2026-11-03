# Hollo iOS SDK (Swift)

In-app support chat for iOS 17+, in SwiftUI with a UIKit wrapper. Swift
Package, library product `Hollo`, no third-party dependencies. Talks only to
the Hollo API, with the app's public key.

Install: in Xcode, **File → Add Package Dependencies…**, paste
`https://github.com/karimrashed017/hollo-sdks` and add the **Hollo** library.

```swift
Hollo.start(appKey: "app_XXXX")       // once, at launch
Hollo.present()                        // the chat as a sheet
HolloChat()                            // or as a SwiftUI view
HolloChatViewController()              // or as a UIKit view controller
Hollo.unreadCount                      // observable, for badges
Hollo.identify(id:name:email:identityToken:) // after sign-in
Hollo.signOut()
try await Hollo.eraseUserData()        // account deletion
Hollo.registerPush(deviceToken:)       // from the app delegate
Hollo.unregisterPush()
Hollo.handle(notification:)            // returns true if it was Hollo's
Hollo.track("paywall_declined")        // automations; also Hollo.log(event:)
Hollo.setSubscriber(true)
Hollo.onOffer = { offer in … }         // offer cards
Hollo.onLink = { link in … }           // link cards that open your screens
Hollo.theme = HolloTheme(accent: …)    // looks
Hollo.language = "fr"                  // label language override
```

Pass an identity token signed by your server to mark the user as verified.
Hollo's AI only runs account actions for verified users.

```swift
Hollo.identify(id: user.id, email: user.email, identityToken: tokenFromYourServer)
```

## How it's built

| File                 | What it does                                                        |
| -------------------- | ------------------------------------------------------------------- |
| `Hollo.swift`        | The public `Hollo` namespace, push permission, device info          |
| `HolloStore.swift`   | `@Observable` state: messages, outbox, unread, polling, push card   |
| `HolloClient.swift`  | HTTP client (an actor) with an injectable transport and storage     |
| `Models.swift`       | Lenient Codable models for the API                                  |
| `Links.swift`        | Review URLs, link-card actions, hex tokens, link detection          |
| `HolloChat.swift`    | The SwiftUI chat                                                    |
| `Presenter.swift`    | `HolloChatViewController` and the sheet `Hollo.present()` shows     |
| `Theme.swift`        | `HolloTheme` and the black-and-white defaults                       |
| `Strings.swift`      | The chat's labels in English, Spanish, French, German, Portuguese, Italian |

- Polls every 3 seconds while a chat is on screen and every 30 seconds
  otherwise, and stops while the app is in the background.
- Messages written offline wait in an outbox and go out with the next
  successful poll, as long as the app stays open.
- The device token is kept in UserDefaults (see the comment in
  `HolloClient.swift` for why not the Keychain). `PrivacyInfo.xcprivacy`
  declares that use (CA92.1) and the data the chat collects.
- Push tokens go to `POST /api/v1/push` as hex with `provider: "apns"`;
  `sandbox` is true in Debug builds unless the app passes it.
- A small "Runs on Hollo" line sits under the composer and opens hollo.so.
  The server turns it off with `branding: false` in `GET /messages`.

## Tests

`Tests/HolloTests` (XCTest) covers the client against a fake transport,
decoding, link handling and the store. Open the repo root in Xcode and press
⌘U, or:

```sh
xcodebuild test -scheme Hollo -destination 'platform=iOS Simulator,name=iPhone 16'
```

