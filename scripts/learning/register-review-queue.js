#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

function required(args, key) {
  const value = args[key];
  if (value === undefined || value === true || String(value).trim() === '') {
    throw new Error(`Missing required argument: --${key}`);
  }
  return String(value).trim();
}

function loadQueue(queuePath) {
  if (!fs.existsSync(queuePath)) return { items: [] };
  const raw = fs.readFileSync(queuePath, 'utf8').trim();
  if (!raw) return { items: [] };
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed.items)) parsed.items = [];
  return parsed;
}

function toDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid date: ${value}`);
  }
  return date;
}

function toKstIso(date) {
  const formatter = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
  const parts = Object.fromEntries(formatter.formatToParts(date).filter(p => p.type !== 'literal').map(p => [p.type, p.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}+09:00`;
}

function appendHistory(historyDir, payload) {
  fs.mkdirSync(historyDir, { recursive: true });
  const day = payload.created_at.slice(0, 10);
  const historyPath = path.join(historyDir, `${day}-review-log.jsonl`);
  fs.appendFileSync(historyPath, `${JSON.stringify(payload)}\n`, 'utf8');
  return historyPath;
}

function nextDayAtEightKst(anchorTime) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  });
  const parts = Object.fromEntries(formatter.formatToParts(anchorTime).filter(p => p.type !== 'literal').map(p => [p.type, p.value]));
  const yyyy = Number(parts.year);
  const mm = Number(parts.month);
  const dd = Number(parts.day) + 1;
  return new Date(`${String(yyyy).padStart(4, '0')}-${String(mm).padStart(2, '0')}-${String(dd).padStart(2, '0')}T08:00:00+09:00`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const workspace = path.resolve(__dirname, '..', '..');
  const queuePath = path.join(workspace, 'review-queue', 'queue.json');
  const historyDir = path.join(workspace, 'review-queue', 'history');

  const cardId = required(args, 'card-id');
  const anchorTime = toDate(required(args, 'anchor-time'));
  const origin = String(args.origin || 'manual').trim();

  const d0 = new Date(anchorTime);
  const d1 = nextDayAtEightKst(anchorTime);

  const createdAt = toKstIso(new Date());
  const items = [
    {
      queue_id: `rq-${cardId.replace(/^lc-/, '')}-d0`,
      card_id: cardId,
      review_type: 'd0',
      mode: 'recall',
      due_at: toKstIso(d0),
      status: 'pending',
      origin,
      created_at: createdAt,
      completed_at: null
    },
    {
      queue_id: `rq-${cardId.replace(/^lc-/, '')}-d1`,
      card_id: cardId,
      review_type: 'd1',
      mode: 'explain',
      due_at: toKstIso(d1),
      status: 'pending',
      origin,
      created_at: createdAt,
      completed_at: null
    }
  ];

  const queue = loadQueue(queuePath);
  const existingIds = new Set(queue.items.map(item => item.queue_id));
  const newItems = items.filter(item => !existingIds.has(item.queue_id));
  queue.items.push(...newItems);
  queue.items.sort((a, b) => a.due_at.localeCompare(b.due_at));
  fs.writeFileSync(queuePath, `${JSON.stringify(queue, null, 2)}\n`, 'utf8');

  const historyPath = appendHistory(historyDir, {
    event: 'register-review-queue',
    card_id: cardId,
    origin,
    created_at: createdAt,
    items: newItems.map(({ queue_id, review_type, mode, due_at, status }) => ({ queue_id, review_type, mode, due_at, status }))
  });

  process.stdout.write(JSON.stringify({ ok: true, queuePath, historyPath, created: newItems.length, items: newItems }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
