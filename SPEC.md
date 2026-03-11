# OpenClaw Workflow Orchestration Specification

Status: Draft v1.0  
Owner: Workspace Automation Team  
Last Updated: 2026-03-05 (KST)

<!-- 고정 규칙: 본문 Markdown은 반드시 영어로 작성하고, 주석은 한국어로만 작성한다. -->
<!-- 변경 금지 정책: English body + Korean comments is mandatory for all future edits. -->

## 1. Problem Statement

This service provides a repeatable, observable, and safe orchestration loop for daily automation work across messaging, workspace files, issue-like task queues, and external APIs.

It solves these operational problems:

- Manual and inconsistent execution of recurring workflows.
- Missing isolation boundaries for long-running agent tasks.
- Weak recovery behavior after restarts or transient provider failures.
- Lack of explicit quality gates before rollout.
- Lack of a shared contract for implementation, operation, and validation.

## 2. Goals and Non-Goals

### 2.1 Goals

- Define one canonical workflow contract (`SPEC.md`) for implementation and operations.
- Provide deterministic orchestration states, transitions, and retry rules.
- Enable dynamic configuration reload with last-known-good fallback.
- Enforce baseline observability and incident response requirements.
- Support safe gradual migration paths (for example `gog` primary + `gws` canary).
- Standardize readiness gates (RFE, RFT, FUT).

### 2.2 Non-Goals

- Building a full multi-tenant control plane.
- Replacing every external tool with in-house integrations.
- Defining UI design systems in this specification.
- Mandating one hardcoded trust posture for all environments.

## 3. System Overview

### 3.1 Main Components

1. **Workflow Contract Loader**  
   Reads and validates this specification and related workflow files.
2. **Config Layer**  
   Resolves runtime settings with deterministic precedence.
3. **Orchestrator**  
   Owns polling, dispatch, retry, reconciliation, and release decisions.
4. **Execution Runner**  
   Runs agent/tool tasks in scoped workspaces.
5. **Workspace Manager**  
   Creates, validates, reuses, and cleans workspaces.
6. **Integration Adapters**  
   Messaging, Google Workspace CLIs (`gog`, `gws`), model providers, and storage.
7. **Observability Layer**  
   Logs, metrics, health snapshots, and operator-facing summaries.

### 3.2 Abstraction Levels

- Policy Layer (business and operational rules)
- Configuration Layer (typed settings)
- Coordination Layer (state machine)
- Execution Layer (task runner)
- Integration Layer (external dependencies)
- Observability Layer (signals and diagnostics)

### 3.3 External Dependencies

- Messaging channels and notification endpoints
- Workspace CLIs and APIs (`gog`, `gws`, others)
- LLM/tool providers
- Local filesystem and optional remote repositories

## 4. Core Domain Model

### 4.1 Entities

- **TaskItem**: `{id, title, source, priority, state, labels, created_at, updated_at}`
- **WorkflowDefinition**: `{config, prompt_template, version}`
- **RunAttempt**: `{task_id, attempt_no, started_at, ended_at, status, error}`
- **LiveSession**: `{session_id, runner_pid, started_at, last_event_at, usage}`
- **RetryEntry**: `{task_id, attempt_no, due_at_ms, reason}`
- **RuntimeState**: `{running, claimed, retry_queue, totals, rate_limits}`
- **WorkspaceRef**: `{workspace_key, path, created_now}`

### 4.2 Stable IDs and Normalization Rules

- IDs must be immutable after creation.
- State names are normalized by `trim + lowercase` for lookup.
- Labels are normalized to lowercase.
- Missing optional values must be represented as `null`, not empty ad-hoc strings.

## 5. Workflow Specification (Repository Contract)

### 5.1 Discovery and Resolution

- Primary workflow file path is explicitly configured when provided.
- Default path is `./SPEC.md`.
- Missing file is a typed startup error.

### 5.2 File Format

