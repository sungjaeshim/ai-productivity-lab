#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const BLOG_DIR = path.resolve('src/content/blog');

function getContentFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith('.md') || name.endsWith('.mdx'))
    .map((name) => path.join(dir, name));
}

const files = getContentFiles(BLOG_DIR);
const slugMap = new Map();

for (const file of files) {
  const slug = path.parse(file).name;
  if (!slugMap.has(slug)) slugMap.set(slug, []);
  slugMap.get(slug).push(path.relative(process.cwd(), file));
}

const duplicates = [...slugMap.entries()].filter(([, linkedFiles]) => linkedFiles.length > 1);

if (duplicates.length === 0) {
  console.log('✅ No duplicate blog slugs found across .md/.mdx files.');
  process.exit(0);
}

console.error('❌ Duplicate blog slugs detected:');
for (const [slug, linkedFiles] of duplicates) {
  console.error(`\nslug: ${slug}`);
  for (const file of linkedFiles) {
    console.error(`  - ${file}`);
  }
}

process.exit(1);
