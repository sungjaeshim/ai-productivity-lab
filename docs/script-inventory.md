# Script Inventory

Generated: `2026-03-06T05:03:22.550418+00:00`

## Summary

- `keep`: 6
- `dormant`: 47
- `live`: 9
- `hold`: 3
- `canonical`: 1
- `candidate`: 1
- `compat`: 2
- `top_level_scripts`: 69
- `retired_aliases`: 8
- `known_missing_refs`: 5

## Canonical Entrypoints

- `brain`: `brainctl.sh`
- `send`: `sendctl.sh`

## Live

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `brain-discord-autopull.sh` | `brain` | `brainctl.sh` | system |
| `brain-nightly-todo-sync.sh` | `brain` | `brainctl.sh` | system |
| `brainctl.sh` | `brain` | `brainctl.sh` | systemd |
| `cloud-firewall-drift-guard.sh` | `-` | `cloud-firewall-drift-guard.sh` | system |
| `github-ci-monitor.sh` | `-` | `github-ci-monitor.sh` | systemd |
| `nightly-growth-release.sh` | `-` | `nightly-growth-release.sh` | system |
| `post-backup-session-maintenance.sh` | `-` | `post-backup-session-maintenance.sh` | system |
| `ssh_login_notify.sh` | `-` | `ssh_login_notify.sh` | system |
| `strava-webhook-setup.sh` | `-` | `strava-webhook-setup.sh` | systemd |

## Canonical

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `sendctl.sh` | `send` | `sendctl.sh` | docs |

## Compat

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `system-monitor.sh` | `-` | `system-monitor.sh` | docs |
| `todoist-monitor.sh` | `-` | `todoist-monitor.sh` | docs |

## Keep

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `auto-blog-post.sh` | `-` | `auto-blog-post.sh` | - |
| `blog-report.sh` | `-` | `blog-report.sh` | - |
| `check-growth-second-brain-public.sh` | `-` | `check-growth-second-brain-public.sh` | - |
| `enforce-dns-fallback.sh` | `-` | `enforce-dns-fallback.sh` | - |
| `full-backup.sh` | `-` | `full-backup.sh` | - |
| `git-ai-note.sh` | `-` | `git-ai-note.sh` | - |

## Attic Candidate

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `sync-growth-site-second-brain.sh` | `-` | `sync-growth-site-second-brain.sh` | - |

## Hold

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `local-rescue-model-eval.sh` | `-` | `local-rescue-model-eval.sh` | - |
| `telegram-egress-monitor.sh` | `-` | `telegram-egress-monitor.sh` | - |
| `test-send-guard.sh` | `-` | `test-send-guard.sh` | - |

## Dormant

