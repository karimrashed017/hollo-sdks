// The chat's colours: the app's own theme, Hollo's defaults, and the colours
// set in the dashboard on top. No React Native here, so it can be unit-tested.

export type HolloTheme = {
  accent: string;
  background: string;
  text: string;
  muted: string;
  bubble: string;
  title: string;
};

export const defaultTheme: HolloTheme = {
  accent: "#0B0B0C",
  background: "#FFFFFF",
  text: "#0B0B0C",
  muted: "#8A8A8E",
  bubble: "#F1F1F0",
  title: "Support",
};

/** Hollo's black and white inverted, for when the dashboard forces dark. */
export const darkTheme: HolloTheme = {
  accent: "#F5F5F4",
  background: "#0B0B0C",
  text: "#F5F5F4",
  muted: "#8E8E93",
  bubble: "#1C1C1E",
  title: "Support",
};

/** A dashboard colour for the light look, the dark look or both. */
export type HolloRemoteColor = { light?: string; dark?: string };

/**
 * Chat colours and title set in the dashboard, applied over the app's theme
 * so the look changes without an app release. Every field is optional.
 */
export type HolloRemoteTheme = {
  /** The user's bubbles, the send button and filled buttons. */
  accent?: HolloRemoteColor;
  /** Text and icons on accent surfaces. */
  onAccent?: HolloRemoteColor;
  background?: HolloRemoteColor;
  /** Bubbles from the team and the AI. */
  incoming?: HolloRemoteColor;
  incomingText?: HolloRemoteColor;
  colorScheme?: "light" | "dark" | "system";
  title?: string;
};

const COLOR_KEYS = [
  "accent",
  "onAccent",
  "background",
  "incoming",
  "incomingText",
] as const;
const HEX = /^#[0-9A-Fa-f]{6}$/;
const MAX_TITLE = 40;

function hex(value: unknown): string | undefined {
  return typeof value === "string" && HEX.test(value)
    ? value.toUpperCase()
    : undefined;
}

/** The server's theme, keeping only well-formed values. */
export function parseTheme(value: unknown): HolloRemoteTheme | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }
  const raw = value as Record<string, unknown>;
  const theme: HolloRemoteTheme = {};
  for (const key of COLOR_KEYS) {
    const pair = raw[key];
    if (typeof pair !== "object" || pair === null) continue;
    const { light, dark } = pair as Record<string, unknown>;
    const color: HolloRemoteColor = {};
    if (hex(light)) color.light = hex(light);
    if (hex(dark)) color.dark = hex(dark);
    if (color.light || color.dark) theme[key] = color;
  }
  const scheme = raw.colorScheme;
  if (scheme === "light" || scheme === "dark" || scheme === "system") {
    theme.colorScheme = scheme;
  }
  if (typeof raw.title === "string" && raw.title.trim()) {
    theme.title = raw.title.trim().slice(0, MAX_TITLE);
  }
  return theme;
}

/** Everything the chat paints with. */
export type ChatColors = HolloTheme & {
  /** Text and icons on the accent colour. */
  onAccent: string;
  /** The ring of the Hollo dot in the avatar. */
  avatarRing: string;
  /** Text in bubbles from the team and the AI. */
  incomingText: string;
  dark: boolean;
};

/**
 * The app's theme over Hollo's defaults, then the dashboard's colours over
 * both. The React Native chat has one look of its own (light by default),
 * so the dark half of a dashboard colour only applies when the dashboard
 * forces dark.
 */
export function chatColors(
  local: Partial<HolloTheme> = {},
  remote: HolloRemoteTheme = {},
): ChatColors {
  const dark = remote.colorScheme === "dark";
  const base = { ...(dark ? darkTheme : defaultTheme), ...local };
  const pick = (color?: HolloRemoteColor) =>
    dark ? color?.dark : color?.light;
  const onAccent = pick(remote.onAccent);
  return {
    accent: pick(remote.accent) ?? base.accent,
    background: pick(remote.background) ?? base.background,
    text: base.text,
    muted: base.muted,
    bubble: pick(remote.incoming) ?? base.bubble,
    title: remote.title ?? base.title,
    // Before 0.1.4 text on the accent was the app's background colour and
    // the dot's ring was white; both stay that way unless something changes.
    onAccent: onAccent ?? base.background,
    avatarRing: onAccent ?? (dark ? base.background : "#FFFFFF"),
    incomingText: pick(remote.incomingText) ?? base.text,
    dark,
  };
}
