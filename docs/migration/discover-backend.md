# Discover / Search backend audit (N3B)

Audit date: 2026-09-15. Public probes against `https://api.modula.digital` (production) and `https://native-n1.modula.digital` (N1 preview). **VPS source inspection (`ssh modula-vps`) was not completed in this environment**; re-run on a Mac with `Host modula-vps` and append route tables from `services/greenfield-api` without inventing contracts.

Success envelope: `{ok:true,data,meta:{requestId,serverTime}}`. Failure: `{ok:false,error:{code,...},meta}`. Native client sends bearer access only inside `GreenfieldClient`. No credentials in logs.

## Existing endpoints

| Method | Path | Auth | Status | Role |
|---|---|---|---|---|
| GET | `/v1/meta` | public | 200 | `engines` includes `search` READY; `publicRead=true` |
| GET | `/v1/discover` | public | 200 | Discover dashboard blob (not scoped subroutes) |
| GET | `/v1/discover/trending` and `/v1/discover/{people,topics,posts,modules}` | — | 404 | Native scopes are client taxonomy over this blob + other collections |
| GET | `/v1/trending` `/v1/feed` `/v1/posts` `/v1/profiles` `/v1/tags` `/v1/hashtags` `/v1/topics` `/v1/suggestions` `/v1/explore` `/v1/social/*` | — | 404 | Do not call |
| GET | `/v1/search?q=` | public | 200; **400 if `q` missing/empty** | Unified search index |
| GET | `/v1/search/{people,posts,modules,topics}` | — | 404 | Filter with `entityType`, never typed subpaths |
| GET | `/v1/registry/products` | public | 200 | Module catalogue; `items[]`, optional `nextCursor` |
| GET | `/v1/profiles/:handle` | public | 200 | Handle lookup. Seed `profile-…` ids often **404** |
| GET | `/v1/profiles/:handle/posts` | public | 200 | `{items,nextCursor,hasMore}` |
| GET | `/v1/profiles/:handle/followers` `/following` | public | 200 | Same page shape |
| GET | `/v1/posts/:id` | public | 200 | Item by id; **no collection list** |
| GET | `/v1/reels` | public | 200 (prod seed; N1 empty via discover) | Seed reels, not a feed |
| GET | `/v1/activity` | public | 200 | Demo seed on production; empty on N1. **Not** Discover |
| GET | `/v1/connections` `/v1/connections/requests` | bearer | 401 unauthenticated | Follow graph / requests |
| POST/DELETE | `/v1/profiles/:id/follow` | bearer | 401 unauthenticated (GET follow is 404) | Follow mutate (N3A public probe) |
| GET | `/v1/modules/installed` | bearer | 401 | Install state |
| GET | `/v1/accounts/me` | bearer | 401 | Session |

## `GET /v1/discover` shape

```text
suggestedProfiles[]   full public profile objects
trendingTopics[]      {id,label,postCount}
featuredModules[]     {id,name,status}   // ids like module-vault-notes, not registry moduleId
media[]               {id,kind,url?,altText?,aspectRatio,title,colour?}
reels[]               {id,author,caption,source,colour,liked,likeCount,replyCount}
```

No dashboard `nextCursor`. No trend velocity (`+24% today`). **Do not fabricate velocity.** `postCount` on topics is real and may be formatted (e.g. 1.8K).

Production currently returns many fixture/test profiles alongside first-party ones (Andrei, Gaia, Design, …). N1 returns a single fixture profile and empty topics/modules/media/reels.

## Search

`GET /v1/search?q={query}&entityType={profile|post|module|module-release}&limit=&cursor=`

- `q` is required. Case: index is effectively case-insensitive for probed queries.
- Partial matches work (`q=a` returns people/posts).
- `entityType` filters; `types=` is **ignored**.
- `entityType=topic` and `entityType=hashtag` are **not** real filters (returns unfiltered-style hits). Topic labels such as `Profile OS` are **not** in the search index.
- Native `/search/topics?q=` therefore matches `GET /v1/discover` `trendingTopics` by label/id. That is the truthful topic contract until Greenfield indexes topics.
- Page: `results[]`, `nextCursor`, `tookMs`, `requestId`.
- Result: `entityType, entityId, title, excerpt, score, matchedFields[], ownerId?, createdAt, updatedAt, metadata`.

