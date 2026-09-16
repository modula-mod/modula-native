# N4D remote staging

Date: 2026-09-16  
Starting branch: `cursor/phase-n4a-ios-profile-polish`  
Starting HEAD: `1ef3fc42d60849a565a5655943861c16ca502431`  
N4B + N4C: uncommitted on the same worktree. N4D is additive and must be split later.

## Repository truth captured without mutation

- Branch file: `.git/HEAD` → `cursor/phase-n4a-ios-profile-polish`
- Ref: `.git/refs/heads/cursor/phase-n4a-ios-profile-polish` → `1ef3fc42d60849a565a5655943861c16ca502431`
- Shell unavailable (`git` / `ssh` returned no exit status). No `git reset`, `git clean`, discard, or fabricated N4D branch.
- Desired eventual branch: `cursor/phase-n4d-ios-command-platform` (create on Mac closeout when Shell works).

## Existing files touched by N4D (integration only)

Do not treat these as N4D-only when splitting commits.

### `ios/Modula/Navigation/AppRoute.swift`
- Added `/command`, `/saved…`, `/collections…`, `/drafts…`
- Profile-tab association for library routes; command has no tab

### `ios/Modula/Navigation/NavigationCoordinator.swift`
- Presentations: `commandCenter`, `createPicker`, `universalShare`, `collectionPicker`, `draftRestore`
- Shell chrome for command / saved / collections / drafts

### `ios/Modula/App/AppEnvironment.swift`
- Injected `commandRecents`, `saved`, `collections`, `drafts`
- `commandCapabilities()` + `refreshQuickActions()`

### `ios/Modula/App/ModulaApp.swift`
- App delegate for Home Screen shortcuts
- Keyboard `Commands` (⌘K / ⌘N / ⌘F)
- Spotlight continuation handler

### `ios/Modula/App/RootView.swift`
- Route hosts for command/saved/collections/drafts
- Presentation hosts
- Composer foundation with draft autosave indicator
- Keyboard modifier

### `ios/Modula/DesignSystem/ShellAccessory.swift`
- Quick Access: Command Center, Saved, Drafts (does not replace Compose/Summary/Filter)

### `ios/Modula/Features/Profile/ProfileContextActions.swift` + `ProfileView.swift`
- Own More menu: Saved / Drafts
- Post context: Save to Collection + universal share

### `ios/Modula/Features/Social/PostContextActions.swift` + `PostDetailView.swift`
- Save to Collection…
- Universal share presentation

### `ios/Modula/Features/Home/HomeView.swift`
- Save to Collection + universal share

### `ios/Modula/Features/InMail/InMailViews.swift`
- In-Mail composer autosave into `DraftStore`

### `ios/Modula/Features/Settings/SettingsView.swift`
- Component catalog samples: CommandRow, DraftRow, SharePreview, CollectionCard

### `ios/Modula.xcodeproj/project.pbxproj`
- Registered N4D Swift + test files

### `docs/architecture/routes.md`
- Documented N4D routes

## New files (N4D-owned)

### Core
- `ios/Modula/Core/Persistence/PrivateFileStore.swift`
- `ios/Modula/Core/Commands/*`
- `ios/Modula/Core/Sharing/ShareModels.swift`

### Features
- `ios/Modula/Features/CommandCenter/`
- `ios/Modula/Features/Saved/`
- `ios/Modula/Features/Collections/`
- `ios/Modula/Features/Drafts/`
- `ios/Modula/Features/UniversalShare/`
- `ios/Modula/Features/SystemIntegration/`

### Tests / docs
- `ios/ModulaTests/N4DTests.swift`
- `docs/migration/command-platform-backend.md`
- `docs/migration/saved-backend.md`
- `docs/architecture/n4d-command-platform.md`
- `docs/environment/n4d-remote-staging.md`
- `docs/environment/n4d-mac-closeout.md`

## N4B / N4C overlap

- N4B `Features/Social/Post*` remains save/share authority; N4D adds collection picker + unified share sheet on top.
- N4C Messages / In-Mail / Stories / Reels directories were not rewritten. In-Mail gained draft autosave only.
- Capability gates for Create Story / Message / In-Mail follow N4C production flags (off until VPS).

## Split plan when Shell recovers

1. Preserve dirty tree (never reset)
2. Commit/push N4B post-system
3. Commit/push N4C communications
4. Branch `cursor/phase-n4d-ios-command-platform` from N4C tip
5. Commit N4D-only directories + listed integration hunks
6. `ssh modula-vps` and flip Saved/collection capabilities when verified
