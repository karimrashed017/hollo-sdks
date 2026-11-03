import {
  HolloClient,
  type ClientOptions,
  type HolloMessage,
  type HolloProfile,
  type HolloPushSettings,
  type HolloUser,
} from "./client";

// The SDK's state: the conversation, the unread count and whether the chat is
// open, plus polling. Plain TypeScript with a tiny subscribe API that the
// React hooks build on.

export type HolloState = {
  started: boolean;
  open: boolean;
  messages: HolloMessage[];
  unread: number;
  /** A message the user typed that's still sending. */
  sending: boolean;
  error: string | null;
  /** Who answers, from the dashboard. */
  profile: HolloProfile;
  push: HolloPushSettings;
  /** Show the "Runs on Hollo" footer. The server decides. */
  branding: boolean;
  /** This device sent Hollo a push token. */
  pushRegistered: boolean;
  /** Show the in-chat card asking to turn on notifications (F-40). */
  askPush: boolean;
};

const OPEN_POLL_MS = 3000;
const CLOSED_POLL_MS = 30000;

export class HolloStore {
  private client: HolloClient | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private listeners = new Set<() => void>();
  state: HolloState = {
    started: false,
    open: false,
    messages: [],
    unread: 0,
    sending: false,
    error: null,
    profile: {},
    push: { permissionCard: "off", notifyLine: true },
    branding: true,
    pushRegistered: false,
    askPush: false,
  };
  /** Set by Hollo.onPushPermission: asks the OS, returns the token or null. */
  pushPermission: (() => Promise<string | null>) | null = null;
  private pushToken: string | null = null;

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getState = () => this.state;

  private set(patch: Partial<HolloState>) {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((l) => l());
  }

  private get api() {
    if (!this.client) {
      throw new Error("Call Hollo.start({ appKey }) before using Hollo.");
    }
    return this.client;
  }

  start(options: ClientOptions) {
    this.client = new HolloClient(options);
    this.set({ started: true, messages: [], unread: 0, error: null });
    void this.refresh();
  }

  setOpen(open: boolean) {
    this.set({ open });
    if (open) {
      void this.api.markRead().catch(() => {});
      this.set({ unread: 0 });
    }
    void this.refresh();
  }

  /** Fetches new messages, then schedules the next poll. */
  async refresh() {
    if (!this.client) return;
    if (this.timer) clearTimeout(this.timer);
    try {
      const last = this.state.messages.at(-1)?.created_at;
      const { messages, unread, profile, push, open, branding } =
        await this.client.messages(last);
      if (open && !this.state.open) this.setOpen(true);
      if (profile) this.set({ profile });
      if (push) this.set({ push });
      if (branding !== this.state.branding) this.set({ branding });
      if (messages.length) {
        const known = new Set(this.state.messages.map((m) => m.id));
        this.set({
          messages: [
            ...this.state.messages,
            ...messages.filter((m) => !known.has(m.id)),
          ],
        });
      }
      if (this.state.open) {
        if (unread > 0) void this.client.markRead().catch(() => {});
        this.set({ unread: 0, error: null });
      } else {
        this.set({ unread, error: null });
      }
    } catch (error) {
      this.set({ error: (error as Error).message });
    }
    this.timer = setTimeout(
      () => void this.refresh(),
      this.state.open ? OPEN_POLL_MS : CLOSED_POLL_MS,
    );
  }

  async send(body: string) {
    const text = body.trim();
    if (!text) return;
    this.set({ sending: true, error: null });
    const first = !this.state.messages.some((m) => m.sender === "end_user");
    try {
      const { message } = await this.api.send(text);
      this.set({ messages: [...this.state.messages, message] });
      if (first) void this.maybeAskForPush();
    } catch (error) {
      this.set({ error: (error as Error).message });
      throw error;
    } finally {
      this.set({ sending: false });
    }
  }

  /** Reports an event; automations may open the chat in response. */
  async track(name: string) {
    const { open } = await this.api.event({ name });
    if (open && !this.state.open) this.setOpen(true);
    else void this.refresh();
  }

  setSubscriber(subscriber: boolean) {
    return this.api.event({ subscriber }).then(() => {});
  }

  /** Saves the push token, or null when the user turns notifications off. */
  async registerPush(token: string | null) {
    this.pushToken = token;
    await this.api.registerPush(token);
    this.set({ pushRegistered: !!token, askPush: false });
  }

  /** Just after the first message: the moment a reply is worth waiting for. */
  private async maybeAskForPush() {
    const { push, pushRegistered } = this.state;
    if (push.permissionCard === "off" || pushRegistered) return;
    if (!this.pushPermission) return;
    if (await this.api.getFlag("pushAsked")) return;
    this.set({ askPush: true });
  }

  /** The user answered the card. Either way it never shows again. */
  async answerPushCard(accept: boolean) {
    this.set({ askPush: false });
    await this.api.setFlag("pushAsked").catch(() => {});
    if (!accept || !this.pushPermission) return;
    const token = await this.pushPermission().catch(() => null);
    if (token) await this.registerPush(token).catch(() => {});
  }

  identify(user: HolloUser) {
    return this.api.identify(user).then(() => this.reload());
  }

  /** Signing out starts a fresh anonymous chat; history stays on the server. */
  async signOut() {
    await this.api.forgetDevice();
    await this.reload();
  }

  /** Deletes this user's support data (App Store account-deletion rules). */
  /** Reports a link card tap for the dashboard's counts. Never throws. */
  linkTapped(messageId: string, opened: boolean) {
    void this.client?.linkTapped(messageId, opened).catch(() => {});
  }

  async eraseUserData() {
    await this.api.eraseUserData();
    await this.reload();
  }

  private async reload() {
    this.set({ messages: [], unread: 0 });
    // Signing in or out makes a new device, so it needs the token again.
    if (this.pushToken) {
      await this.registerPush(this.pushToken).catch(() => {});
    }
    await this.refresh();
  }
}
