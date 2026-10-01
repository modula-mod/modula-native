# Story media upload: proxy limit and the server change still needed

Status: client fix on `fix/story-upload-login-redesign`. nginx is being raised
(25 MiB JSON body on prod and N1, 101m for attachment PUTs); the API change below is
**not** done.

## Root cause (verified 2026-10-01)

- Greenfield `POST /v1/stories` (`services/greenfield-api/src/app/register-phase7f-stories-routes.ts`,
  `domains/stories/service.ts` in `modula-latest*`) accepts **only** inline media:
  `{ mediaKind, base64, contentType, width, height, caption?, visibility? }`. It writes
  `Buffer.from(base64)` to `mediaRoot/stories`. There is no attachment/upload-id
  field, and `StoryService` has no reference to the attachments domain.
- Both edges cap request bodies at 1 MiB: `ops/nginx/api.modula.digital.conf` and
  `scripts/n1/nginx-native-n1.conf` set `client_max_body_size 1m`. Fastify's own
  limit (`MODULA_REQUEST_BODY_LIMIT_BYTES`, default 4 MiB) is never reached.
- The composer prepares a 2048px JPEG at q0.86 (`MediaPreparation`). Real photos
  are usually 0.8–2 MB, so the base64 JSON body (≈4/3 of the bytes, plus `\/`
  escaping from `JSONEncoder`) exceeds 1 MiB. nginx answers with an HTML 413;
  the client failed to decode it and showed "Couldn't share your story."
  Probe (`~/modula-sim/probe-post-stories.txt`): prod accepted a 1,013,426 B body
  and returned 413 for 1,066,758 B; N1 behaves the same.
- Post attachments use `POST /v1/attachments/uploads` + `PUT …/content` (raw
  bytes, route `bodyLimit` 100 MiB). That route exists on production but returns
  404 on N1. Per the checked-in nginx configs its `PUT` also passes the same
  1 MiB limit (no per-location override), so post attachments over ~1 MiB are
  likely rejected too; not verified against the live edge.

## Client behaviour (this branch)

- Stories are prepared at full-screen quality: long edge 3072px (when the source is
  that large), JPEG q0.9 (`StoryUploadBudget.targetLongEdge` / `preferredQuality`).
- `StoryBackendRepository.uploadableBody` fits the JPEG to a byte budget derived
  from one constant, `StoryUploadBudget.maximumBodyBytes` (20,000,000 B JSON body,
  ≈14.7 MB raw JPEG; server limits are being raised to 25 MiB). Over budget only,
  `MediaPreparation.jpegFitting` lowers quality first (0.9 → 0.6) at 3072px; only
  if that still doesn't fit does it fall back to 2048px, then 1440px. The encoded
  JSON size is checked before sending; anything already within budget is sent as is.
- Story POSTs use a 120 s request timeout (`StoryUploadBudget.requestTimeout`)
  instead of the 20 s default.
- `GreenfieldClient.decodeEnvelope` maps non-JSON 413/429/5xx to
  `PAYLOAD_TOO_LARGE` / `RATE_LIMITED` / `SERVER_UNAVAILABLE` with user-facing
  copy, and logs them (`digital.modula.app.native`, category `network`).
- Requires the edge and API limits for `POST /v1/stories` to be ≥ 20 MB.

## Known server issues

- N1's `MODULA_PUBLIC_API_URL` is `https://localhost:44021`, so story `mediaUrl`s
  from N1 point at localhost and render as broken images in the app.

## Server change needed (recommended)

1. Let stories reference an uploaded attachment, e.g.
   `POST /v1/stories { attachmentId, caption?, visibility? }`, with
   `StoryService.create` resolving a `ready` attachment owned by the actor
   (image/jpeg|png|webp, video/mp4) instead of `base64`. Keep `base64` for
   compatibility. Advertise it (capability flag) so the client can switch to
   `GreenfieldMediaUploader` (`/v1/attachments/uploads` → `PUT …/content`) and
   send full-quality images.
2. In nginx, raise the body limit for the upload content route only, e.g.
   `location ~ ^/v1/attachments/uploads/[^/]+/content$ { client_max_body_size 100m; proxy_request_buffering off; proxy_read_timeout 300s; proxy_send_timeout 300s; proxy_pass … }`
   on both `api.modula.digital` and `native-n1.modula.digital`. `POST /v1/stories` needs ≥ 20 MB while it is inline base64; other JSON routes can stay at `1m`.
3. Deploy the attachments routes to N1 (currently 404) so acceptance tests cover
   the same path as production.
