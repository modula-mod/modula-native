# N4G remote staging

Date: 2026-09-16  
Starting branch: `cursor/phase-n4a-ios-profile-polish`  
Starting HEAD: `1ef3fc42d60849a565a5655943861c16ca502431`  
N4B + N4C + N4D + N4E + N4F: uncommitted on the same worktree. N4G is additive and must be split later.

## Repository truth captured without mutation

- Branch file now: `.git/HEAD` → `cursor/phase-n4g-visual-language-fc45` (ref created without mutating files; HEAD commit unchanged)
- Ref: `.git/refs/heads/cursor/phase-n4g-visual-language-fc45` → `1ef3fc42d60849a565a5655943861c16ca502431`
- Shell (`git` / `xcodebuild` / `ssh`) returned no exit status this run. No `git reset`, `git clean`, discard, rebase, commit, or push was possible. N4G source is in the dirty worktree on that branch.

## VPS ACCESS — OPEN

N4G is native presentation only. No new Greenfield endpoints were attempted.

**GREENFIELD LIVE AUDIT: not required for N4G**

## New files (N4G-owned)

### Surface / Edge Loop / Immersive
- `ios/Modula/DesignSystem/Surface/ModulaSurfaceSystem.swift`
- `ios/Modula/DesignSystem/EdgeLoop/EdgeLoopEngine.swift`
- `ios/Modula/DesignSystem/EdgeLoop/EdgeLoopShape.swift`
- `ios/Modula/DesignSystem/EdgeLoop/ModulaEdgeLoop.swift`
- `ios/Modula/DesignSystem/Immersive/ModulaImmersiveSurfaces.swift`
- `ios/Modula/Features/Settings/TypographyPreview.swift`

### Tests / docs
- `ios/ModulaTests/N4GTests.swift`
- `docs/architecture/n4g-surface-system.md`
- `docs/environment/n4g-remote-staging.md`
- `docs/environment/n4g-mac-closeout.md`

## Existing files modified by N4G (integration only)

Do not treat these as N4G-only when splitting commits.

### `ios/Modula/App/RootView.swift`
- Overlay uses `ShellEdgeLoop` instead of the previous rail implementation
- Sets `trailingInteractionInset` when the shell loop is visible

### `ios/Modula/DesignSystem/ShellComponents.swift`
- `ModulaContextRail` is a compatibility wrapper around `ShellEdgeLoop`
- `ModulaRailShape` retained for the previous silhouette (not deleted)

### `ios/Modula/DesignSystem/ShellAccessory.swift`
- Pre-iOS 26 bottom chrome docks accessory into one control surface with the tab bar
- Selected tab pill is thinner and accent-tinted instead of a grey mass

### `ios/Modula/Features/Home/HomeView.swift`
- Header: Modula + Create + Messages (Settings removed from Home header)
- Compact Stories tray; large hero and Product Hub/Compose shelf removed so feed appears immediately
- Trailing content inset for Edge Loop

### `ios/Modula/Features/Stories/StoryViews.swift`
- Compact tray height (~78–86pt) for Home

### `ios/Modula/Features/Profile/ProfileView.swift`
- Cover pocket geometry passed into `ProfileCover`
- Posts trailing inset for Edge Loop / action rail clearance

### `ios/Modula/Features/Profile/ProfileComponents.swift`
- `AvatarPocketShape` / `AvatarPocketCarve` replace the private ellipse carve
- Cover can mask a carved identity pocket

### `ios/Modula/Features/ProductHub/ModuleDetail/ModuleDetailV2View.swift`
- `FullBleedHero`, `ArtworkPocket`, `FloatingHeroControls`
- No ratings, reviews, or download counts added

### `ios/Modula/Features/Onboarding/OnboardingView.swift`
- `OnboardingHeroScene` (brand gradient + abstract modules, no photography)
- Skip / progress / large statement / three value rows / Next

### `ios/Modula/Features/Social/PostActionRail.swift`
- Material token, truthful compact counts under React / Comment / Share
- Still a distinct component from Edge Loop

### `ios/Modula/Features/Social/PostComponents.swift`
- Extra trailing clearance when the action rail is shown

### `ios/Modula/Features/Settings/SettingsView.swift`
- Appearance typography uses `TypographyPreviewCard`
- Catalog / preview show Edge Loop

### `ios/Modula.xcodeproj/project.pbxproj`
- Registered N4G Swift + test files

### Docs
- `docs/design/context-rail.md`
- `docs/architecture/home.md`
- `docs/architecture/appearance.md`
- `docs/architecture/native-shell.md`

## Explicitly not done

- No new backend / DTO / feed work
- No Profile five-tab strip (Media / About / Links stay overview content)
- No duplicate Home Following | For You | Modules tab strip
- No center + tab destination
- No fabricated marketplace metrics
- No N4H

## Overlap with prior phases

- N4A/N4E Profile cover + avatar pocket: N4G upgrades geometry via shared shapes
- N4B `PostActionRail`: visual/count polish only
- N4C Stories tray: compact Home placement only
- N4D chrome policy: destinations unchanged
- N4F Create: Home header Create opens existing composer route

## Xcode / device gates

- `xcodebuild` Debug + Release
- Simulator: Edge Loop tap/drag/snap, Home/Profile/Module Detail/Onboarding, font preview
- Physical iPhone: Edge Loop haptics, full-bleed covers, tab+accessory layering, Reduce Motion / VoiceOver
- `NativeLaunchTests` that tap Home `Settings` need a destination update (header is now Create + Messages; Settings remains in Command Center / accessory More / Profile)
- Metro-free Release
