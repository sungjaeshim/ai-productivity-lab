#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const defaultBlogDir = path.join(repoRoot, 'src/content/blog');

function collectMarkdownFilesFromDir(dirPath) {
  if (!fs.existsSync(dirPath)) return [];
  return fs
    .readdirSync(dirPath)
    .filter((name) => name.endsWith('.md'))
    .map((name) => path.join(dirPath, name));
}

function resolveInputFiles(argvFiles) {
  if (!argvFiles.length) return collectMarkdownFilesFromDir(defaultBlogDir);

  return argvFiles
    .map((file) => path.isAbsolute(file) ? file : path.join(repoRoot, file))
    .filter((file) => file.endsWith('.md'))
    .filter((file) => fs.existsSync(file));
}

function extractFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : null;
}

const args = process.argv.slice(2);
const files = resolveInputFiles(args);

if (!files.length) {
  console.log('ℹ️ No markdown files to validate.');
  process.exit(0);
}

const violations = [];

for (const file of files) {
  const rel = path.relative(repoRoot, file);
  const raw = fs.readFileSync(file, 'utf8');
  const fm = extractFrontmatter(raw);

  if (!fm) {
    violations.push(`${rel}: missing frontmatter block (--- ... ---)`);
    continue;
  }

  const hasPubDate = /^pubDate\s*:/m.test(fm);
  const hasDate = /^date\s*:/m.test(fm);

  if (!hasPubDate) {
    const hint = hasDate
      ? 'found `date:` only → rename to `pubDate:`'
      : 'add `pubDate: YYYY-MM-DD`';
    violations.push(`${rel}: missing required pubDate (${hint})`);
  }
}

if (violations.length) {
  console.error('\n❌ Frontmatter validation failed. `pubDate` is required for all blog posts.\n');
  for (const v of violations) console.error(`- ${v}`);
  console.error('\nFix the items above, then push again.\n');
  process.exit(1);
}

console.log(`✅ Frontmatter validation passed (${files.length} file(s)).`);
