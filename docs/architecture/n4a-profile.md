# N4A — Profile production interaction system

Branch: `cursor/phase-n4a-ios-profile-polish`  
Depends on: N3D Profile checkpoint `3a507ec`  
Greenfield audit: `docs/migration/n4a-profile-capabilities.md`

## What shipped

### Visual system
- Full-bleed `ProfileCover` with accent-derived geometric fallback, loading/failure paths, scroll dissolve into progressive blur
- `ProfileAvatarPocket` carve geometry intersecting cover/content edge
- Compact progressive header identity (avatar + name + handle)
- Slimmer context rail (Overview / Posts / Modules only) with shape+fill selection
- Lighter Profile selected tab pill; tool-focused accessory (`Edit` / `Share` / `More`)

### Interaction
- `ModulaMediaViewer` for avatar/cover (pinch, double-tap zoom, swipe dismiss, share)
- Ownership-aware `ProfileContextActions` + reusable `ModulaContextAction` / `ModulaContextMenu`
- Profile share sheet + **My Modula Code** QR (canonical `https://modula.digital/profile/<handle>` only)
- Follow morph busy state + `lightImpact` → `followComplete` / `failure` haptics
- Report via `POST /v1/reports` (spam / harassment / other)
- Post context menus (supported actions only; edit/delete disabled until contracts exist)

### Overview polish
- Compact compositional metrics row with selection haptics
- About grid collapses to one column at accessibility Dynamic Type
- Role-aware empty states (posts / modules / links) — no catalogue/OAuth technical copy

### Haptics
Expanded `HapticSemantic` and Profile map routed exclusively through `HapticEngine` (Off respected).

### Editing
Live preview header; Save / Saving… / Saved; unsaved Save / Discard / Cancel; writable fields remain Greenfield-true (`displayName`, `bio`, `visibility`).

## Explicitly not invented
- Avatar/cover upload, remove, reposition
- Featured module reorder/curation writes
- Follow `Requested` state
- Message CTA
- Fake verification

## Acceptance notes
- Debug build: PASS (`Modula.xcworkspace`)
- Profile unit tests: run via workspace + simulator
- Physical device `modula.digital` available for haptic/media review
- Release/Metro-off and full visual matrix remain operator-verified on device
