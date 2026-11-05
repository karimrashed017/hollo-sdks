// Paywall adapters (F-31): what tapping an offer card opens. Each takes the
// tool's own module as an argument instead of importing it, so apps only
// install the one they use. The types below are just the parts we call.

/** How a paywall shown for an offer ended. Hollo tracks it as `offer_<result>`. */
export type HolloPaywallResult =
  "purchased" | "restored" | "declined" | "pending" | "failed";

/** Shows the app's paywall for an offer's ref and reports how it ended. */
export type HolloPaywall = (ref: string) => Promise<HolloPaywallResult>;

/** Runs a paywall for a ref; any error counts as failed, never a crash. */
export async function runPaywall(
  paywall: HolloPaywall,
  ref: string,
): Promise<HolloPaywallResult> {
  try {
    return await paywall(ref);
  } catch {
    return "failed";
  }
}

// --- Adapty (react-native-adapty, Paywall Builder) ---

type AdaptyHandlers = {
  onPurchaseCompleted?: (result: { type?: string }) => boolean;
  onRestoreCompleted?: () => boolean;
  onCloseButtonPress?: () => boolean;
  onAndroidSystemBack?: () => boolean;
  onRenderingFailed?: () => boolean;
  onLoadingProductsFailed?: () => boolean;
};
type AdaptyView = {
  // setEventHandlers since 3.14; registerEventHandlers before.
  setEventHandlers?: (handlers: AdaptyHandlers) => unknown;
  registerEventHandlers?: (handlers: AdaptyHandlers) => unknown;
  present: () => Promise<unknown>;
};
type AdaptyPaywallObject = { hasViewConfiguration?: boolean };

/**
 * Shows the Adapty paywall for the placement ID in the offer's ref.
 *
 *   import { adapty, createPaywallView } from "react-native-adapty";
 *   Hollo.usePaywall(adaptyPaywall({ adapty, createPaywallView }));
 */
export function adaptyPaywall(deps: {
  adapty: { getPaywall: (placementId: string) => Promise<AdaptyPaywallObject> };
  createPaywallView: (paywall: AdaptyPaywallObject) => Promise<AdaptyView>;
}): HolloPaywall {
  return async (placementId) => {
    const paywall = await deps.adapty.getPaywall(placementId);
    // Without a Paywall Builder layout there is nothing to show.
    if (paywall.hasViewConfiguration === false) return "failed";
    const view = await deps.createPaywallView(paywall);
    return new Promise<HolloPaywallResult>((resolve) => {
      // Returning true closes the paywall.
      const end = (result: HolloPaywallResult) => {
        resolve(result);
        return true;
      };
      const handlers: AdaptyHandlers = {
        onPurchaseCompleted: (result) => {
          // A cancelled purchase leaves the paywall open to try again.
          if (result?.type === "user_cancelled") return false;
          return end(result?.type === "pending" ? "pending" : "purchased");
        },
        onRestoreCompleted: () => end("restored"),
        onCloseButtonPress: () => end("declined"),
        onAndroidSystemBack: () => end("declined"),
        onRenderingFailed: () => end("failed"),
        onLoadingProductsFailed: () => end("failed"),
      };
      const set = view.setEventHandlers ?? view.registerEventHandlers;
      set?.call(view, handlers);
      view.present().catch(() => resolve("failed"));
    });
  };
}

// --- Superwall (expo-superwall/compat) ---

type SuperwallHandler = {
  onDismiss: (
    fn: (info: unknown, result: { type?: string }) => void,
  ) => unknown;
  onSkip: (fn: (reason: unknown) => void) => unknown;
  onError: (fn: (error: unknown) => void) => unknown;
};

/**
 * Registers the Superwall placement named in the offer's ref, so your
 * campaign decides which paywall shows.
 *
 *   import Superwall, { PaywallPresentationHandler } from "expo-superwall/compat";
 *   Hollo.usePaywall(superwallPaywall({ Superwall, PaywallPresentationHandler }));
 */
export function superwallPaywall(deps: {
  Superwall: {
    shared: {
      register: (args: {
        placement: string;
        handler?: SuperwallHandler;
      }) => Promise<unknown>;
    };
  };
  PaywallPresentationHandler: new () => SuperwallHandler;
}): HolloPaywall {
  return (placement) =>
    new Promise<HolloPaywallResult>((resolve) => {
      const handler = new deps.PaywallPresentationHandler();
      handler.onDismiss((_info, result) => {
        const type = result?.type;
        resolve(
          type === "purchased" || type === "restored" ? type : "declined",
        );
      });
      // Skipped: no audience matched, a holdout, or the user already pays.
      handler.onSkip(() => resolve("failed"));
      handler.onError(() => resolve("failed"));
      deps.Superwall.shared
        .register({ placement, handler })
        .catch(() => resolve("failed"));
    });
}

// --- RevenueCat (react-native-purchases + react-native-purchases-ui) ---

/**
 * Shows the RevenueCat paywall of the offering whose ID is the offer's ref.
 *
 *   import Purchases from "react-native-purchases";
 *   import RevenueCatUI from "react-native-purchases-ui";
 *   Hollo.usePaywall(revenueCatPaywall({ Purchases, RevenueCatUI }));
 */
export function revenueCatPaywall<Offering>(deps: {
  Purchases: {
    getOfferings: () => Promise<{ all: Record<string, Offering | undefined> }>;
  };
  RevenueCatUI: {
    presentPaywall: (params: {
      offering?: Offering;
      displayCloseButton?: boolean;
    }) => Promise<string>;
  };
}): HolloPaywall {
  return async (offeringId) => {
    const offering = (await deps.Purchases.getOfferings()).all[offeringId];
    // Without it RevenueCat would show the current offering, not this one.
    if (!offering) return "failed";
    const result = await deps.RevenueCatUI.presentPaywall({
      offering,
      displayCloseButton: true,
    });
    switch (result) {
      case "PURCHASED":
        return "purchased";
      case "RESTORED":
        return "restored";
      case "CANCELLED":
        return "declined";
      default:
        return "failed";
    }
  };
}
