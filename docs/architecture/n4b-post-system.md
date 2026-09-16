# N4B Post interaction architecture

Native ownership: Swift + SwiftUI under `ios/Modula/Features/Social/`.  
React Native has no role in ordinary social posts.

## Layout

```text
Social/
  PostModels.swift              Canonical SocialPost / SocialComment / decoder
  PostBackendCapabilities.swift Honest capability flags + provisional comment paths
  PostStateStore.swift          Shared engagement cache by post ID
  PostActionController.swift    Optimistic like/save/repost + race generations
  PostRepository.swift          Greenfield post/comment networking
  PostGestureThresholds.swift   Centralized gesture ownership constants
  PostContextActions.swift      Own/other menus on ModulaContextAction
  PostComponents.swift          PostCard, header/body/actions, renderer registry
  PostReactionPicker.swift      Floating like-anchored picker (like-only commit)
  PostActionRail.swift          Media rail + drag-to-context morph
  PostCommentsView.swift        List + composer + sheet detents
  PostDetailView.swift          /post/:id sections + share/edit/people honesty
```

## Shared state

```text
Home / Profile / Discover / Detail
        │
        ▼
 PostActionController ──► GreenfieldPostRepository
        │
        ▼
   PostStateStore (by ID)
```

Liking on Home updates Profile/Discover/Detail without app restart when the same ID is resolved through `posts.resolved(_:)`.

## Renderers

`PostRendererRegistry` selects content by `SocialPostKind` while shared chrome (`PostHeader`, `PostActions`, `PostMetadata`) stays shared. Reserved kinds (video/poll/audio/movie) never fabricate playback UI.

## Gestures

| Zone | Owner |
|---|---|
| Feed vertical scroll | ScrollView (dominant) |
| Reaction long-press | Like control only |
| Reaction scrub | Picker local state |
| Action rail drag | Rail hit-region + vertical dominance |
| Comments swipe-up | Comment bar zone |
| Media carousel | Media bounds + horizontal dominance |
| Interactive Back | System edge |

Thresholds live in `PostGestureThresholds`.

## Reactions

Domain enum includes multiple values; HTTP remains **like toggle** until a dedicated reaction route exists. Picker UI + VoiceOver “React” action are present; non-like commits are capability-gated off.

## Comments

Provisional paths (see `post-system-backend.md`). Draft text is preserved on send failure. Sheet presentation for feed; full route for deep links.

## Remote gates

SSH / Xcode / Simulator / physical device / Metro-free Release may remain OPEN on remote runs without exec. Unavailable infrastructure ≠ PASS.
