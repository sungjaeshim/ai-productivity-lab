# Ralph Loop + Morning Briefing Approval Workflow v1

Status: draft-for-implementation
Owner: Jarvis
Date: 2026-03-11

## 1. Goal

Nightly Ralph Loop should explore **safe, bounded candidate improvements** without touching production.
Morning Briefing should surface the best candidate in a compact approval-friendly format.
Production changes happen **only after morning human approval**.

In one line:
- **Night = explore and score**
- **Morning = review and approve/reject**
- **Production = change only after approval**

---

## 2. Core Principles

1. **No auto-promote at night**
   - Ralph Loop may generate, score, and shortlist candidates.
   - It must not overwrite production behavior automatically.

2. **Bounded experiment scope**
   - Start with low-risk prompt/template/routing experiments.
   - No gateway config change, restart, delivery-path rewrite, or broad code mutation in v1.

3. **Baseline vs candidate discipline**
   - Every experiment compares candidate against a fixed baseline.
   - Candidate must beat baseline on score and avoid regression gates.

4. **Morning briefing is the approval gate**
   - Best candidate appears in Morning Briefing under a dedicated approval card.
   - User can approve / hold / reject.

5. **Promote only with explicit approval**
   - Approved candidate becomes the new production baseline.
   - Rejected candidate is discarded.
   - Hold keeps it for re-test, not promote.

---

## 3. v1 Experiment Lane

### 3.1 Initial experiment target

Start with **topic routing prompt/rule candidate optimization**.

Why:
- measurable
- low blast radius
- easy to sandbox
- easy to compare against baseline
- aligns with prior routing issues already seen in operations

### 3.2 Allowed changes in v1

Allowed:
- prompt text
- heuristic weights
- few-shot examples
- ranking/selection wording
- evaluation rubric wording

Not allowed in v1:
- gateway config changes
- restart-required changes
- message delivery path rewrites
- cron topology change
- cross-channel routing changes
- multi-file code refactors in production path

---

## 4. State Model

### 4.1 Entities
- **baseline**: current production version
- **candidate**: experimental variant created at night
- **shortlisted**: candidate passed score threshold and regression gate
- **promoted**: approved and applied to production
- **discarded**: rejected or under-threshold candidate
- **held**: promising candidate awaiting more evidence

### 4.2 Transitions
1. baseline -> candidate
2. candidate -> shortlisted if score passes
3. candidate -> discarded if score fails or regression found
4. shortlisted -> promoted if user approves in morning
5. shortlisted -> held if user wants more validation
6. shortlisted -> discarded if user rejects

---

## 5. Nightly Ralph Loop Stage Design

Add a new stage after the existing reflection/improvement logic:

- **Stage X: Candidate Experiment Lane**

### 5.1 Inputs
- fixed experiment target (`topic-routing-v1`)
- production baseline file/spec
- evaluation dataset
- scoring rubric
- previous candidate history (optional)

### 5.2 Night loop steps
1. Load current baseline metadata
2. Select one bounded experiment topic
3. Generate 1~N candidates
4. Evaluate each candidate against the same dataset
5. Compute:
   - quality score
   - regression flags
   - confidence
6. Keep only top candidate if it clears threshold
7. Write result artifacts to state/data path
8. Do **not** apply to production

### 5.3 Required output artifacts
Recommended files:
- `data/ralph-experiments/latest.json`
- `data/ralph-experiments/history.jsonl`
- `data/ralph-experiments/candidates/<date>-<id>.json`

Suggested schema for latest.json:

```json
{
  "date_kst": "2026-03-11",
  "experiment": "topic-routing-v1",
  "baseline": {
    "id": "routing-baseline-001",
    "score": 82.0,
    "version": "prod"
  },
  "best_candidate": {
    "id": "routing-candidate-20260311-a",
    "score": 89.0,
    "delta": 7.0,
    "confidence": "medium",
    "status": "shortlisted",
    "risk_summary": "AC2 과민 라우팅 가능성 소폭",
    "change_summary": "few-shot 2개 추가 + AC2 keyword weight 조정",
    "evidence": {
      "samples": 42,
      "wins": 8,
      "ties": 32,
      "losses": 2
    },
    "recommendation": "promote_if_user_approves"
  }
}
```

---

## 6. Scoring Model v1

### 6.1 Candidate score
Use a simple weighted score first.

Example:
- routing accuracy: 60%
- false positive penalty: 20%
- false negative penalty: 15%
- complexity penalty: 5%

Formula example:

```text
score =
  accuracy * 0.60
  - false_positive_rate * 20
  - false_negative_rate * 15
  - complexity_penalty * 5
```

### 6.2 Promotion threshold
Shortlist only if all are true:
- delta >= +3.0 score
- no critical regression flag
- no duplicate/delivery regression
- evaluation sample size >= minimum threshold

Initial recommended minimums:
- samples >= 30
- losses <= 10% of samples
- critical regression count = 0

