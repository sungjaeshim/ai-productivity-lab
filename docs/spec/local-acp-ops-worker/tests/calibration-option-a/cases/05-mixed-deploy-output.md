# Case 05 - Mixed Deploy Output Style

## Input
```text
Deploy started: service=checkout env=staging sha=9c2ab7f
[build] npm ci complete
[build] tests passed=128 failed=0
[k8s] rollout status: waiting for deployment "checkout" rollout to finish: 1 old replica is pending termination
operator-note: previous canary looked slow but no rollback yet
[k8s] warning: readiness probe failed on pod checkout-6f7d9c8b5d-x2lqv timeout after 5s
[k8s] rollout status: deployment "checkout" successfully rolled out
```

## Intended Worker Path
`local-ops-triage -> local-ops-summarizer`

## Expected Validation Checklist
- triage `input_class = deploy_output`
- triage route = `local-ops-summarizer`
- summarizer treats final state as bounded and mixed: rollout succeeded with readiness warning during deploy
- facts distinguish build success, temporary readiness issue, and final rollout success
- inferred state may note transient degradation risk, not final failure
- escalation is optional and should depend on evidence conflict, not on any single warning line

## Common Failure Modes
- declares failure because a warning appears before the final success line
- declares fully healthy and drops the readiness warning
- routes to patterns even though repetition is not the main question
- ignores the human note or treats it as hard evidence
