# MCAT-02 Repository Inventory

Date: 2026-09-26

## Repository truth

- Repository: `/Users/msjoy/Developer/modula-native`
- Base branch: `origin/main`
- Start SHA: `8752f767ae302639c4a2844ac9ac15fbfc29e55b`
- Work branch: `phase-mcat-02-advanced-interaction-components`
- `main` and `origin/main` matched at the start gate.
- The canonical checkout contained one pre-existing protected modification at
  `.cursor/hooks/state/continual-learning.json`. MCAT-02 will not modify, discard, stage, or commit it.

## Existing architecture to reuse

### Components Catalog

- `ComponentCatalogView` in `Features/Settings/SettingsView.swift` is the canonical DEBUG catalog.
- It is reachable through `/developer/components`, Settings → Developer, the sidebar, Command Center,
  and the shell accessory.
- It already includes live Appearance controls and examples for core controls, typography, identity,
  states, navigation chrome, Edge Picker, messaging, stories, creation, and commands.
- MCAT-02 will extend this catalog with one `Advanced Interaction` hierarchy. It will not create a
  second catalog.

### Design tokens, theme, type, spacing, corners, materials, and shadows

- `DesignSystem/ModulaDesignSystem.swift` owns `ModulaSpacing`, `ModulaRadius`, `ModulaLayout`,
  `ModulaMotion`, `HapticEngine`, the icon registry, `ModulaPalette`, typography, controls, badges,
  cards, rows, sheets, and common states.
- `AppearanceStore` is the sole appearance authority. It provides Light/Dark/System, Dark/Dim/OLED,
  Modula Teal `#369CAA`, density, Dynamic Type scaling, motion personality, haptic intensity,
  transparency/contrast, icon style, and shape style.
- `DesignSystem/Surface/ModulaSurfaceSystem.swift` owns semantic materials, shape roles, depth/shadow
  roles, interaction insets, and count formatting.
- MCAT-02 should extend these existing roles and keep appearance resolution environment-driven.

### Motion and haptics

- `ModulaMotion.animation` already centralizes selection/navigation/morph/reveal/dismiss/rail/sheet
  animations and accepts both motion personality and Reduce Motion.
- `HapticEngine` is centralized and respects the Appearance haptic setting.
- Existing semantic events cover selection, context open, reaction selection, confirmation, warning,
  drag thresholds, and drops. MCAT-02 will add only missing semantic aliases/events required by the
  mission and will route all components through this engine.

### Accessibility

- Existing components use SwiftUI accessibility labels, values, traits, actions, minimum 44-point
  targets, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, and Dynamic Type.
- No separate accessibility helper framework exists. MCAT-02 should use native environment values
  and small component-local contracts rather than add a parallel framework.

### Navigation, sheets, and overlays

- `NavigationCoordinator`, typed `AppRoute`, `PresentationCoordinator`, and `ShellChromePolicy` are
  authoritative. MCAT-02 must not create another navigation framework.
- Presentation is currently fragmented across `.sheet`, `.fullScreenCover`, `.popover`, and local
  overlays. The existing `ModulaSheet` is only a `NavigationStack` with medium/large detents.
- No reusable overlay host/route contract exists. MCAT-02 will add presentation infrastructure only,
  without taking over route navigation.

### Context menus

- `DesignSystem/ModulaContextMenu.swift` already defines `ModulaContextActionRole`,
  `ModulaContextAction`, and a native `Menu` wrapper.
- Post, Profile, Message, and comment action registries already consume the action model, while many
  views still render ad-hoc `.contextMenu` buttons.
- MCAT-02 will extend this accepted contract with grouping, submenus, previews, custom context-host
  presentation, dismissal behavior, accessibility actions, and native-menu fallback.

### Reactions

- `PostReactionPicker` already supports tap and horizontal scrub selection, current selection,
  centralized thresholds, Reduce Motion, accessibility, and haptics.
- It is coupled to `SocialReaction` and Posts. `PostActions` owns its presentation.
- MCAT-02 will consolidate this behavior into generic `ModulaReactionBar` contracts and make
  `PostReactionPicker` a compatibility/adoption wrapper rather than keep two reaction systems.

### Tabs and filters

- The root tab bar, Edge Picker, Discover scope controls, Activity modes, Messages scope, and screen
  filters are separate implementations.
