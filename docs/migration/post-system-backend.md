# Post system backend audit (N4B)

Audit date: 2026-09-16.  
Remote agent run: `bc-01a0a9ad-113b-7866-8e33-8f4f03d3caf1` on private worker `modula-mac`.

## Remote probe status

| Probe | Result |
|---|---|
| `ssh modula-vps` | **UNAVAILABLE** — Shell exec-daemon on the private worker returned no exit status for every command in this run; Computer Use blocked (Screen Recording permission). Exact SSH failure string could not be captured live. |
| Backend deployment path | **OPEN** — cannot verify without SSH / working shell |
| Live HTTP acceptance | **OPEN** |

Prior N3C audit (`home-feed-backend.md`) remains the last verified VPS source read (`ssh modula-vps` → `/root/modula-latest/services/greenfield-api`, production images from SHA `ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65`).

## Backend source visibility

- **In this checkout:** native clients + migration docs only (no Greenfield API tree).
- **Public contracts verified (repo docs + native DTOs):** Home feed, single post, like/save/repost toggles, profile posts, Discover post keys.
- **Contracts inferred only from repository docs/inventory:** comments list/create, share receipt, edit/delete, moderation taxonomy, multi-reaction HTTP.
- **Unverified functionality:** anything requiring live VPS/DB/API probes this run.

## Post contracts (from N3C + native DTOs)

| Method | Path | Auth | Status |
|---|---|---|---|
| GET | `/v1/feed/home?mode=&limit=&cursor=` | optional / required by mode | Verified in N3C |
| GET | `/v1/posts/:postId` | optional | Verified in N3C |
| POST | `/v1/posts` | bearer + `post:create` | Documented; composer deferred |
| POST/DELETE | `/v1/posts/:postId/like` | bearer + `post:engage` | Verified client |
| POST/DELETE | `/v1/posts/:postId/save` | bearer + `post:engage` | Verified client |
| POST/DELETE | `/v1/posts/:postId/repost` | bearer + `post:engage` | Verified client |
| POST | `/v1/posts/:postId/share` | bearer + `post:engage` | Documented; native share receipt **OPEN** |
| GET | `/v1/profiles/:handle/posts` | optional | Verified client |
| GET/POST | `/v1/comments…` | bearer for mutate | Documented in N3C; **exact paths unconfirmed this run** |
| PATCH/DELETE | `/v1/posts/:postId` | bearer + ownership | **Inferred / OPEN** |
| Multi-reaction | dedicated reaction route | — | **Missing** per N3C (like toggle only) |

Native N4B comment client uses provisional paths aligned with Greenfield style and marks live acceptance **OPEN** until SSH confirms:

```text
GET    /v1/posts/:postId/comments?limit=&cursor=
POST   /v1/posts/:postId/comments   { text, parentId? }
DELETE /v1/comments/:commentId
PATCH  /v1/posts/:postId           { text }     # edit — capability gated
DELETE /v1/posts/:postId                         # delete — capability gated
POST   /v1/posts/:postId/share     {}            # share receipt — optional
```

## Types

| Kind | DTO today | Native render |
|---|---|---|
| text | yes | full |
| media / image | yes (`PostMediaDto.kind = image`) | full |
| link | yes | full |
| module | yes | full |
| carousel | multi-image array only | paging if `media.count > 1` |
| video | **not in DTO** | reserved — **VIDEO: OPEN — BACKEND CONTRACT** |
| poll / audio / movie | not in SocialPostDto | reserved — no fake UI |

## Engagement

- `liked`, `saved`, `reposted` booleans + counts.
- Optimistic UI with rollback in native clients.
- Shared `PostStateStore` (N4B) synchronizes viewer state across Home / Profile / Discover / Detail.

## Reactions

- Domain values: `like | love | laugh | fire | celebrate | insightful | support | curious`.
- Field: `viewerReaction?`, `reactionCount?`.
- HTTP: **like toggle only**. Multi-reaction picker commits only `.like` until a dedicated reaction route exists.
- **REACTIONS HTTP: OPEN**

## Comments

- Counts: `replyCount`.
- Create/list routes claimed in Greenfield social tests; native client shipped with provisional paths + capability flag.
- Thread depth / replies: decode `parentId` when present; UI shows one honest reply level only when data exists.
- **COMMENTS LIVE: OPEN**

## Reposts / Save / Share

| Action | Backend | Native |
|---|---|---|
| Save / unsave | real | real |
| Repost / unrepost | real | real |
| Quote | `quoteCount` only | not fabricated |
| Share receipt | documented | optional POST; system share always available |
| Canonical URL | — | `https://modula.digital/post/:postId` |

## Moderation / visibility

| Capability | Truth |
|---|---|
| Block / mute | Profile graph APIs exist (N4A); feed excludes blocked/muted actors server-side (N3C) |
| Report post/comment | **Taxonomy / endpoint OPEN** — do not invent categories |
| Not interested | **No verified recommender feedback endpoint** — hide locally only as “Hide this post”, not training |
| Audience | `public \| followers \| private`; Home lists public; single-post policy gates reads |
| Deleted | `deleted_at IS NULL`; client shows “This post isn't available.” |

## Privacy (server is boundary)

Client must not invent visibility. Unverified this run without SSH:

- private / followers-only single-post authorization
- blocked-account post reads
- muted content omission
- comment visibility under audience rules

**PRIVACY LIVE: OPEN**

## Backend changes this phase

None deployed. No Greenfield source tree in this checkout. Any small contract additions require a verified deployment path.

## Deployment

```text
DEPLOYMENT: OPEN
LIVE ACCEPTANCE: OPEN
SSH: UNAVAILABLE (this run)
```
