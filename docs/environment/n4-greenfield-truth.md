# N4 Greenfield truth matrix

Date: 2026-09-16  
Probed from: `https://api.modula.digital` (production Greenfield v1) and `https://native-n1.modula.digital`  
VPS shell (`ssh modula-vps`): **not executed** — private-worker exec-daemon returned no command results this run. Live HTTP against the public API is the verification that *was* possible.  
No production-user rows were inserted. No isolated fixture accounts were provisioned.

Status vocabulary:

| Status | Meaning |
|---|---|
| **VERIFIED** | Live HTTP this run, or a prior N3C VPS source read of the same route family |
| **IMPLEMENTED** | Native production path is wired to a verified contract |
| **MISSING** | Live 404 / no honest contract |
| **CAPABILITY-OFF** | Native flag is false; UI must be unavailable, not fake |

`SOURCE-ONLY` is not used below.

## GET `/v1/meta` (2026-09-16T18:42:45Z)

```text
backend: greenfield
environment: production
registration.mode: open
registration.emailVerificationRequired: true
capabilities.mediaUpload: true
capabilities.modulaMail: true
capabilities.greenfieldAccounts / Sessions / ModuleRegistry / ModuleInstallation: true
capabilities.modules: false  (legacy flag; registry/install flags are true)
engine.media: READY (service.greenfield-media)
engine.files: CONTRACT_ONLY
apple authentication: not configured
```

`modulaMail: true` is the transactional mail engine (verification / reset). It is **not** a social In-Mail inbox. `/v1/mail` and `/v1/in-mail` are 404.

## Matrix

| Area | Native assumes | Greenfield truth | Action |
|---|---|---|---|
| Post comments | Provisional `/v1/posts/:id/comments` | **VERIFIED** GET `{items}` on that path. Live rows use `comment_id`, `author_actor_id`, `parent_comment_id`, `reply_count`, `created_at`. Nested replies are **not** in the list (top-level only). | Decoder aligned. `commentsList` **IMPLEMENTED**. `commentReplies` **CAPABILITY-OFF**. Create stays on (collection exists; POST still needs authenticated closeout). Delete **CAPABILITY-OFF**. |
| Reactions | Like toggle + V2 picker; hoped `breakdown` | **VERIFIED** GET `/v1/posts/:id/reactions` → `{viewerReaction,total,byType}`. Post payloads still have `viewerReaction` + `reactionCount` and like toggle. | Decode `byType`. `breakdownHTTP` **IMPLEMENTED**. `multiReactions` / PUT-DELETE **CAPABILITY-OFF** (mutation not live-verified). People list **CAPABILITY-OFF**. |
| Saved list | Unknown | **MISSING** `GET /v1/saved`, `/v1/posts/saved`, `/v1/accounts/me/saved` all 404. Save **toggle** remains the N3C contract. | `/saved` list **CAPABILITY-OFF**. Toggle stays **IMPLEMENTED**. |
| Edit/delete post | Capability gated | Not live-probed (would be mutating). | Remain **CAPABILITY-OFF**. |
| Report/mute | Mute via profile graph; report unknown | Report endpoints not found this run. Mute remains N4A graph. | Report **CAPABILITY-OFF**. Mute **IMPLEMENTED** (existing graph). |
| Messages | Unknown / off | **MISSING** `GET /v1/conversations`, `/v1/messages` 404 | **CAPABILITY-OFF** |
| In-Mail | Unknown / off | **MISSING** `/v1/in-mail`, `/v1/mail` 404. `modulaMail` meta flag is transactional email. | **CAPABILITY-OFF** |
| Stories | read/create | **MISSING** `GET /v1/stories` 404. `GET /v1/media/stories/:file` is file serve, not a tray. | **CAPABILITY-OFF** |
| Reels | seed/read/video | **VERIFIED** `GET /v1/reels` seed cards (caption, colour, likeCount). **No video URL / duration**. Same seed appears on Discover `reels[]`. | Seed **IMPLEMENTED**. Video playback / ranked feed / create **CAPABILITY-OFF**. |
| Collections | Unknown | No server list. | **On This iPhone** local only. Do not claim sync. |
| Media upload | Unknown | Meta `mediaUpload: true`. `GET /v1/media` and `/v1/media/upload` 404. `GET /v1/media/:id.png` returned **500**. Discover still emits some `/v1/media/:id` URLs. | Photo publish **CAPABILITY-OFF**. Do not improvise upload. |
| Post creation | Conservative `{text,kind,audience,idempotencyKey}` | `POST /v1/posts` **VERIFIED** as a route family in N3C VPS source. `GET /v1/posts` 404 (expected). Body not live-POSTed this run (no isolated fixture). | Text publish remains **IMPLEMENTED** with conservative encoder. Live authenticated publish still needs Mac fixture. |
| Register | Documented POST `/v1/accounts/register` | GET 404 (method). Meta `registration.mode=open`, email verification required. Not live-POSTed against production. | Keep documented client. Isolated fixture still required. |
| Verify email | Documented | Meta requires it. Not live-POSTed this run. | Keep documented client. |
| Reset password | Documented | Not live-POSTed this run. | Keep documented client. |
| Profile cover/avatar | Verify | Profile DTOs on Discover/posts include bio, pronouns, location, links, counts. Cover/avatar URLs were not a dedicated live field on the andrei.modula post author blob. | Native N4A/N4E cover remains; do not invent marketplace metrics. |
| Module metadata | Verify | **VERIFIED** `GET /v1/registry/products` and `GET /v1/registry/products/digital.modula.vault-notes`. Vault Notes 1.7.0 published/installable. CRM/Tasks/GAIA Atlas `coming_soon`. Publisher `{publisherId,displayName,website}`. **No ratings, review counts, or download counts.** | Module Detail must not fabricate stars/downloads. |
| Publisher metadata | Verify | Present on product detail (`publisher.displayName`, `publisherId`, `website`). | Wire existing Publisher view; no invented stats. |

