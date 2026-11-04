# Changelog

## 0.1.6

- Photo attachments: an attach button beside the composer lets users send up to 5 photos, with an optional caption. They're resized and compressed on the device through `image_picker`, which needs `NSPhotoLibraryUsageDescription` in the iOS app's `Info.plist`.
- Photos in the chat open full screen, with pinch and double-tap to zoom and swiping between a message's photos.
- `HolloMessage.photos` holds an image message's photo URLs. Older servers send none.

## 0.1.0

First version, feature-equivalent to the React Native SDK.

- `Hollo.start`, `Hollo.present` (through `Hollo.navigatorKey` or a `BuildContext`), `Hollo.dismiss` and an embeddable `HolloChat` widget.
- `Hollo.identify`, `Hollo.signOut` and `Hollo.eraseUserData`.
- `Hollo.unreadCount` as a `ValueListenable<int>`.
- Review request, offer and link cards, with `Hollo.onOffer` and `Hollo.onLink`.
- `Hollo.track` and `Hollo.setSubscriber` for automations.
- Push hand-off: `Hollo.registerPush` (FCM), `Hollo.handle` and the in-chat permission card through `Hollo.onPushPermission`.
- Black-and-white `HolloTheme` with light and dark versions.
