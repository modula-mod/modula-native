# Profile backend audit (N3D)

Audit date: 2026-09-16. VPS source: `ssh modula-vps` → `/home/andrei/modula-latest/services/greenfield-api` (profiles domain + `register-routes.ts`). Live probes against `https://api.modula.digital`.

**N3D depends on N3C.** Branch from `cursor/phase-n3c-ios-home-feed` @ `012f081ee92f20c44fb97b4001974b97e20387a7`.

Success envelope: `{ok:true,data,meta:{requestId,serverTime}}`. Native client sends bearer access only inside `GreenfieldClient`. No credentials in logs.

## Existing endpoints

| Method | Path | Auth | Role |
|---|---|---|---|
| GET | `/v1/profiles/:handle` | optional | Public profile by **handle** (not seed id) |
| GET | `/v1/profiles/:handle/posts` | optional | Profile posts page `{items,nextCursor,hasMore}` |
| GET | `/v1/profiles/:handle/followers` | optional | People page by profile id cursor |
| GET | `/v1/profiles/:handle/following` | optional | Same shape |
| GET | `/v1/feed/profile/:profileId` | optional | Alternate timeline by profile **id** |
| POST | `/v1/profiles/:profileId/follow` | bearer + `social:follow` | Follow (profile **id**) |
| DELETE | `/v1/profiles/:profileId/follow` | bearer + `social:follow` | Unfollow |
| PATCH | `/v1/profiles/me` | bearer + `profile:update` | Own profile write |
| POST/DELETE | `/v1/profiles/:profileId/block` | bearer + `social:block` | Block / unblock |
| POST/DELETE | `/v1/profiles/:profileId/mute` | bearer + `social:mute` | Mute / unmute |
| GET | `/v1/accounts/me` | bearer | Session account (handle, not social profile DTO) |
| POST | `/v1/accounts/me/handle` | bearer | Handle change (account authority) |
| GET | `/v1/accounts/handles/:handle/availability` | public | Handle availability |
| GET | `/v1/profiles/:handle/modules` | — | **404** — does not exist |
| GET | `/v1/connections` | bearer | **Connector OAuth** connections, not social mutuals |

## Models / tables

- `profiles` — identity row: `id`, `actor_id`, `handle`, `display_name`, `kind`, `avatar_url`, `cover_url`, `cover_colour`, `bio`, `pronouns`, `location_*`, `website_*`, `focus_status_*`, `visibility`, `module_count`, `featured_module_ids`, `identity_claims`, `joined_at`, `version`, soft-delete
- `profile_links` — extra links with `visibility` + `sort_order`
- `follows` — soft-delete graph (`follower_actor_id` → `followed_actor_id`); **no approval / Requested state**
- `blocks` / mutes — moderation; blocked profiles return not-found style hides via `canView`

## Public profile DTO fields (`ModulaProfileDto`)

```text
id, handle, displayName, kind
avatarUri?, coverUri?, coverColour?
bio, pronouns?, location?, website?
followerCount, followingCount, moduleCount, postCount
joinedAt, focusStatus, identityClaims[], links[]
featuredModuleIds[], isFollowing, followsViewer, version
```

Wire keys observed live: camelCase as above. Mapper emits `avatarUri` / `coverUri` (not `avatarUrl`). Counts are **server aggregates**, not client page lengths.

Production probe (`andrei.modula`): cover/avatar often **absent**; `identityClaims` empty → **no verification badge**. Location/website/links respect visibility; non-owners only see `public` links.

## Follow lifecycle

1. POST `/v1/profiles/:profileId/follow` inserts or undeletes follow; enqueues `notification.create`
2. DELETE soft-deletes the follow row
3. Response includes refreshed `{profile, isFollowing, followerCount}`
4. **No `Requested` / approval queue** on profiles. Activity “Requests” are a separate surface. Native Follow CTA is Follow ↔ Following only.

## Editing

| Contract (`PatchProfileInput` in api-contracts) | Runtime `ProfileWriteService.updateMe` |
|---|---|
| displayName, bio, pronouns, avatarUri, coverUri, coverColour, location, website, visibility, focusStatus, expectedVersion | **Only** `displayName`, `bio`, `visibility`, `expectedVersion` applied |

`PATCH /v1/accounts/me` is a **no-op** for profile fields (Phase 6R note: account row is identity authority; social fields live on `profiles`).

Native Edit Profile must expose only fields Greenfield actually persists today: **display name**, **bio**, optional **visibility**. Do not fake pronouns/location/website/avatar/cover editors until writes land.

Handle change: `POST /v1/accounts/me/handle` + availability GET. Significant routing impact — implement carefully or omit from Profile editor if out of N3D scope; prefer Account Settings for handle.

## Media upload

| Surface | Status |
|---|---|
| Post media | `PostMediaStorage` + `GET /v1/media/:file` |
| Stories media | `GET /v1/media/stories/:file` |
| Profile avatar / cover upload | **Missing** — columns exist; no authenticated upload/presign route for profile art |

Native may render remote `avatarUri` / `coverUri` when present. PhotosPicker → upload is **OPEN** until Greenfield adds a profile media contract.

## Profile modules semantics

- There is **no** public installed-module list on profiles.
- Profile exposes `featuredModuleIds` (e.g. `module-vault-notes`) and `moduleCount`.
- Native resolves featured ids against `GET /v1/registry/products` the same way Discover does (catalogue `moduleId` / name / slug). Unresolved ids stay out of the grid.
- Do **not** call `/v1/modules/installed` for another user’s Profile — that is the viewer’s install state.
- Privacy: only emit featured / public catalogue resolution. Never dump raw installs.

## Pagination

| Surface | Mechanism |
|---|---|
| Posts | `limit` + opaque `nextCursor`; `hasMore` |
| Followers / following | `toCursorPage` on profile `id`; items are full profile DTOs |
| Featured modules | client resolve of id list (no cursor) |

## Privacy

- `canView`: public always; followers/teams require follow; private = owner only; blocks either direction → treat as not found
- Links: non-owners filtered to `visibility = public`
- Email / phone / sessions never appear on profile DTO
- Blocked profile: client shows “This profile isn’t available.” / not found — do not distinguish block vs missing if server returns NOT_FOUND

## Connections route (native)

Canonical `/profile/:userId/connections` must **not** bind to `GET /v1/connections` (connector OAuth). Social mutuals are not a Greenfield profile contract today → honest unavailable empty state.

## Missing contracts (do not invent client-side)

- Profile avatar / cover upload
- Full `PatchProfileInput` write path (pronouns, location, website, media URIs)
- `GET /v1/profiles/:handle/modules`
- Social mutuals / connection graph for Profile
- Follow approval (`Requested`)
- Message deep-link from Profile (Messages routing not Profile-ready)

## Fixture guidance

Extend isolated N1 fixture with:

- current user profile (cover optional)
- second public user with posts + follow edge
- profile with long bio / missing location / multiple links
- empty posts case

Use normal register/verify/session/follow/post APIs. Credentials stay in `.env.n1.local`.

## Native ownership

```text
ProfileStore → GreenfieldProfileRepository → GreenfieldClient → Greenfield
Posts → shared SocialPost / PostCard (N3C)
Modules → featuredModuleIds → Product Hub components
Follow → POST/DELETE /v1/profiles/:id/follow
Edit → PATCH /v1/profiles/me (displayName, bio, visibility)
```

No React Native. No second profile microservice.
