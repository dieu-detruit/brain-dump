export interface NotificationJob {
  id: string;
  lease_id: string;
  device_id: string;
  push_token: string;
  push_environment: string;
  session_id: string;
  confirmation_revision: string;
  operation_id: string;
  thread_title: string;
  deadline: string;
  collapse_id: string;
}
const b64 = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
export function importAPNsKey(pem: string): Promise<CryptoKey> {
  const raw = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  return crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}
export async function signAPNs(
  key: CryptoKey,
  team: string,
  keyID: string,
  now = Math.floor(Date.now() / 1000),
): Promise<string> {
  const enc = new TextEncoder();
  const input = b64(enc.encode(JSON.stringify({ alg: "ES256", kid: keyID }))) + "." +
    b64(enc.encode(JSON.stringify({ iss: team, iat: now })));
  return input + "." +
    b64(new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(input))));
}
export function buildPayload(job: NotificationJob) {
  return {
    aps: {
      alert: { title: "まだやっている？", body: Array.from(job.thread_title).slice(0, 200).join("") },
      sound: "default",
      category: "EXECUTION_CHECK_IN",
    },
    session_id: job.session_id,
    confirmation_revision: job.confirmation_revision,
    operation_id: job.operation_id,
    deadline: job.deadline,
  };
}
export async function sendAPNs(
  job: NotificationJob,
  fetcher: typeof fetch,
  jwt: string,
  topic: string,
): Promise<"sent" | "retry" | "invalid_token" | "configuration_error"> {
  try {
    const host = job.push_environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    const response = await fetcher(`https://${host}/3/device/${job.push_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.parse(job.deadline) / 1000)),
        "apns-collapse-id": job.collapse_id,
      },
      body: JSON.stringify(buildPayload(job)),
      signal: AbortSignal.timeout(8000),
    });
    if (response.ok) return "sent";
    let reason = "";
    try {
      reason = (await response.json()).reason ?? "";
    } catch { /* retain status classification */ }
    if (response.status === 410 || reason === "BadDeviceToken") return "invalid_token";
    if (response.status === 429 || response.status >= 500) return "retry";
    return "configuration_error";
  } catch {
    return "retry";
  }
}
