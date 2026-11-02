# Changelog

## 0.1.0

First version, feature-equivalent to the React Native SDK.

- `Hollo.start`, `Hollo.present` (through `Hollo.navigatorKey` or a `BuildContext`), `Hollo.dismiss` and an embeddable `HolloChat` widget.
- `Hollo.identify`, `Hollo.signOut` and `Hollo.eraseUserData`.
- `Hollo.unreadCount` as a `ValueListenable<int>`.
- Review request, offer and link cards, with `Hollo.onOffer` and `Hollo.onLink`.
- `Hollo.track` and `Hollo.setSubscriber` for automations.
- Push hand-off: `Hollo.registerPush` (FCM), `Hollo.handle` and the in-chat permission card through `Hollo.onPushPermission`.
- Black-and-white `HolloTheme` with light and dark versions.
