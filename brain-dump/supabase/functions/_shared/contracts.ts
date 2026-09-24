export type ExpectedExecution = { session_id: string; confirmation_revision: string } | null;
export type ActiveExecution = NonNullable<ExpectedExecution> & {
  thread_id: string;
  last_confirmed_at: string;
  deadline: string;
};
export type Snapshot = {
  server_time: string;
  threads: { id: string; title: string; delegation: "ai" | "colleague" | null; priority: number }[];
  active: ActiveExecution | null;
};
export type Mutation = {
  operation_id: string;
  action: "confirm" | "switch";
  expected: ExpectedExecution;
  target_thread_id?: string | null;
};
export type MutationResult = { status: "applied" | "stale" | "expired"; snapshot: Snapshot };
export const uuid = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export function parseMutation(value: unknown): Mutation {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_request");
  const v = value as Record<string, unknown>;
  if (!uuid(v.operation_id) || !["confirm", "switch"].includes(String(v.action))) {
    throw new Error("invalid_request");
  }
  const e = v.expected as Record<string, unknown> | null;
  if (
    e !== null &&
    (!e || typeof e.session_id !== "string" || !/^[1-9][0-9]{0,18}$/.test(e.session_id) ||
      !uuid(e.confirmation_revision))
  ) throw new Error("invalid_request");
  if (v.action === "confirm" && e === null) throw new Error("invalid_request");
  if (v.action === "switch" && v.target_thread_id !== null && !uuid(v.target_thread_id)) {
    throw new Error("invalid_request");
  }
  return {
    operation_id: v.operation_id,
    action: v.action as Mutation["action"],
    expected: e as ExpectedExecution,
    ...(v.action === "switch" ? { target_thread_id: v.target_thread_id as string | null } : {}),
  };
}
