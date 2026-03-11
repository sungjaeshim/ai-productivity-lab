# Product Delivery Gate Template

## RFE Gate
1. What exact user/business pain are we solving now?
2. What are North Star, Guardrail, and Kill Metric?
3. What happens under offline/timeout/retry/refund edge cases?
4. Any legal/privacy/compliance risk?
5. Is rollback + observability plan ready before implementation?

## RFT Gate
A. Feature Flag exists and can disable immediately.
B. Canary/gradual rollout plan is defined.
C. One-command rollback and owner/on-call are assigned.

## FUT Decision
- FL: North Star improves and all Guardrails are healthy.
- FNL: Kill Metric triggered or Guardrail degraded.
