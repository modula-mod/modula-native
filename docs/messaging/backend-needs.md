# Messaging: native features waiting on server support

The native DM polish (inbox, conversation, composer) uses only the Greenfield
endpoints that are live today:

| Endpoint | Used for |
| --- | --- |
| `GET /v1/conversations` | Inbox list, unread counts, last-message preview |
| `GET /v1/conversations/:id/messages` | Thread |
| `POST /v1/conversations/:id/messages` (`{ text }`) | Send |
| `POST /v1/conversations/:id/read` | Mark read (on open, swipe, context menu) |
| `GET /v1/conversations/unread` | Account unread total |
| `GET /v1/message-requests`, `POST …/accept`, `POST …/decline` | Requests |

Everything below is **not built** on the native side beyond what is noted,
because it needs new server behaviour. `MessagingBackendCapabilities` keeps each
flag `false` until the server ships it, and the UI hides the control.

## Needed from the server

1. **Typing indicators** (`capabilities.typing`). Needs a realtime channel
   (WebSocket/SSE) with `typing.start` / `typing.stop` per conversation, rate
   limited, and never persisted. Native: show the three-dot glass bubble at the
   end of the thread while a peer is typing.
2. **Realtime delivery** (`capabilities.realtime`). Push new messages, read
   receipts and edits over the same channel; today the thread refreshes on open
   and pull-to-refresh only.
3. **Per-message read/delivered state** (`capabilities.readReceipts` is on).
   The client reads `delivery`/`status` on each message (`sent`, `delivered`,
   `read`). Please return `read` with a `readAt` timestamp on the sender's copy
   once the recipient calls `/read`, so "Read 2m ago" shows the real time
   (today it shows the message time).
4. **Reactions** (`capabilities.reactions`, new). `POST /v1/messages/:id/reactions`
   `{ emoji }`, `DELETE …/reactions/:emoji`, and `reactions: [{ emoji, count,
   viewerReacted }]` on each message. Native: long-press tapback bar and a
   reaction pill under the bubble.
5. **Replies** (`capabilities.reply`). A `replyToId` on send and a
   `replyTo: { id, senderName, excerpt }` on read. Until then the composer's
   reply chip sends the quoted line as plain text (`> …`).
6. **Media attachments** (`capabilities.attachments`). Upload (signed URL or
   multipart) returning a media id, then `{ text, mediaIds }` on send and
   `media: [{ id, kind, url, width, height, thumbnailUrl }]` on messages. Size and
   type limits, virus scanning, and EXIF stripping server-side.
7. **Edit / delete own** (`capabilities.edit`, `capabilities.deleteOwn`).
   `PATCH /v1/messages/:id` and `DELETE /v1/messages/:id` with tombstones.
8. **Mute / archive / pin conversations** (`capabilities.mute`, `archive`).
   Per-viewer flags on the conversation plus a filter on `GET /v1/conversations`.
9. **Server-side search** across all conversations. Search in the inbox is local
   to loaded conversations today and says so.
10. **Report message / block from chat** (`capabilities.report`).
11. **Presence** (`capabilities.presence`): "Active now" in the header.

## DEBUG-only fixture

`--debug-messages-fixture` (with `--uitest-local-module-session`) seeds the inbox and a
thread for screenshots. It is compiled out of Release and never calls the server.
