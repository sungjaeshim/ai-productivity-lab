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
    if (args[key] === undefined) {
      args[key] = next;
    } else if (Array.isArray(args[key])) {
      args[key].push(next);
    } else {
      args[key] = [args[key], next];
    }
    i += 1;
  }
  return args;
}

function ensureArray(value) {
  if (value === undefined) return [];
  return Array.isArray(value) ? value : [value];
}

function required(args, key) {
  const value = args[key];
  if (value === undefined || value === true || String(value).trim() === '') {
    throw new Error(`Missing required argument: --${key}`);
  }
  return String(value).trim();
}

function nowKst() {
  const formatter = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
  const parts = Object.fromEntries(formatter.formatToParts(new Date()).filter(p => p.type !== 'literal').map(p => [p.type, p.value]));
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour: parts.hour,
    minute: parts.minute,
    second: parts.second,
    iso: `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}+09:00`,
    date: `${parts.year}-${parts.month}-${parts.day}`,
    compact: `${parts.year}${parts.month}${parts.day}`
  };
}

function nextSequence(dir, prefix) {
  if (!fs.existsSync(dir)) return '001';
  const files = fs.readdirSync(dir).filter(name => name.startsWith(prefix) && name.endsWith('.md')).sort();
  if (files.length === 0) return '001';
  const last = files[files.length - 1];
  const match = last.match(/-(\d+)\.md$/);
  const num = match ? Number(match[1]) + 1 : 1;
  return String(num).padStart(3, '0');
}

function yamlList(items, indent = '  ') {
  if (!items.length) return `${indent}[]`;
  return items.map(item => `${indent}- ${String(item).replace(/\n/g, ' ')}`).join('\n');
}

function markdownNumbered(items) {
  return items.map((item, idx) => `${idx + 1}. ${item}`).join('\n');
}

function markdownBullets(items) {
  return items.map(item => `- ${item}`).join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const workspace = path.resolve(__dirname, '..', '..');
  const stamp = nowKst();
  const title = required(args, 'title');
  const sourceType = required(args, 'source-type');
  const sourceRef = required(args, 'source-ref');
  const summary = required(args, 'summary');
  const applyAction = required(args, 'apply-action');
  const sourceTitle = String(args['source-title'] || title).trim();
  const keyPoints = ensureArray(args['key-point']);
  const recallQuestions = ensureArray(args['recall-question']);
  const connectPoints = ensureArray(args['connect-point']);
  const tags = ensureArray(args.tag);

  if (keyPoints.length < 1) throw new Error('At least one --key-point is required');
  if (recallQuestions.length < 1) throw new Error('At least one --recall-question is required');

  const dayDir = path.join(workspace, 'learning-cards', stamp.year, stamp.date);
  fs.mkdirSync(dayDir, { recursive: true });
  const seq = nextSequence(dayDir, `lc-${stamp.compact}-`);
  const itemId = `lc-${stamp.compact}-${seq}`;
  const filePath = path.join(dayDir, `${itemId}.md`);

  const content = `---\nitem_id: ${itemId}\ncreated_at: ${stamp.iso}\nsource_type: ${sourceType}\nsource_ref: ${sourceRef}\nsource_title: ${sourceTitle}\nstatus: new\ntags:\n${yamlList(tags)}\nreview:\n  first_due_at:\n  last_reviewed_at:\n  next_due_at:\n  review_count: 0\napply:\n  action: \"${applyAction.replace(/\"/g, '\\\"')}\"\n  evidence:\ntransfer_score:\n---\n\n# ${title}\n\n## Summary\n${summary}\n\n## Key Points\n${markdownBullets(keyPoints)}\n\n## Recall Questions\n${markdownNumbered(recallQuestions)}\n\n## Connect Points\n${connectPoints.length ? markdownBullets(connectPoints) : '- (to be added)'}\n\n## Apply Action\n${applyAction}\n`;

  fs.writeFileSync(filePath, content, 'utf8');
  process.stdout.write(JSON.stringify({ ok: true, itemId, filePath }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
