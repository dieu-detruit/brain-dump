// deno-lint-ignore-file require-await -- async boundary fakes implement fetch/RPC contracts
import { createHandler } from "./handler.ts";
const assert = (ok: boolean) => {
  if (!ok) throw new Error("assertion failed");
};
const handler = createHandler({
  rpc: async (name, args) => ({ name, args }),
  user: async (token) => token === "user-token" ? "11111111-1111-4111-8111-111111111111" : null,
});
Deno.test("device cannot approve pairings and empty bearer is rejected", async () => {
  for (const auth of ["Bearer device-token", "Bearer "]) {
    const r = await handler(
      new Request("https://x/watch-api/pairings/approve", {
        method: "POST",
        headers: { Authorization: auth },
        body: '{"code":"12345678"}',
      }),
    );
    assert(r.status === 401);
  }
});
Deno.test("bad JSON and unsupported mutation fail without database access", async () => {
  let calls = 0;
  const h = createHandler({
    rpc: async () => {
      calls++;
      return {};
    },
    user: async () => null,
  });
  for (const body of ["{", '{"action":"delete"}']) {
    const r = await h(
      new Request("https://x/watch-api/execution", {
        method: "POST",
        headers: { Authorization: "Bearer " + "a".repeat(64) },
        body,
      }),
    );
    assert(r.status === 400);
  }
  assert(calls === 0);
});
Deno.test("device token is hashed and client owner cannot select another workspace", async () => {
  const r = await handler(
    new Request("https://x/watch-api/state?user_id=attacker", {
      headers: { Authorization: "Bearer " + "a".repeat(64) },
    }),
  );
  const body = await r.json();
  assert(body.name === "watch_device_request");
  assert(body.args.token_hash !== "a".repeat(64));
  assert(body.args.owner === undefined);
});
Deno.test("rate limit and stale results keep their HTTP meanings", async () => {
  for (
    const [result, status] of [[{ error: "rate_limited" }, 429], [{ status: "stale", snapshot: {} }, 409], [{
      error: "unauthorized",
    }, 401]] as const
  ) {
    const h = createHandler({ rpc: async () => result, user: async () => null });
    const r = await h(
      new Request("https://x/watch-api/state", { headers: { Authorization: "Bearer " + "a".repeat(64) } }),
    );
    assert(r.status === status);
  }
});

Deno.test("thread operations validate payloads and never trust a client owner", async () => {
  const id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const command = {
    operation_id: id,
    action: "delegate",
    thread_id: id,
    expected: null,
    expected_thread: { title: "作業", delegation: null },
    delegation: "ai",
    owner: "attacker",
  };
  const request = (body: unknown, token = "a".repeat(64)) =>
    new Request("https://x/watch-api/thread", {
      method: "POST",
      headers: { Authorization: "Bearer " + token },
      body: JSON.stringify(body),
    });
  const r = await handler(request(command));
  assert(r.status === 200);
  const result = await r.json();
  assert(result.args.action === "thread" && result.args.args.delegation === "ai");
  assert(result.args.args.owner === undefined && result.args.token_hash !== "a".repeat(64));
  assert((await handler(request(command, ""))).status === 401);
  for (
    const invalid of [
      { ...command, delegation: "anyone" },
      { ...command, action: "delete" },
      { ...command, thread_id: "bad" },
      { ...command, expected: undefined },
      { ...command, expected_thread: { title: "作業" } },
    ]
  ) {
    assert((await handler(request(invalid))).status === 400);
  }
  assert((await handler(request({ ...command, action: "complete" }))).status === 200);
});
