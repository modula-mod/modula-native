# Messaging / In-Mail backend audit (N4C)

Audit date: 2026-09-16. Native source: `modula-native` on `cursor/phase-n4a-ios-profile-polish` (HEAD `1ef3fc42d60849a565a5655943861c16ca502431`) plus uncommitted N4B post-system files. Expo inventory: `docs/migration/social-inventory.md`, `docs/migration/backend-contracts.md`, `docs/migration/discover-backend.md`, `docs/migration/profile-backend.md`.

**`ssh modula-vps` was not completed in this environment.** Live Greenfield source (`services/greenfield-api`) was not inspected. HTTP probes were not run (no shell). This document is repository-contract truth only. Anything not listed here is **OPEN — VPS ACCEPTANCE** and must not be treated as implemented.

Success envelope remains `{ok:true,data,meta}`. Native networking stays on `GreenfieldClient`. No parallel HTTP stack.

## Known related contracts (not chat)

| Method | Path | Status in repo docs | Role |
|---|---|---|---|
| GET | `/v1/activity` | documented | Social activity, **not** unread messages |
| GET | `/v1/connections` `/v1/connections/requests` | bearer | Follow graph, **not** message requests |
| GET | `/v1/reels` | public seed | Short-form seed cards, **not** messaging |
| GET | `/v1/media/stories/:file` | profile media | File serve, **not** a story/conversation list |
| GET | `/v1/discover` | public | Dashboard blob; `reels[]` is discovery seed |
| GET/POST/DELETE | `/v1/profiles/:id/follow` | bearer | Follow, **not** DM permission |

No native or migration document currently lists:

- `/v1/conversations`
- `/v1/messages`
- `/v1/in-mail`
- `/v1/chats`
- WebSocket / SSE / push message delivery
- typing, presence, read receipts, mute, archive, conversation delete
- attachment upload for chat
- In-Mail privacy (`Everyone` / `Followers` / `Connections` / `Nobody`)

Expo inventory mentions `ApiStories` / `ApiReels` TypeScript repositories as **source presence**, not verified Greenfield HTTP.

## Capability map used by native N4C

`MessagingBackendCapabilities.production` and `InMailBackendCapabilities.production` default to **all mutation/list flags off** until VPS confirms routes.

| Concern | Native stance |
|---|---|
| Conversation list | Architecture + decoder ready; **no production GET** |
| Send / receive | Architecture; send fails closed with draft retained |
| Pagination | Cursor page shape mirrored from other Greenfield lists |
| Unread count | Not derived from loaded rows; account-wide badge **off** |
| Read receipts | UI omitted |
| Presence / typing | UI omitted |
| Attachments | Composer has no attachment buttons |
| Message requests | UI ready; accept/decline **off** |
| Realtime | Poll/refresh boundary only. No fake live socket |
| E2EE / Vault Chat / Encrypted labels | **Never shown** |
| In-Mail | Separate domain; list/composer/thread UI; **no production POST** |
| In-Mail privacy setting | Capability designed, setting **not exposed** |
| Local cache | In-memory only. No Documents JSON dumps |
| Logging | Conversation/message IDs and latency only. **Never body text** |

## Provisional paths (do not call until capability is true)

These are placeholders for Mac/VPS closeout. They are **not** verified:

```
GET  /v1/conversations?limit=&cursor=
GET  /v1/conversations/:id/messages?limit=&cursor=
POST /v1/conversations/:id/messages
POST /v1/conversations/:id/read
GET  /v1/message-requests
POST /v1/message-requests/:id/accept
POST /v1/message-requests/:id/decline
GET  /v1/in-mail?limit=&cursor=
GET  /v1/in-mail/:threadId
POST /v1/in-mail
POST /v1/in-mail/:threadId/replies
```

If VPS shows different paths, replace these constants in `MessagingBackendCapabilities.Paths` / `InMailBackendCapabilities.Paths`. Do not invent a second client.

## Decoder honesty

`MessagingPayloadDecoder` / `InMailPayloadDecoder` accept Greenfield-like `{items,nextCursor,hasMore}` envelopes so a live audit can flip flags without rewriting models. Production repositories throw `APIError.unavailable` while flags are false.

DEBUG / PREVIEW fixtures exist for SwiftUI previews and unit tests. They are **not** a production fallback.