| Script | Family | Canonical | Signals |
|---|---|---|---|
| `brain-auto-route-learn.sh` | `brain` | `brainctl.sh` | internal |
| `brain-content-analyze.sh` | `brain` | `brainctl.sh` | internal |
| `brain-daily-done-summary.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-done-broadcast.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-inbox-resend-clean.sh` | `brain` | `brainctl.sh` | internal |
| `brain-link-ingest.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-note-ingest.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-queue-autoclean.sh` | `brain` | `brainctl.sh` | internal |
| `brain-route-retry.sh` | `brain` | `brainctl.sh` | internal |
| `brain-router-health-monitor.sh` | `brain` | `brainctl.sh` | internal |
| `brain-tag-route.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-telegram-autopull.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-thread-manage.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-todo-reaction-sync.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-todo-route.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-todoist-done-summary.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-todoist-stale-check.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-todoist-sync.sh` | `brain` | `brainctl.sh` | docs, internal |
| `brain-weekly-knowledge-report.sh` | `brain` | `brainctl.sh` | internal |
| `callme-v1-dispatch.sh` | `-` | `callme-v1-dispatch.sh` | docs, internal |
| `callme-v1-healthcheck.sh` | `-` | `callme-v1-healthcheck.sh` | docs |
| `callme-v1-router.js` | `-` | `callme-v1-router.js` | docs, internal |
| `callme-v1-sample-event.sh` | `-` | `callme-v1-sample-event.sh` | docs |
| `daily-intelligence-collector.sh` | `-` | `daily-intelligence-collector.sh` | docs |
| `discord-send-safe.sh` | `-` | `discord-send-safe.sh` | docs, internal |
| `env-loader.sh` | `-` | `env-loader.sh` | docs, internal |
| `growth-center-env-setup.sh` | `-` | `growth-center-env-setup.sh` | docs |
| `health-cross-context.sh` | `-` | `health-cross-context.sh` | docs |
| `incident-db.sh` | `-` | `incident-db.sh` | docs, internal |
| `incident-router.sh` | `-` | `incident-router.sh` | docs |
| `local-rescue-canary.sh` | `-` | `local-rescue-canary.sh` | docs |
| `local-rescue-q35-eval.sh` | `-` | `local-rescue-q35-eval.sh` | docs |
| `log-mistake.sh` | `-` | `log-mistake.sh` | internal |
| `market_sentiment_delta.py` | `-` | `market_sentiment_delta.py` | docs |
| `memory_promote.py` | `-` | `memory_promote.py` | docs |
| `recall_quick_check.py` | `-` | `recall_quick_check.py` | docs |
| `resend-sentry-smoke.sh` | `-` | `resend-sentry-smoke.sh` | docs |
| `safe-autorepair.sh` | `-` | `safe-autorepair.sh` | docs |
| `script_inventory.py` | `-` | `script_inventory.py` | docs |
| `send-briefing.sh` | `send` | `sendctl.sh` | internal |
| `send-guard-observe.sh` | `send` | `sendctl.sh` | internal |
| `send-guarded-message.sh` | `send` | `sendctl.sh` | internal |
| `sentry-smoke-check.sh` | `-` | `sentry-smoke-check.sh` | docs |
| `system-inventory-scan.sh` | `-` | `system-inventory-scan.sh` | docs |
| `token-refresh-all.sh` | `-` | `token-refresh-all.sh` | docs |
| `validate_spec_contract.py` | `-` | `validate_spec_contract.py` | docs |
| `vix_alert.py` | `-` | `vix_alert.py` | docs |

## Orphaned

_None_

## Retired Aliases

| Alias | Replacement | Attic | Mentioned |
|---|---|---|---|
| `monitor-brain-link-ci.sh` | `github-ci-monitor.sh` | `_attic/2026-03/monitor-brain-link-ci.sh` | 3 |
| `auto_post.sh` | `auto-blog-post.sh` | `_attic/2026-03/auto_post.sh` | 0 |
| `batch_posts.py` | `auto-blog-post.sh` | `_attic/2026-03/batch_posts.py` | 0 |
| `fetch_unsplash.py` | `-` | `_attic/2026-03/fetch_unsplash.py` | 0 |
| `memory-grep-search.sh` | `-` | `_attic/2026-03/memory-grep-search.sh` | 0 |
| `cron-daily-diff-report.py` | `-` | `_attic/2026-03/cron-daily-diff-report.py` | 0 |
| `notion_log.py` | `-` | `_attic/2026-03/notion_log.py` | 0 |
| `usdkrw_alert.py` | `-` | `_attic/2026-03/usdkrw_alert.py` | 0 |

## Known Missing Refs

| Missing Name | Replacement | Mentioned | Notes |
|---|---|---|---|
| `refresh-strava-token.sh` | `-` | 0 | Legacy disabled cron payload; no workspace replacement is committed. |
| `check-gmail.py` | `-` | 0 | Legacy disabled cron payload; feature is not implemented in this workspace. |
| `sentiment-gambler.js` | `market_sentiment_delta.py` | 0 | Legacy market sentiment JS path replaced by Python delta script. |
| `tga-fetcher.js` | `-` | 0 | Legacy liquidity fetcher path is absent from the workspace. |
| `nq-macd-analyzer.js` | `/root/.openclaw/scripts/nq_macd_multi.py` | 0 | Legacy Node MACD runner replaced by Python runner outside workspace. |
