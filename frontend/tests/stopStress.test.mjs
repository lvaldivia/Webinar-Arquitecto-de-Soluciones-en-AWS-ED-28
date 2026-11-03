import test from "node:test";
import assert from "node:assert/strict";
import { stopStressOnInstances } from "../src/api.ts";

function response(id, status = "stopped") {
  return new Response(JSON.stringify({ instance_id: id, status, remaining_seconds: 0 }), {
    status: status === "stopping" ? 202 : 200,
  });
}

test("repite hasta confirmar ambas EC2: duplicados y stopping no cuentan como parada global", async (t) => {
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  let calls = 0;
  globalThis.fetch = async () => {
    const index = calls++;
    if (index === 1) return response("i-b", "stopping");
    return response(index >= 4 ? "i-b" : "i-a");
  };
  const confirmed = [];
  const result = await stopStressOnInstances(["i-a", "i-b"], (id) => confirmed.push(id));
  assert.equal(calls, 8);
  assert.deepEqual(result.pending, []);
  assert.deepEqual(result.stopped, ["i-a", "i-b"]);
  assert.deepEqual(confirmed, ["i-a", "i-b"]);
});

test("informa parada parcial si el ALB nunca alcanza una instancia activa", async (t) => {
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  globalThis.fetch = async (path) => path === "/api/scaling"
    ? new Response(JSON.stringify({ status: "ok", instances: [
        { instance_id: "i-a", state: "ready" }, { instance_id: "i-b", state: "ready" },
      ] }))
    : response("i-a");
  const result = await stopStressOnInstances(["i-a", "i-b"], () => {});
  assert.deepEqual(result.stopped, ["i-a"]);
  assert.deepEqual(result.pending, ["i-b"]);
});
