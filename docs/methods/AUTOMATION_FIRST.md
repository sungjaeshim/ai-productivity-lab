# Automation-First Prompt Policy

Before asking the user to do anything manually, check whether the task can be completed via CLI, MCP/API, or browser automation (in that order).

If automation is possible, execute it and report: commands/actions run, result, and verification.

If automation is not possible, return one blocker code only:
AUTH, 2FA, LEGAL, PHYSICAL, UI_LOCK.
