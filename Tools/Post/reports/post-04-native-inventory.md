# POST-04 native inventory

Date: 2026-09-27
Start: `b2ff94d35e5ebf7243f855ab11c6b8d87b2f1f98` (`origin/main`)

## Existing architecture to extend

- Creation is centralized under `Features/Creation`: `CreationDraft`, `CreationStudioStore`, `CreationStudioView`, `DraftStore`, `DraftMediaStore`, `PublishingRepository`, and `MediaUploading`.
- `CreationDraft` already persists ordered media, an idempotency key, audience, link/poll metadata, and the canonical publishing lifecycle (`editing` through `published`/`failed`/`cancelled`).
- `DraftMediaStore` uses the app-private `PrivateFileStore`; picker URLs and credentials are not persisted.
- `MediaUploading` already defines progress/cancellation/background capability reporting, but production is intentionally wired to `DisabledMediaUploader`.
- `GreenfieldPublishingRepository` publishes only text to `/v1/posts`; `CreationCapabilities.production` truthfully disables media.
- POST-03 already supplies `ModulaAttachment`, ordered post content mapping/rendering, image/video/PDF/document/audio/link views, `AttachmentDownloadManager`, PDF/QuickLook/media viewer routing, attachment states, and Content & Posts catalog fixtures.
- MCAT supplies the shared reaction, context, sheet, overlay, composer, indicators, tabs, and media viewer primitives. No parallel component stack is required.
- `GreenfieldClient` owns authenticated JSON transport and Keychain-backed sessions. Binary upload needs an authenticated file-transfer method on this actor, not another auth client.

## Gaps confirmed

- Photos are currently metadata-stripped and downscaled into JPEG draft files. POST-04 must retain the selected original in the upload staging area and generate a separate lightweight preview.
- Production picker support is image-only. Video/audio/PDF/document import needs `PhotosPicker`/`fileImporter` plus security-scoped staging.
- Per-attachment remote ID, state, progress, MIME, checksum, error, and server processing status are not represented in the persisted draft.
- Publish never invokes the uploader and cannot preserve successful uploads when another asset fails.
- There is no bounded upload coordinator or real URLSession byte progress.

## POST-03 debt

- `N3CHomeUITests` still taps `For You`; accepted Edge Picker behavior is drag/scrub (or VoiceOver adjust). Tests must use the accessibility-adjust path or coordinate drag, not change production behavior.
- Real-binary fixture and 50+ mixed-feed routes exist only partially; acceptance needs JPEG/PNG/MP4/audio/PDF/QuickLook and profiling evidence.
- Debug model preparation and Release exclusion are intentional NODUS-01D packaging behavior. The reported Release R7 discrepancy is a verification/reporting ambiguity unless the build scripts prove otherwise; production Release must continue to exclude R7 by default.

## Decision

Extend `CreationDraft` and `CreationStudioStore`; implement a Greenfield attachment uploader behind `MediaUploading`; keep POST-03 `ModulaAttachment` and viewer routing authoritative. Do not create a second composer, post renderer, attachment viewer, auth stack, or download cache.
