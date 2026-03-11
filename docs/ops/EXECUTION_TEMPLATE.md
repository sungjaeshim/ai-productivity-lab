# Execution Template (SPEC-Aligned)

<!-- 규칙: 본문 영어, 주석 한국어 -->

## 0) Context

- Initiative:
- Owner:
- Date:
- Environment:

## 1) RFE Gate (Must pass all)

1. Problem and urgency are explicit.
2. North Star, Guardrail, Kill Metric are defined.
3. Edge cases are defined (timeout/retry/offline/refund-equivalent).
4. Legal/privacy/compliance constraints are defined.
5. Rollback and observability plans are defined before implementation.

## 2) Plan

- Scope in:
- Scope out:
- Dependencies:
- Risk assumptions:

## 3) Execution Steps

1. Validate preconditions.
2. Run implementation task.
3. Run validation checks.
4. Produce rollback proof.

## 4) Validation

- Unit checks:
- Integration checks:
- Spec contract check:
  - `python3 scripts/validate_spec_contract.py`

## 5) RFT Gate (Before rollout)

- [ ] Feature flag / quick disable path
- [ ] Canary scope and stop condition
- [ ] One-command rollback and owner

## 6) FUT Decision

- FL (Launch): North Star improves and guardrails healthy
- FNL (Do not launch): Kill metric triggered or guardrails degraded

## 7) Run Report

- Outcome:
- Metrics:
- Incidents:
- Follow-ups:
