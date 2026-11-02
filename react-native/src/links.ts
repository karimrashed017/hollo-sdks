// Pure helpers, kept apart from the UI so they can be unit-tested.

/** The store page to leave a review on, per platform. */
export function reviewUrl(
  os: string,
  payload: Record<string, unknown> = {},
): string | null {
  const ios = typeof payload.appStoreId === "string" ? payload.appStoreId : "";
  const android =
    typeof payload.playStorePackage === "string"
      ? payload.playStorePackage
      : "";
  if (os === "android" && android) return `market://details?id=${android}`;
  if (os === "ios" && ios) {
    return `itms-apps://itunes.apple.com/app/id${ios}?action=write-review`;
  }
  if (ios) return `https://apps.apple.com/app/id${ios}?action=write-review`;
  if (android) {
    return `https://play.google.com/store/apps/details?id=${android}`;
  }
  return null;
}

/** What tapping a link card does: open a URL, or one of the app's screens. */
export type LinkAction =
  | { type: "url"; url: string }
  | { type: "screen"; screen: string; value: string | null };

// Never opened from a card, whatever the server sends.
const BLOCKED = /^(javascript|data|file|vbscript|blob):/i;

export function linkAction(
  payload: Record<string, unknown> = {},
): LinkAction | null {
  const url = typeof payload.url === "string" ? payload.url.trim() : "";
  if (url) return BLOCKED.test(url) ? null : { type: "url", url };
  const screen = typeof payload.screen === "string" ? payload.screen : "";
  if (!screen) return null;
  const value = typeof payload.value === "string" ? payload.value : null;
  return { type: "screen", screen, value };
}
