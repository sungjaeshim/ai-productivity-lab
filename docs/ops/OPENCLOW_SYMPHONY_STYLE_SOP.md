# OpenClaw SOP — Symphony-style Task Operations

## Purpose
Turn complex work into managed tasks rather than ad-hoc chat execution.
Keep the main session focused on control, prioritization, approvals, and concise reporting.

---

## 1. Core Rule
If a request is likely to:
- take more than 10 minutes,
- modify code or configuration,
- require verification evidence,
- touch multiple files/systems,
- or benefit from parallel execution,

then convert it into a **task run** instead of handling it entirely inline.

**Default split**
- Small/simple work → handle in main session.
- Complex/risky/long work → isolated run first.

---

## 2. Operating Model
```text
User request
→ Task envelope
→ Isolated execution
→ Evidence collection
→ Concise result report
→ Approval gate (if needed)
→ Apply / ship / close
```

The chat is the **control tower**, not the full execution surface.

---

## 3. Task Envelope (required for non-trivial work)
Before execution, define these 4 items:

### 3.1 Goal
What outcome must exist when the task is done?

### 3.2 Scope
What files, systems, channels, repos, or environments are in-bounds?

### 3.3 Done Condition
What exact result counts as complete?

### 3.4 Evidence
What proof must be returned?

### Template
```text
Task: <short title>
Goal: <target outcome>
Scope: <in/out of scope>
Done: <completion condition>
Evidence: <logs/tests/diff/links/screenshots/message ids>
```

### Example
```text
Task: Harden KIS dry_run safety checks
Goal: Prevent unsafe execution path before live trade route
Scope: scripts/, tests/, docs/
Done: tests pass + behavior validated + changes summarized
Evidence: git diff, test output, changed files list
```

---

## 4. Isolated Run First
Use isolated execution (`sessions_spawn`, sub-agent, ACP runtime, or equivalent) when:
- writing/refactoring code,
- exploring a large codebase,
- handling multi-step diagnostics,
- running a risky or noisy workflow,
- or doing work that should not pollute the main chat.

### Why
- reduces main-session noise,
- limits blast radius,
- preserves task context,
- makes result review easier.

---

## 5. Proof Bundle (mandatory completion format)
Every non-trivial task must return a result in 4 blocks:

### 5.1 Changes
What changed?

### 5.2 Verification
What was tested/checked?

### 5.3 Result
Did it work? What is now true?

### 5.4 Risk / Follow-up
What remains uncertain, blocked, or optional?

### Template
```text
변경:
- ...

검증:
- ...

결과:
- ...

리스크/후속:
- ...
```

### Example
```text
변경:
- duplication gate script 추가
- CI workflow 추가

검증:
- baseline 0.29%
- PASS @0.50%
- FAIL @0.10% 확인

결과:
- 중복 방지 게이트 정상 동작

리스크/후속:
- threshold는 추후 팀 기준에 맞게 조정 가능
```

---

## 6. Approval Gate (must ask before applying)
Explicit user approval is required before:
- external sends with meaningful impact,
- config changes,
- gateway restart/update,
- destructive actions,
- cron enablement with side effects,
- deployment / merge / publish / moderation action,
- irreversible state changes.

### Principle
Automate execution.
Do **not** automate irreversible decisions.

---

## 7. Main Session Role
The main session should prioritize:
- request intake,
- task shaping,
- choosing A/B path,
- approvals,
- concise reporting,
- cross-task coordination.

The main session should avoid becoming:
- a raw execution log dump,
- a long-running scratchpad,
- a noisy multi-tool transcript.

---

## 8. When to Stay Inline
Do **not** force taskization for:
- one-line fixes,
- pure explanation,
- quick factual lookups,
- tiny edits with obvious validation,
- short decisions that need no evidence bundle.

Use judgment. The rule is not “task everything.”
The rule is “task the work that benefits from isolation and proof.”

---

## 9. Channel / Messaging Rule
Treat delivery as a separate concern from execution.

Always be clear about:
- what result is being reported,
- to which channel,
- with what evidence,
- and whether cross-context restrictions apply.

### Preferred pattern
```text
task result
→ proof bundle
→ channel-specific formatting
→ approved delivery
```

This reduces routing noise and accidental misposts.

---

## 10. Incident Handling Rule
For incidents and unexpected behavior:

```text
incident detected
→ incident task created
→ investigation run isolated
→ evidence + RCA summarized
→ approval for mitigation/change
→ apply fix
```

### Report format
- Symptom
- Evidence
- Likely root cause
- Mitigation applied / proposed
- Remaining risk

Avoid speculative diagnosis when runtime evidence is available.

---

## 11. Adoption Rules (minimum set)
Adopt these immediately:

1. 10min+ work → convert to task.
2. Code/config changes → prefer isolated run.
3. Non-trivial completion → always return proof bundle.
4. External-impact action → require approval.
5. Main session → control/decision/report, not raw execution.

---

## 12. Recommended OpenClaw Mapping
### Use main session for
- triage,
- deciding fast vs thorough path,
- user communication,
- approval collection.

### Use isolated run / sub-agent / ACP for
- coding,
- repo exploration,
- long diagnostics,
- structured remediation.

### Use cron for
- scheduled checks,
- reminders,
- periodic maintenance,
- isolated recurring jobs with controlled output.

### Use proof bundle for
- code change summaries,
- cron/incident outcomes,
- delivery verification,
- RCA reports.

---

## 13. Anti-Patterns
Avoid these:
- doing long work entirely in the main chat,
- reporting “done” without evidence,
- mixing execution logs with user summary,
- sending cross-channel output without delivery plan,
- changing config/restarting first and explaining later.

---

## 14. One-line Philosophy
**Do not change tools first. Change the unit of operation first.**

Manage work.
Not agents.