- Markdown body with optional YAML front matter.
- Front matter must decode to an object map.
- Parsing errors must be surfaced as typed errors.

### 5.3 Front Matter Schema (Minimum)

- `orchestrator`
- `polling`
- `workspace`
- `hooks`
- `runner`
- `integrations`
- `observability`
- `safety`

Unknown top-level keys are ignored for forward compatibility.

### 5.4 Prompt Template Contract

- Strict template rendering is required.
- Unknown variables are treated as errors.
- Unknown filters are treated as errors.

### 5.5 Validation and Error Surface

Typed errors include:

- `missing_spec_file`
- `spec_parse_error`
- `front_matter_not_object`
- `template_parse_error`
- `template_render_error`

## 6. Configuration Specification

### 6.1 Precedence and Resolution

1. Runtime argument
2. Front matter values
3. Environment indirection (`$VAR_NAME`)
4. Built-in defaults

### 6.2 Dynamic Reload Semantics

- Reload must be attempted on file change.
- Invalid reload must keep the last-known-good effective config.
- Reloaded config applies to future dispatches and retries.

### 6.3 Dispatch Preflight Validation

Every dispatch tick validates:

- Required credentials and endpoints
- Workspace root validity
- Runner command availability
- Concurrency and timeout constraints

If validation fails, dispatch is skipped but reconciliation continues.

## 7. Orchestration State Machine

### 7.1 Internal States

- `Unclaimed`
- `Claimed`
- `Running`
- `RetryQueued`
- `Released`

### 7.2 Run Lifecycle

- `PreparingWorkspace`
- `BuildingContext`
- `LaunchingRunner`
- `Streaming`
- `Finishing`
- terminal: `Succeeded | Failed | TimedOut | Stalled | Canceled`

### 7.3 Transition Triggers

- Poll tick
- Worker normal exit
- Worker abnormal exit
- Retry timer fired
- Reconciliation refresh
- Stall timeout

### 7.4 Idempotency Rules

- A single authority mutates orchestration state.
- No dispatch without `claimed` and `running` checks.
- Reconciliation always executes before dispatch.

## 8. Polling, Scheduling, and Reconciliation

### 8.1 Poll Loop

Tick order:

1. Reconcile active runs
2. Preflight validation
3. Fetch candidates
4. Sort and dispatch
5. Emit observability events

### 8.2 Candidate Selection

Dispatch eligibility requires:

- Required fields present
- Active state and non-terminal state
- Not already running or claimed
- Concurrency slots available
- Blocker policy passed

### 8.3 Concurrency Control

- Global max concurrent workers
- Optional per-state caps
- Deterministic slot accounting

### 8.4 Retry and Backoff

- Continuation retry: fixed short delay
- Failure retry: exponential backoff with cap
- Existing retry timer for a task is canceled before requeue

### 8.5 Active Run Reconciliation

- Stall detection by inactivity threshold
- Terminal-state transition stops worker and performs cleanup policy
- Non-active non-terminal transition stops worker without terminal cleanup

### 8.6 Startup Cleanup

- Sweep terminal workspaces at startup when configured
- Log and continue on cleanup fetch failure

## 9. Workspace Management and Safety

### 9.1 Workspace Layout

- Workspace root is configured and normalized.
- Per-task path uses sanitized stable task key.

### 9.2 Creation and Reuse

- Existing workspace directories are reused.
- Non-directory collisions must fail safely.

### 9.3 Optional Population

- Optional sync/bootstrap hooks may populate workspace content.

### 9.4 Hooks

- `after_create`, `before_run`, `after_run`, `before_remove`
- Hook timeout is mandatory.

### 9.5 Safety Invariants

- Workspace path must remain under configured root.
- Runner cwd must be exactly the scoped workspace path.
- Secrets must never be emitted to logs.

## 10. Runner Protocol (Agent Integration)

### 10.1 Launch Contract

