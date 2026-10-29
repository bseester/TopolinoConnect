const ROUTE = "/api/v1/vehicle/latest";
const ROUTES = "/api/v1/vehicle/routes";
const MAX_BODY_BYTES = 16 * 1024;
const MAX_ROUTES_BYTES = 1024 * 1024;
const MAX_AGE_MS = 45_000;

function response(status, body = "") {
  const headers = {
    "Cache-Control": "no-store, max-age=0",
    "X-Content-Type-Options": "nosniff",
  };
  if (body) headers["Content-Type"] = "application/json; charset=utf-8";
  return new Response(body, { status, headers });
}

function json(status, value) {
  return response(status, JSON.stringify(value));
}

async function tenantId(key) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function readEnvelope(request) {
  const declaredLength = Number(request.headers.get("Content-Length") || 0);
  if (declaredLength > MAX_BODY_BYTES) throw new Error("too_large");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) throw new Error("too_large");
  const envelope = JSON.parse(text);
  const temperature = envelope?.espTemperature;
  const hasTemperature = Number.isFinite(temperature?.celsius) && temperature.celsius >= -55 &&
    temperature.celsius <= 125 && typeof temperature.timestamp === "string" && temperature.timestamp.length <= 40;
  const espCan = envelope?.espCan;
  const hasRawCanFrames = Array.isArray(espCan?.canFrames) && espCan.canFrames.some((frame) => {
    const identifier = typeof frame?.id === "string" && /^0x[0-9a-fA-F]{3,8}$/.test(frame.id);
    const dlc = Number.isInteger(frame?.dlc) && frame.dlc >= 0 && frame.dlc <= 8;
    const data = typeof frame?.data === "string" && /^(?:[0-9a-fA-F]{2}(?: [0-9a-fA-F]{2}){0,7})?$/.test(frame.data);
    return identifier && dlc && data && typeof frame.timestamp === "string" && frame.timestamp.length <= 40;
  });
  const hasVehicleCan = espCan?.canLive !== false &&
    ["speedKmh", "odometerKm", "batteryPercent", "rangeKm", "voltageV", "currentA", "batteryPowerKw",
      "battery12V", "temperature1C", "temperature2C", "gear", "ready", "handbrake"]
      .some((key) => espCan?.[key] !== null && espCan?.[key] !== undefined) &&
    typeof espCan.timestamp === "string" && espCan.timestamp.length <= 40;
  const hasChargeOnly = espCan?.canLive === false && typeof espCan.charging === "boolean" &&
    (Number.isFinite(espCan.chargeMinutesRemaining) || Number.isFinite(espCan.chargePowerKw)) &&
    typeof espCan.timestamp === "string" && espCan.timestamp.length <= 40;
  const hasEspCan = hasVehicleCan || hasChargeOnly ||
    (hasRawCanFrames && typeof espCan?.timestamp === "string" && espCan.timestamp.length <= 40);
  if (!hasTemperature && !hasEspCan) {
    throw new Error("invalid_vehicle_sample");
  }
  return envelope;
}

async function readRoutes(request) {
  const declaredLength = Number(request.headers.get("Content-Length") || 0);
  if (declaredLength > MAX_ROUTES_BYTES) throw new Error("too_large");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_ROUTES_BYTES) throw new Error("too_large");
  const value = JSON.parse(text);
  if (!Array.isArray(value?.trips) || value.trips.length > 500) throw new Error("invalid_routes");
  return value;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json(200, { ok: true, service: "Topolino Gateway Relay" });
    }
    if (url.pathname === ROUTES && ["GET", "PUT"].includes(request.method)) {
      const key = request.headers.get("X-Topolino-Key") || "";
      if (!/^[A-Za-z0-9_-]{32,128}$/.test(key)) return json(401, { error: "invalid_key" });
      const id = await tenantId(key);
      try {
        if (request.method === "PUT") {
          let payload;
          try { payload = await readRoutes(request); }
          catch (error) {
            const tooLarge = error?.message === "too_large";
            return json(tooLarge ? 413 : 400, { error: tooLarge ? "payload_too_large" : "invalid_routes" });
          }
          await env.DB.prepare(
            "INSERT INTO vehicle_routes (tenant_id, payload, updated_at) VALUES (?1, ?2, ?3) " +
            "ON CONFLICT(tenant_id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at",
          ).bind(id, JSON.stringify(payload), Date.now()).run();
          return json(202, { accepted: true });
        }
        const saved = await env.DB.prepare("SELECT payload, updated_at FROM vehicle_routes WHERE tenant_id = ?1").bind(id).first();
        return saved
          ? json(200, { ...JSON.parse(saved.payload), updatedAt: saved.updated_at })
          : json(200, { trips: [], lastParkedLocation: null, lastParkedAt: null, updatedAt: null });
      } catch {
        return json(503, { error: "relay_storage_unavailable" });
      }
    }
    if (url.pathname !== ROUTE || !["GET", "POST"].includes(request.method)) {
      return json(404, { error: "not_found" });
    }

    const key = request.headers.get("X-Topolino-Key") || "";
    if (!/^[A-Za-z0-9_-]{32,128}$/.test(key)) return json(401, { error: "invalid_key" });
    const id = await tenantId(key);

    try {
      if (request.method === "POST") {
        let envelope;
        try {
          envelope = await readEnvelope(request);
        } catch (error) {
          const tooLarge = error?.message === "too_large";
          return json(tooLarge ? 413 : 400, {
            error: tooLarge ? "payload_too_large" : error?.message === "invalid_vehicle_sample" ? "invalid_vehicle_sample" : "invalid_request",
          });
        }

        const latestStatement = env.DB.prepare(
          "INSERT INTO latest_vehicle (tenant_id, envelope, received_at) VALUES (?1, ?2, ?3) " +
          "ON CONFLICT(tenant_id) DO UPDATE SET envelope = excluded.envelope, received_at = excluded.received_at",
        ).bind(id, JSON.stringify(envelope), Date.now());
        await env.DB.batch([latestStatement]);
        return json(202, { accepted: true });
      }

      const saved = await env.DB.prepare(
        "SELECT envelope, received_at FROM latest_vehicle WHERE tenant_id = ?1",
      ).bind(id).first();
      if (!saved) return response(204);
      const envelope = JSON.parse(saved.envelope);
      const sampleTime = Date.parse(envelope?.espCan?.timestamp || envelope?.espTemperature?.timestamp || "");
      const stale = envelope?.testReplay === true || envelope?.isStale === true ||
        !Number.isFinite(sampleTime) || Date.now() - sampleTime > MAX_AGE_MS;
      if (envelope?.espTemperature) {
        const temperatureTime = Date.parse(envelope.espTemperature.timestamp || "");
        envelope.espTemperature.isStale = !Number.isFinite(temperatureTime) || Date.now() - temperatureTime > MAX_AGE_MS;
      }
      if (envelope?.espCan) {
        const espCanTime = Date.parse(envelope.espCan.timestamp || "");
        envelope.espCan.isStale = !Number.isFinite(espCanTime) || Date.now() - espCanTime > MAX_AGE_MS;
      }
      envelope.isStale = stale;
      if (stale && envelope?.testReplay !== true) {
        envelope.status = "Son bilinen gerçek araç verisi · Android’den yeni paket bekleniyor";
      }
      return json(200, envelope);
    } catch {
      return json(503, { error: "relay_storage_unavailable" });
    }
  },
};
