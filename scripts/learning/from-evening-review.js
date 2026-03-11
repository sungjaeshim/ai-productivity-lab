#!/usr/bin/env node
import { spawnSync } from 'child_process';
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

function required(args, key) {
  const value = args[key];
  if (value === undefined || value === true || String(value).trim() === '') {
    throw new Error(`Missing required argument: --${key}`);
  }
  return String(value).trim();
}

function ensureArray(value) {
  if (value === undefined) return [];
  return Array.isArray(value) ? value : [value];
}

function runNode(scriptPath, scriptArgs) {
  const proc = spawnSync('node', [scriptPath, ...scriptArgs], {
    encoding: 'utf8',
    cwd: path.resolve(__dirname, '..', '..')
  });
  if (proc.status !== 0) {
    throw new Error((proc.stderr || proc.stdout || `Failed: ${path.basename(scriptPath)}`).trim());
  }
  return JSON.parse(proc.stdout);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const createScript = path.join(__dirname, 'create-learning-card.js');
  const registerScript = path.join(__dirname, 'register-review-queue.js');

  const title = required(args, 'title');
  const summary = required(args, 'summary');
  const sourceRef = String(args['source-ref'] || 'evening-review').trim();
  const sourceTitle = String(args['source-title'] || '저녁 회고').trim();
  const applyAction = required(args, 'apply-action');
  const anchorTime = String(args['anchor-time'] || new Date().toISOString()).trim();
  const keyPoints = ensureArray(args['key-point']);
  const recallQuestions = ensureArray(args['recall-question']);
  const connectPoints = ensureArray(args['connect-point']);
  const tags = ensureArray(args.tag);

  if (keyPoints.length < 1) throw new Error('At least one --key-point is required');
  if (recallQuestions.length < 1) throw new Error('At least one --recall-question is required');

  const createArgs = [
    '--title', title,
    '--source-type', 'evening-review',
    '--source-ref', sourceRef,
    '--source-title', sourceTitle,
    '--summary', summary,
    '--apply-action', applyAction,
  ];

  for (const item of keyPoints) createArgs.push('--key-point', item);
  for (const item of recallQuestions) createArgs.push('--recall-question', item);
  for (const item of connectPoints) createArgs.push('--connect-point', item);
  for (const item of tags) createArgs.push('--tag', item);

  const created = runNode(createScript, createArgs);
  const registered = runNode(registerScript, [
    '--card-id', created.itemId,
    '--anchor-time', anchorTime,
    '--origin', 'evening-review'
  ]);

  process.stdout.write(JSON.stringify({
    ok: true,
    itemId: created.itemId,
    cardPath: created.filePath,
    queueCreated: registered.created,
    queueItems: registered.items
  }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