- Command executed via shell in workspace cwd
- Stdout protocol stream separated from stderr diagnostics

### 10.2 Startup Handshake

- Initialization exchange
- Session/thread creation
- Turn/run start with contextual input

### 10.3 Streaming Processing

- Parse complete protocol lines only
- Buffer partial lines until newline
- Terminal events map to normalized statuses

### 10.4 Emitted Runtime Events

- `session_started`
- `run_completed`
- `run_failed`
- `run_cancelled`
- `approval_handled`
- `input_required`
- `malformed_event`

### 10.5 Approval and Input Policy

- Explicit policy required per deployment profile.
- Runs must not stall indefinitely waiting for input.

### 10.6 Timeout and Error Mapping

- `read_timeout`
- `run_timeout`
- `stall_timeout`
- normalized categories for startup, transport, and runtime failures

## 11. Integration Contract

### 11.1 Required Operations

- Candidate fetch/query
- State refresh
- Optional terminal-state fetch for cleanup

### 11.2 Normalization Rules

- External payloads normalized into stable internal model before orchestration logic

### 11.3 Error Handling Contract

- Transport, schema, and semantic errors are mapped to typed categories

### 11.4 Write Boundary

- Orchestrator may read and schedule.
- Task-side writes should happen through explicit tool workflows with guardrails.

## 12. Prompt Construction and Context Assembly

### 12.1 Inputs

- Normalized task object
- Attempt metadata
- Workflow template
- Optional policy fragments

### 12.2 Rendering Rules

- Strict template mode
- Deterministic field inclusion order

### 12.3 Retry Semantics

- First attempt receives full context
- Continuation attempts receive minimal incremental guidance

### 12.4 Failure Semantics

- Template failures fail the attempt and enter retry policy path

## 13. Observability (Logs/Metrics/Status)

### 13.1 Logging Conventions

Structured logs must include:

- `task_id`
- `task_identifier`
- `session_id`
- `attempt_no`
- `state`
- `event`
- `timestamp`

### 13.2 Metrics

- Success/failure counts by class
- Retry queue depth
- Dispatch latency
- Runner active seconds
- Token/usage counters where available

### 13.3 Status Surface

- Optional human-readable dashboard
- Optional JSON snapshot API
- Observability failures must not crash orchestrator

## 14. Failure Model and Recovery Strategy

### 14.1 Failure Classes

- Workflow/config failures
- Workspace failures
- Runner/session failures
- Integration failures
- Observability failures

### 14.2 Recovery Behavior

- Validation failure: skip dispatch, keep reconciliation
- Worker failure: enqueue retry with policy
- Integration fetch failure: skip tick and retry next cycle

### 14.3 Restart Recovery

- In-memory scheduling state is not required to persist
- Recovery is tracker-driven and filesystem-driven

### 14.4 Operator Intervention Points

- Edit workflow/spec files
- Change task states externally
- Trigger controlled restart when needed

## 15. Security and Operational Safety

### 15.1 Trust Boundary

Each deployment must declare:

- trusted or restricted environment profile
- approval posture
- sandbox/isolation posture

### 15.2 Filesystem Safety

- Enforce root containment
- Reject out-of-root cwd usage
- Use sanitized workspace names only

### 15.3 Secret Handling

- Support environment indirection
- Never log secret material

### 15.4 Hook Safety

- Hooks are trusted code
- Timeout and output truncation required

### 15.5 Harness Hardening

Recommended controls:

- least-privilege credentials
- constrained tool surface
- network and filesystem restrictions
- scoped integration permissions

## 16. Reference Algorithms (Pseudo)

### 16.1 Startup

```text
initialize_logging()
load_and_validate_spec()
recover_last_known_good_config()
startup_cleanup_if_enabled()
schedule_tick(0)
```

### 16.2 Poll Tick

