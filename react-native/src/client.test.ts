import { describe, expect, it } from "vitest";
import { HolloClient, HolloError, type Storage } from "./client";

function memoryStorage(): Storage & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    getItem: async (k) => data.get(k) ?? null,
    setItem: async (k, v) => void data.set(k, v),
    removeItem: async (k) => void data.delete(k),
  };
}

type Call = { url: string; init: RequestInit };

/** A fake SDK API that answers by path. */
function fakeServer(routes: Record<string, (call: Call) => [number, unknown]>) {
  const calls: Call[] = [];
  const fetch = (async (url: string, init: RequestInit) => {
    const call = { url, init };
    calls.push(call);
    const path = new URL(url).pathname.replace("/api/v1", "");
    const [status, body] = routes[`${init.method} ${path}`](call);
    return new Response(JSON.stringify(body), { status });
  }) as unknown as typeof globalThis.fetch;
  return { fetch, calls };
}

const APP_KEY = `app_${"a".repeat(32)}`;

function client(storage: Storage, fetch: typeof globalThis.fetch) {
  return new HolloClient({
    appKey: APP_KEY,
    storage,
    platform: "ios",
    fetch,
  });
}

const header = (call: Call, name: string) =>
  (call.init.headers as Record<string, string>)[name];

describe("HolloClient", () => {
  it("registers once, then sends the device token on every call", async () => {
    let registrations = 0;
    const server = fakeServer({
      "POST /devices": () => {
        registrations++;
        return [201, { deviceToken: "hdt_first_token_value_1234" }];
      },
      "GET /messages": () => [200, { messages: [], unread: 0 }],
    });
    const storage = memoryStorage();
    const api = client(storage, server.fetch);

    await api.messages();
    await api.messages();

    expect(registrations).toBe(1);
    const last = server.calls.at(-1)!;
    expect(header(last, "x-hollo-app-key")).toBe(APP_KEY);
    expect(header(last, "authorization")).toBe(
      "Bearer hdt_first_token_value_1234",
    );
  });

  it("reuses a token saved by an earlier launch", async () => {
    const storage = memoryStorage();
    await storage.setItem(`hollo.deviceToken.${APP_KEY}`, "hdt_saved");
    const server = fakeServer({
      "GET /messages": () => [200, { messages: [], unread: 2 }],
    });
    const { unread } = await client(storage, server.fetch).messages();
    expect(unread).toBe(2);
    expect(header(server.calls[0], "authorization")).toBe("Bearer hdt_saved");
  });

  it("registers again when the server has forgotten the device", async () => {
    const storage = memoryStorage();
    await storage.setItem(`hollo.deviceToken.${APP_KEY}`, "hdt_old");
    const server = fakeServer({
      "GET /messages": (call) =>
        header(call, "authorization") === "Bearer hdt_old"
          ? [401, { error: { code: "invalid_device", message: "Unknown" } }]
          : [200, { messages: [], unread: 0 }],
      "POST /devices": () => [201, { deviceToken: "hdt_new" }],
    });
    await client(storage, server.fetch).messages();
    expect(storage.data.get(`hollo.deviceToken.${APP_KEY}`)).toBe("hdt_new");
  });

  it("surfaces a missing plan as a clear error", async () => {
    const server = fakeServer({
      "POST /devices": () => [
        402,
        { error: { code: "plan_required", message: "No plan" } },
      ],
    });
    await expect(
      client(memoryStorage(), server.fetch).messages(),
    ).rejects.toMatchObject(
      new HolloError("plan_required", "No plan", 402) as object,
    );
  });
});
