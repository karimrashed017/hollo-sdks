import { describe, expect, it, vi } from "vitest";
import {
  adaptyPaywall,
  revenueCatPaywall,
  runPaywall,
  superwallPaywall,
} from "./paywalls";

// The adapters get fakes shaped like each tool's SDK, so these check what we
// call and how each ending maps to a result, without the real SDKs.

describe("runPaywall", () => {
  it("turns an error into failed instead of crashing", async () => {
    expect(
      await runPaywall(() => Promise.reject(new Error("no network")), "x"),
    ).toBe("failed");
  });
});

describe("Adapty", () => {
  type Handlers = Record<string, (arg?: { type?: string }) => boolean>;
  const setup = (opts: { builder?: boolean; legacy?: boolean } = {}) => {
    let handlers: Handlers = {};
    const view = {
      present: vi.fn(() => Promise.resolve()),
      [opts.legacy ? "registerEventHandlers" : "setEventHandlers"]: (
        h: Handlers,
      ) => {
        handlers = h;
      },
    };
    const getPaywall = vi.fn(() =>
      Promise.resolve({ hasViewConfiguration: opts.builder ?? true }),
    );
    const paywall = adaptyPaywall({
      adapty: { getPaywall },
      createPaywallView: () => Promise.resolve(view),
    });
    return { paywall, getPaywall, view, handlers: () => handlers };
  };

  it("shows the placement's paywall and reports a purchase", async () => {
    const { paywall, getPaywall, view, handlers } = setup();
    const result = paywall("winback");
    await vi.waitFor(() => expect(view.present).toHaveBeenCalled());
    expect(getPaywall).toHaveBeenCalledWith("winback");
    // A cancelled purchase keeps the paywall open.
    expect(handlers().onPurchaseCompleted({ type: "user_cancelled" })).toBe(
      false,
    );
    expect(handlers().onPurchaseCompleted({ type: "success" })).toBe(true);
    expect(await result).toBe("purchased");
  });

  it("reports closing, restoring and the older handler API", async () => {
    const closed = setup({ legacy: true });
    const r1 = closed.paywall("p");
    await vi.waitFor(() => expect(closed.view.present).toHaveBeenCalled());
    closed.handlers().onCloseButtonPress();
    expect(await r1).toBe("declined");

    const restored = setup();
    const r2 = restored.paywall("p");
    await vi.waitFor(() => expect(restored.view.present).toHaveBeenCalled());
    restored.handlers().onRestoreCompleted();
    expect(await r2).toBe("restored");
  });

  it("fails when the paywall has no builder layout", async () => {
    expect(await setup({ builder: false }).paywall("p")).toBe("failed");
  });
});

describe("Superwall", () => {
  const setup = (register = vi.fn(() => Promise.resolve())) => {
    const fns: Record<string, (...args: unknown[]) => void> = {};
    class PaywallPresentationHandler {
      onDismiss(fn: (...args: unknown[]) => void) {
        fns.dismiss = fn;
      }
      onSkip(fn: (...args: unknown[]) => void) {
        fns.skip = fn;
      }
      onError(fn: (...args: unknown[]) => void) {
        fns.error = fn;
      }
    }
    const paywall = superwallPaywall({
      Superwall: { shared: { register } },
      PaywallPresentationHandler,
    });
    return { paywall, register, fns };
  };

  it("registers the placement and maps how it was dismissed", async () => {
    const { paywall, register, fns } = setup();
    const bought = paywall("offer_winback");
    expect(register).toHaveBeenCalledWith(
      expect.objectContaining({ placement: "offer_winback" }),
    );
    fns.dismiss({}, { type: "purchased", productId: "pro" });
    expect(await bought).toBe("purchased");

    const declined = paywall("p");
    fns.dismiss({}, { type: "declined" });
    expect(await declined).toBe("declined");
  });

  it("fails when skipped or on an error", async () => {
    const { paywall, fns } = setup();
    const skipped = paywall("p");
    fns.skip("holdout");
    expect(await skipped).toBe("failed");
    const rejected = setup(vi.fn(() => Promise.reject(new Error("x"))));
    expect(await rejected.paywall("p")).toBe("failed");
  });
});

describe("RevenueCat", () => {
  const setup = (result: string, offerings = { all: { winback: {} } }) => {
    const presentPaywall = vi.fn(() => Promise.resolve(result));
    const paywall = revenueCatPaywall({
      Purchases: { getOfferings: () => Promise.resolve(offerings) },
      RevenueCatUI: { presentPaywall },
    });
    return { paywall, presentPaywall };
  };

  it("shows the offering's paywall and maps the result", async () => {
    const { paywall, presentPaywall } = setup("PURCHASED");
    expect(await paywall("winback")).toBe("purchased");
    expect(presentPaywall).toHaveBeenCalledWith({
      offering: {},
      displayCloseButton: true,
    });
    expect(await setup("RESTORED").paywall("winback")).toBe("restored");
    expect(await setup("CANCELLED").paywall("winback")).toBe("declined");
    expect(await setup("ERROR").paywall("winback")).toBe("failed");
  });

  it("fails for an offering that doesn't exist", async () => {
    const { paywall, presentPaywall } = setup("PURCHASED");
    expect(await paywall("missing")).toBe("failed");
    expect(presentPaywall).not.toHaveBeenCalled();
  });
});
