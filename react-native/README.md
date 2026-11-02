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
```

You need a Hollo workspace and an app key: sign up at [hollo.so](https://hollo.so).
Full guide: [hollo.so/docs/react-native](https://hollo.so/docs/react-native).
