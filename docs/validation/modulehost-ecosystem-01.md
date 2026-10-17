# MODULEHOST-ECOSYSTEM-01 validation

## Repository truth (fetched before edits)

| Field | Value |
| --- | --- |
| Native origin/main start | `8f2fa522e32a11a694772e216d08fbdbfca44ebd` |
| PR #64 | draft, mergeable, `09c2750` cherry-picked as `e8b561e` |
| GreenField origin/main | `d536d5141e8d9a4762a1a2d67097fd4bb0355fe7` |
| GreenField deployed | `d536d5141e8d9a4762a1a2d67097fd4bb0355fe7` |
| Vault origin/main | `d45190e1f47c6802c5f15797a4abb36fa6bfdbe4` (1.8.0) |
| Vault candidate | `12f12e96af83ce66ba7ac737ce344a6282acef84` (2.0.0-rc.2) |

## Feasibility gate

Current RN brownfield is a single bundled `main.jsbundle`. Arbitrary downloaded JS is not a supported executor. The generic declarative path is the accepted execution model.

## Tests

See `ModuleHostEcosystemTests` for cache slots, digest refusal, rollback, generic prepare, permission isolation, and Product UI parsing.
