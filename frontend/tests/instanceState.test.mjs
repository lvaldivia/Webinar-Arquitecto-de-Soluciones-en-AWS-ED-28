import test from "node:test";
import assert from "node:assert/strict";
import { isServing } from "../src/instanceState.ts";

const group = (instances) => ({ status: "ok", instances });
test("una instancia retirada desaparece aunque haya respondido recién", () => {
  assert.equal(isServing("i-old", 9999, 10000, group([{ instance_id: "i-new", state: "ready" }])), false);
});
test("una instancia sin salud o retirándose no cuenta como activa", () => {
  for (const state of ["deploying", "terminating"]) {
    assert.equal(isServing("i-old", 9999, 10000, group([{ instance_id: "i-old", state }])), false);
  }
});
test("no recibir tráfico no declara muerta una instancia que AWS confirma sana", () => {
  assert.equal(isServing("i-live", 0, 100000, group([{ instance_id: "i-live", state: "ready" }])), true);
});
test("sin AWS, las observaciones caducan aunque ya no lleguen respuestas", () => {
  assert.equal(isServing("local", 0, 19999, null), true);
  assert.equal(isServing("local", 0, 20000, null), false);
});
