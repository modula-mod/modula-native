# N4 Greenfield truth matrix

Date: 2026-09-16 (closeout VPS + live HTTP refresh)  
Probed from: `https://api.modula.digital` (production) and `https://native-n1.modula.digital` (isolated N1)  
VPS: `ssh modula-vps` → `/root/modula-latest`  
Production image after closeout fix: `modula-greenfield-api:80c2c0d506da50df28f342ca43e9898391afe79d`  
Backend PR: https://github.com/modula-mod/modula-latest/pull/99 (merged)

Status vocabulary:

| Status | Meaning |
|---|---|
| **VERIFIED** | Live HTTP this run against production or N1 |
| **IMPLEMENTED** | Native production path wired to a verified contract |
| **MISSING** | Live 404 / no honest contract |
| **CAPABILITY-OFF** | Native flag is false; UI must be unavailable, not fake |

## GET `/v1/meta` (reconfirmed)

```text
backend: greenfield
environment: production
registration.mode: open
registration.emailVerificationRequired: true
capabilities.mediaUpload: true
capabilities.modulaMail: true  (transactional only — not social In-Mail)
engine.media: READY
```

## Priority production fixes (N4 closeout)

| Bug | Root cause | Fix | Evidence |
|---|---|---|---|
| `GET /v1/feed/home?mode=forYou` → `SERVER_ERROR` | Public posts by **private** profiles: hydrate used `getByActorId` (visibility-gated, no viewer) → threw `Missing author` → entire For You page 500'd | `getAuthorForReadablePost` (attribution ignores visibility, respects blocks); `hydrateMany` skips residual orphans; `getById` returns null instead of throwing | After deploy: **200** + `rankingVersion=ranking-v1`, items present |
| `GET /v1/media/:uuid.jpg` → HTTP 500 | Same hydrate throw via `posts.getById` on media gate | Same author attribution + null getById | Sample media now **200** JPEG/PNG |

Backend starting HEAD (prod before fix): `ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65`  
Backend fix HEAD: `80c2c0d506da50df28f342ca43e9898391afe79d`  
Merged to main as: `0c83b6f45f9e02838e769bedde68aa8585daeeb1`

## Matrix

| Area | Native assumes | Greenfield truth | Action |
|---|---|---|---|
| Auth | register / verify / login / reset | **VERIFIED** meta open + N1 sign-in path | **IMPLEMENTED** |
| Feed Following | `/v1/feed/home?mode=following` | **VERIFIED** 200 `following-graph-v1` | **IMPLEMENTED** |
| Feed For You | `/v1/feed/home?mode=forYou` | **VERIFIED** 200 `ranking-v1` (fixed) | **IMPLEMENTED** |
| Feed Modules | `mode=modules` | **VERIFIED** 200 `modules-chrono-v1` | **IMPLEMENTED** |
| Posts | detail / create text | **VERIFIED** GET detail; POST family in source | Text create **IMPLEMENTED**; photo **CAPABILITY-OFF** |
| Comments | list + create | **VERIFIED** snake_case list DTOs | List/create **IMPLEMENTED**; replies/delete **CAPABILITY-OFF** |
| Reactions | like + V2 picker | **VERIFIED** GET breakdown; write Like-only | Like **IMPLEMENTED**; multi-reaction **CAPABILITY-OFF** |
| Save | toggle + list | Toggle **VERIFIED**; list endpoints **MISSING** | Toggle **IMPLEMENTED**; `/saved` list **CAPABILITY-OFF** |
| Repost | toggle | Prior N3C contract | **IMPLEMENTED** |
| Discover | dashboard | **VERIFIED** | **IMPLEMENTED** |
| Activity | timeline | **VERIFIED** | **IMPLEMENTED** |
| Search | native commands + server search | Server search exists; command palette local | **IMPLEMENTED** (commands); product search as prior |
| Messaging | conversations | **MISSING** `/v1/conversations` | **CAPABILITY-OFF** |
| In-Mail | social inbox | **MISSING** (modulaMail ≠ In-Mail) | **CAPABILITY-OFF** |
| Stories | tray / create | **MISSING** `/v1/stories` | **CAPABILITY-OFF** |
| Reels | seed / video | Seed **VERIFIED**; no video URL | Seed **IMPLEMENTED**; playback **CAPABILITY-OFF** |
| Media | serve files | **VERIFIED** after fix (honest 404/forbid when missing) | **IMPLEMENTED** |
| Media Upload | upload route | Meta true; upload HTTP path still absent/404 | **CAPABILITY-OFF** |
| Profile | cover/avatar/metrics | **VERIFIED** profile DTOs | **IMPLEMENTED** |
| Module Registry | Vault / CRM / Tasks / GAIA | **VERIFIED** Vault 1.7.0; others coming_soon | **IMPLEMENTED** |
| Module Install | async worker | Prior N1/N2 verified path | **IMPLEMENTED** |
| Publisher | product-hub publisher | **VERIFIED** publisher block on product detail | **IMPLEMENTED** |

## Native production flags (honest)

| Flag | Value |
|---|---|
| `commentsList` / `commentsCreate` | true |
| `commentsDelete` / `commentReplies` / `multiReactions` | false |
| `ReactionBackendCapabilities.breakdownHTTP` | true |
| `ReactionBackendCapabilities.multiReactionHTTP` | false |
| `Messaging*` / `InMail*` / `Story list/create` | false |
| `ReelBackendCapabilities.seedList` | true |
| `ReelBackendCapabilities.videoPlayback` | false |
| `SavedBackendCapabilities.listSavedPosts` | false |
| `CreationCapabilities.textPost` | true |
| `CreationCapabilities.photoPost` / `mediaUpload` | false |

## Capability-off does not block N4 PASS

Messaging, In-Mail, Stories, Reels playback, Saved-list, photo publishing, and multi-reactions may remain off if the UI does not promise them.
