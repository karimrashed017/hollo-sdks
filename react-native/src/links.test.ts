import { describe, expect, it } from "vitest";
import { linkAction, reviewUrl } from "./links";

const both = { appStoreId: "123456789", playStorePackage: "com.example.app" };

describe("reviewUrl", () => {
  it("opens the App Store review sheet on iPhone", () => {
    expect(reviewUrl("ios", both)).toBe(
      "itms-apps://itunes.apple.com/app/id123456789?action=write-review",
    );
  });

  it("opens Google Play on Android", () => {
    expect(reviewUrl("android", both)).toBe(
      "market://details?id=com.example.app",
    );
  });

  it("falls back to a web link when the platform's store isn't set", () => {
    expect(reviewUrl("android", { appStoreId: "123456789" })).toBe(
      "https://apps.apple.com/app/id123456789?action=write-review",
    );
    expect(reviewUrl("web", { playStorePackage: "com.example.app" })).toBe(
      "https://play.google.com/store/apps/details?id=com.example.app",
    );
  });

  it("returns null with no store IDs", () => {
    expect(reviewUrl("ios", {})).toBeNull();
  });
});

describe("linkAction", () => {
  it("opens a URL", () => {
    expect(linkAction({ url: "https://example.com" })).toEqual({
      type: "url",
      url: "https://example.com",
    });
  });

  it("opens a screen with its value", () => {
    expect(linkAction({ url: null, screen: "order", value: "123" })).toEqual({
      type: "screen",
      screen: "order",
      value: "123",
    });
  });

  it("refuses scripts and empty cards", () => {
    expect(linkAction({ url: "javascript:alert(1)" })).toBeNull();
    expect(linkAction({})).toBeNull();
  });
});
