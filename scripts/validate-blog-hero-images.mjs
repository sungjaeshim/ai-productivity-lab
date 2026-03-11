#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const defaultBlogDir = path.join(repoRoot, 'src/content/blog');
const publicDir = path.join(repoRoot, 'public');

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

function extractFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : null;
}

function extractTitle(frontmatter) {
  const match = frontmatter?.match(/^title:\s*(.+)$/m);
  return match ? match[1].trim().replace(/^['"]|['"]$/g, '') : null;
}

function extractHeroImage(frontmatter) {
  const match = frontmatter?.match(/^heroImage:\s*(.+)$/m);
  if (!match) return null;
  return match[1].trim().replace(/^['"]|['"]$/g, '');
}

async function checkRemoteImage(url) {
  const headers = { 'user-agent': 'AI Snowball hero-image validator' };

  try {
    const headResponse = await fetch(url, {
      method: 'HEAD',
      headers,
      redirect: 'follow',
      signal: AbortSignal.timeout(15000),
    });

    if (headResponse.ok) {
      return { ok: true, status: headResponse.status, finalUrl: headResponse.url };
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

  return { ok: getResponse.ok, status: getResponse.status, finalUrl: getResponse.url };
}

function checkLocalImage(url) {
  const relativePath = url.replace(/^\/+/, '');
  const resolvedPath = path.join(publicDir, relativePath);
  return {
    ok: fs.existsSync(resolvedPath),
    resolvedPath,
  };
}

const args = process.argv.slice(2);
const files = resolveInputFiles(args);

if (!files.length) {
  console.log('INFO: No blog files to validate.');
  process.exit(0);
}

const violations = [];

for (const file of files) {
  const rel = path.relative(repoRoot, file);
  const raw = fs.readFileSync(file, 'utf8');
  const fm = extractFrontmatter(raw);
  const heroImage = extractHeroImage(fm);
  const title = extractTitle(fm) || rel;

  if (!heroImage) continue;

  if (/^https?:\/\//.test(heroImage)) {
    try {
      const result = await checkRemoteImage(heroImage);
      if (!result.ok) {
        violations.push(`${rel}: heroImage returned HTTP ${result.status} (${title}) -> ${heroImage}`);
      }
    } catch (error) {
      violations.push(`${rel}: heroImage check failed (${title}) -> ${heroImage} :: ${error.message}`);
    }
    continue;
  }

  if (heroImage.startsWith('/')) {
    const result = checkLocalImage(heroImage);
    if (!result.ok) {
      violations.push(`${rel}: heroImage file not found (${title}) -> ${heroImage} => ${result.resolvedPath}`);
    }
    continue;
  }

  violations.push(`${rel}: unsupported heroImage path format (${title}) -> ${heroImage}`);
}

if (violations.length) {
  console.error('\nERROR: Hero image validation failed.\n');
  for (const violation of violations) console.error(`- ${violation}`);
  console.error('\nFix the items above, then rerun validation.\n');
  process.exit(1);
}

console.log(`OK: Hero image validation passed (${files.length} file(s)).`);
