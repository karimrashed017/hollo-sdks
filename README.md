# Hollo SDKs

In-app support chat for iOS, Android, React Native, Expo and Flutter apps.
Every SDK talks to the same Hollo API with your app's public key (`app_…`),
and every conversation lands in one inbox. Sign up at [hollo.so](https://hollo.so).

| Folder          | Platform                   | Install                                                               | Guide                                                         |
| --------------- | -------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------- |
| `ios/`          | Swift (SwiftUI and UIKit)  | Swift Package Manager: `https://github.com/karimrashed017/hollo-sdks` | [iOS quickstart](https://hollo.so/docs/quickstart)            |
| `android/`      | Kotlin (Compose and Views) | JitPack: `com.github.karimrashed017.hollo-sdks:hollo`                 | [Android quickstart](https://hollo.so/docs/android)           |
| `react-native/` | React Native and Expo      | npm: `@hollo/react-native`                                            | [React Native quickstart](https://hollo.so/docs/react-native) |
| `flutter/`      | Flutter (pure Dart)        | Git dependency on this repo with `path: flutter`                      | [Flutter quickstart](https://hollo.so/docs/flutter)           |

Each SDK has the same concepts: `start(appKey)`, `present()`, `identify(...)`,
`signOut()`, `eraseUserData()`, `unreadCount`, `track(...)`, push token
hand-off and notification handling.

Releases are tagged (`0.1.0`, …). The APIs are a preview and may change before
1.0. Questions: contact@hollo.so.
