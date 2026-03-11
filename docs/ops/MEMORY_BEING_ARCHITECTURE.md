# MEMORY_BEING_ARCHITECTURE.md

## Purpose

This document defines the **Memory Efficacy Layer v0.1** for the workspace.
The goal is not to replace the existing memory infrastructure, but to ensure that memory changes behavior.

In short:

- Storage is already sufficient.
- Retrieval is already sufficient.
- Promotion exists.
- What is missing is identity reflection, recall intent routing, and behavior-change verification.

---

## Design Principle

Do not build a brand-new memory system.
Add a lightweight operating layer on top of the current one.

Target flow:

`Capture -> Distill -> Route by Recall Intent -> Apply -> Verify -> Promote/Demote`

Compared to the previous flow:

`Capture -> Store -> Search -> Promote`

The newly emphasized stages are:

1. **Route by Recall Intent**
2. **Apply**
3. **Verify**

---

## Core Concepts

### 1. Recall Intent
Questions should not recall all memory equally.
The system should prefer different memory sections depending on the user’s purpose.

Recall intent categories:

- **Preference**: preferences, style, format, naming, dislikes
- **Decision Rationale**: why a decision was made, background, reasoning
- **Rule / SOP**: procedure, operating rule, execution standard
- **Active Context**: current status, blockers, ongoing work, open loops
- **Identity / Relationship**: stable relationship rules, persona alignment, interaction invariants
- **Factual Memory**: names, dates, direct facts

### 2. Memory Applied
Memory is not only something that exists.
It should be recorded when it actually changes a response or action.

Typical examples:

- Structured summary-first response was applied.
- Approval-before-side-effects rule was applied.
- Non-trivial work was taskized before execution.

### 3. Promotion Candidate
A memory candidate is not promoted just because it is true.
It should be promoted when it is reusable, behavior-changing, or relationship-forming.

### 4. Recall Miss
Recall failure is not only search failure.
It also includes situations where the right memory likely existed but was not operationally applied.

---

## Memory Taxonomy

### Identity / Relationship Invariants
Top-level rules that should remain stable in this relationship.
These are not just facts; they guide how the assistant should behave.

Examples:

- Prefer structured summary-first replies.
- Prefer isolated task execution for non-trivial work.
- Ask before external send, restart, cron side effects, or other impactful actions.

### User Preferences
Stable user-facing preferences, such as response structure, detail level, or communication style.

### Confirmed Decisions
Explicit choices or approvals made by the user.

### Operating Rules
Reusable execution rules and learned SOPs.

### Decision Rationales
Why a choice was made.
This section exists to preserve reasoning, not only outcomes.

### Active Context
Short-horizon state, blockers, work in progress, or recently relevant context.

### Reused Memory Signals
Memories repeatedly applied in real work.
This helps determine durable promotion strength.

### Demotion Watchlist
Old or low-value memory candidates that may no longer deserve active long-term placement.

---

## Recall Intent Routing

This is intentionally lightweight in v0.1.
Start with soft routing rules before adding any heavy automation.

### Preference Route
Trigger examples:

- 선호
- 좋아해
- 싫어해
- 호칭
- 스타일
- 형식
- 짧게
- 길게
- 구조화

Preferred sources:

1. `MEMORY.md -> Identity / Relationship Invariants`
2. `MEMORY.md -> User Preferences`
3. Recent daily `Memory Applied`

### Decision Rationale Route
Trigger examples:

- 왜
- 이유
- 배경
- 왜 그렇게 했지
- 왜 그렇게 결정했어

Preferred sources:

1. `MEMORY.md -> Decision Rationales`
2. `MEMORY.md -> Confirmed Decisions`
3. Daily `Decisions`

### Rule / SOP Route
Trigger examples:

- 어떻게
- 절차
- 규칙
- 원칙
- SOP
- 기준
- 운영 방식

Preferred sources:

1. `MEMORY.md -> Operating Rules`
2. `AGENTS.md`
3. Relevant `docs/ops/*`

### Active Context Route
Trigger examples:

- 지금 뭐 진행 중
- 상태 어때
- 막힌 거 있어
- 현재 상황
- 최근 뭐 했어

Preferred sources:

1. `MEMORY.md -> Active Context`
2. Today/yesterday daily `Active Tasks / WIP`
3. Daily `Open Loops`

### Identity / Relationship Route
Trigger examples:

- 너는 어떤 존재야
- 우리 방식
- 너답게
- 관계에서 중요한 것

Preferred sources:

1. `SOUL.md`
2. `MEMORY.md -> Identity / Relationship Invariants`
3. `USER.md`

---

## Promotion Rules (Efficacy-Aware)

Promotion should favor memory that changes future behavior.

### Promote immediately when:

- The user explicitly states a durable preference.
- The user explicitly approves an operating principle.
- The memory repeatedly changes execution behavior.
- The memory meaningfully shapes the relationship.

### Promote conditionally when:

- The pattern is reused at least twice.
- Weekly review confirms operational reuse.
- The item helps prevent repeated mistakes.

### Defer when:

- It is interesting but one-off.
- It is factual but low-impact.
- It is active context rather than durable memory.

Promotion checklist:

1. Does it change future behavior?
2. Is it reusable beyond a single event?
3. Was it explicit or repeatedly demonstrated?
4. Would forgetting it likely repeat a mistake?
5. Does it reinforce identity or relationship consistency?

---

## Demotion Rules

A memory may move to watchlist or be demoted when:

- It has not been reused for 14+ days.
- It was temporary active context.
- Its operational value faded.
- It is absorbed by a more general invariant or rule.

---

## Daily Memory Operations

Daily notes should include not only events, but memory efficacy signals.

Recommended sections:

- `## Decisions`
- `## Blockers`
- `## Active Tasks / WIP`
- `## Open Loops`
- `## Memory Applied`
- `## Promotion Candidates`
- `## Recall Misses`

### Meaning of the added sections

#### Open Loops
Unresolved questions, pending approvals, or follow-up items.

#### Memory Applied
Record memory that actually affected response or execution.

#### Promotion Candidates
Durable candidates for `MEMORY.md` promotion.

#### Recall Misses
Cases where the right memory should have been applied but was not.

---

## Weekly Review

Weekly review should evaluate memory efficacy, not only collection volume.

Recommended sections:

1. 이번 주 새로 배운 것
2. 이번 주 실제로 재사용한 기억
3. 장기기억 후보
4. 잊어도 되는 기억
5. 정체성/선호 업데이트 후보

Suggested metrics:

- reused memory count
- promotion candidate count
- recall miss count
- demotion candidate count
- identity candidate count

Reference template:

- `docs/ops/MEMORY_WEEKLY_TEMPLATE.md`
- `docs/ops/MEMORY_RECALL_ROUTING.md`

---

## Verification Standard

This system is working if memory measurably changes behavior.

Examples of evidence:

- A reply structure changes because a known user preference was applied.
- A task is isolated because a known operating rule was applied.
- A side-effecting action is paused for approval because the rule was remembered.
- A weekly review identifies actually reused memory rather than only newly stored memory.

---

## Rollout Plan

### Phase 1
- Expand `MEMORY.md`
- Expand daily note structure
- Standardize weekly review sections
- Create this architecture document

### Phase 2
- Apply soft recall-intent routing operationally
- Prefer intent-aware memory lookup order

### Phase 3
- Review one week of `Memory Applied` and `Recall Misses`
- Strengthen promotion/demotion based on reuse

---

## One-Line Summary

The purpose of this architecture is not to remember more.
It is to make memory visibly change responses, decisions, and behavior.
