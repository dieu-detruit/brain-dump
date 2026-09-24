import { hash, json, type RPC } from "../_shared/http.ts";
import { type NotificationJob, sendAPNs } from "../_shared/apns.ts";
export function createNotificationHandler(
  deps: { rpc: RPC; secret: string; jwt: () => Promise<string>; topic: string; fetcher?: typeof fetch },
) {
  return async (request: Request) => {
    if (request.method !== "POST") return json({ error: "invalid_request" }, 405);
    // Hash comparisons avoid leaking the secret length/prefix through string comparison.
    if (
      !deps.secret ||
      await hash(request.headers.get("Authorization") ?? "") !== await hash(`Bearer ${deps.secret}`)
    ) return json({ error: "unauthorized" }, 401);
    try {
      const jwt = await deps.jwt();
      // Ten jobs concurrently keep the work comfortably inside the 30-second leases.
      const jobs = await deps.rpc("claim_watch_notifications", { batch_size: 10 }) as {
        id: string;
        lease_id: string;
      }[];
      const outcomes = await Promise.all(jobs.map(async (leased) => {
        const job = await deps.rpc("check_watch_notification", {
          job_id: leased.id,
          lease: leased.lease_id,
        }) as NotificationJob | null;
        if (!job) {
          await deps.rpc("finish_watch_notification", {
            job_id: leased.id,
            lease: leased.lease_id,
            outcome: "invalid_token",
          });
          return "cancelled";
        }
        const outcome = await sendAPNs(job, deps.fetcher ?? fetch, jwt, deps.topic);
        await deps.rpc("finish_watch_notification", { job_id: job.id, lease: job.lease_id, outcome });
        if (outcome === "invalid_token") {
          await deps.rpc("invalidate_watch_push_token", { device: job.device_id, token: job.push_token });
        }
        return outcome;
      }));
      return json({ outcomes });
    } catch {
      return json({ error: "unavailable" }, 503);
    }
  };
}
