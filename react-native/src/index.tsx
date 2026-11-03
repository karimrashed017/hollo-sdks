import AsyncStorage from "@react-native-async-storage/async-storage";
import { createElement, Fragment, type ReactNode } from "react";
import { Linking, Platform } from "react-native";
import type {
  HolloLink,
  HolloMessage,
  HolloOffer,
  HolloUser,
  Storage,
} from "./client";
import { linkAction } from "./links";
import { HolloStore } from "./store";
import {
  HolloChat as Chat,
  HolloSheet,
  defaultTheme,
  useStore,
  type HolloTheme,
} from "./ui";

export {
  HolloError,
  type HolloLink,
  type HolloMessage,
  type HolloOffer,
  type HolloProfile,
  type HolloPushSettings,
  type HolloUser,
} from "./client";
export type { HolloTheme };

// Public API: Hollo.start, present, identify, signOut, eraseUserData, the
// <HolloProvider> that hosts the chat sheet, an embeddable <HolloChat />, and
// useHolloUnreadCount().

const store = new HolloStore();
let theme: HolloTheme = defaultTheme;
let offerHandler: ((offer: HolloOffer) => void) | undefined;
// Read at tap time, so onOffer can be set before or after the provider mounts.
const onOffer = (offer: HolloOffer) => {
  store.setOpen(false);
  offerHandler?.(offer);
};
let linkHandler: ((link: HolloLink) => void) | undefined;
// Links open a URL themselves; screens go to the app's Hollo.onLink handler.
const onLink = (message: HolloMessage) => {
  const action = linkAction(message.payload);
  if (action?.type === "url") {
    Linking.openURL(action.url).then(
      () => store.linkTapped(message.id, true),
      () => store.linkTapped(message.id, false),
    );
  } else if (action?.type === "screen" && linkHandler) {
    store.setOpen(false);
    linkHandler({ screen: action.screen, value: action.value });
    store.linkTapped(message.id, true);
  } else {
    store.linkTapped(message.id, false);
  }
};

/** AsyncStorage keeps the device token across launches (localStorage on web). */
const defaultStorage = (): Storage => AsyncStorage as Storage;

export const Hollo = {
  /** Call once when the app starts. */
  start(options: {
    appKey: string;
    /** Only for testing against a local server. */
    apiUrl?: string;
    storage?: Storage;
    theme?: Partial<HolloTheme>;
  }) {
    theme = { ...defaultTheme, ...options.theme };
    store.start({
      appKey: options.appKey,
      apiUrl: options.apiUrl,
      storage: options.storage ?? defaultStorage(),
      platform:
        Platform.OS === "ios" || Platform.OS === "android"
          ? Platform.OS
          : "web",
      info: {
        os: `${Platform.OS} ${String(Platform.Version ?? "")}`.trim(),
        // Review requests and other team messages use it to pick wording.
        language: Intl.DateTimeFormat().resolvedOptions().locale,
        sdk: "react-native 0.1.0",
      },
    });
  },
  /** Opens the support chat as a sheet. Needs <HolloProvider> in the tree. */
  present() {
    store.setOpen(true);
  },
  dismiss() {
    store.setOpen(false);
  },
  /**
   * Links this device to your app's user, so history follows them. Pass
   * `identityToken` (an HMAC-SHA256 of `id`, made by your server with the
   * app's identity secret) to mark the user as verified.
   */
  identify(user: HolloUser) {
    return store.identify(user);
  },
  signOut() {
    return store.signOut();
  },
  /**
   * Runs when the user taps an offer the team sent. Open your paywall or
   * apply the discount for offer.ref here.
   */
  onOffer(handler: (offer: HolloOffer) => void) {
    offerHandler = handler;
  },
  /**
   * Runs when the user taps a link card that opens one of your screens.
   * Navigate to link.screen here (with link.value, if it has one).
   */
  onLink(handler: (link: HolloLink) => void) {
    linkHandler = handler;
  },
  /**
   * Reports something the user did, like "paywall_declined" or
   * "checkout_cancelled". Automations set up in the dashboard can reply,
   * send an offer or open the chat right away.
   */
  track(event: string) {
    return store.track(event);
  },
  /** Tells Hollo whether the user pays, for automation audiences and the AI. */
  setSubscriber(isSubscriber: boolean) {
    return store.setSubscriber(isSubscriber);
  },
  /**
   * Saves the device's Expo push token, so replies reach the user when the
   * chat is closed. Call it at every launch once the user has allowed
   * notifications; pass null if they turn them off.
   */
  registerPush(expoPushToken: string | null) {
    return store.registerPush(expoPushToken);
  },
  /**
   * Pass a notification's data when the user taps it. Returns true and opens
   * the chat if it was Hollo's, so your own notifications still reach you.
   */
  handleNotification(data: unknown) {
    const ours =
      typeof data === "object" &&
      data !== null &&
      (data as { hollo?: unknown }).hollo === true;
    if (ours) store.setOpen(true);
    return ours;
  },
  /**
   * Lets the chat ask for notifications after the user's first message, if
   * the permission card is on in the dashboard. Ask the OS for permission
   * here and return the Expo push token, or null if they said no.
   */
  onPushPermission(handler: () => Promise<string | null>) {
    store.pushPermission = handler;
  },
  /** Deletes the user's support data, for account-deletion flows. */
  eraseUserData() {
    return store.eraseUserData();
  },
};

/** Wrap your app once so Hollo.present() can show the chat. */
export function HolloProvider({ children }: { children: ReactNode }) {
  return createElement(
    Fragment,
    null,
    children,
    createElement(HolloSheet, { store, theme, onOffer, onLink }),
  );
}

/** The chat as a screen you place in your own navigation. */
export function HolloChat() {
  return createElement(Chat, { store, theme, onOffer, onLink });
}

/** Live count of replies the user hasn't read, for your Support badge. */
export function useHolloUnreadCount() {
  return useStore(store).unread;
}
