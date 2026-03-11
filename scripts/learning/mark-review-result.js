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

function loadJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  const raw = fs.readFileSync(filePath, 'utf8').trim();
  if (!raw) return fallback;
  return JSON.parse(raw);
}

function toKstIso(date = new Date()) {
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

function findCardPath(cardsRoot, cardId) {
  if (!fs.existsSync(cardsRoot)) return null;
  const stack = [cardsRoot];
  while (stack.length) {
    const dir = stack.pop();
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith('.md')) continue;
      const raw = fs.readFileSync(fullPath, 'utf8');
      if (raw.includes(`item_id: ${cardId}`)) return fullPath;
    }
  }
  return null;
}

function replaceField(raw, field, value) {
  const regex = new RegExp(`^${field}:.*$`, 'm');
  if (!regex.test(raw)) {
    throw new Error(`Field not found in card: ${field}`);
  }
  return raw.replace(regex, `${field}: ${value}`);
}

function appendBlockValue(raw, blockKey, fieldKey, value) {
  const regex = new RegExp(`(^${blockKey}:\\n(?:[ \\t].*\\n)*)`, 'm');
  const match = raw.match(regex);
  if (!match) throw new Error(`Block not found in card: ${blockKey}`);
  const block = match[1];
  const fieldRegex = new RegExp(`^  ${fieldKey}:.*$`, 'm');
  let updatedBlock;
  if (fieldRegex.test(block)) {
    updatedBlock = block.replace(fieldRegex, `  ${fieldKey}: ${value}`);
  } else {
    updatedBlock = `${block}  ${fieldKey}: ${value}\n`;
  }
  return raw.replace(block, updatedBlock);
}

function appendHistory(historyDir, payload) {
  fs.mkdirSync(historyDir, { recursive: true });
  const day = payload.at.slice(0, 10);
  const historyPath = path.join(historyDir, `${day}-review-log.jsonl`);
  fs.appendFileSync(historyPath, `${JSON.stringify(payload)}\n`, 'utf8');
  return historyPath;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const workspace = path.resolve(__dirname, '..', '..');
  const queuePath = path.join(workspace, 'review-queue', 'queue.json');
  const historyDir = path.join(workspace, 'review-queue', 'history');
  const cardsRoot = path.join(workspace, 'learning-cards');

  const queueId = required(args, 'queue-id');
  const result = required(args, 'result');
  const notes = String(args.notes || '').trim();
  const applyEvidence = String(args['apply-evidence'] || '').trim();
  const at = toKstIso(new Date());

  if (!['done', 'skipped', 'stale'].includes(result)) {
    throw new Error('Invalid --result. Use done|skipped|stale');
  }

  const queue = loadJson(queuePath, { items: [] });
  const item = queue.items.find(entry => entry.queue_id === queueId);
  if (!item) throw new Error(`Queue item not found: ${queueId}`);

  item.status = result;
  item.completed_at = at;
  if (notes) item.notes = notes;

  fs.writeFileSync(queuePath, `${JSON.stringify(queue, null, 2)}\n`, 'utf8');

  const cardPath = findCardPath(cardsRoot, item.card_id);
  if (!cardPath) throw new Error(`Card not found for item: ${item.card_id}`);
  let cardRaw = fs.readFileSync(cardPath, 'utf8');

  const nextStatus = result === 'stale'
    ? 'stale'
    : (applyEvidence ? 'applied' : 'reviewing');

  cardRaw = replaceField(cardRaw, 'status', nextStatus);
  cardRaw = appendBlockValue(cardRaw, 'review', 'last_reviewed_at', at);

  const reviewCountMatch = cardRaw.match(/^  review_count:\s*(\d+)$/m);
  const reviewCount = reviewCountMatch ? Number(reviewCountMatch[1]) + 1 : 1;
  cardRaw = appendBlockValue(cardRaw, 'review', 'review_count', reviewCount);

  if (applyEvidence) {
    cardRaw = appendBlockValue(cardRaw, 'apply', 'evidence', `"${applyEvidence.replace(/"/g, '\\"')}"`);
  }

  fs.writeFileSync(cardPath, cardRaw, 'utf8');

  const historyPath = appendHistory(historyDir, {
    event: 'mark-review-result',
    queue_id: queueId,
    card_id: item.card_id,
    result,
    notes,
    apply_evidence: applyEvidence,
    at
  });

  process.stdout.write(JSON.stringify({
    ok: true,
    queuePath,
    cardPath,
    historyPath,
    queue_id: queueId,
    card_id: item.card_id,
    status: result,
    card_status: nextStatus
  }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
