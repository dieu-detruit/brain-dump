import { backend } from "../_shared/http.ts";
import { createHandler } from "./handler.ts";
Deno.serve(createHandler(backend(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)));
