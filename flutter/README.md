# Hollo for Flutter

In-app support chat for Flutter apps on iOS and Android. Pure Dart: the chat is built from Flutter widgets, and the package talks to `https://hollo.so/api/v1` over HTTP. Full guide: [hollo.so/docs/flutter](https://hollo.so/docs/flutter).

## Install

Until the package is on pub.dev, add it from git in `pubspec.yaml`:

```yaml
dependencies:
  hollo:
    git:
      url: https://github.com/karimrashed017/hollo-sdks.git
      path: flutter
      ref: 0.1.2
```

It uses `http`, `shared_preferences` (to keep the device token) and `url_launcher` (to open store pages and links). After adding it, stop the app and run `flutter run` again; a hot reload doesn't pick up new plugins.

## Use

```dart
import 'package:flutter/material.dart';
import 'package:hollo/hollo.dart';

Future<void> main() async {
  await Hollo.start(appKey: 'app_XXXX');
  runApp(MaterialApp(navigatorKey: Hollo.navigatorKey, home: const Home()));
}

// A Support button:
TextButton(onPressed: () => Hollo.present(), child: const Text('Support'));
```

If your app already has a navigator key, set `Hollo.navigatorKey = yourKey`, or call `Hollo.present(context: context)`. To put the chat in your own navigation instead, use the `HolloChat()` widget.

| Call                                                | What it does                                                     |
| --------------------------------------------------- | ---------------------------------------------------------------- |
| `Hollo.identify(id:, name:, email:)`                | Links the device to your user after sign-in.                     |
| `Hollo.signOut()`                                   | Starts a fresh anonymous chat.                                   |
| `Hollo.eraseUserData()`                             | Deletes the user's support data. Throws if it fails.             |
| `Hollo.unreadCount`                                 | `ValueListenable<int>` for a badge.                              |
| `Hollo.onOffer = (offer) {}`                        | The user tapped an offer card. Open your paywall.                |
| `Hollo.onLink = (link) {}`                          | The user tapped a link card for one of your screens.             |
| `Hollo.track('paywall_declined')`                   | Reports an event for automations.                                |
| `Hollo.setSubscriber(true)`                         | Whether the user pays.                                           |
| `Hollo.registerPush(token)`                         | Saves the FCM token from firebase_messaging (null turns it off). |
| `Hollo.handle(message.data)`                        | Opens the chat for a tapped Hollo notification.                  |
| `Hollo.onPushPermission = () async => token`        | Lets the chat ask for notifications after the first message.     |
| `Hollo.theme`, `Hollo.darkTheme`, `Hollo.themeMode` | Colours, title and font. Black and white by default.             |

## Develop

```bash
flutter pub get
flutter analyze
flutter test
```
