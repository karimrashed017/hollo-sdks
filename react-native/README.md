# Hollo for React Native and Expo

In-app support chat with an AI that answers from your docs, a shared inbox,
and review, offer and link cards. Works in Expo Go; no native code.

```bash
npx expo install @hollo-so/react-native @react-native-async-storage/async-storage
```

```tsx
import { Hollo } from "@hollo-so/react-native";

Hollo.start({ appKey: "app_XXXX" });
// Later, from a Support button:
Hollo.present();
// After sign-in:
Hollo.identify({ id: user.id, email: user.email });
```

To let users attach up to 5 photos to a message (screenshots of an error,
say), also install the two Expo modules the photo picker uses. Photos are
compressed on the device, and Hollo's AI reads them. Without these the
chat simply has no attach button.

```bash
npx expo install expo-image-picker expo-image-manipulator
```

Pass an identity token signed by your server to mark the user as verified.
Hollo's AI only runs account actions for verified users.

```tsx
Hollo.identify({ id: user.id, identityToken: tokenFromYourServer });
```

Colours, the look (light or dark) and the title set on the app's page in
the dashboard go over the `theme` you pass to `Hollo.start`, so they change
without an app release. Anything the dashboard leaves unset keeps your own
theme. The chat has one look of its own, so a colour's dark half only shows
when the dashboard forces dark.

You need a Hollo workspace and an app key: sign up at [hollo.so](https://hollo.so).
Full guide: [hollo.so/docs/react-native](https://hollo.so/docs/react-native).
