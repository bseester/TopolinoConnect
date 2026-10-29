import { createHash } from 'node:crypto';
import { createServer } from 'node:http';

const port = Number(process.env.PORT || 8080);
const samples = new Map();
const maxBodyBytes = 16 * 1024;
const maxAgeMs = 45_000;

function tenantId(key) {
  return createHash('sha256').update(key).digest('hex');
}

function send(res, status, body = '') {
  res.writeHead(status, {
    'Cache-Control': 'no-store, max-age=0',
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(body);
}

function validKey(req) {
  const key = req.headers['x-topolino-key'];
  return typeof key === 'string' && /^[A-Za-z0-9_-]{32,128}$/.test(key) ? key : null;
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBodyBytes) throw new Error('too_large');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

const server = createServer(async (req, res) => {
  const path = new URL(req.url || '/', 'http://relay.local').pathname;
  if (req.method === 'GET' && path === '/health') {
    return send(res, 200, JSON.stringify({ ok: true, service: 'Topolino Gateway Relay' }));
  }
  if (path !== '/api/v1/vehicle/latest' || !['GET', 'POST'].includes(req.method || '')) {
    return send(res, 404, JSON.stringify({ error: 'not_found' }));
  }
  const key = validKey(req);
  if (!key) return send(res, 401, JSON.stringify({ error: 'invalid_key' }));
  const id = tenantId(key);

  if (req.method === 'POST') {
    try {
      const envelope = await readBody(req);
      const can = envelope?.espCan;
      const validCan = Number.isFinite(can?.speedKmh) && Number.isFinite(can?.batteryPercent) &&
        can.batteryPercent >= 0 && can.batteryPercent <= 100 && typeof can.timestamp === 'string';
      if (!validCan) {
        return send(res, 400, JSON.stringify({ error: 'invalid_vehicle_sample' }));
      }
      samples.set(id, { envelope, receivedAt: Date.now() });
      return send(res, 202, JSON.stringify({ accepted: true }));
    } catch (error) {
      return send(res, error?.message === 'too_large' ? 413 : 400, JSON.stringify({ error: 'invalid_request' }));
    }
  }

  const saved = samples.get(id);
  if (!saved) {
    res.writeHead(204, { 'Cache-Control': 'no-store, max-age=0', 'Content-Length': '0' });
    return res.end();
  }
  const envelope = { ...saved.envelope };
  const sampleTime = Date.parse(envelope?.espCan?.timestamp || '');
  const stale = envelope?.testReplay === true || envelope?.isStale === true ||
    !Number.isFinite(sampleTime) || Date.now() - sampleTime > maxAgeMs;
  envelope.isStale = stale;
  if (stale && envelope?.testReplay !== true) {
    envelope.status = 'Son bilinen gerçek araç verisi · Android’den yeni paket bekleniyor';
  }
  return send(res, 200, JSON.stringify(envelope));
});

server.listen(port, '0.0.0.0', () => console.log(`Topolino relay listening on ${port}`));
