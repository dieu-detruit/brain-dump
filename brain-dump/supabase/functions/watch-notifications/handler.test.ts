// deno-lint-ignore-file require-await -- boundary fakes
import { createNotificationHandler } from "./handler.ts";
const assert = (x: boolean) => {
  if (!x) throw new Error("assertion failed");
};
Deno.test("Cron rejects missing secret without accessing jobs", async () => {
  let calls = 0;
  const h = createNotificationHandler({
    rpc: async () => {
      calls++;
      return [];
    },
    secret: "test",
    jwt: async () => "jwt",
    topic: "topic",
  });
  const r = await h(new Request("https://x", { method: "POST" }));
  assert(r.status === 401);
  assert(calls === 0);
});
Deno.test("stale lease never sends a push", async () => {
  let sends = 0;
  const h = createNotificationHandler({
    rpc: async (name) => name === "claim_watch_notifications" ? [{ id: "a", lease_id: "b" }] : null,
    secret: "test",
    jwt: async () => "jwt",
    topic: "topic",
    fetcher: async () => {
      sends++;
      return new Response();
    },
  });
  const r = await h(new Request("https://x", { method: "POST", headers: { Authorization: "Bearer test" } }));
  assert(r.status === 200);
  assert(sends === 0);
});
Deno.test("failure recording successful APNs delivery leaves recovery to lease expiry", async () => {
  let sends = 0;
  const job = {
    id: "a",
    lease_id: "b",
    device_id: "c",
    push_token: "ab",
    push_environment: "production",
    session_id: "1",
    confirmation_revision: "r",
    operation_id: "o",
    thread_title: "作業",
    deadline: "2030-01-01T00:00:00Z",
    collapse_id: "c",
  };
  const h = createNotificationHandler({
    rpc: async (name) => {
      if (name === "claim_watch_notifications") return [{ id: "a", lease_id: "b" }];
      if (name === "check_watch_notification") return job;
      throw new Error("DB unavailable");
    },
    secret: "test",
    jwt: async () => "jwt",
    topic: "topic",
    fetcher: async () => {
      sends++;
      return new Response(null, { status: 200 });
    },
  });
  const r = await h(new Request("https://x", { method: "POST", headers: { Authorization: "Bearer test" } }));
  assert(r.status === 503);
  assert(sends === 1);
});
