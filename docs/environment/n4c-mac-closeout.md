# N4C Mac closeout

Run this when Mac / VPS / device access returns. Unavailable infrastructure is not a PASS.

## 1. Preserve N4B

```bash
cd /path/to/modula-native
git status
git diff --stat
# Do NOT git reset / git clean / git checkout -- .
```

N4B currently lived uncommitted on `cursor/phase-n4a-ios-profile-polish` (HEAD `1ef3fc42d60849a565a5655943861c16ca502431`). See `docs/environment/n4c-remote-staging.md` for the existing-file touch list.

## 2. Split N4B / N4C commits

Preferred chain:

```text
N4A
 ↓
N4B Post System
 ↓
N4C Communications & Media Expansion
```

Suggested N4C series (after N4B is committed):

```text
docs(messages): audit Greenfield communication contracts
feat(messages): add native messaging domain and routes
feat(messages): build conversation inbox and chat
feat(inmail): add structured Modula In-Mail
feat(profile): expand public identity information
feat(profile): add presentation customization
feat(stories): add native story tray and viewer
feat(reels): add native reels architecture and viewer
feat(media): unify native media playback primitives
feat(a11y): add communication and immersive-media semantics
test(n4c): add communication stories reels and profile coverage
docs(n4c): record social expansion architecture
```

## 3. Create N4B branch

```bash
git checkout -b cursor/phase-n4b-post-system
# stage only Social/Post* + n4b docs + related Home/Discover/Profile post wiring
git commit
git push -u origin cursor/phase-n4b-post-system
```

## 4. Create N4C branch

```bash
git checkout -b cursor/phase-n4c-communications
# stage Messages/InMail/Stories/Reels/Media/Customization + listed integration hunks
git commit
git push -u origin cursor/phase-n4c-communications
```

## 5. ssh modula-vps

```bash
ssh modula-vps
# inspect services/greenfield-api conversation, in-mail, stories, reels routes
```

## 6. Audit live Greenfield

Flip capability flags only after route + payload confirmation:

- `MessagingBackendCapabilities`
- `InMailBackendCapabilities`
- `StoryBackendCapabilities`
- `ReelBackendCapabilities`
- `ProfileCustomizationCapabilities`

## 7. Replace provisional contracts

Update path enums in those capability types. Do not add a second HTTP client.

## 8. xcodebuild

```bash
cd ios
xcodebuild -workspace Modula.xcworkspace -scheme Modula -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 9. Simulator

Exercise Messages, In-Mail, Profile edit sections, Story tray/viewer, Reels paging. Confirm no sixth tab.

## 10. Physical iPhone

Messaging send/retry, story hold/tap, reels paging, haptics.

## 11. Instruments

Media memory: adjacent-only reel/story preparation, offscreen player release.

## 12. Release without Metro

Confirm Messages / In-Mail / Stories / Reels / Profile customization do not initialize Hermes.

## Additional gates

- Credential / private-message scan (no bodies in logs)
- N1 → N4 regression
- APNs remains out of scope until notification infrastructure owns it
