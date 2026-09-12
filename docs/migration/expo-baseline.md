# Expo baseline

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Clean checkout: `/Users/msjoy/Developer/modula-latest-reference`; branch `main`; HEAD equals `origin/main`; status clean. Latest commit: merge #97, Konsta overlays/navigation stabilization, 2026-09-09.

| Property | Evidence |
|---|---|
| Expo | `package.json`: ~57.0.16 |
| React Native | `package.json`: 0.86.2 |
| Expo Router | `package.json`: ~57.0.16; entry `expo-router/entry` |
| React | 19.2.3 |
| Workspace | pnpm; `pnpm-workspace.yaml`, `pnpm-lock.yaml`; root, services/*, packages/* |
| Node pin | No .node-version or .nvmrc found; no root engines/packageManager field |
| Dependency caveat | Multiple file:../modula-mod/modula-module-standard dependencies; checkout is not standalone without siblings |

No install, formatter, build, refactor or verifier was run in this checkout. Existing working copies were untouched. Source guardrails distinguish shell from product repositories; N1 deliberately supersedes the old declarative-only frontend restriction for **bundled** RN modules, without enabling remote code execution.

Canonical Vault Notes was separately inspected at `/Users/msjoy/Developer/modula-vault-notes-canonical-reference`, `main`, `106b57d40a456e2812e9b3a6e9f3bb32fb15e11d`, package 1.7.0. Archived historical repository `modula-mod/modula-module-vault-notes` was initially inspected in another read-only checkout, branch `modula/main`, `ef712a383e262ba760a67e6f1fdb936f3f4d444f`. It is not the source for migration.

