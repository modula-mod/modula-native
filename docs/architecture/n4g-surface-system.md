# N4G — Visual language, Edge Loop, immersive surfaces

N4G is presentation and interaction convergence. It does not add Greenfield endpoints, feeds, or social writes.

## Keep / do not copy

Keep: full-bleed imagery, edge-docked loop, cover/avatar geometry, media-forward posts, glass controls, strong typography, depth, immersive product pages.

Do not copy from mockups: duplicate Home tabs + rail, Profile five-tab strip, center + destination, fake ratings/downloads, fake module features, fake video, hardcoded scenic photography.

## A — Edge Loop / Edge Picker

```text
EdgeLoopEngine
├── ModulaEdgeLoop          shell-edge or contained
├── ShellEdgeLoop           Home / Activity / Profile + Appearance prefs
└── ContainedLoopPicker     Typography sample reel
```

Contract:

- `items`, `selection: Binding<Item.ID>`, `behavior: looping | bounded`, `position: leading | trailing`
- Caller owns navigation meaning
- Drag state is local; only committed selection updates screen context
- Notch aperture is spatially stable; items reel through it
- Vertical label reveal along the rail (On Change / Always / Icons Only)
- Liquid Glass body via `edgeLoopBody` / `edgeLoopSelection` / `edgeLoopReveal`
- VoiceOver: single adjustable control, N of M, drag not required; loop clones hidden
- Reduce Motion / Reduce Transparency win over Edge Picker overrides
- Haptic: one `.selection` per item boundary (+ optional tick), not per pixel
- Preferences: Appearance → Edge Picker (`/settings/appearance/edge-picker`)

See `docs/design/edge-picker.md`.

Used on: Home (Following / For You / Modules), Activity (All / Mentions / Requests), Profile (Overview / Posts / Modules). Not used for Settings lists, Product Hub, search, or conversations.

## B — Immersive surfaces

`FullBleedHero`, `FloatingHeroControls`, `AvatarPocketShape`, `ArtworkPocket`, `OnboardingHeroScene`.

Cover starts at the physical top edge. Identity (avatar / artwork) is carved into the cover/content seam.

## C — Surface system

Semantic tokens, not scattered `cornerRadius(28)` / `.ultraThinMaterial`:

- `ModulaMaterial`: none, content, floating, control, immersiveOverlay, edgeLoopBody, edgeLoopSelection, edgeLoopReveal
- `ModulaShapeRole`: canvas, contentCard, control, capsule, floatingControl, media, edgeLoop, avatarPocket
- `ModulaDepth`
- `TrailingInteractionSafeArea` / `EdgeInteractionSafeArea` so Edge Picker and `PostActionRail` do not collide (side-aware)

Liquid Glass belongs on floating Back/Share/More, Edge Loop selected state, post action rail, bottom shell, selected onboarding rows. Not on every card.

## D — Core screens

Home: Modula + Create + Messages, compact Stories (~78–86pt), feed immediately, Edge Loop only (no horizontal mode tabs).

Profile: full-bleed cover, carved avatar pocket, Edge Loop Overview / Posts / Modules. About / Links / Modules stay overview content.

Module Detail: cover-driven product page. No fabricated ratings, reviews, or download counts.

Onboarding: brand atmosphere scene, large statement, three value rows, Next / Create Account. No scenic photos.

## E — Posts

Canonical `PostCard` / `PostActionRail` only. Rail shows React / Comment / Save / Share with truthful counts. Distinct from Edge Loop.

## F — Typography

Appearance → Font Family preview shows Letters / Numbers / Body / Symbols via a contained loop that does not cover the sample.

## Destinations

Five root tabs remain Home, Discover, Modules, Activity, Profile. No center +.
