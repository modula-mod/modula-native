# Creation / publishing backend audit (N4F)

Audit date: 2026-09-16.  
Remote agent run on private worker. **GREENFIELD LIVE AUDIT: OPEN**.

Status vocabulary (one per capability):

| Status | Meaning |
|---|---|
| **VERIFIED** | Confirmed against live VPS or a prior N3C VPS source read of the running Greenfield tree |
| **SOURCE-ONLY** | Present in repository docs / Expo inventory / native DTOs, not live-confirmed this run |
| **MISSING** | No honest contract in this checkout |
| **OPEN — VPS** | Exists as a claim or inference; SSH required |

## Remote probe status

| Probe | Result |
|---|---|
| `ssh modula-vps` | **OPEN — VPS** |
| Live HTTP `POST /v1/posts` | **OPEN — VPS** |
| Media upload | **OPEN — VPS** |
| Link preview | **MISSING** / **OPEN — VPS** |

Prior N3C audit (`home-feed-backend.md`) remains the last verified VPS source read (`ssh modula-vps` → `/root/modula-latest/services/greenfield-api`).

## Capability matrix

| Capability | Status | Evidence | Production UI |
|---|---|---|---|
| Create post (`POST /v1/posts`, `post:create`) | **VERIFIED** (endpoint in N3C source) / body **OPEN — VPS** | home-feed-backend.md, post-system-backend.md | Text only, conservative encoder |
| Edit post | **OPEN — VPS** | N4B inferred `PATCH /v1/posts/:id`; `editOwnPost = false` | Off |
| Delete post | **OPEN — VPS** | N4B inferred `DELETE /v1/posts/:id`; `deleteOwnPost = false` | Off |
| Text body | **SOURCE-ONLY** | `SocialPostDto.text` | On with create |
| Single image | **SOURCE-ONLY** read / upload **OPEN — VPS** | `PostMediaDto.kind = image`; `GET /v1/media/:file` | Publish off |
| Multiple media / carousel | **SOURCE-ONLY** | Native render if `media.count > 1` | **CAROUSEL PUBLISHING — OFF** |
| Video | **MISSING** in DTO | post-system-backend.md | Architecture only |
| Link | **SOURCE-ONLY** read | `SocialPostDto.link` | Structured publish off; URL may live in text |
| Poll | **MISSING** | Not in SocialPostDto | Composer behind capability (off) |
| Audio | **MISSING** | Reserved kind | Architecture only |
| Movie | **MISSING** | Distinct future kind | Architecture only |
| Mentions (structured) | **MISSING** | No entity write field | Architecture extract only |
| Hashtags / topics | **MISSING** | No composer topic API | Architecture extract only; reuse Discover/search later |
| Location on post | **MISSING** | Profile location ≠ post attachment | Off; no GPS permission |
| Audience / visibility | **SOURCE-ONLY** | `audience?: public \| followers \| private` | Picker uses these three only |
| Media upload | **OPEN — VPS** | Serve path exists; upload path unverified | Uploader protocol; production adapter disabled |
| Upload limits / MIME / size | **OPEN — VPS** | — | No invented limits |
| Image transforms | **OPEN — VPS** | — | Client re-encodes JPEG (strips EXIF) before any future upload |
| Video transforms | **MISSING** | — | Off |
| Link preview endpoint | **MISSING** | Do not scrape websites from Swift | Off |
| Draft server storage | **MISSING** | N4D local `DraftStore` | Local only |
| Scheduled publishing | **MISSING** | — | Off |
| Story creation | **OPEN — VPS** | N4C `create = false`; media serve `GET /v1/media/stories/:file` | Off |
| Reel creation | **MISSING** | N4C viewer only | Off |
| Character limit | **MISSING** | — | No 280-character invention; hide counter |
| Reply permission on create | **SOURCE-ONLY** | social-inventory.md | Not sent |
| Idempotency key | **SOURCE-ONLY** | social-inventory.md | Sent on text create |

## Conservative text create payload (N4F)

Encoder emits only:

```text
POST /v1/posts
Authorization: Bearer <native session>
{
  "text": String,
  "kind": "text",
  "audience": "public" | "followers" | "private",
  "idempotencyKey": String
}
```

No media, poll, link object, mentions, location, or guessed fields.

Live acceptance remains **OPEN — VPS**. Failure keeps the local draft.

## Media metadata privacy (client, before any upload)

When the image pipeline re-encodes via bitmap → JPEG:

| Survives | Stripped |
|---|---|
| Pixel content (downsampled) | EXIF, GPS, camera/device metadata, original filename |

Documented because production upload is still off; the strip happens at prepare time so drafts do not retain picker EXIF blobs unnecessarily.

## Do not invent

- Extra POST endpoints
- Fake poll-as-text
- Fake video upload progress
- Client-side 24-hour story expiry authority
- Inner Circle / Teams audiences
