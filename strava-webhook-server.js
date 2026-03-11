#!/usr/bin/env node
import http from 'node:http';
import { appendFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PORT = Number(process.env.STRAVA_WEBHOOK_PORT || 18790);
const VERIFY_TOKEN = process.env.STRAVA_VERIFY_TOKEN || 'jarvis-strava-2026';
const EVENTS_DIR = join(__dirname, 'data');
const EVENTS_LOG = join(EVENTS_DIR, 'strava-webhook-events.jsonl');

function now() {
  return new Date().toISOString();
}

function log(msg) {
  console.log(`[${now()}] ${msg}`);
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body)
  });
  res.end(body);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    return { raw };
  }
}

async function recordEvent(obj) {
  await mkdir(EVENTS_DIR, { recursive: true });
  await appendFile(EVENTS_LOG, JSON.stringify({ ts: now(), ...obj }) + '\n', 'utf8');
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', `http://127.0.0.1:${PORT}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, { ok: true, service: 'strava-webhook', ts: now() });
    }

    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/webhook')) {
      const mode = url.searchParams.get('hub.mode');
      const token = url.searchParams.get('hub.verify_token');
      const challenge = url.searchParams.get('hub.challenge');

      if (mode === 'subscribe') {
        if (token !== VERIFY_TOKEN) {
          log(`verify failed (token mismatch)`);
          return sendJson(res, 403, { ok: false, error: 'verify_token_mismatch' });
        }
        log('verify success');
        return sendJson(res, 200, { 'hub.challenge': challenge || '' });
      }

      return sendJson(res, 200, {
        ok: true,
        service: 'strava-webhook',
        endpoint: '/webhook',
        ts: now()
      });
    }

    if (req.method === 'POST' && (url.pathname === '/' || url.pathname === '/webhook')) {
      const body = await readBody(req);
      await recordEvent({ method: 'POST', path: url.pathname, body });
      log(`event received object_type=${body.object_type || 'unknown'} aspect_type=${body.aspect_type || 'unknown'}`);
      return sendJson(res, 200, { ok: true, accepted: true });
    }

    return sendJson(res, 404, { ok: false, error: 'not_found' });
  } catch (err) {
    log(`error: ${err?.message || String(err)}`);
    return sendJson(res, 500, { ok: false, error: 'internal_error' });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  log(`Strava webhook server listening on 127.0.0.1:${PORT}`);
});
