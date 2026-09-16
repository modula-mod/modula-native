# N4C remote staging

Date: 2026-09-16  
Starting branch: `cursor/phase-n4a-ios-profile-polish`  
Starting HEAD: `1ef3fc42d60849a565a5655943861c16ca502431`  
N4B: uncommitted on the same worktree. N4C is additive and must be split later.

## Repository truth captured without mutation

- Branch file: `.git/HEAD` → `cursor/phase-n4a-ios-profile-polish`
- Ref: `.git/refs/heads/cursor/phase-n4a-ios-profile-polish` → `1ef3fc42d60849a565a5655943861c16ca502431`
- Shell was unavailable at the start of this session (`ssh` / `git status` returned no exit status). No `git reset`, `git clean`, or discard of N4B files was performed.

## Existing files touched by N4C

These are already-tracked or N4B-dirty files that received **small targeted** integration edits. Do not treat them as N4C-only when splitting commits.

### `ios/Modula/Navigation/AppRoute.swift`
- Expanded `MessagesRoute` to inbox / requests / in-mail / new / conversation
- Added `InMailRoute`, `StoriesRoute`, `ReelsRoute`
- Canonical `/messages` → `/messages/inbox`
- Added `NotificationRouteResolver` for future push payloads

### `ios/Modula/Navigation/NavigationCoordinator.swift`
- Shell chrome: messages hide tab/rail/accessory; stories immersive; reels immersive without accessory

### `ios/Modula/App/AppEnvironment.swift`
- Injected `MessagingStore`, `InMailStore`, `StoryStore`, `ReelStore`

### `ios/Modula/App/RootView.swift`
- Routed messages / stories / reels to native hosts
- Share URLs for story, reel, conversation

### `ios/Modula/Features/Home/HomeView.swift`
- Compact Messages + Settings header icons (not one capsule)
- Story tray host before feed (only when groups exist)
- Unread badge only if `accountUnreadCount` exists

### `ios/Modula/Features/Profile/ProfileModels.swift`
- Optional headline, languages, `ProfilePresentation`, cover focal point
- Visitor-visible projection (not a security authority)

### `ios/Modula/Features/Profile/ProfileStore.swift`
- Visitor preview flag
- Customization capability map
- Preserve new fields when copying follower counts

### `ios/Modula/Features/Profile/ProfileComponents.swift`
- Headline, languages, Message / In-Mail CTA, story ring on avatar

### `ios/Modula/Features/Profile/ProfileView.swift`
- Message / In-Mail entry, story ring tap vs photo, visitor preview banner, profile accent environment

### `ios/Modula/Features/Profile/ProfileEditView.swift`
- Identity / Media / About / Links / Modules / Presentation sections (writes capability-gated)

### `ios/Modula/Features/Discover/DiscoverModels.swift`
- Decode dashboard `reels[]` into `Reel` (no fabricated ranking)

### `ios/Modula/Features/Discover/DiscoverDashboard.swift`
- Optional Reels shelf when `reels[]` is non-empty

### `ios/Modula/Features/Discover/DiscoverScreen.swift`
- Open reel viewer from the shelf; ingest seed into `ReelStore`

### `ios/Modula/Features/Settings/SettingsView.swift`
- Component catalog samples: MessageBubble, StoryRing, StoryProgress, ProfileAccentPicker

### `ios/ModulaTests/NativeFoundationTests.swift`
- Route round-trips and shell chrome for N4C destinations

### `ios/Modula.xcodeproj/project.pbxproj`
- Registered new N4C Swift files

### `docs/architecture/routes.md`
- Documented expanded communication and media routes

## New files (N4C-owned)

See `docs/architecture/n4c-communications.md`. Feature directories:

- `ios/Modula/Features/Messages/`
- `ios/Modula/Features/InMail/`
- `ios/Modula/Features/Stories/`
- `ios/Modula/Features/Reels/`
- `ios/Modula/Features/Media/`
- `ios/Modula/Features/Profile/Customization/`
- `ios/ModulaTests/N4CTests.swift`
- `docs/migration/messaging-backend.md`
- `docs/migration/stories-backend.md`
- `docs/migration/reels-backend.md`
- `docs/architecture/n4c-communications.md`
- `docs/environment/n4c-mac-closeout.md`

## N4B files intentionally not rewritten

All `Features/Social/Post*` files remain the post-system authority. Reels reuse `PostActionRail`, `PostCommentsView`, and `PostStateStore` via `Reel.asSocialPost()`.

## Split plan when Shell recovers

1. Preserve N4B (do not reset the worktree)
2. Commit N4B post-system on its branch
3. Branch N4C from that commit
4. Move/commit N4C files + the existing-file integration hunks listed above
