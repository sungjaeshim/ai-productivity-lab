# Runtime Stability Guard

When OpenAI/Codex returns `server_error`:
1. Retry exactly once with compact context.
2. If it fails again, stop auto-retries and report request_id + short cause.
