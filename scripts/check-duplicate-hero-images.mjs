#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const BLOG_DIR = path.resolve('src/content/blog');

function getMarkdownFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .map((name) => path.join(dir, name));
}

function extractFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : '';
}

function extractHeroImage(frontmatter) {
  const match = frontmatter.match(/^heroImage:\s*(.+)$/m);
  if (!match) return null;

  // Keep exact-match semantics: only trim outer quotes/whitespace.
  return match[1].trim().replace(/^['"]|['"]$/g, '');
}

const files = getMarkdownFiles(BLOG_DIR);
const imageToFiles = new Map();
const targetFiles = process.argv.slice(2).map((f) => path.normalize(f));
const targetSet = new Set(targetFiles);

for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  const frontmatter = extractFrontmatter(content);
  const heroImage = extractHeroImage(frontmatter);

  if (!heroImage) continue;

  if (!imageToFiles.has(heroImage)) imageToFiles.set(heroImage, []);
  imageToFiles.get(heroImage).push(path.relative(process.cwd(), file));
}

const duplicates = [...imageToFiles.entries()].filter(([, linkedFiles]) => {
  if (linkedFiles.length <= 1) return false;

  // No target files passed => enforce globally.
  if (targetSet.size === 0) return true;

  // Target files passed => fail only when changed files are involved.
  return linkedFiles.some((file) => targetSet.has(path.normalize(file)));
});

if (duplicates.length === 0) {
  if (targetSet.size === 0) {
    console.log('✅ No exact duplicate heroImage values found.');
  } else {
    console.log('✅ No exact duplicate heroImage values found in changed posts.');
  }
  process.exit(0);
}

console.error('❌ Exact duplicate heroImage values detected:');
for (const [image, linkedFiles] of duplicates) {
  console.error(`\nheroImage: ${image}`);
  for (const file of linkedFiles) {
    const marker = targetSet.has(path.normalize(file)) ? ' (changed)' : '';
    console.error(`  - ${file}${marker}`);
  }
}

process.exit(1);
