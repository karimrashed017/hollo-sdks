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

Pass an identity token signed by your server to mark the user as verified.
Hollo's AI only runs account actions for verified users.

```tsx
Hollo.identify({ id: user.id, identityToken: tokenFromYourServer });
```

You need a Hollo workspace and an app key: sign up at [hollo.so](https://hollo.so).
Full guide: [hollo.so/docs/react-native](https://hollo.so/docs/react-native).
