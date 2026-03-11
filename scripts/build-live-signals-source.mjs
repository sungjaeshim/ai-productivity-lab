#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const repoRoot = process.cwd();
const blogDir = path.join(repoRoot, 'src/content/blog');
const srcOutput = path.join(repoRoot, 'src/data/live-signals.json');
const publicOutput = path.join(repoRoot, 'public/data/live-signals-source.json');

if (
  String(process.env.LIVE_SIGNALS_SOURCE_MODE || '').trim().toLowerCase() === 'notion' ||
  String(process.env.LIVE_SIGNALS_NOTION_DB || '').trim()
) {
  const result = spawnSync('python3', [path.join(repoRoot, 'scripts/export-notion-live-signals.py')], {
    stdio: 'inherit',
    cwd: repoRoot,
    env: process.env,
  });

  process.exit(result.status ?? 1);
}

function extractFrontmatter(raw) {
  const match = raw.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : '';
}

function extractField(frontmatter, key) {
  const match = frontmatter.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  return match ? match[1].trim().replace(/^['"]|['"]$/g, '') : '';
}

function normalizeDate(input) {
  const date = new Date(input);
  if (!Number.isNaN(date.getTime())) {
    return date.toISOString().slice(0, 10);
  }
  return String(input || '').trim();
}

function buildSignal(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const frontmatter = extractFrontmatter(raw);
  const slug = path.basename(file).replace(/\.(md|mdx)$/i, '');
  const title = extractField(frontmatter, 'title') || slug;
  const description = extractField(frontmatter, 'description') || 'Latest AI Snowball post';
  const category = extractField(frontmatter, 'category') || 'Latest Post';
  const updatedAt = normalizeDate(extractField(frontmatter, 'updatedDate') || extractField(frontmatter, 'pubDate'));

  return {
    id: slug,
    title,
    summary: description,
    href: `/blog/${slug}/`,
    category,
    updatedAt,
    sort: 999,
  };
}

const files = fs
  .readdirSync(blogDir)
  .filter((name) => name.endsWith('.md') || name.endsWith('.mdx'))
  .map((name) => path.join(blogDir, name));

const signals = files
  .map((file) => buildSignal(file))
  .sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))
  .map((entry, index) => ({ ...entry, sort: index + 1 }))
  .slice(0, 6);

fs.mkdirSync(path.dirname(srcOutput), { recursive: true });
fs.mkdirSync(path.dirname(publicOutput), { recursive: true });

const output = JSON.stringify(signals, null, 2) + '\n';
fs.writeFileSync(srcOutput, output, 'utf8');
fs.writeFileSync(publicOutput, output, 'utf8');

console.log(`OK: wrote ${signals.length} live signals to ${path.relative(repoRoot, srcOutput)} and ${path.relative(repoRoot, publicOutput)}`);
