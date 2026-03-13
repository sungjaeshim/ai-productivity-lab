# GitHub Vercel Release Workflow

## Canonical Repos

- `growth-center`
  - local: `/root/.openclaw/workspace/growth-center`
  - github: `sungjaeshim/growth-center`
  - vercel: `growth-center`
  - legacy local clone: `/root/Projects/growth-center` (compat/migration only; not the release source of truth)

- `blog-aisnowball`
  - local: `/root/.openclaw/workspace/ai-productivity-lab`
  - github: `sungjaeshim/ai-productivity-lab`
  - vercel: `blog-aisnowball`

The root workspace is not a release repo.
Do not deploy the blog from `/root/.openclaw/workspace` itself.
Use the nested canonical repo `/root/.openclaw/workspace/ai-productivity-lab`.

## Commands

Audit:

```bash
bash /root/.openclaw/workspace/scripts/github-vercel-audit.sh
```

Dry-run:

```bash
bash /root/.openclaw/workspace/scripts/repo-backup-release.sh growth-center --dry-run
bash /root/.openclaw/workspace/scripts/repo-backup-release.sh blog-aisnowball --dry-run
```

Run wrappers:

```bash
bash /root/.openclaw/workspace/scripts/growth-center-auto-backup.sh
bash /root/.openclaw/workspace/scripts/blog-aisnowball-auto-backup.sh
```

## Flow

1. Create timestamped tar.gz backup.
2. Stage tracked changes.
3. Commit with GitHub/Vercel-compatible author.
4. Pull rebase and push.
5. Run repo-specific production release command.

## Notes

- `growth-center` uses `bash scripts/release-prod.sh`
- Treat `/root/.openclaw/workspace/growth-center` as the only local release source of truth.
- Treat `/root/Projects/growth-center` as a legacy clone. Keep only migration-only notes/wrappers there and migrate any reusable test or release assets into the canonical repo before cleanup.
- `blog-aisnowball` uses `vercel --prod --yes`
- For the blog, automation is enabled only on the nested canonical repo.
- The root workspace may still contain blog-related source files for ops context, but it is not the deploy target.

## growth-center Legacy Cleanup

- Keep `/root/.openclaw/workspace/growth-center` as the only repo for new edits, release, and test execution.
- Keep `/root/Projects/growth-center` only while `.env`, wrappers, or operator references still depend on it.
- Migrate reusable assets from the legacy clone before cleanup.
  Current migrated set: `playwright.prod.config.ts`, `tests/prod-smoke.spec.ts`, `test:prod-smoke`.
- Remove or update lingering references to `/root/Projects/growth-center` in docs, services, and helper scripts.
- Do not use the legacy clone for debugging result mismatches unless the task is specifically about migration or cleanup.
