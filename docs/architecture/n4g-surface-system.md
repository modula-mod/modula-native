# N4G — Visual language, Edge Loop, immersive surfaces

N4G is presentation and interaction convergence. It does not add Greenfield endpoints, feeds, or social writes.

## Keep / do not copy

Keep: full-bleed imagery, edge-docked loop, cover/avatar geometry, media-forward posts, glass controls, strong typography, depth, immersive product pages.

Do not copy from mockups: duplicate Home tabs + rail, Profile five-tab strip, center + destination, fake ratings/downloads, fake module features, fake video, hardcoded scenic photography.

## A — Edge Loop

```text
EdgeLoopEngine
├── ModulaEdgeLoop          shell-edge or contained
├── ShellEdgeLoop           Home / Activity / Profile adapter
└── ContainedLoopPicker     Typography sample reel
```

Contract:

- `items`, `selection: Binding<Item.ID>`, `behavior: looping | bounded`, `position: trailing`
- Caller owns navigation meaning
- Drag state is local; only committed selection updates screen context
- Notch height is stable; items move through a centred aperture
- Selected cell expands (~46 → ~96pt) then retracts after 1.75s
- VoiceOver: adjustable increment/decrement, N of M, drag not required
- Reduce Motion: short fade instead of kinetic reel
- Haptic: one `.selection` per item boundary, not per pixel

Used on: Home (Following / For You / Modules), Activity (All / Mentions / Requests), Profile (Overview / Posts / Modules). Not used for Settings lists, Product Hub, search, or conversations.

## B — Immersive surfaces

`FullBleedHero`, `FloatingHeroControls`, `AvatarPocketShape`, `ArtworkPocket`, `OnboardingHeroScene`.

Cover starts at the physical top edge. Identity (avatar / artwork) is carved into the cover/content seam.

## C — Surface system

Semantic tokens, not scattered `cornerRadius(28)` / `.ultraThinMaterial`:

- `ModulaMaterial`: none, content, floating, control, immersiveOverlay
- `ModulaShapeRole`: canvas, contentCard, control, capsule, floatingControl, media, edgeLoop, avatarPocket
- `ModulaDepth`
- `TrailingInteractionSafeArea` so Edge Loop and `PostActionRail` do not collide

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
