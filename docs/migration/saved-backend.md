# Saved backend audit (N4D)

Audit date: 2026-09-16. **`ssh modula-vps` not completed.**

## Known from N4B

| Method | Path | Role |
|---|---|---|
| POST | `/v1/posts/:id/save` | Save toggle |
| DELETE | `/v1/posts/:id/save` | Unsave toggle |

These are SOURCE-ONLY relative to this remote session (implemented in `GreenfieldPostRepository`, documented in post-system migration notes). Live VPS re-audit still required for FULL PASS.

## Not verified

| Concern | Status |
|---|---|
| List saved posts | OPEN — VPS |
| Pagination for saved posts | OPEN — VPS |
| Saved modules | OPEN — VPS / likely MISSING |
| Saved links | OPEN — VPS / likely MISSING |
| Collections / folders | OPEN — VPS / likely MISSING |

## Native stance

- Do **not** reconstruct a Saved list from session memory of toggled posts.
- `SavedRepository` + `SavedStore` exist behind `SavedBackendCapabilities.listSavedPosts = false`.
- Unsave from a future list reuses the N4B toggle path.
- Saved ≠ Product Hub Installed.
