#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require("fs");
const path = require("path");

const agentsRoot = "/root/.openclaw/agents";

function listSessionStores(root) {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(root, entry.name, "sessions", "sessions.json"))
    .filter((file) => fs.existsSync(file));
}

function resolveBackfillTs(entry, stat) {
  if (typeof entry.updatedAt === "number" && Number.isFinite(entry.updatedAt) && entry.updatedAt > 0) return entry.updatedAt;
  const mtimeMs = stat?.mtimeMs;
  if (typeof mtimeMs === "number" && Number.isFinite(mtimeMs) && mtimeMs > 0) return Math.round(mtimeMs);
  return Date.now();
}

const stores = listSessionStores(agentsRoot);
const results = [];

for (const file of stores) {
  const raw = fs.readFileSync(file, "utf8");
  const stat = fs.statSync(file);
  const data = JSON.parse(raw);
  let changed = 0;
  let candidates = 0;

  for (const entry of Object.values(data)) {
    if (!entry || typeof entry !== "object") continue;
    const hasFallbackState = Boolean(entry.fallbackNoticeSelectedModel || entry.fallbackNoticeActiveModel || entry.fallbackNoticeReason);
    if (!hasFallbackState) continue;
    candidates += 1;
    const hasChangedAt = typeof entry.fallbackNoticeChangedAt === "number" && Number.isFinite(entry.fallbackNoticeChangedAt);
    if (hasChangedAt) continue;
    entry.fallbackNoticeChangedAt = resolveBackfillTs(entry, stat);
    changed += 1;
  }

  if (changed > 0) fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n", "utf8");
  results.push({ file, candidates, changed });
}

for (const result of results) {
  console.log(JSON.stringify(result));
}

const summary = results.reduce((acc, result) => {
  acc.candidates += result.candidates;
  acc.changed += result.changed;
  return acc;
}, { candidates: 0, changed: 0 });

console.log(JSON.stringify({ summary }));
NODE
