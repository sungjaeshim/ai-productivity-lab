# MEMORY_RECALL_ROUTING.md

## Purpose

This document defines the **soft recall-intent routing** rules for memory usage.
It is intentionally lightweight and operational.

The goal is simple:

When a user asks a question, do not recall everything equally.
Prefer the most relevant memory layer first.

---

## Core Rule

Before answering questions about prior work, decisions, dates, people, preferences, or todos:

1. infer likely recall intent
2. prioritize the matching memory sections
3. run `memory_search`
4. pull only needed snippets with `memory_get`
5. answer using the most relevant memory class first

If confidence is low, say so.

---

## Recall Intent Types

### 1. Preference
Used when the user is asking about style, format, naming, likes/dislikes, or communication preference.

Typical triggers:

- 선호
- 좋아해
- 싫어해
- 어떻게 불러
- 호칭
- 스타일
- 형식
- 짧게
- 길게
- 구조화

Preferred sources:

1. `MEMORY.md -> Identity / Relationship Invariants`
2. `MEMORY.md -> User Preferences`
3. recent daily `Memory Applied`

Query hint examples:

- `user preference response structure style format`
- `structured summary preference cognitive load`
- `호칭 선호 응답 형식`

---

### 2. Decision Rationale
Used when the user asks why something was done or what background led to a decision.

Typical triggers:

- 왜
- 이유
- 배경
- 왜 그렇게 했지
- 왜 그렇게 결정했어

Preferred sources:

1. `MEMORY.md -> Decision Rationales`
2. `MEMORY.md -> Confirmed Decisions`
3. daily `Decisions`

Query hint examples:

- `decision rationale why background`
- `taskization rationale approval evidence separation`
- `왜 그렇게 결정 이유 배경`

---

### 3. Rule / SOP
Used when the user asks how to proceed, what the rule is, or what execution standard should apply.

Typical triggers:

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
3. `docs/ops/*`

Query hint examples:

- `operating rule sop procedure`
- `how should we run this task`
- `어떻게 절차 운영 규칙`

---

### 4. Active Context
Used when the user asks what is ongoing, blocked, pending, or recently active.

Typical triggers:

- 지금 뭐 진행 중
- 상태 어때
- 막힌 거 있어
- 현재 상황
- 최근 뭐 했어
- 열린 루프

Preferred sources:

1. `MEMORY.md -> Active Context`
2. today/yesterday daily `Active Tasks / WIP`
3. daily `Open Loops`

Query hint examples:

- `active context current status blocker`
- `open loops today pending`
- `지금 상태 진행중 blocker`

---

### 5. Identity / Relationship
Used when the user asks about persona, relationship, stance, or interaction consistency.

Typical triggers:

- 너는 어떤 존재야
- 우리 방식
- 너답게
- 관계에서 중요한 것
- 너의 태도

Preferred sources:

1. `SOUL.md`
2. `MEMORY.md -> Identity / Relationship Invariants`
3. `USER.md`

Query hint examples:

- `identity relationship invariant`
- `persona relationship user interaction`
- `우리 방식 관계 정체성`

---

### 6. Factual Memory
Used when the user needs a date, name, concrete event, or plain recall.

Typical triggers:

- 언제
- 누가
- 뭐였지
- 날짜
- 이름
- 어떤 이슈

Preferred sources:

1. `memory_search`
2. matching daily notes
3. `MEMORY.md` matching sections

Query hint examples:

- `date issue event name`
- `언제 누구 어떤 이슈`

---

## Routing Strategy

This is **soft routing**, not hard classification.

Rules:

- Prefer one primary intent.
- Allow one secondary intent when needed.
- If uncertain, search mixed queries rather than overcommitting.
- Do not force a single memory class when the question is clearly hybrid.

Examples:

- “왜 큰 작업은 task로 먼저 분리하자고 했지?”
  - primary: Decision Rationale
  - secondary: Rule / SOP

- “내가 답변 형식을 어떻게 좋아한다고 했지?”
  - primary: Preference
  - secondary: Identity / Relationship

- “지금 메모리 개편 관련 열린 루프 뭐 있어?”
  - primary: Active Context
  - secondary: Rule / SOP

---

## Operational Workflow

Recommended workflow before answering:

1. classify likely recall intent
2. choose top source order
3. run focused `memory_search`
4. pull exact lines with `memory_get` if needed
5. answer with the most relevant memory class first
6. if memory materially changed the answer, consider recording it in daily `Memory Applied`
7. if memory should have been used but was missed, consider recording a `Recall Miss`

---

## Failure Handling

If the search is weak or mixed:

- say you checked memory
- state uncertainty briefly
- avoid pretending confidence
- if necessary, use fallback phrasing such as:
  - “I checked the available memory, and the strongest match suggests…”
  - “I checked memory, but confidence is low; here’s the best current reading…”

---

## What Not To Do

- Do not invent memory when evidence is weak.
- Do not answer preference questions only with factual events.
- Do not answer rationale questions only with decisions.
- Do not answer process questions only with active context.
- Do not overload the user with every matched memory snippet.

---

## Recommended Future Upgrade

After v0.1 operational adoption, consider:

- semi-automatic query expansion by recall intent
- weekly routing quality review
- recall miss pattern clustering
- promotion weighting by repeated routed reuse

---

## One-Line Summary

Recall routing works when the right kind of memory is consulted first, not when all memory is treated the same.
