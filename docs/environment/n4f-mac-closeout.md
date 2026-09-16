# N4F Mac closeout

Future home-machine mission. Remote source is PARTIAL until these gates pass.

This closeout is **not N4G**. After N4F, stop adding features and run:

**N4 CLOSEOUT — Recovery, Split, VPS Truth, Xcode, iPhone & Integration**

## Recover / split phases (never reset)

1. Preserve the dirty worktree. Do not `git reset`, `git clean`, or checkout over files.
2. If Shell works, capture `git status`, `git diff --stat`.
3. Split commits in this order:
   - N4B post-system
   - N4C communications
   - N4D command platform
   - N4E first-run / security / surfaces
   - N4F creation studio  
     Recommended branch: `cursor/phase-n4f-creation-studio-480e`
4. Record exact shared hunks from `docs/environment/n4f-remote-staging.md`.

Recommended eventual N4F commits (when Git is recovered):

```text
docs(create): audit Greenfield publishing contracts
feat(create): add native creation domain
feat(composer): build native post composer
feat(media): add draft media and upload pipeline
feat(create): add audience and entity attachments
feat(create): add native link composer
feat(polls): add capability-driven poll composer
feat(stories): integrate story creation
feat(drafts): connect real composer autosave
feat(create): wire universal create and app shortcuts
feat(a11y): add creation accessibility
test(create): add drafts publishing and media coverage
docs(n4f): document creation platform
```

## Backend (`ssh modula-vps`)

Replace every provisional contract in `docs/migration/creation-backend.md`:

- `POST /v1/posts` exact write body (text, audience, kind, media, link, poll, mentions, location, idempotency)
- Edit / delete post
- Media upload path, MIME, size, transforms, EXIF handling
- Link preview endpoint (do not scrape in Swift)
- Poll create / vote / expiry
- Story create (photo + text)
- Reel create
- Character limits
- Scheduled posts / server drafts

Do not enable production tools until the live route accepts the encoder payload.

## Native execution

- `xcodebuild` Debug PASS
- `xcodebuild` Release PASS
- Simulator: text publish, restore draft, discard, App Lock mid-compose, sign-out account isolation
- Physical iPhone: PhotosPicker, limited library, keyboard, Dynamic Type, VoiceOver
- Instruments: composer open, keyboard, image prepare, draft autosave
- Metro-free Release — Create Post must not initialize Hermes

## Product walkthrough

- Home Compose → Creation Studio (not foundation stub)
- Command Center Create Post → same studio
- App Shortcut Create Post → opens composer, does not publish
- Profile “Share your first post” → studio
- Publish success → Home/Profile cache updates from canonical post
- Publish failure → “Couldn't publish your post. Your draft is safe.”
- Clear cache → drafts and draft media remain
- Story plus / Create Reel remain hidden until capabilities are live