Profile metadata: `kind, handle, moduleCount, publicLinks, publicLocation, featuredModuleIds`.  
Post metadata: `feed, kind, handle, audience, linkDomain, mediaCount, authorDisplayName`.  
Module metadata: `status, version, platforms, publisher, categories, trustState, installable, capabilities`.

Ranking is server `score`. Native Search must not invent a second ranker.

## Profiles

Public profile keys: `id, handle, displayName, kind, bio, pronouns?, location?, website?, followerCount, followingCount, moduleCount, postCount, joinedAt, focusStatus, identityClaims[], links[], featuredModuleIds[], isFollowing, followsViewer, version`.

`identityClaims` is empty on probed rows — do not show a verification badge unless a claim is present. No `avatarUrl` on probed profiles — render initials. Location/website respect `visibility` when present; backend is the privacy authority.

Native people routes use **handle** (`/profile/andrei.modula`) because handle lookup works and seed ids often do not.

Production `suggestedProfiles` currently includes leftover phase/VPS/search-boundary fixture identities mixed with first-party profiles. **This is a Greenfield eligibility bug, not an iOS filter.** Native Discover must not hard-code test handles. Prefer a backend discoverability/environment marker so production returns only public eligible identities; isolated N1 may still return fixture profiles. VPS source confirmation of the discover assembler remains OPEN until `ssh modula-vps` succeeds.

## Posts

No global `/v1/posts` list. Discover Posts uses:

1. `GET /v1/profiles/:handle/posts` for suggested people with `postCount > 0`
2. Search `entityType=post` when the user is querying
3. `GET /v1/posts/:id` for a single card / `/post/:postId` destination

Post keys: `id, author, createdAt, feed, text, liked, viewerReaction, reactionCount, saved, reposted, likeCount, replyCount, repostCount, quoteCount, audience, version, kind` plus optional `media`, `module`, `link`.

`kind` observed: `text`, `media`. Do not label a Popular sort from a partial client window.

## Modules

Canonical catalogue remains `GET /v1/registry/products`. Discover `featuredModules` ids (`module-vault-notes`) are **not** registry `moduleId` values (`digital.modula.vault-notes`) on the current production payload. Native resolve uses `moduleId`/`catalogueId` when the payload already carries a dotted catalogue id, otherwise name/slug against the catalogue. Do not grow a client alias table. Preferred backend fix: `/v1/discover` featured entries emit canonical `moduleId`. Do not Install/Open unresolved preview ids.

Installed state: authenticated `GET /v1/modules/installed`. Compatibility: catalogue `installable` / `installability`.

## Follow graph

`isFollowing` / `followsViewer` on profile objects. Mutate with POST/DELETE `/v1/profiles/:id/follow` (confirm id vs handle against VPS). No separate “Requested” field on public profiles; only show Requested if a future payload says so.

Blocked/muted exclusion was **not** visible on public discover. Prefer server-side exclusion; do not invent a client block list.

## Pagination

| Surface | Mechanism |
|---|---|
| Search | `limit` + `nextCursor` (honoured) |
| Profile posts / followers / following | `items`, `nextCursor`, `hasMore` |
| Discover dashboard | none |
| Registry products | `nextCursor` present on catalogue page |

## Ranking

Server search `score`. Topic `postCount`. No ML, vectors, collaborative filtering, or “For You” personalization service. Native labels stay **Trending / Popular-as-postCount / Featured / New** only where those fields exist. Do not label sections For You.

## Missing capabilities (do not fake)

- Dedicated people/topic/post/module discover collections
- Hashtag/topic search entity types
- Trend velocity
- Global chronological/popular feed
- Avatar URLs on public profiles
- Personalized recommendations
- Not interested / hide topic / mute from discover
- Unread-count style discover APIs

## Fixture

N1 (`native-n1.modula.digital`) already exposes `native-n1-integration` on `/v1/discover`. Topics/media/featured modules are empty there — UI must show compact empty states, not production seed copy.

Prefer normal account/profile/post flows over SQL. Credentials stay in `.env.n1.local`.

## Native ownership

```
DiscoverStore → GreenfieldDiscoverRepository → GreenfieldClient (URLSession) → Greenfield
SearchScreen → same repository (GET /v1/search)
Product Hub catalogue → existing ProductHubStore / GET /v1/registry/products
```

No React Native involvement. No parallel recommendation microservice.
