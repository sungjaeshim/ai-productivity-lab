# Local Rescue Runtime Snapshot

This snapshot stores the patched OpenClaw `dist` bundles that harden the `local-rescue` lane.

Included behavior:
- fresh `local-rescue` run sessions
- reduced `local-rescue` prompt mode
- Ollama `stream:false` for `local-rescue`
- Ollama `num_ctx=4096` for `local-rescue`
- `local-rescue` default timeout pinned to `15s`

Restore command:

```bash
bash /root/.openclaw/workspace/scripts/reapply-local-rescue-runtime.sh
```

Verify snapshot only:

```bash
bash /root/.openclaw/workspace/scripts/reapply-local-rescue-runtime.sh --verify-only
```

Notes:
- This snapshot is tied to the current OpenClaw dist chunk names.
- If an update changes hashed dist filenames, the restore script will stop and ask for a new baseline instead of guessing.
