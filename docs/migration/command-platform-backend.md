# Command platform / Saved / Collections backend audit (N4D)

Audit date: 2026-09-16.  
Branch context: `cursor/phase-n4a-ios-profile-polish` at HEAD `1ef3fc42d60849a565a5655943861c16ca502431` plus uncommitted N4B/N4C/N4D source.  
**`ssh modula-vps` was not completed** (remote Shell returned no exit status). Live Greenfield was not inspected.

## Status legend

| Status | Meaning |
|---|---|
| VERIFIED | Confirmed against live Greenfield / prior accepted audit |
| SOURCE-ONLY | Present in native or Expo inventory; not live-verified |
| MISSING | No known contract |
| OPEN — VPS | Requires VPS acceptance before production enablement |

## Capability matrix

| Concern | Status | Notes |
|---|---|---|
| Post save toggle | SOURCE-ONLY / N4B | `POST/DELETE /v1/posts/:id/save` used by `GreenfieldPostRepository` |
| Saved post list | OPEN — VPS | No verified list endpoint. Provisional `GET /v1/saved/posts` gated off |
| Saved modules list | OPEN — VPS / MISSING | Not assumed |
| Saved links list | OPEN — VPS / MISSING | Not assumed |
| Collections / bookmark folders | OPEN — VPS / MISSING | Native local collections only (`CollectionStorage.local`) |
| Server collection reorder | MISSING | Do not fake durable order |
| Server drafts | OPEN — VPS / MISSING | Local `PrivateFileStore` drafts only |
| Share cards in Messages | OPEN — VPS | Messaging send itself OPEN — N4C |
| Share cards in In-Mail | OPEN — VPS | Prefill body/link only; no auto-send |
| Module declared create actions | SOURCE-ONLY | Manifest/action authorization not generalized in N4D |
| Module open command | VERIFIED (architecture) | Typed `/module/:id` → `ModuleHost` → RN (N1 intact) |

## Provisional paths (do not call until capability true)

```
GET    /v1/saved/posts?limit=&cursor=
GET    /v1/collections
POST   /v1/collections
POST   /v1/collections/:id/items
DELETE /v1/collections/:id/items/:itemId
GET    /v1/drafts
```

If VPS shows different paths, replace constants in `SavedBackendCapabilities.Paths` / future collection capabilities. Do not invent a second HTTP client.

## Native stance

- Command Center is local/deterministic — no backend search on keystrokes.
- Saved UI architecture ships; list remains capability-gated (`listSavedPosts = false`).
- Collections default to **On This Device** and never pretend to sync.
- Drafts never log bodies; diagnostics are counts/kind/last-edited only.
- System Share and Copy Link remain available for public shareable payloads.
