# N4A — Greenfield Profile capabilities (production audit)

Audit date: 2026-09-16.  
VPS: `ssh modula-vps` → `core.modula.digital`.  
Source of truth: `/home/andrei/modula-latest/services/greenfield-api` @ `1ce28c422458dc024c67a45a5fb42454629679b4`.  
Running API image: `modula-greenfield-api:ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65`.

Live probe: `GET https://api.modula.digital/v1/profiles/andrei.modula`.

N4A branches from N3D checkpoint `3a507ecd49b0cc973fa23a67180177693a716398` on `cursor/phase-n4a-ios-profile-polish`.

## Deployed contracts used by Profile

| Capability | Contract | N4A client rule |
|---|---|---|
| Public profile | `GET /v1/profiles/:handle` | Render all public DTO fields |
| Own session | `GET /v1/accounts/me` + profile by handle | Ownership from handle match |
| Posts | `GET /v1/profiles/:handle/posts` | Shared `PostCard` |
| Followers / following | `GET …/followers` · `GET …/following` | Typed people routes |
| Follow / unfollow | `POST` / `DELETE /v1/profiles/:id/follow` | Follow ↔ Following only |
| Edit | `PATCH /v1/profiles/me` | **Only** `displayName`, `bio`, `visibility`, `expectedVersion` |
| Mute / unmute | `POST` / `DELETE …/mute` | Other profiles only |
| Block / unblock | `POST` / `DELETE …/block` | Other profiles only |
| Report | `POST /v1/reports` | `{targetType,targetId,category,details?}` — profile target supported |
| Featured modules | `featuredModuleIds[]` on profile DTO | Resolve via Product Hub catalogue |
| Share URL | Canonical `https://modula.digital/profile/<handle>` | No debug hosts |

## Media

| Surface | Status |
|---|---|
| `avatarUri` / `coverUri` on DTO | Present when set (columns `avatar_url` / `cover_url`) |
| Avatar / cover **upload** | **Missing** — no authenticated profile media/presign route |
| Cover **position / focal point** | **Missing** — no `coverPosition` / offset field anywhere |
| Remove avatar / cover | **Missing** — cannot clear via write path |
| Change photo menus | View only (+ Share / Copy link). Do **not** show Change / Remove / Reposition |

## Relationships

- Follow graph soft-deletes; response returns refreshed `isFollowing` + `followerCount`.
- **No** follow-request / `Requested` state on profiles.
- Activity “Requests” remain a separate surface.

## Modules

- Profile exposes `featuredModuleIds` + `moduleCount` only.
- **No** `GET /v1/profiles/:handle/modules`.
- **No** write path to reorder / curate featured modules from native.
- Native must **not** list viewer installed modules as another user’s profile modules.
- Empty / unresolved catalogue → product copy, not “catalogue resolution” language.

## Editing gaps (do not invent)

- Pronouns, location, website, links, avatarUri, coverUri, coverColour are **readable** but **not** applied by `ProfileWriteService.updateMe`.
- Handle change remains `POST /v1/accounts/me/handle` (Account authority).

## Privacy (release-blocking)

Public `andrei.modula` payload keys (live):

```text
id, handle, displayName, kind, bio, pronouns, location, website,
followerCount, followingCount, moduleCount, postCount, joinedAt,
focusStatus, identityClaims, links, featuredModuleIds,
isFollowing, followsViewer, version
```

Sensitive-key scan (`email`, `phone`, `token`, `password`, `session`, `secret`, `auth`): **none**.

Blocked profiles collapse to not-found / unavailable via `canView` — client must not distinguish block vs missing when server returns `NOT_FOUND`.

Links for non-owners are filtered to `visibility = public` server-side.

## N4A menu capability map

### Own profile
Share Profile · Copy Profile Link · My Modula Code · Preview as Visitor (local UI) · Profile Settings · Edit Profile

### Other profile
Share Profile · Copy Profile Link · Mute · Block · Report

### Avatar / cover long-press
View Photo / View Cover · Share Profile · Copy Profile Link  
**Not** Change / Remove / Reposition (no backend)

## Missing contracts (OPEN — document only)

1. Profile avatar / cover upload + remove  
2. Cover positioning persistence  
3. Full `PatchProfileInput` write path  
4. Featured-module curation / reorder API  
5. Follow approval (`Requested`)  
6. Message deep-link from Profile  
7. Social mutuals graph (do not bind to OAuth `/v1/connections`)
