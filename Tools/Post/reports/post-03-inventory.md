# POST-03 Repository Inventory

Date: 2026-09-27

## Repository truth

- Repository: `/Users/msjoy/Developer/modula-native`
- Base: `origin/main`
- Start SHA: `166e1b2f9de0c68f9081547398846d21edc8613d`
- Work branch: `phase-post-03-rich-content-system`
- Local `main` matched `origin/main` at the start gate.
- The pre-existing protected `.cursor/hooks/state/continual-learning.json` modification is user-owned and will not be staged, discarded, or committed.

## Current post domain

- `Features/Social/PostModels.swift` owns `SocialPost`, `SocialPostMedia`, `SocialPostLink`,
  `SocialPostModule`, engagement, comments, and the current Greenfield JSON decoder.
- `SocialPost` is the presentation-facing shape today. SwiftUI directly switches over its backend-oriented
  `kind`, `media`, `link`, and `module` fields.
- `SocialPostMedia` carries only `id`, optional URL/alt text, string kind, and optional aspect ratio.
  It has no MIME type, filename, byte size, poster/preview URLs, duration, or document metadata.
- `DiscoverPost` and `DiscoverPostMedia` form a second lightweight post/media representation. The accepted
  adapter `DiscoverPost.asSocialPost()` is the convergence point and should ultimately map into the canonical
  post representation instead of creating a third renderer.
- The native boundary needed by POST-03 is therefore:
  `Greenfield JSON -> SocialPost DTO compatibility -> ModulaPost mapper -> PostContentBlock renderer`.

## Current post rendering

- `PostCard`, `PostHeader`, `PostBody`, `PostMediaView`, `PostCarouselMedia`, `PostLinkPreview`,
  `PostActions`, and `PostMetadata` live in `Features/Social/PostComponents.swift`.
- `PostRendererRegistry` is already the repository-consistent renderer entry point, but it switches over
  `SocialPostKind` and cannot render documents, PDFs, or mixed ordered blocks.
- Single images and carousels use `AsyncImage`; loaded images are `scaledToFill` into fixed feed heights.
  Very tall images can therefore crop aggressively.
- `PostDetailView` uses the same renderer and MCAT `ModulaMediaViewer`, but only opens a single image.
- Home uses `PostCard`; Profile/Discover/Search ultimately converge on the social post/card surfaces.

## Existing media and viewers

- `Features/Media/MediaModels.swift` defines `MediaResource` for image/video/audio URLs, poster URL,
  dimensions, duration, and a logical cache key.
- `Features/Media/ModulaVideoPlayer.swift` already uses AVKit/AVPlayer with a shared playback controller,
  tap play/pause, scene-background pause, poster state, and accessible play/pause action.
- There is no feed-wide active-player coordinator, visibility registry, seek/progress contract, or full-player
  surface.
- MCAT-02 consolidated `DesignSystem/ModulaMediaViewer.swift` for image paging, zoom, double-tap zoom,
  paging/zoom arbitration, and interactive dismissal. POST-03 must reuse it.
- No post PDFKit viewer, PDF preview renderer, QuickLook adapter, audio player, or universal attachment router
  exists.

## Context, reactions, comments, share, and save

- `PostActionRail` already supports media-post vertical actions and downward morph into real context actions.
- `PostReactionPicker` is a compatibility wrapper around MCAT `ModulaReactionBar`.
- `PostContextActions` capability-gates save, collection, share, copy, hide, edit, delete, report, and mute.
  Unsupported operations are not exposed.
- `PostCommentsView` uses the shared MCAT composer and `PostCommentsSheet` uses `ModulaSheet`.
- `PostDetailView` and Home route sharing through the accepted Universal Share surface or system `ShareLink`.
- `PostStateStore` is the shared engagement overlay for feed/detail consistency.

## Networking and backend DTO truth

- `GreenfieldClient` is the accepted native networking boundary.
- `GreenfieldHomeRepository` and `GreenfieldPostRepository` own post, engagement, and comment HTTP calls.
- Production post creation is intentionally text-only. `CreationCapabilities.production` declares photo,
  carousel, video, link, audio, and media-upload capabilities false.
- `GreenfieldPublishingRepository` sends only the documented text-post body; every unsupported kind fails
  honestly with `APIError.unavailable`.
- `DisabledMediaUploader` is the production adapter until a verified Greenfield upload contract exists.
- POST-03 must not enable or simulate unsupported uploads. Catalog/development fixtures may demonstrate all
  renderer types without creating production fake posts.

## Draft and picker architecture

- Creation Studio uses native `PhotosPicker` for images and app-private `DraftMediaStore` for prepared JPEGs.
- Draft media is stored through `PrivateFileStore` with complete-file-protection-until-first-authentication.
- Draft models already reserve image/video/audio kinds, ordering, dimensions, duration, byte count, alt text,
  and accessibility metadata.
- There is no Files picker or general document draft store yet. POST-03 may add truthful local attachment
  preview contracts, but must leave publishing disabled unless Greenfield capability truth changes.

## Caching and downloads

- Network responses and `AsyncImage` rely on `URLCache.shared`; there is no shared decoded-image cache.
- `MediaCacheKey` exists but has no cache implementation.
- Profile has a narrow in-memory avatar/photo cache that is not appropriate as a universal attachment cache.
- No downloads subsystem exists; Settings explicitly says so.
- POST-03 should add a bounded thumbnail cache and an attachment download manager using app-private cache or
  Application Support storage, deduplicated in-flight tasks, cancellation, truthful state, and protected files.
- Preview priority must remain server thumbnail -> cached thumbnail -> local native generation. Large original
  documents should not be fetched merely to render a feed cell when a preview URL exists.

## Apple framework availability

- AVKit/AVFoundation are already imported and used.
- PDFKit is already available in the application build through Nodus PDF importing/tests, but not used by posts.
- UniformTypeIdentifiers is already used by creation and Nodus imports.
- QuickLook has no existing wrapper in the post/media stack and requires a small native adapter.
- No third-party carousel, media, PDF, document, or animation framework is present or needed.

## Components Catalog and test architecture

- `ComponentCatalogView` is the canonical developer catalog and already links to MCAT-02 Advanced Interaction.
- POST-03 will add one `Content & Posts` hierarchy to the same catalog, not another shell.
- Native unit tests live in `ios/ModulaTests`; UI traversal is in `ios/ModulaUITests/NativeLaunchTests.swift`.
- Existing post tests cover decoding, carousel mapping, engagement, context capability gating, gestures,
  comments, accessibility summary, Discover conversion, and real capability boundaries.

## Consolidation decisions

1. Preserve `SocialPost` as the Greenfield compatibility DTO and introduce a canonical `ModulaPost` mapper.
2. Expand the accepted media concepts into `ModulaAttachment`; MIME type is authoritative when supplied.
3. Evolve `PostRendererRegistry` into `ModulaPostContentRenderer` and keep compatibility wrappers for routes.
4. Reuse MCAT context, reaction, sheet, composer, overlay, sharing, indicators, and image viewer components.
5. Evolve the AVPlayer controller rather than add another video stack.
6. Add native PDFKit and QuickLook viewers behind a universal attachment routing contract.
7. Add bounded/deduplicated cache/download primitives; do not pretend uncached remote content is offline.
8. Keep upload capability false and document backend gaps rather than fake media publishing.
9. Keep catalog fixtures development-only; production Home continues to render only backend posts.