### 6.3 Hold rule
If candidate is better but evidence is weak:
- delta >= +2.0 and < +3.0
- or sample size too small
- or one non-critical concern exists

Then set status = `held`, not `promoted`

---

## 7. Morning Briefing Integration

The current Morning Briefing already has:
- headline
- tasks
- daily intelligence
- HQ cards
- `오늘 의사결정 필요`

v1 integration should add a dedicated decision card inside HQ cards.

### 7.1 New HQ card
Title:
- `야간 후보 실험 승인`

Bullets format:
- 후보: `<candidate id / experiment>`
- baseline: `<score>`
- candidate: `<score>`
- 개선폭: `+x.x`
- 변경 내용: `<short summary>`
- 리스크: `<short risk summary>`
- 권장안: `A. 오늘 승인 후 반영 / B. 하루 더 hold / C. 폐기`

### 7.2 If no valid candidate exists
Show:
- `야간 후보 실험: 승인 요청 없음 (기준 미통과 또는 후보 없음)`

### 7.3 Placement
Recommended placement in HQ cards:
1. 시장/시그널
2. 프로젝트 헬스
3. 리스크/장애
4. **야간 후보 실험 승인**
5. 오늘 의사결정 필요
6. 오늘 단일 핵심 액션

This keeps the approval item visible but not more important than system health.

---

## 8. Morning Decision Semantics

The briefing should lead to one of three user decisions.

### A. Approve
Meaning:
- best shortlisted candidate is safe enough
- promote candidate to production baseline
- archive old baseline metadata

### B. Hold
Meaning:
- do not promote yet
- candidate remains stored
- schedule another night validation or expanded eval

### C. Reject
Meaning:
- discard candidate
- keep current production baseline unchanged

---

## 9. Promotion Flow (after approval)

Promotion should be a **separate explicit action**, never bundled into the nightly loop.

### 9.1 Promote steps
1. Read shortlisted candidate artifact
2. Apply approved change to production-controlled file/spec
3. Save previous baseline snapshot/metadata
4. Mark candidate `promoted`
5. Update baseline metadata
6. Append promotion event to history

### 9.2 Discard steps
1. Mark candidate `discarded`
2. Keep baseline unchanged
3. Append discard reason to history

### 9.3 Hold steps
1. Mark candidate `held`
2. Keep baseline unchanged
3. Queue extended evaluation on next eligible night

---

## 10. File and Data Layout v1

Recommended additions:

```text
/root/.openclaw/workspace/
  data/
    ralph-experiments/
      latest.json
      history.jsonl
      candidates/
  docs/ops/
    RALPH_LOOP_MORNING_BRIEFING_APPROVAL_WORKFLOW_V1.md
  scripts/
    ralph_experiment_lane.py
    morning_briefing_experiment_card.py
```

---

## 11. Implementation Plan v1

### Step 1. Build experiment artifact producer
Create `scripts/ralph_experiment_lane.py`

Responsibilities:
- load fixed experiment config
- evaluate baseline vs candidates
- pick best candidate
- write `latest.json` + `history.jsonl`

### Step 2. Add Morning Briefing card injector
Create `scripts/morning_briefing_experiment_card.py`

Responsibilities:
- read `data/ralph-experiments/latest.json`
- convert it to a briefing card payload
- return either:
  - approval card
  - or no-candidate summary

### Step 3. Wire into `build_morning_briefing_payload.py`
- load experiment card helper
- insert `야간 후보 실험 승인` card into HQ cards
- keep fallback behavior when experiment artifact missing

### Step 4. Ralph Loop integration
Wherever Ralph Loop currently runs its nightly stages, add:
- `python3 scripts/ralph_experiment_lane.py --experiment topic-routing-v1`

Important:
- this writes candidate artifacts only
- it must not promote automatically

### Step 5. Morning approval operation
Morning briefing shows the recommendation.
Actual promote/reject action is triggered later by explicit user instruction.

---

## 12. First Pilot Recommendation

### Recommended pilot
- **topic-routing-v1**

### Baseline artifact should include
- current prompt/rule version
- baseline score
- last validated date

### Candidate generation ideas
- add AC2-specific few-shot examples
- rebalance keyword weights
- tighten generic-ideas fallback
- reduce over-routing to broad bucket

### Eval set
- 30~50 recent labeled messages
- include known confusing examples
- include AC2/non-AC2 boundary cases

---

## 13. Guardrails

Must block shortlist/promote if any occurs:
- critical false-route on protected category
- duplicate reply risk increase
- delivery-path side effect
- evaluation sample corruption
- missing baseline artifact

---

## 14. Success Criteria for v1

After 1 week, v1 is successful if:
- Ralph Loop generates nightly candidate artifacts without production drift
- Morning Briefing shows clear approval-ready summaries
- at least 1 candidate reaches shortlist quality
- approval/promote process is understandable in one glance
- no accidental night auto-promotion happens

---

## 15. Operator Summary

The operating contract is simple:

- Ralph Loop explores at night.
- Morning Briefing asks for approval.
- User decides.
- Only then does production change.
