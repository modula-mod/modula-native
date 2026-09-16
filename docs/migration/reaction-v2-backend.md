# Reaction System V2 backend contract (N4E)

Audit date: 2026-09-16.  
`ssh modula-vps` — **OPEN** (Shell exec-daemon returned no exit status).

## Current verified truth

N3C/N4B: like toggle only.

```text
POST   /v1/posts/:postId/like
DELETE /v1/posts/:postId/like
```

Native DTO fields: `liked`, `likeCount`, optional `viewerReaction`, `reactionCount`.

## Preferred Modula vocabulary (client)

Semantic identifiers, not emoji:

`like | love | laugh | wow | support | sad | angry`

N4B aliases still parse: `fire → wow`, `celebrate → love`, `insightful/curious → wow`.

## Required Greenfield contract (not live)

Until this is deployed and verified, native `PostBackendCapabilities.multiReactions` and `ReactionBackendCapabilities.multiReactionHTTP` stay **false**. Simple tap remains Like.

### Summary on post payloads

```json
{
  "total": 128,
  "viewerReaction": "love",
  "breakdown": {
    "like": 64,
    "love": 41,
    "laugh": 8,
    "wow": 7,
    "support": 4,
    "sad": 3,
    "angry": 1
  }
}
```

Do not fabricate breakdown from visible users.

### Mutations (proposed, unverified)

```text
PUT    /v1/posts/:postId/reactions   { "kind": "love" }
DELETE /v1/posts/:postId/reactions
GET    /v1/posts/:postId/reactions?kind=
```

If Greenfield already defines different identifiers, backend wins. Native `ReactionKind` must be remapped after VPS inspection.

## Native status

- Domain + picker architecture: shipped
- HTTP multi-reaction: **OFF**
- People list: truthful unavailable until `reactionsList` is verified
