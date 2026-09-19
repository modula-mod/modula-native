# Activity backend audit (N3A)

Audit date: 2026-09-15. Environment: public production probes from the Cloud Agent plus existing migration inventories. **VPS source inspection (`ssh modula-vps`, `/root/modula-latest/services/greenfield-api`) was unavailable in this environment** (hostname unresolved, no SSH keys). Re-run the VPS pass on a Mac with authorized access and append findings below without inventing contracts.

## Event types observed

### Public demo seed — `GET /v1/activity` (unauthenticated, HTTP 200)

Static four-item payload. Query parameters `mode`, `cursor`, and `limit` are **ignored**. Types present:

| type | notes |
|---|---|
| `like` | actor + preview text |
| `follow` | actor only |
| `moduleUpdate` | actor + preview |
| `mention` | actor + preview |

Fields: `id`, `group` (`today` \| `earlier`), `type`, `actor` (full profile-shaped object), `description`, `timestamp`, optional `preview`.

**Do not use this endpoint for signed-in Activity acceptance.** It is seed/demo content, not account-scoped notifications.

### Authenticated surfaces (route exists; body shape pending authenticated fixture capture)

| Method | Path | Probe result |
|---|---|---|
| GET | `/v1/notifications` | 401 `UNAUTHENTICATED` |
| GET | `/v1/notifications?mode=&limit=&cursor=` | 401 (route accepts query) |
| POST | `/v1/notifications/:id/read` | 401 |
| POST | `/v1/notifications/read-all` | 401 |
| GET | `/v1/connections/requests` | 401 |
| GET | `/v1/connections` | 401 |
| GET/DELETE | `/v1/connections/:id` | 401 |
| POST/DELETE | `/v1/profiles/:id/follow` | 401 |
| GET | `/v1/accounts/me/notification-preferences` | 401 |
| POST | `/v1/accounts/forgot-password` | 200 `{requested:true}` |

Native N3A maps:

- **All / Mentions** → `GET /v1/notifications` (Mentions passes `mode=mentions`)
- **Requests** → `GET /v1/connections/requests`
- **Mark read** → `POST /v1/notifications/:id/read`
- **Mark all read** → `POST /v1/notifications/read-all`
- **Accept request** → `POST /v1/profiles/:actorId/follow`
- **Decline request** → `DELETE /v1/profiles/:actorId/follow`

Accept/decline path selection is the best public-route match; confirm against Greenfield source on VPS before treating as frozen.

## Tables / models

Not inspected on VPS. Expo-era inventories reference `ApiActivityRepository` and notification preferences; social inventory defers full Activity to N3.

## Pagination

Preferred contract: cursor + limit on notifications/requests. Decoder accepts:

- bare arrays
- `{ items|notifications|requests|events, nextCursor|next_cursor|cursor, unreadCount }`

Public demo activity does **not** paginate.

## Read-state mechanism

Canonical native rule (unless backend dictates otherwise after VPS audit):

1. Opening Activity does **not** mark everything read.
2. Opening/tapping an event marks that event read.
3. Mark All Read calls `POST /v1/notifications/read-all`.

## Request lifecycle

List via `GET /v1/connections/requests`. Accept/decline via profile follow mutate routes (pending VPS confirmation). UI disables controls during the request and restores on failure.

## Mentions

Client requests `mode=mentions` when the Activity rail selects Mentions. If the backend ignores `mode`, client may still show the full page until VPS confirms filtering — document any server-side filter gap after fixture login.

## Aggregation

If Greenfield returns pre-aggregated actor groups, render `actors[]` as an overlapping stack and a single row. Client-side aggregation is only applied when multiple events share an identical subject and kind within a short window **and** the backend does not already aggregate — default N3A does **not** client-aggregate; it trusts server rows.

## Authentication requirements

All real Activity endpoints require Bearer access from `POST /v1/sessions`. Session storage remains Keychain-only (`digital.modula.app.native.session`).

## Known missing contracts

- Exact notification JSON schema (awaiting authenticated fixture capture / VPS source)
- Dedicated Accept/Decline routes under `/v1/connections/requests/:id/*` were **not** found via public probing
- Unread-count endpoint (`/v1/notifications/unread-count`) → 404
- Push / APNs infrastructure not present in native app
- AI Activity summary service not confirmed; N3A ships deterministic aggregates with `ActivitySummarySource` ready for later AI

## Fixture plan

Extend N1 isolated Greenfield (`scripts/n1/`) once VPS access exists:

- 1 mention, 2 reactions, 1 comment, 1 follow, 2 connection requests, 1 module event if supported
- Prefer normal service flows over raw SQL inserts
- Keep credentials in `.env.n1.local` (gitignored)

## Native ownership

```
ActivityStore → GreenfieldActivityRepository → GreenfieldClient (URLSession) → Greenfield
```

No React Native involvement. No parallel Activity microservice.
