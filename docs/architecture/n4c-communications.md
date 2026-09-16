# N4C — Communications, identity, stories, reels

Native Swift/SwiftUI only. React Native remains installed-modules via `ModuleHost`. None of Messages, In-Mail, Stories, Reels, or Profile customization initialize Hermes.

## Product freeze

| System | Meaning |
|---|---|
| Chat | Fast conversational communication |
| In-Mail | Structured asynchronous communication |
| Activity | Things that happened around me |
| Notifications | Delivery mechanism |
| Story | Temporary identity/content update |
| Reel | Immersive short-form discovery media |
| Video post | Ordinary social post that happens to contain video |
| Profile | Public digital identity |
| Account Settings | Private account management |
| AppearanceStore | How I experience Modula on this device |
| ProfilePresentation | How my public Profile identifies itself |
| Story Ring | Ephemeral content availability |
| Focus Halo | Profile/focus semantic status (separate; do not conflate) |

Chat and In-Mail are different screens, not restyled copies.

## App vs Profile accent

Viewer Appearance accent owns global tab bar, Settings, and native system chrome.

Viewed profile accent (when the public Profile actually has one) may tint profile highlights, selected local rail, story ring, and profile buttons. It must never recolor the viewer’s application chrome.

## Routes

Typed in `AppRoute`. No filesystem routing.

```text
/messages                → /messages/inbox
/messages/inbox
/messages/requests
/messages/in-mail        → In-Mail inbox
/messages/in-mail/new
/messages/in-mail/:threadId
/messages/new
/messages/:conversationId
/stories                 → stories root (no fake id)
/stories/create
/stories/:storyId        → Story Viewer
/reels                   → reels feed
/reels/:reelId
/profile/:id/edit        → N4C customization sections live here
```

Messages is **not** a sixth root tab. Entry: Home header, Profile Message / In-Mail, Activity/notification deep links later.

## Layout

```text
Features/Messages/
Features/InMail/
Features/Stories/
Features/Reels/
Features/Media/
Features/Profile/Customization/
```

N4B `Features/Social/Post*` remains the post interaction authority. Reels adapt to it; they do not fork comments, reactions, or share URLs.

## Realtime / encryption / badges

No WebSocket/SSE is claimed. Repositories are refresh/poll-shaped.

TLS is not E2EE. No Encrypted / Vault Chat copy.

Home Messages badge only if Greenfield supplies an account-wide unread count. Never inferred from loaded rows. Do not change the iOS app icon badge in N4C.

## Privacy

Messages/In-Mail stay out of logs, diagnostics payloads, and the bundle. Cache is in-memory for this source phase. Screenshot blocking is not applied globally.

## Shell chrome

| Surface | Tab bar | Context rail | Root accessory |
|---|---|---|---|
| `/messages/*` | hidden | hidden | hidden (conversation uses native composer) |
| `/stories/*` | hidden | hidden | hidden, immersive |
| `/reels` `/reels/:id` | hidden or minimized | hidden | hidden; action rail only |