```text
reconcile_running()
if not validate_preflight():
  emit_validation_error()
  schedule_next_tick()
  return

candidates = fetch_candidates()
for task in sort_candidates(candidates):
  if slots_available() and should_dispatch(task):
    dispatch(task)

schedule_next_tick()
```

### 16.3 Retry Handling

```text
cancel_existing_retry(task_id)
compute_backoff(attempt_no)
enqueue_retry(task_id, due_at, reason)
```

### 16.4 Reconciliation

```text
for run in running:
  if is_stalled(run):
    stop_and_retry(run)
  else:
    refresh_state(run)
```

## 17. Test and Validation Matrix

### 17.1 Core Conformance

- Workflow load and reload behavior
- Typed config defaults and precedence
- Dispatch/retry/reconciliation state transitions
- Workspace root containment and hook policies
- Runner protocol handling and timeout mapping
- Structured logging correctness

### 17.2 Extension Conformance

- Optional dashboard/API behaviors
- Optional integration adapters and tool extensions

### 17.3 Real Integration Profile

- Credentialed smoke tests with isolated test resources
- Skip reporting must be explicit, never silent

## 18. Implementation Checklist (Definition of Done)

### 18.1 Required

- All core conformance tests passing
- Failure classes mapped and observed
- Retry and reconciliation behavior verified
- Security baseline controls enforced
- Observability signals available to operators

### 18.2 Recommended

- Extension conformance tests passing
- Cost guardrails and budget alerts configured
- Human-readable runbook and rollback playbook published

### 18.3 Operational Validation Before Production

- Execute pre-production real integration checks
- Validate rollback path in under 60 seconds
- Verify RFE, RFT, FUT gate compliance

---

## Appendix A: Product Delivery Gates (Normative)

### A.1 RFE Gate (Before Engineering)

1. Problem and urgency are explicit.
2. North Star, Guardrail, and Kill Metric are defined.
3. Edge cases (timeout/retry/offline/refund-equivalent) are covered.
4. Legal/privacy/compliance posture is defined.
5. Rollback and observability plans exist before implementation.

### A.2 RFT Gate (Before Rollout)

A. Feature flag exists with immediate disable path.  
B. Canary scope and stop conditions are explicit.  
C. One-command rollback and owner/on-call assignment are explicit.

### A.3 FUT Decision (After Experiment)

- **FL**: Launch only if North Star improves and guardrails stay healthy.
- **FNL**: Do not launch if kill metric triggers or guardrails degrade.

<!-- 점검 주석: 위 게이트는 운영 정책과 일치해야 하며 임의 삭제 금지 -->

## Appendix B: Proof of Work (PoW) Evidence Gate (Normative)

### B.1 Objective

PoW is required to make rollout quality auditable, reproducible, and rollback-ready.

### B.2 Evidence Profiles

- **Minimal PoW (speed-first)**
  - CI result
  - Test result summary
  - Change summary
- **Full PoW (quality-first, default for production-bound changes)**
  - CI result
  - PR review evidence
  - Test result summary
  - Change summary
  - Rollback evidence

### B.3 Full PoW Required Fields

1. **CI Evidence**
   - workflow/run identifier
   - final status (`success` required)
2. **PR Review Evidence**
   - reviewer identity
   - review decision (`approved` required)
3. **Test Evidence**
   - test command(s)
   - pass/fail counts
4. **Change Summary Evidence**
   - scope of changed files/components
   - behavior and risk summary
5. **Rollback Evidence**
   - exact rollback command/path
   - verification result from rollback readiness check

### B.4 Gate Decision Rules

- If any required Full PoW field is missing, release decision is blocked.
- If CI or tests are not passing, release decision is blocked.
- If rollback evidence is missing or unverified, release decision is blocked.

### B.5 Automation Hook Contract

The repository must include a machine-checkable PoW validation step that:

- validates required evidence fields for the selected profile,
- exits non-zero on missing/invalid required evidence,
- emits a concise validation report for operators.
