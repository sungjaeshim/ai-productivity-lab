#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const defaultBlogDir = path.join(repoRoot, 'src/content/blog');
const defaultFallback = '/og-default.png';

function collectContentFiles(dirPath) {
  if (!fs.existsSync(dirPath)) return [];
  return fs
    .readdirSync(dirPath)
    .filter((name) => name.endsWith('.md') || name.endsWith('.mdx'))
    .map((name) => path.join(dirPath, name));
}

function resolveInputFiles(argvFiles) {
  if (!argvFiles.length) return collectContentFiles(defaultBlogDir);
  return argvFiles
    .map((file) => (path.isAbsolute(file) ? file : path.join(repoRoot, file)))
    .filter((file) => file.endsWith('.md') || file.endsWith('.mdx'))
    .filter((file) => fs.existsSync(file));
}

function parseArgs(argv) {
  let replaceWith = defaultFallback;
  let dryRun = false;
  const files = [];

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--replace-with') {
      replaceWith = argv[i + 1] || defaultFallback;
      i += 1;
      continue;
    }
    if (arg === '--dry-run') {
      dryRun = true;
      continue;
    }
    files.push(arg);
  }

  return { replaceWith, dryRun, files };
}

function extractFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : null;
}

function extractHeroImage(frontmatter) {
  const match = frontmatter?.match(/^heroImage:\s*(.+)$/m);
  if (!match) return null;
  return match[1].trim().replace(/^['"]|['"]$/g, '');
}

async function checkRemoteImage(url) {
  const headers = { 'user-agent': 'AI Snowball hero-image fixer' };

  try {
    const headResponse = await fetch(url, {
      method: 'HEAD',
      headers,
      redirect: 'follow',
      signal: AbortSignal.timeout(15000),
    });
    if (headResponse.ok) {
      return { ok: true, status: headResponse.status };
    }
  } catch {
    // Fall through to GET when HEAD is blocked or times out.
  }

  const getResponse = await fetch(url, {
    method: 'GET',
    headers,
    redirect: 'follow',
    signal: AbortSignal.timeout(15000),
  });
  return { ok: getResponse.ok, status: getResponse.status };
}

const { replaceWith, dryRun, files: argvFiles } = parseArgs(process.argv.slice(2));
const files = resolveInputFiles(argvFiles);

if (!files.length) {
  console.log('INFO: No blog files to process.');
  process.exit(0);
}

const changedFiles = [];

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const frontmatter = extractFrontmatter(raw);
  const heroImage = extractHeroImage(frontmatter);

  if (!heroImage || !/^https?:\/\//.test(heroImage)) continue;

  let isBroken = false;
  try {
    const result = await checkRemoteImage(heroImage);
    isBroken = !result.ok;
  } catch {
    isBroken = true;
  }

  if (!isBroken) continue;

  const updated = raw.replace(
    /^heroImage:\s*(.+)$/m,
    `heroImage: "${replaceWith}"`,
  );

  if (updated === raw) continue;

  changedFiles.push(path.relative(repoRoot, file));

  if (!dryRun) {
    fs.writeFileSync(file, updated, 'utf8');
  }
}

if (!changedFiles.length) {
  console.log('OK: No broken remote hero images required fixing.');
  process.exit(0);
}

console.log(`${dryRun ? 'DRY_RUN' : 'OK'}: ${changedFiles.length} file(s) updated to ${replaceWith}`);
for (const file of changedFiles) console.log(`- ${file}`);
