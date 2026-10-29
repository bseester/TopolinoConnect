import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.mjs";

const key = "0123456789abcdef0123456789abcdef";
const frame = { id: "0x580", dlc: 8, data: "D8 FE 58 1B 00 4E 13 00", timestamp: "2026-10-29T12:00:00Z" };

function fakeEnv() {
  return {
    DB: {
      prepare(sql) {
        return { sql, bind(...values) { return { sql, values }; } };
      },
      async batch() { return { success: true }; }
    }
  };
}

test("relay accepts current raw CAN frames even when no known signal decoded", async () => {
  const response = await worker.fetch(new Request("https://relay.test/api/v1/vehicle/latest", {
    method: "POST",
    headers: { "X-Topolino-Key": key, "Content-Type": "application/json" },
    body: JSON.stringify({ espCan: { canLive: false, timestamp: frame.timestamp, canFrames: [frame] } })
  }), fakeEnv());
  assert.equal(response.status, 202);
  assert.deepEqual(await response.json(), { accepted: true });
});

test("relay rejects malformed frame-only payloads with a specific 400 code", async () => {
  const response = await worker.fetch(new Request("https://relay.test/api/v1/vehicle/latest", {
    method: "POST",
    headers: { "X-Topolino-Key": key, "Content-Type": "application/json" },
    body: JSON.stringify({ espCan: { canLive: false, timestamp: frame.timestamp, canFrames: [{ ...frame, id: "bad-id" }] } })
  }), fakeEnv());
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_vehicle_sample" });
});
