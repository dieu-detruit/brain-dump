import { parseMutation } from "./contracts.ts";
function assert(value: boolean) {
  if (!value) throw new Error("assertion failed");
}
Deno.test("malformed and oversized IDs cannot become execution commands", () => {
  for (
    const input of [null, {}, { action: "delete" }, { action: "confirm", operation_id: "x", expected: null }]
  ) {
    let rejected = false;
    try {
      parseMutation(input);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("large session IDs remain strings; switch from idle is allowed", () => {
  const id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const parsed = parseMutation({
    action: "confirm",
    operation_id: id,
    expected: { session_id: "9007199254740993", confirmation_revision: id },
  });
  assert(parsed.expected?.session_id === "9007199254740993");
  assert(
    parseMutation({ action: "switch", operation_id: id, expected: null, target_thread_id: id }).expected ===
      null,
  );
});
