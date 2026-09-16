# N4E remote staging

Date: 2026-09-16  
Starting branch: `cursor/phase-n4a-ios-profile-polish`  
Starting HEAD: `1ef3fc42d60849a565a5655943861c16ca502431`  
N4B + N4C + N4D: uncommitted on the same worktree. N4E is additive and must be split later.

## Repository truth captured without mutation

- Branch file: `.git/HEAD` → `cursor/phase-n4a-ios-profile-polish`
- Ref: `.git/refs/heads/cursor/phase-n4a-ios-profile-polish` → `1ef3fc42d60849a565a5655943861c16ca502431`
- Shell unavailable at the start of this session (`git` / `ssh` returned no exit status). No `git reset`, `git clean`, discard, or fabricated N4E branch.
- Desired eventual branch: `cursor/phase-n4e-ios-first-run-security-surfaces` (create on Mac closeout when Shell works).

## VPS ACCESS — OPEN

`ssh modula-vps` could not be executed. Backend-dependent behavior remains OPEN. Native uses existing DTOs, `GreenfieldClient`, migration docs, and tests only.

## New files (N4E-owned)

### Core
- `ios/Modula/Core/AppGate/AppLaunchState.swift`
- `ios/Modula/Core/AppGate/AppGate.swift`
- `ios/Modula/Core/AppGate/AppGateHost.swift`
- `ios/Modula/Core/Security/AppLockModels.swift`
- `ios/Modula/Core/Security/AppLockCredentialStore.swift`
- `ios/Modula/Core/Security/BiometricAuthService.swift`
- `ios/Modula/Core/Security/AppLockStore.swift`
- `ios/Modula/Core/Settings/SettingsRegistry.swift`
- `ios/Modula/Core/Networking/GreenfieldAccountClient.swift`

### Features
- `ios/Modula/Features/Onboarding/`
- `ios/Modula/Features/FirstRun/`
- `ios/Modula/Features/AppLock/`
- `ios/Modula/Features/Settings/SettingsCategoryViews.swift`
- `ios/Modula/Core/Authentication/AuthProductViews.swift`
- `ios/Modula/Features/Social/Reactions/`
- `ios/Modula/Features/Profile/FullBleed/`
- `ios/Modula/Features/ProductHub/ModuleDetail/`
- `ios/Modula/Features/ProductHub/Publisher/`

### Tests / docs
- `ios/ModulaTests/N4ETests.swift`
- `docs/environment/n4e-remote-staging.md`
- `docs/environment/n4e-mac-closeout.md`
- `docs/environment/settings-route-audit.md`
- `docs/architecture/n4e-first-run-security.md`
- `docs/migration/reaction-v2-backend.md`

## Existing files modified by N4E (integration only)

Do not treat these as N4E-only when splitting commits.

### `ios/Modula/App/ModulaApp.swift`
- Window root is `AppGateHost` instead of `RootView`
- Keyboard shortcuts and Spotlight no-op / hold while gate is not ready
- Quick actions refuse to run while locked/unsigned

### `ios/Modula/App/AppEnvironment.swift`
- Injected `gate` and `appLock`
- `bootstrapLaunch`, `refreshLaunchState`, `openRouted`, `handleScenePhase`, `performSignOut`

### `ios/Modula/App/RootView.swift`
- Removed session restore and `onOpenURL` (owned by AppGate)
- `/` no longer renders Home
- Product Hub module → `ModuleDetailV2View`; publisher → `PublisherView`
- Settings → `SettingsDestinationHost`

### `ios/Modula/Core/Authentication/SignInView.swift`
- Product login chrome
- Success calls `refreshLaunchState()` instead of jumping Home
- Auth routes: welcome/onboarding, register, verify, reset

### `ios/Modula/Core/Authentication/AuthenticationStore.swift`
- Invalid credentials copy: “Email or password is incorrect.”

### `ios/Modula/Core/Authentication/AccountSettingsView.swift`
- Personal information / username / email / password / sessions / delete classified
- Sign out uses `performSignOut`

### `ios/Modula/Core/Networking/GreenfieldClient.swift`
- INVALID_CREDENTIALS product copy

### `ios/Modula/Features/Settings/SettingsView.swift`
- Search uses `SettingsRegistry`
- Route host no longer falls through to placeholder copy

### `ios/Modula/Core/Commands/CommandRegistry.swift`
- Settings commands generated from `SettingsRegistry`

### `ios/Modula/Features/Profile/ProfileView.swift` + `ProfileComponents.swift`
- Full-bleed cover geometry, floating Back on pushed profiles

### `ios/Modula/Features/Social/PostReactionPicker.swift` + `PostDetailView.swift` + `PostModels.swift`
- Reaction V2 vocabulary / summary decode / people route

### `ios/Modula/Features/ProductHub/ProductHubView.swift`
- `ProductBackdrop` made internal for Module Detail V2

### `ios/Modula/Info.plist`
- `NSFaceIDUsageDescription`

### `ios/Modula.xcodeproj/project.pbxproj`
- Registered N4E Swift + test files

### `docs/architecture/routes.md`
- Boot gate documentation

## Overlap with N4B

- Reaction picker / post engagement / people lists. N4E adds `ReactionKind` + summary + capability still OFF for multi-reaction HTTP.

## Overlap with N4C

- App Lock privacy cover hides Messages / In-Mail / Stories / Reels because the gate replaces the shell while locked. No N4C files rewritten for content.

## Overlap with N4D

- Command Center settings list now comes from `SettingsRegistry` (single source). Command Center cannot run while locked because `AppGateHost` does not mount `RootView`.
- Drafts retained on sign-out; App Lock reset is explicit.

## Backend contracts requiring VPS verification

- Auth register / verify / reset / sessions list+revoke
- Notification preferences GET/PATCH
- Username / email change / delete account
- Block list
- Multi-reaction HTTP + breakdown
- Profile cover/media contracts
- Module coverImage / screenshots / release notes / install mutation
- Quiet hours honoring

## Xcode / device gates

- `xcodebuild` Debug + Release
- Simulator onboarding / login / App Lock (passcode only)
- Physical iPhone Face ID
- Metro-free Release
