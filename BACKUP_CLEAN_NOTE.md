Clean backup branch for GitHub remote preservation.
Excluded from this branch:
- local secrets/config snapshots containing tokens
- tmp/ and large generated artifacts
- node_modules, .vercel, runtime caches, transient state
Purpose: keep a safe, pushable workspace snapshot without secrets.
