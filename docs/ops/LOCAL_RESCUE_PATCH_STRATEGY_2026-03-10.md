# Local Rescue Patch Strategy (2026-03-10)

## Summary

Direction is **not full patch removal**.
Direction is:
- keep the 4 core local-rescue policies temporarily,
- treat non-core patches as recovery/removal candidates,
- progressively move behavior back into upstream OpenClaw / official config when supported.

## Core policies to keep temporarily

These are considered part of the current `local-rescue` lane identity:
1. fresh-run / ephemeral session behavior
2. prompt mode `none` / lightweight bootstrap
3. small-context behavior (`num_ctx` policy)
4. non-streaming behavior (`stream:false` policy)

## Current runtime minimum keep-set (installed dist names)

Current installed dist files that repeatedly show the local-rescue policy markers:
- `compact-D3emcZgv.js`
- `reply-DeXK9BLT.js`
- `pi-embedded-CrsFdYam.js`
- `pi-embedded-jHMb7qEG.js`

Interpretation:
- conceptual minimum set = 3 axes (`compact`, `reply`, `pi-embedded`)
- operational current keep-set = 4 files (because `pi-embedded` is split)

## Standard operating path

As of this decision, the standard recovery/restore path for local-rescue runtime is:
- `bash /root/.openclaw/workspace/scripts/reapply-local-rescue-runtime.sh --core-only`

Operational rule:
1. Try `--core-only` first.
2. Validate gateway health and local-rescue behavior.
3. Treat legacy full restore artifacts as archive/reference only unless they are explicitly re-baselined for the current build.

## Legacy restore status

The old full restore path is **not a valid current operational recovery path** for the current build.
Reason:
- legacy target filenames no longer exist in the installed dist,
- full restore currently fails on missing install targets,
- the current operational recovery path is the core-only path.

Therefore the legacy full restore set should be treated as:
- archive/reference material,
- historical comparison data,
- optional future re-baseline input,
not as an active default/fallback recovery path.

## Non-core patch status

The following non-core patch families are now treated as **retired candidates**:
- `model-selection*`
- `gateway-cli*`
- `auth-profiles*`

Reason:
- they are not included in the active core-only recovery model,
- they are not required for current lane identity preservation,
- they belong to a legacy restore path that is no longer operational for the installed build.

## Upstream / officialization direction

Target long-term state:
- keep local-rescue semantics,
- remove dist-patch dependence where official config/runtime supports it.

Likely future officialization targets:
- per-agent timeout policy
- per-agent bootstrap/prompt mode
- per-agent provider runtime options (`num_ctx`, `stream:false`)
- per-agent fresh-run / ephemeral session mode

## Operational rule

When evaluating a patch change:
1. preserve local-rescue lane identity first,
2. prefer upstream behavior over local dist patching,
3. move behavior into official config when truly supported,
4. do not treat already-upstreamed behavior as local-patch dependency.

## Status

As of 2026-03-10:
- core 4 policies: keep temporarily
- core-only restore path: standard operating path
- legacy full restore: archive/reference only (not current operational path)
- non-core patches: retired candidates
- no GitHub issue filing required right now
