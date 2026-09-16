# N4F remote staging

Date: 2026-09-16  
Starting branch: `cursor/phase-n4a-ios-profile-polish`  
Starting HEAD: `1ef3fc42d60849a565a5655943861c16ca502431`  
N4B + N4C + N4D + N4E: uncommitted on the same worktree. N4F is additive and must be split later.

## Repository truth captured without mutation

- Branch file: `.git/HEAD` → `cursor/phase-n4a-ios-profile-polish`
- Ref: `.git/refs/heads/cursor/phase-n4a-ios-profile-polish` → `1ef3fc42d60849a565a5655943861c16ca502431`
- Shell unavailable throughout this session (`git` / `ssh` / `xcodebuild` returned no exit status). No `git reset`, `git clean`, discard, rebase, or fabricated isolated N4F commit.
- Desired eventual branch: `cursor/phase-n4f-creation-studio-480e` (create on Mac closeout when Shell works). Do not treat this remote worktree as already split.

## VPS ACCESS — OPEN

`ssh modula-vps` could not be treated as verified this run. Backend-dependent publishing remains OPEN. Native uses existing DTOs, `GreenfieldClient`, N3C `home-feed-backend.md`, N4B `post-system-backend.md`, and tests only.

**GREENFIELD LIVE AUDIT: OPEN**

## Capability truth used by production UI

| Kind | Production publish | Reason |
|---|---|---|
| Text post | **ON** (live acceptance OPEN) | `POST /v1/posts` documented in N3C VPS source; body is conservative `{text, kind, audience, idempotencyKey}` |
| Photo / carousel | **OFF** | Media upload contract not verified |
| Video | **OFF** | Video not in `PostMediaDto` |
| Link (structured) | **OFF** | No verified link-preview or write contract |
| Poll | **OFF** | Not in `SocialPostDto` |
| Audio / Movie | **OFF** | Architecture only |
| Story | **OFF** | N4C `storyCreate = false` |
| Reel | **OFF** | N4C video/Reels publish missing |

No fake upload progress. No client-only posts presented as server content.

## New files (N4F-owned)

### Domain / pipeline
- `ios/Modula/Features/Creation/CreationModels.swift`
- `ios/Modula/Features/Creation/CreationCapabilities.swift`
- `ios/Modula/Features/Creation/Composer/CreationStudioStore.swift`
- `ios/Modula/Features/Creation/Composer/CreationStudioView.swift`
- `ios/Modula/Features/Creation/Composer/CreationComponents.swift`
- `ios/Modula/Features/Creation/Audience/AudiencePicker.swift`
- `ios/Modula/Features/Creation/Poll/PollEditor.swift`
- `ios/Modula/Features/Creation/Media/DraftMediaStore.swift`
- `ios/Modula/Features/Creation/Media/MediaPreparation.swift`
- `ios/Modula/Features/Creation/Publishing/PublishingRepository.swift`
- `ios/Modula/Core/MediaUpload/MediaUploading.swift`

### Tests / docs
- `ios/ModulaTests/N4FTests.swift`
- `docs/environment/n4f-remote-staging.md`
- `docs/environment/n4f-mac-closeout.md`
- `docs/migration/creation-backend.md`
- `docs/architecture/n4f-creation-studio.md`

## Existing files modified by N4F (integration only)

Do not treat these as N4F-only when splitting commits.

### `ios/Modula/App/RootView.swift`
- `/compose/*` and `.composer` presentation now host `CreationStudioView` instead of the foundation stub.

### `ios/Modula/App/AppEnvironment.swift`
- Draft account namespace on auth change
- Draft flush on background
- Command capabilities include photo/poll from `CreationCapabilities`

### `ios/Modula/Navigation/NavigationCoordinator.swift`
- Compose chrome: tab bar / accessory / rail hidden; composer owns Cancel/Post

### `ios/Modula/Features/Drafts/DraftModels.swift` + `DraftStore.swift` + `DraftsView.swift`
- Richer post draft fields, account isolation, resume ID, media cleanup hooks

### `ios/Modula/Core/Persistence/PrivateFileStore.swift`
- Nested filenames; `draftMedia` domain

### `ios/Modula/Features/Social/PostRepository.swift`
- `createPost` using documented `POST /v1/posts`

### `ios/Modula/Features/Home/HomeStore.swift` + `ProfileStore.swift`
- Ingest canonical published posts into caches (no fabricated counts)

### `ios/Modula/Core/Commands/CreateActionRegistry.swift` + `CommandRegistry.swift` + `CommandModels.swift`
- Capability-aware Create Photo / Poll; Create Post remains the real composer

### `ios/Modula/Features/Stories/StoryViews.swift`
- `/stories/create` uses Creation Studio when story publish is enabled

### `ios/Modula/Features/Settings/SettingsCategoryViews.swift` + `SettingsView.swift`
- Draft Media storage category; catalog primitives; clear-cache still excludes drafts

### `ios/Modula.xcodeproj/project.pbxproj`
- Registered N4F Swift + test files

### `docs/architecture/routes.md`
- Composer owns `/compose/*`; Stories create integrates the same domain

## Overlap with N4B

- `PostRepository` / `PostStateStore` / Home-Profile caches. N4F adds create + ingest after server success only.

## Overlap with N4C

- `/stories/create` host. No Stories/Reels viewer rewrite. Story/Reel publishing stays capability-off.

## Overlap with N4D

- `DraftStore`, Create Action, Command Center, App Intents `Create Post` (opens composer, never auto-publishes).

## Overlap with N4E

- App Lock / session teardown: drafts flush to disk; account-namespaced restore after unlock/login. Sign-out retains drafts under the original account ID. Data & Storage Draft Media category.

## Xcode / device gates

- `xcodebuild` Debug + Release
- Simulator composer / keyboard / PhotosPicker
- Physical iPhone publish against live Greenfield
- Instruments: composer open, image prepare, upload
- Metro-free Release (Hermes count remains 0 on Create Post)
