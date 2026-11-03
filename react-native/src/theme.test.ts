import { describe, expect, it } from "vitest";
import { chatColors, darkTheme, defaultTheme } from "./theme";

describe("chatColors", () => {
  it("is exactly the app's theme when the dashboard sets nothing", () => {
    const local = { accent: "#FF0000", background: "#FFF8F0" };
    expect(chatColors(local, {})).toEqual({
      ...defaultTheme,
      ...local,
      onAccent: "#FFF8F0",
      avatarRing: "#FFFFFF",
      incomingText: defaultTheme.text,
      dark: false,
    });
    expect(chatColors(local, { colorScheme: "system" })).toEqual(
      chatColors(local, {}),
    );
  });

  it("puts a full dashboard theme over the app's, by look", () => {
    const remote = {
      accent: { light: "#FF5500", dark: "#FFAA77" },
      onAccent: { light: "#FFFFFF", dark: "#000000" },
      background: { light: "#FAFAFA", dark: "#101010" },
      incoming: { light: "#EEEEEE", dark: "#222222" },
      incomingText: { light: "#111111", dark: "#F0F0F0" },
      title: "Driftwood help",
    };
    const light = chatColors({ accent: "#FF0000" }, remote);
    expect(light).toMatchObject({
      accent: "#FF5500",
      onAccent: "#FFFFFF",
      avatarRing: "#FFFFFF",
      background: "#FAFAFA",
      bubble: "#EEEEEE",
      incomingText: "#111111",
      title: "Driftwood help",
      dark: false,
    });
    const dark = chatColors({}, { ...remote, colorScheme: "dark" });
    expect(dark).toMatchObject({
      accent: "#FFAA77",
      onAccent: "#000000",
      background: "#101010",
      bubble: "#222222",
      incomingText: "#F0F0F0",
      text: darkTheme.text,
      dark: true,
    });
  });

  it("keeps the app's colour for a look the dashboard left unset", () => {
    const local = { accent: "#FF0000", title: "Help" };
    const remote = { accent: { dark: "#123456" } };
    expect(chatColors(local, remote)).toEqual(chatColors(local, {}));
    const dark = chatColors(local, { ...remote, colorScheme: "dark" });
    expect(dark.accent).toBe("#123456");
    // Forced dark with nothing else set: Hollo's dark defaults under the app's.
    expect(chatColors(local, { colorScheme: "dark" })).toMatchObject({
      accent: "#FF0000",
      background: darkTheme.background,
      title: "Help",
    });
  });
});
