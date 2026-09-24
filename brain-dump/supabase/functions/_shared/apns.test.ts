// deno-lint-ignore-file require-await -- async boundary fakes implement fetch/RPC contracts
import { buildPayload, sendAPNs, signAPNs } from "./apns.ts";
const assert = (x: boolean) => {
  if (!x) throw new Error("assertion failed");
};
const job = {
  id: "a",
  lease_id: "b",
  device_id: "c",
  push_token: "ab",
  push_environment: "production",
  session_id: "9007199254740993",
  confirmation_revision: "r",
  operation_id: "o",
  thread_title: "日本語",
  deadline: "2026-09-24T01:00:00Z",
  collapse_id: "c".repeat(64),
};
Deno.test("notification preserves immutable target and bounded expiration", async () => {
  const payload = buildPayload(job);
  assert(payload.session_id === "9007199254740993");
  assert(payload.aps.category === "EXECUTION_CHECK_IN");
  let deadline = "";
  const r = await sendAPNs(
    job,
    async (_url, options) => {
      deadline = new Headers(options?.headers).get("apns-expiration") ?? "";
      return new Response(null, { status: 200 });
    },
    "jwt",
    "dev.brain.watch",
  );
  assert(r === "sent");
  assert(deadline === "1790211600");
});
Deno.test("delivery failures distinguish invalid tokens, retries and configuration", async () => {
  for (
    const [status, reason, want] of [
      [410, "Unregistered", "invalid_token"],
      [400, "BadDeviceToken", "invalid_token"],
      [429, "TooManyRequests", "retry"],
      [503, "ServiceUnavailable", "retry"],
      [403, "InvalidProviderToken", "configuration_error"],
    ] as const
  ) {
    assert(
      await sendAPNs(
        job,
        async () => new Response(JSON.stringify({ reason }), { status }),
        "jwt",
        "topic",
      ) === want,
    );
  }
});
Deno.test("provider JWT signature verifies and contains team/key/iat", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  const jwt = await signAPNs(pair.privateKey, "team", "key", 123);
  const [head, body, sig] = jwt.split(".");
  const decode = (s: string) =>
    Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  assert(JSON.parse(new TextDecoder().decode(decode(head))).kid === "key");
  assert(JSON.parse(new TextDecoder().decode(decode(body))).iat === 123);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pair.publicKey,
      decode(sig),
      new TextEncoder().encode(head + "." + body),
    ),
  );
});
