export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
};
export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
export async function body(request: Request): Promise<Record<string, unknown>> {
  const reader = request.body?.getReader();
  let total = 0;
  const chunks: Uint8Array[] = [];
  if (!reader) throw new Error("invalid_request");
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > 16384) throw new Error("invalid_request");
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    bytes.set(c, offset);
    offset += c.length;
  }
  let data;
  try {
    data = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Error("invalid_request");
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("invalid_request");
  return data;
}
export async function hash(value: string): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
export type RPC = (name: string, args: Record<string, unknown>) => Promise<unknown>;
export function backend(
  url: string,
  key: string,
): { rpc: RPC; user: (token: string) => Promise<string | null> } {
  const headers = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  return {
    async rpc(name, args) {
      const r = await fetch(`${url}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers,
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(10000),
      });
      if (!r.ok) throw new Error("unavailable");
      return r.json();
    },
    async user(token) {
      const r = await fetch(`${url}/auth/v1/user`, {
        headers: { apikey: key, Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(5000),
      });
      if (!r.ok) return null;
      return (await r.json()).id ?? null;
    },
  };
}
