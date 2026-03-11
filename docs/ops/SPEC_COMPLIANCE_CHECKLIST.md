# SPEC Compliance Checklist (Operational)

<!-- 주석 규칙: 본문은 영어, 주석은 한국어 유지 -->

## Scope

This checklist validates that `SPEC.md` follows the adopted orchestration specification structure and language policy.

## Required Structure

- [ ] Section 1: Problem Statement
- [ ] Section 2: Goals and Non-Goals
- [ ] Section 3: System Overview
- [ ] Section 4: Core Domain Model
- [ ] Section 5: Workflow Specification (Repository Contract)
- [ ] Section 6: Configuration Specification
- [ ] Section 7: Orchestration State Machine
- [ ] Section 8: Polling, Scheduling, and Reconciliation
- [ ] Section 9: Workspace Management and Safety
- [ ] Section 10: Runner Protocol (Agent Integration)
- [ ] Section 11: Integration Contract
- [ ] Section 12: Prompt Construction and Context Assembly
- [ ] Section 13: Observability (Logs/Metrics/Status)
- [ ] Section 14: Failure Model and Recovery Strategy
- [ ] Section 15: Security and Operational Safety
- [ ] Section 16: Reference Algorithms (Pseudo)
- [ ] Section 17: Test and Validation Matrix
- [ ] Section 18: Implementation Checklist (Definition of Done)

## Mandatory Gates

- [ ] RFE Gate exists
- [ ] RFT Gate exists
- [ ] FUT Decision exists

## Language Policy

- [ ] Markdown body is English only
- [ ] Korean text appears only inside HTML comments (`<!-- ... -->`)
- [ ] Language policy note exists near the top of `SPEC.md`

## Operational Quality

- [ ] No required section is duplicated with conflicting headings
- [ ] Typed error surface exists for workflow/config/template failures
- [ ] Retry/backoff behavior is defined
- [ ] Reconciliation behavior is defined
- [ ] Security boundary and secret handling are defined
- [ ] Test matrix and DoD are present

## Validation Command

```bash
python3 scripts/validate_spec_contract.py
```

## Pass Criteria

Validation passes only when:

1. Missing required headings = 0
2. Missing mandatory gates = 0
3. Hangul outside HTML comments = 0
4. Exit code = 0
