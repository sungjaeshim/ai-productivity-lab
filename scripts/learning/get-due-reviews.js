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

function loadJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  const raw = fs.readFileSync(filePath, 'utf8').trim();
  if (!raw) return fallback;
  return JSON.parse(raw);
}

function readCardMap(cardsRoot) {
  const map = new Map();
  if (!fs.existsSync(cardsRoot)) return map;

  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith('.md')) continue;
      const raw = fs.readFileSync(fullPath, 'utf8');
      const itemIdMatch = raw.match(/^item_id:\s*(.+)$/m);
      const titleMatch = raw.match(/^#\s+(.+)$/m);
      const summaryMatch = raw.match(/^## Summary\n([\s\S]*?)(?:\n## |$)/m);
      if (!itemIdMatch) continue;
      map.set(itemIdMatch[1].trim(), {
        filePath: fullPath,
        title: titleMatch ? titleMatch[1].trim() : '(untitled)',
        summary: summaryMatch ? summaryMatch[1].trim().replace(/\n+/g, ' ') : ''
      });
    }
  }

  walk(cardsRoot);
  return map;
}

function toDate(value) {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

function pickDueItems(items, now, limit) {
  return items
    .filter(item => item.status === 'pending')
    .map(item => ({ ...item, dueDate: toDate(item.due_at) }))
    .filter(item => item.dueDate && item.dueDate.getTime() <= now.getTime())
    .sort((a, b) => a.dueDate - b.dueDate)
    .slice(0, limit);
}

function formatBriefing(items) {
  if (!items.length) return 'Learning Review: due item 없음';
  const lines = ['Learning Review'];
  for (const item of items) {
    lines.push(`- [${item.review_type.toUpperCase()}][${item.mode}] ${item.title} (${item.card_id})`);
    if (item.summary) {
      lines.push(`  → ${item.summary}`);
    }
  }
  return lines.join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const workspace = path.resolve(__dirname, '..', '..');
  const queuePath = path.join(workspace, 'review-queue', 'queue.json');
  const cardsRoot = path.join(workspace, 'learning-cards');

  const limit = Number(args.limit || 3);
  const now = args.now ? new Date(args.now) : new Date();
  if (Number.isNaN(now.getTime())) {
    throw new Error(`Invalid --now value: ${args.now}`);
  }

  const queue = loadJson(queuePath, { items: [] });
  const cardMap = readCardMap(cardsRoot);
  const dueItems = pickDueItems(Array.isArray(queue.items) ? queue.items : [], now, limit).map(item => {
    const card = cardMap.get(item.card_id) || { title: '(missing card)', summary: '', filePath: null };
    return {
      ...item,
      title: card.title,
      summary: card.summary,
      card_path: card.filePath
    };
  });

  const result = {
    ok: true,
    now: now.toISOString(),
    limit,
    count: dueItems.length,
    items: dueItems,
    briefing: formatBriefing(dueItems)
  };

  process.stdout.write(JSON.stringify(result, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
