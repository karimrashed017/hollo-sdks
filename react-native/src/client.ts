// The Hollo HTTP client: no React, no React Native, so it can be unit-tested.
// Talks to the SDK API at https://hollo.so/api/v1 with the app key and this
// install's device token.

import { parseTheme } from "./theme";

export type Sender = "end_user" | "team" | "ai" | "system";

export type HolloMessage = {
  id: string;
  sender: Sender;
  kind: string;
  body: string;
  /** Card details for review_request and offer messages. */
  payload?: Record<string, unknown>;
  /** Links to the photos of an image message, in order (F-17). */
  photos?: string[];
  created_at: string;
};

/** Photos per message, as the server allows. */
export const MAX_PHOTOS = 5;

/** An offer card the user tapped; ref is the ID you set in the dashboard. */
export type HolloOffer = { ref: string; title: string };

/**
 * A link card that opens one of your app's screens. screen is the name you
 * gave it in the dashboard, value its optional value (an order number, say).
 */
export type HolloLink = { screen: string; value: string | null };

/**
 * Who answers, set on the app's page in the dashboard: a name, a short role,
 * a photo URL and the welcome line. Every field is optional.
 */
export type HolloProfile = {
  name?: string;
  role?: string;
  photo?: string;
  welcome?: string;
};

/** Push options from the dashboard. */
export type HolloPushSettings = {
  permissionCard: "off" | "replies" | "replies_offers";
  notifyLine: boolean;
};

/** The app's own user. `identityToken` comes from the developer's server. */
export type HolloUser = {
  id: string;
  name?: string;
  email?: string;
  identityToken?: string;
};

export type Storage = {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
};

export type ClientOptions = {
  appKey: string;
  apiUrl?: string;
  storage: Storage;
  platform: "ios" | "android" | "web";
  info?: Record<string, string>;
  fetch?: typeof fetch;
};

export class HolloError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "HolloError";
  }
}

const TOKEN_KEY = "hollo.deviceToken";

export class HolloClient {
  private readonly apiUrl: string;
  private readonly fetch: typeof fetch;
  private token: Promise<string> | null = null;

  constructor(private readonly options: ClientOptions) {
    this.apiUrl = (options.apiUrl ?? "https://hollo.so/api/v1").replace(
      /\/$/,
      "",
    );
    this.fetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  }

  /** The device token, registering this install the first time. */
  private deviceToken(): Promise<string> {
    this.token ??= (async () => {
      const saved = await this.options.storage.getItem(this.key());
      if (saved) return saved;
      const { deviceToken } = await this.call<{ deviceToken: string }>(
        "/devices",
        {
          method: "POST",
          body: {
            platform: this.options.platform,
            info: this.options.info ?? {},
          },
          auth: false,
        },
      );
      await this.options.storage.setItem(this.key(), deviceToken);
      return deviceToken;
    })().catch((error) => {
      // Let the next call try again.
      this.token = null;
      throw error;
    });
    return this.token;
  }

  private key() {
    return `${TOKEN_KEY}.${this.options.appKey}`;
  }

  private async call<T>(
    path: string,
    init: {
      method?: string;
      body?: unknown;
      /** Sent as is (a photo), instead of a JSON body. */
      raw?: { data: Blob | ArrayBuffer | Uint8Array; type: string };
      auth?: boolean;
    } = {},
    retried = false,
  ): Promise<T> {
    const headers: Record<string, string> = {
      "x-hollo-app-key": this.options.appKey,
    };
    if (init.body !== undefined) headers["content-type"] = "application/json";
    if (init.raw) headers["content-type"] = init.raw.type;
    if (init.auth !== false) {
      headers.authorization = `Bearer ${await this.deviceToken()}`;
    }

    const response = await this.fetch(`${this.apiUrl}${path}`, {
      method: init.method ?? "GET",
      headers,
      body: init.raw
        ? (init.raw.data as BodyInit)
        : init.body === undefined
          ? undefined
          : JSON.stringify(init.body),
    });
    const data = (await response.json().catch(() => ({}))) as {
      error?: { code: string; message: string };
    };

    if (!response.ok) {
      const code = data.error?.code ?? "network_error";
      // The server forgot this device (e.g. data was erased): register again.
      if (code === "invalid_device" && !retried && init.auth !== false) {
        await this.forgetDevice();
        return this.call<T>(path, init, true);
      }
      throw new HolloError(
        code,
        data.error?.message ?? `Request failed (${response.status})`,
        response.status,
      );
    }
    return data as T;
  }

  async forgetDevice() {
    this.token = null;
    await this.options.storage.removeItem(this.key());
  }

  async identify(user: HolloUser) {
    const { identityToken, ...details } = user;
    const data = await this.call<{ userId: string; verified?: boolean }>(
      "/identify",
      {
        method: "POST",
        body: identityToken ? { ...details, token: identityToken } : details,
      },
    );
    // Older servers don't send `verified`; that means not verified.
    return { userId: data.userId, verified: data.verified === true };
  }

  async messages(after?: string) {
    const query = after ? `?after=${encodeURIComponent(after)}` : "";
    const data = await this.call<{
      messages: HolloMessage[];
      unread: number;
      profile?: HolloProfile;
      push?: HolloPushSettings;
      /** An automation asked to open the chat. */
      open?: boolean;
      branding?: boolean;
      /** Dashboard colours and title; servers before 0.1.4 leave it out. */
      theme?: unknown;
    }>(`/messages${query}`);
    // Show "Runs on Hollo" unless the server says not to.
    return {
      ...data,
      branding: data.branding !== false,
      theme: parseTheme(data.theme),
    };
  }

  /** Sends a message; `photos` are paths from uploadPhoto, up to five. */
  send(body: string, photos: string[] = []) {
    return this.call<{ message: HolloMessage }>("/messages", {
      method: "POST",
      body: photos.length ? { body, photos } : { body },
    });
  }

  /** Uploads one JPEG (compressed on the device) and returns its path. */
  async uploadPhoto(jpeg: Blob | ArrayBuffer | Uint8Array) {
    const { photo } = await this.call<{ photo: { path: string } }>("/photos", {
      method: "POST",
      raw: { data: jpeg, type: "image/jpeg" },
    });
    return photo.path;
  }

  /** Counts a link card tap; opened is false when nothing could open it. */
  linkTapped(messageId: string, opened: boolean) {
    return this.call<{ ok: true }>("/links/tap", {
      method: "POST",
      body: { messageId, opened },
    });
  }

  /** Reports an event (Hollo.track) or the subscription status. */
  event(body: { name?: string; subscriber?: boolean }) {
    return this.call<{ open: boolean }>("/events", { method: "POST", body });
  }

  /** Saves the Expo push token, or null to stop notifications. */
  registerPush(token: string | null) {
    return this.call<{ ok: true }>("/push", {
      method: "POST",
      body: { token },
    });
  }

  /** Small flags kept beside the device token, like "asked for push". */
  getFlag(name: string) {
    return this.options.storage.getItem(`hollo.${name}.${this.options.appKey}`);
  }

  setFlag(name: string) {
    return this.options.storage.setItem(
      `hollo.${name}.${this.options.appKey}`,
      "1",
    );
  }

  markRead() {
    return this.call<{ unread: number }>("/read", { method: "POST" });
  }

  async eraseUserData() {
    await this.call("/user", { method: "DELETE" });
    await this.forgetDevice();
  }
}