- Home/Activity/Profile mode switching must remain owned by the contextual Edge Picker per repository
  policy. The new tab strip is for in-content/filter consumers and must not create duplicate mode
  navigation on those screens.
- No generic fixed/scrollable/equal-width tab component with icons, badges, or fluid indicator exists.

### Spaces and selection

- Collections and the Edge Picker provide domain-specific selection, and `PeoplePicker` has local
  multi-selection, but there is no generic `ModulaSpace` or reusable selection-state/toolbar system.
- MCAT-02 will add model-agnostic spaces and selection infrastructure. It will not implement Merge
  Feeds or chat folders.

### Media

- `ModulaMediaViewer` already provides a black full-screen single-image viewer with pinch, double-tap
  zoom, downward dismissal, sharing, and accessibility.
- Profile media uses it; Posts have carousel/media rendering elsewhere.
- MCAT-02 will consolidate and extend this viewer to multiple items/paging and preserve the existing
  single-item initializer/API where practical.

### Sharing

- `ModulaShareSheet`, `SharePreview`, `ShareDestination`, and `ShareDestinationRegistry` already form
  a production pre-share surface and hand off to native sharing.
- MCAT-02 will polish/reuse these accepted contracts and expose them in Advanced Interaction. It will
  not reimplement the system share sheet.

### Indicators

- A basic text `ModulaBadge`, `ModulaCountFormat`, Story indicators, avatar rings, and several local
  unread/count badges exist.
- MCAT-02 will evolve `ModulaBadge` compatibly and add notification, unread, count, and presence
  primitives to reduce local badge duplication.

### Composer

- `MessageComposer` and the Post comments composer independently implement multiline input and send
  controls. Creation Studio and In-Mail have separate domain-specific editors.
- MCAT-02 will extract generic composer primitives and adopt them in Messages and Post comments while
  leaving business logic in the feature stores.

### Production surfaces

- Home/Post: `PostActions`, `PostReactionPicker`, Post context registries, comments sheets.
- Activity: typed modes (`all`, `mentions`, `requests`), unread counts, timeline, options sheet.
- Profile: accepted context registries, media viewer, share surface, Edge Picker-owned sections.
- Product Hub: collection/filter routes and existing product cards.
- GAIA/AI: the global accessory exists, but governance and Nodus runtime are out of scope. MCAT-02
  will not invent GAIA business logic.

## Existing tests

- One native unit-test target is split across sixteen Swift files, including `N4GTests`,
  `PostSystemTests`, Activity, Home, Profile, sharing, navigation, and design-system contracts.
- One `NativeLaunchTests.swift` UI suite covers AppGate, shell, Developer Components, appearance,
  Home/Post interaction, Activity, and other production routes.
- MCAT-02 will add behavior-focused unit tests for context models, reaction mapping/replacement, tabs,
  spaces, selection, sheet state, indicators, and composer state, plus catalog UI navigation tests.

## Consolidation decisions

1. Keep `DesignSystem` as the component home; add a focused `AdvancedInteraction` subdirectory.
2. Extend `ModulaMotion`, `HapticEngine`, `ModulaMaterial`, and shape/depth tokens instead of creating
   competing token systems.
3. Extend `ModulaContextAction` and `ModulaContextMenu`; add a custom host for richer previews.
4. Replace the internals of `PostReactionPicker` with generic `ModulaReactionBar`.
5. Evolve `ModulaSheet` rather than introduce `BetterSheet` or a third-party sheet package.
6. Extend `ModulaMediaViewer` rather than add another gallery.
7. Reuse `ModulaShareSheet` and its registry.
8. Evolve `ModulaBadge` and add focused indicator types beside it.
9. Replace `MessageComposer` and the comment composer UI with `ModulaComposer`, retaining feature
   store ownership of drafts and send operations.
10. Keep Home/Activity/Profile contextual Edge Picker behavior; use `ModulaTabStrip` on an appropriate
    production in-content filter surface rather than adding duplicate navigation.

## Clean-room external-reference boundary

The iMe/Telegram repository is treated only as a behavioral reference described by the mission. No
external source, assets, constants, comments, class structures, layout code, or animation code will be
copied or mechanically translated. APIs and implementation will be designed independently around
SwiftUI, Apple frameworks, existing Modula tokens, and current repository architecture.
