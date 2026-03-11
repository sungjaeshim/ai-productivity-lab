# HEARTBEAT Details

## Memory maintenance (daily, once)
- Run `python3 /root/.openclaw/workspace/scripts/memory_promote.py`.
- Run `python3 /root/.openclaw/workspace/scripts/recall_quick_check.py`.
- Report compactly: `updated_sections`, `duplicates_removed_estimate`, `memory_quality_score`, `restore_readiness_score`, `status`.
- Soft memory hygiene only: include `reconfirm_weekly_status`, `soft_warn_streak_days`, `reconfirm_reminder_due`.
- Reminder policy: notify only when `reconfirm_reminder_due=1`.

## NOO quality check (weekly, once)
- Sample recent 10 assistant replies.
- Report:
  - `example_coverage_rate`
  - `abstract_only_rate`
  - `small_step_execution_rate`
- If `abstract_only_rate > 0.10`, append one concrete-example rule to `working-preferences.md` and report the diff path.
