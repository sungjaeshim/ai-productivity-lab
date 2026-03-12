#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import path from 'node:path';

const repoRoot = process.cwd();
const BLOG_DIR = 'src/content/blog';
const DEFAULT_WINDOW_DAYS = 30;

function runGit(args, { allowFailure = false } = {}) {
  const result = spawnSync('git', args, {
    cwd: repoRoot,
    encoding: 'utf8',
  });

  if (result.status !== 0 && !allowFailure) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw new Error(`git ${args.join(' ')} failed${detail ? `: ${detail}` : ''}`);
  }

  return result;
}

function parseArgs(argv) {
  const parsed = {
    base: null,
    head: 'HEAD',
    windowDays: DEFAULT_WINDOW_DAYS,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--base') {
      parsed.base = argv[i + 1] ?? null;
      i += 1;
    } else if (arg === '--head') {
      parsed.head = argv[i + 1] ?? parsed.head;
      i += 1;
    } else if (arg === '--window-days') {
      parsed.windowDays = Number.parseInt(argv[i + 1] ?? `${DEFAULT_WINDOW_DAYS}`, 10);
      i += 1;
    } else if (arg === '-h' || arg === '--help') {
      console.log('Usage: node scripts/check-blog-regression.mjs --base <git-ref> [--head <git-ref>] [--window-days <n>]');
      process.exit(0);
    } else {
      throw new Error(`Unknown arg: ${arg}`);
    }
  }

  if (!parsed.base) {
    throw new Error('Missing required --base <git-ref>');
  }

  return parsed;
}

function listBlogFiles(ref) {
  const result = runGit(['ls-tree', '-r', '--name-only', ref, '--', BLOG_DIR], { allowFailure: true });
  if (result.status !== 0) return [];

  return result.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((file) => file.endsWith('.md') || file.endsWith('.mdx'));
}

function readFileAtRef(ref, filePath) {
  const result = runGit(['show', `${ref}:${filePath}`], { allowFailure: true });
  if (result.status !== 0) return null;
  return result.stdout;
}

function extractFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : null;
}

function extractField(frontmatter, field) {
  const regex = new RegExp(`^${field}\\s*:\\s*"?([^"\\n]+)"?`, 'm');
  const match = frontmatter.match(regex);
  return match ? match[1].trim() : null;
}

function parseDateValue(raw) {
  if (!raw) return null;

  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return new Date(`${raw}T00:00:00Z`);
  }

  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function collectSnapshot(ref) {
  const files = listBlogFiles(ref);
  const posts = [];

  for (const file of files) {
    const content = readFileAtRef(ref, file);
    if (!content) continue;
    const fm = extractFrontmatter(content);
    if (!fm) continue;
    const rawDate = extractField(fm, 'pubDate') ?? extractField(fm, 'date');
    const parsedDate = parseDateValue(rawDate);
    if (!parsedDate) continue;

    posts.push({
      file,
      title: extractField(fm, 'title') ?? path.basename(file),
      rawDate,
      parsedDate,
    });
  }

  posts.sort((a, b) => b.parsedDate.getTime() - a.parsedDate.getTime());
  return posts;
}

function formatDay(date) {
  return date.toISOString().slice(0, 10);
}

function listDeletedBlogFiles(base, head) {
  const result = runGit(['diff', '--name-status', '--diff-filter=D', base, head, '--', BLOG_DIR], { allowFailure: true });
  if (result.status !== 0) return [];

  return result.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => line.split('\t').at(-1))
    .filter(Boolean);
}

const args = parseArgs(process.argv.slice(2));

const bypass = process.env.ALLOW_BLOG_HISTORY_REWRITE === '1';
const basePosts = collectSnapshot(args.base);
const headPosts = collectSnapshot(args.head);

if (!basePosts.length || !headPosts.length) {
  console.log('ℹ️ Blog regression guard skipped: unable to resolve comparable blog snapshots.');
  process.exit(0);
}

const baseMax = basePosts[0];
const headMax = headPosts[0];
const thresholdMs = args.windowDays * 24 * 60 * 60 * 1000;
const deletedFiles = listDeletedBlogFiles(args.base, args.head);
const baseByFile = new Map(basePosts.map((post) => [post.file, post]));
const recentDeleted = deletedFiles
  .map((file) => baseByFile.get(file))
  .filter(Boolean)
  .filter((post) => baseMax.parsedDate.getTime() - post.parsedDate.getTime() <= thresholdMs);

const violations = [];

if (headMax.parsedDate.getTime() < baseMax.parsedDate.getTime()) {
  violations.push(
    `latest pubDate regressed: ${formatDay(baseMax.parsedDate)} (${baseMax.file}) -> ${formatDay(headMax.parsedDate)} (${headMax.file})`
  );
}

if (recentDeleted.length) {
  const details = recentDeleted
    .map((post) => `${formatDay(post.parsedDate)} ${post.file}`)
    .join(', ');
  violations.push(`recent blog posts deleted within ${args.windowDays}d window: ${details}`);
}

if (!violations.length) {
  console.log(`✅ Blog regression guard passed (${args.base} -> ${args.head}).`);
  process.exit(0);
}

console.error('\n❌ Blog regression guard failed.\n');
for (const violation of violations) {
  console.error(`- ${violation}`);
}

if (bypass) {
  console.error('\n⚠️ ALLOW_BLOG_HISTORY_REWRITE=1 set. Bypassing failure.\n');
  process.exit(0);
}

console.error('\nIf this rewrite is intentional, rerun with ALLOW_BLOG_HISTORY_REWRITE=1.\n');
process.exit(1);
