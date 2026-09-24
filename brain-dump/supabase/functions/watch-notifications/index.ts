import { backend } from "../_shared/http.ts";
import { importAPNsKey, signAPNs } from "../_shared/apns.ts";
import { createNotificationHandler } from "./handler.ts";
let cached: { jwt: string; expires: number } | undefined;
const key = () => importAPNsKey(Deno.env.get("APNS_PRIVATE_KEY")!);
Deno.serve(createNotificationHandler({
  ...backend(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!),
  secret: Deno.env.get("WATCH_CRON_SECRET") ?? "",
  topic: Deno.env.get("WATCH_BUNDLE_ID")!,
  jwt: async () => {
    if (!cached || cached.expires < Date.now()) {
      cached = {
        jwt: await signAPNs(await key(), Deno.env.get("APPLE_TEAM_ID")!, Deno.env.get("APNS_KEY_ID")!),
        expires: Date.now() + 40 * 60000,
      };
    }
    return cached.jwt;
  },
}));
