# Home feed backend audit (N3C)

Audit date: 2026-09-16. VPS source: `ssh modula-vps` → `/root/modula-latest/services/greenfield-api`. Production API/worker images rebuilt from committed N3C SHA `ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65` (merged via `modula-mod/modula-latest` PR #98). N1 continues to run `tsx src/main.ts` against the same source tree.

Success envelope: `{ok:true,data,meta:{requestId,serverTime}}`. Native client sends bearer access only inside `GreenfieldClient`. No credentials in logs.

## Canonical Home feed contract

| Method | Path | Auth | Role |
|---|---|---|---|
| GET | `/v1/feed/home?mode=&limit=&cursor=` | optional bearer | Home Following / For You / Modules |
| GET | `/v1/feed/profile/:profileId` | optional | Profile timeline by profile id |
| GET | `/v1/profiles/:handle/posts` | optional | Profile timeline by handle |
| GET | `/v1/posts/:postId` | optional | Single post |
| POST | `/v1/posts` | bearer + `post:create` | Compose |
| POST/DELETE | `/v1/posts/:postId/like` | bearer + `post:engage` | Like toggle |
| POST/DELETE | `/v1/posts/:postId/save` | bearer + `post:engage` | Save toggle |
| POST/DELETE | `/v1/posts/:postId/repost` | bearer + `post:engage` | Repost toggle |
| POST | `/v1/posts/:postId/share` | bearer + `post:engage` | Share receipt |

**Important:** bare `GET /v1/feed` and `GET /v1/posts` remain **404**. N3B documented those correctly. The real collection is `/v1/feed/home`.

### Query

- `mode`: `following` | `forYou` | `modules` (default `following`)
- `limit`: existing Greenfield `parseLimit`
- `cursor`: opaque string from `nextCursor`

### Response `data`

```text
items: SocialPostDto[]
nextCursor: string | null
hasMore: boolean
rankingVersion: following-graph-v1 | ranking-v1 | modules-chrono-v1
```

## Existing post model (`SocialPostDto`)

From `@modula/api-contracts`:

```text
id, author (ModulaProfileDto), createdAt, feed, text?
liked, viewerReaction?, reactionCount?, saved, reposted
likeCount, replyCount, repostCount, quoteCount, quotedPost?
kind: text | media | link | module
audience?: public | followers | private
version?, media?, glowColour?, link?, module?
```

`PostMediaDto.kind` is currently **`image` only** in the contract. Do not claim native video playback until Greenfield emits video media.

Reactions supported in domain: `like | love | laugh | fire | celebrate | insightful | support | curious`. HTTP surface for N3C is **like toggle** via `/like`; richer reaction picker waits on a dedicated reaction route.

## Social graph & visibility

| Concern | Source of truth |
|---|---|
| Following | `follows` (`follower_actor_id` → `followed_actor_id`, soft-delete) |
| Blocks / mutes | `moderation.blockedSet` / `mutedSet` merged into `excludedActorIds` on feed route |
| Audience | Feed lists `audience = public` for Home v1; policy engine still gates single-post reads |
| Deleted posts | `deleted_at IS NULL` |

## Mode semantics (N3C)

### Following — `following-graph-v1`

Server-side join on `follows`. Reverse chronological. Requires authenticated viewer (`actorId`); unsigned callers receive an empty page (native UI shows Sign In, not a fabricated public firehose).

### For You — `ranking-v1`

Deterministic score (not ML, not “AI curated”):

```text
score =
  like_count * 2
+ reply_count * 3
+ repost_count * 4
+ reaction_count * 2
+ max(0, 48 - ageHours)
```

Eligible rows: `feed IN ('forYou','following')`, public, not deleted, not blocked/muted. Cursor: `score|createdAt|id`. Public reads allowed.

### Modules — `modules-chrono-v1`

`feed = 'modules'` posts only (module updates / announcements authored as module-kind social posts). Reverse chronological. Do not invent install telemetry as social activity. Product Hub catalogue remains separate (`/v1/registry/products`).

## Pagination

Cursor pages via existing `toCursorPage`. Client must not invent page numbers.

## Comments

Comment create/list routes exist in Greenfield social tests (`/v1/comments…`). Native Post destination opens `/post/:postId` (and comments section when routed). Home must not invent a parallel comments host.

## Ranking signals available today

| Signal | Present |
|---|---|
| Recency (`created_at`) | yes |
| Likes / replies / reposts / reactions counts | yes |
| Follow-graph proximity | used for Following; not yet a For You boost |
| Topic affinity | no dedicated Home signal |
| ML / embeddings | **absent** |

## Module events

Truthful Modules stream = posts tagged `feed=modules` (often `kind=module` with `module` DTO). Registry releases are **not** automatically merged into `/v1/feed/home` in N3C.

## Missing / deferred

- Dedicated reaction HTTP beyond like
- Video media kind in DTO
- Server feed summary aggregate endpoint (native Summary uses the loaded window + `FeedSummarySource.aggregate`)
- Followers-only / private posts inside Home (policy exists; Home list still filters public)

## Fixture

Extend isolated N1 DB only via `scripts/n1/home-fixture.mjs` and ordinary register/follow/post APIs. Never seed production.

## Native ownership

```text
HomeStore → GreenfieldHomeRepository → GreenfieldClient → GET /v1/feed/home
Social/Post* → shared PostCard used by Home (and later Profile/Discover)
```

No React Native on Home. No client-side merge of every followed profile’s posts.