## Feed / catalogue extras

| Probe | Result |
|---|---|
| `GET /v1/feed/home` (unsigned) | **VERIFIED** empty following page `rankingVersion=following-graph-v1` |
| `GET /v1/feed/home?mode=forYou` | **SERVER_ERROR** `"Failed to load feed"` — production bug, not a native decoder issue |
| `GET /v1/feed/home?mode=modules` | **VERIFIED** module posts, `modules-chrono-v1` |
| `GET /v1/discover` | **VERIFIED** large dashboard including `reels[]` and media URLs |
| `GET /v1/profiles/andrei.modula/posts` | **VERIFIED** mix of live UUID post + seed `post-local-*` |
| `GET /v1/posts/:uuid` | **VERIFIED** |
| `GET /v1/activity` | **VERIFIED** public seed activity |
| `GET /v1/registry/products` | **VERIFIED** |

## Native production flags after this closeout

| Flag | Value |
|---|---|
| `PostBackendCapabilities.like/save/repost` | true |
| `commentsList` / `commentsCreate` | true |
| `commentsDelete` / `commentReplies` / `multiReactions` / edit / delete / report | false |
| `ReactionBackendCapabilities.breakdownHTTP` | true |
| `ReactionBackendCapabilities.multiReactionHTTP` | false |
| `MessagingBackendCapabilities.*` | false |
| `InMailBackendCapabilities.*` | false |
| `StoryBackendCapabilities.list/create` | false |
| `ReelBackendCapabilities.seedList` | true |
| `ReelBackendCapabilities.videoPlayback` | false |
| `SavedBackendCapabilities.listSavedPosts` | false |
| `CreationCapabilities.textPost` | true |
| `CreationCapabilities.photoPost` / `mediaUpload` | false |

## Still requiring authenticated Mac closeout

- Register / verify / login / reset against an **isolated** N1-style fixture (not a real user)
- `POST /v1/posts` body exactness
- `POST /v1/posts/:id/comments` create + failure draft retain
- Like/save/repost round-trip
- App Lock / Face ID / App Gate
- For You `SERVER_ERROR` backend fix
- Media upload path (engine ready, HTTP path missing/broken)
