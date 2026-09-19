# Reels backend audit (N4C)

Audit date: 2026-09-16. **`ssh modula-vps` not completed.** Public contract already recorded in `discover-backend.md`.

## Known

| Method | Path | Status | Role |
|---|---|---|---|
| GET | `/v1/reels` | public 200 (prod seed; N1 empty via discover) | Seed cards, **not** a ranked feed |
| GET | `/v1/discover` `reels[]` | public | Same seed shape inside the dashboard blob |

Documented seed shape:

```text
reels[]  {id, author, caption, source, colour, liked, likeCount, replyCount}
```

This is **not** a video playback contract. `source` is not treated as an AV URL. `colour` is a poster fallback. No duration, poster image, captions/subtitles, or audio attribution keys are documented.

## Native stance

- Reel domain can wrap seed cards and optionally a `SocialPost` when `postId` / video media exist
- Vertical viewer + paging architecture is native SwiftUI
- Engagement reuses N4B `PostStateStore` / `PostActionController` / `PostActionRail` / comments **when the reel is post-identity**
- Seed-only reels: like counts may render from the seed object; mutations stay capability-gated
- Discover may show a Reels shelf **only when the dashboard actually returned `reels[]`**
- Do not fabricate “Original sound”, transcription, or production playback
- `REELS LIVE DATA: OPEN` until VPS confirms a video media contract

`ReelBackendCapabilities.production.seedList = true` (path is documented). `videoPlayback`, `audioAttribution`, `rankedFeed`, `captions` remain false.
