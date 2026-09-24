import { parseMutation, uuid } from "../_shared/contracts.ts";
import { body, hash, json, type RPC } from "../_shared/http.ts";
const hex = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
export function createHandler(deps: { rpc: RPC; user: (token: string) => Promise<string | null> }) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return json({});
    const path = new URL(request.url).pathname.split("/watch-api").pop()!;
    const bearer = /^Bearer (\S+)$/i.exec(request.headers.get("Authorization") ?? "")?.[1];
    try {
      let result: unknown;
      if (request.method === "POST" && path === "/pairings") {
        const b = await body(request);
        if (!hex(b.pairing_secret) || !hex(b.device_token_hash)) {
          return json({ error: "invalid_request" }, 400);
        }
        const secret_hash = await hash(b.pairing_secret);
        for (let i = 0; i < 3; i++) {
          // Rejection sampling avoids modulo bias in the displayed eight-digit code.
          let n: number;
          do {
            n = crypto.getRandomValues(new Uint32Array(1))[0];
          } while (n >= 4200000000);
          result = await deps.rpc("watch_manage", {
            action: "start",
            args: {
              secret_hash,
              token_hash: b.device_token_hash,
              code: String(n % 100000000).padStart(8, "0"),
            },
          });
          if ((result as { error?: string }).error !== "code_collision") break;
        }
      } else if (request.method === "POST" && path === "/pairings/status") {
        const b = await body(request);
        if (!uuid(b.pairing_id) || !hex(b.pairing_secret)) return json({ error: "invalid_request" }, 400);
        result = await deps.rpc("watch_manage", {
          action: "status",
          args: { pairing_id: b.pairing_id, secret_hash: await hash(b.pairing_secret) },
        });
      } else if (path === "/pairings/approve" || path === "/devices" || path.startsWith("/devices/")) {
        if (!bearer) return json({ error: "unauthorized" }, 401);
        const owner = await deps.user(bearer);
        if (!owner) return json({ error: "unauthorized" }, 401);
        if (request.method === "POST" && path === "/pairings/approve") {
          const b = await body(request);
          if (typeof b.code !== "string" || !/^\d{8}$/.test(b.code)) {
            return json({ error: "invalid_request" }, 400);
          }
          result = await deps.rpc("watch_manage", { action: "approve", args: { code: b.code }, owner });
        } else if (request.method === "GET" && path === "/devices") {
          result = await deps.rpc("watch_manage", { action: "devices", args: {}, owner });
        } else if (request.method === "DELETE" && uuid(path.slice("/devices/".length))) {
          result = await deps.rpc("watch_manage", {
            action: "revoke",
            args: { device_id: path.slice("/devices/".length) },
            owner,
          });
        } else return json({ error: "invalid_request" }, 400);
      } else if (["GET /state", "POST /execution", "PUT /push-token"].includes(`${request.method} ${path}`)) {
        if (!hex(bearer)) return json({ error: "unauthorized" }, 401);
        let args: Record<string, unknown> = {};
        if (path === "/execution") args = parseMutation(await body(request));
        if (path === "/push-token") {
          const b = await body(request);
          if (
            typeof b.token !== "string" || !/^([0-9a-f]{2}){1,256}$/.test(b.token) ||
            !["sandbox", "production"].includes(String(b.environment))
          ) return json({ error: "invalid_request" }, 400);
          args = { token: b.token, environment: b.environment };
        }
        result = await deps.rpc("watch_device_request", {
          token_hash: await hash(bearer),
          action: path.slice(1),
          args,
        });
      } else return json({ error: "not_found" }, 404);
      const r = result as { error?: string; status?: string };
      return json(
        result,
        r.error === "unauthorized"
          ? 401
          : r.error === "rate_limited"
          ? 429
          : r.error
          ? 400
          : r.status === "stale" || r.status === "expired"
          ? 409
          : 200,
      );
    } catch (e) {
      return json({
        error: e instanceof Error && e.message === "invalid_request" ? "invalid_request" : "unavailable",
      }, e instanceof Error && e.message === "invalid_request" ? 400 : 503);
    }
  };
}
