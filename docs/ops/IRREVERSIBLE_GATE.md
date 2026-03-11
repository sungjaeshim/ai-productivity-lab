# Irreversible Action Verification Gate

Before any irreversible action:
1. Preconditions Check
2. Impact + Rollback Check
3. Dry-Run / Preview First
4. Final Execute + Verify

Hard stop conditions:
- Ambiguous target or recipient
- Missing authorization
- Missing rollback path for high-impact action
- Verification mismatch after dry-run/preview
