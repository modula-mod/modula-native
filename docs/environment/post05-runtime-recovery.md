# POST-05 runtime recovery — acceptance ledger

Updated 2026-10-01. Status: **PARTIAL**, not production acceptance PASS.

## Repository truth

- Native start/base: `f6d35c68f9bb867654a0deacc12da38a0f97ad04`.
- Greenfield start/base: `fc96af0a0ff5ce454d70bda7608ea2c535e04e34`.
- Both feature branches: `phase-post-05-runtime-recovery-immersive-feed`.
- Greenfield feature deployed to API and worker: `58fdcd82e4c2ef52aa8f8f0cf2486c958bb46623`.
- Migration 058 applied after a database backup; live/ready HTTP 200 and public version endpoint confirm that SHA.
- No production credentials changed. Canonical user/Nodus changes preserved. Recovery source is also applied to `/Users/msjoy/Developer/modula-native` for the user's builds.
- No acceptance merge: `origin/main` still requires the remaining gates below.

## Verified causes and changes

| Surface | Cause | Repair / verification boundary |
| --- | --- | --- |
| Avatar / cover | Native sent base64 to profile-media endpoints that did not exist. | Existing attachment upload followed by owned, ready-image binding; backend stores avatar/cover references and returns them on fresh profile fetch. Ownership, private reads, binding and removal are integration-tested. Real Photos selection/relaunch still open. |
| Private profile Save | Mutation re-read profile without the owner actor, returning a false not-found after saving. | Owner-aware response and visibility mapping; backend private-save regression passes. |
| Save after media edit | Avatar/cover mutation increments profile version while the text editor retained its old concurrency token. | Rebase the editor version after own media mutations, preserving unsaved text. Pointer verification open. |
| Images / gallery / files | Raw image/file consumers did not attach Greenfield authorization. | Shared authenticated media requests, bounded timeout, downsampling, stable attachment cache identity, in-flight image request reuse, explicit failure/retry. Real-account media matrix still open. |
| PDF | Generic placeholder never downloaded/rendered a first page. | Authenticated download, PDFKit first-page thumbnail/cache and decode-specific failure/retry. Viewer retained. |
| Video / audio | Protected remote URLs reached unauthenticated player paths; no resting poster. | Authenticated local-file playback and decoded video poster; visibility lifecycle retained. Codec/audio/offscreen device acceptance open. |
| Saved library | Client disabled a supported server capability and used a nonexistent provisional list URL. | Enable `/v1/saves`, hydrate canonical engagement state, serialize repeated save taps; backend save/list integration test passes. |
| Draft backgrounding | Flush handled pending posts only; cancelled pending In-Mail/story autosaves were lost. | Flush pending writes for every draft kind; disk reload regression passes. |
| Draft resurrection | Discard did not cancel debounce; composer close also persisted published/discarded drafts. | Cancel pending writes and reject terminal drafts in persistence. Regression tests pass. |
| False saved feedback | Draft and collection writes swallowed storage errors. | Report failure, retain/retry draft data, rollback failed collection changes, and keep Save Draft UI open on failure. Deterministic disk-failure/retry tests pass. |
| Shell overlap | Catalog/content could stack shell rail/accessories without a shared clearance contract. | Canonical shell policy/inset and inspection/viewer policies, covered by routing/policy tests. Device visual inspection open. |

## Scope of the broader saving audit

Reviewed Profile text/media, post save/unsave, Saved list, collections, Creation Studio, local post/In-Mail/story drafts, and Appearance persistence. Existing Appearance round-trip/reset/account-isolated draft tests pass. Collections and drafts remain honestly **on-device**, not claimed as server-synced. Unsupported backend capabilities remain gated; this is not a claim that every Settings destination or every app workflow has been certified.

## Evidence

- Native unit run: 337 tests, 3 documented environment/model skips, zero failures. Includes profile/attachment mapping, ordered content, shell policies, draft loss/resurrection, disk failures, story-photo retention and Appearance round trips.
- Earlier focused profile/media run and profile/stress UI automation passed. Final-source UI/build reruns are recorded in the PR/closeout; they do not substitute for pointer acceptance.
- Greenfield profile, attachment/security and migration test run: 27 passing tests. Additional save/social and policy/notification suites passed. A profile rerun hit registration rate limits on the reused disposable test database; clearing only that database's counters and rerunning yielded 4/4 passes. Production limits were not changed.
- Migration down/up round trip passed on disposable PostgreSQL.
- API contracts and production API/worker Docker builds passed. Local standalone API typecheck has separately documented pre-existing workspace dependency drift; fresh dependency builds succeeded in Docker.
- Simulator: iPhone 17 Pro, iOS 26.5, `439E8DF1-EA4F-4028-98A0-32CA9469EAE0`.
- Local logs: `/tmp/post05-final-regression.log`, `/tmp/post05-final-release.log`, `/tmp/post05-save-backend-tests.log`, `/tmp/post05-profile-save-retest.log`.

## Required open acceptance

The Mac is locked and the user is remote and cannot unlock it. Physical device unavailable at last check. No manual-pointer PASS is claimed.

- Real production account: avatar and cover selection/upload/save, kill/relaunch and fresh API fetch.
- POST-04 image/PDF/video pointer-selected publish, kill/relaunch and fresh fetch/view/play. POST-04 stays unclosed.
- Real gallery, document, audio and mixed-content flow; every viewer/playback/retry/offline state.
- Reaction scrub, comments morph, context, post detail and transitions on real content.
- Light/Dark/OLED visual evidence; VoiceOver, accessibility text sizes, Reduce Motion/Transparency.
- 60+ representative real mixed posts. The lab reuses available live API posts up to 60 and labels fixture fallback honestly; repeated rows are not proof of the complete asset-kind matrix.
- Instruments Time Profiler, Allocations, Leaks and hitch/retention checks. No numeric performance PASS claimed.
- Entire UI suite zero unexpected failures, final Debug/Release source verification, both PRs/main synchronization after acceptance.

## Authorized social expansion and reference-led refinement

The user subsequently expanded the mission to Stories, Reels, comments, hashtags and broader social UI. This supersedes the original Stories/Reels exclusion, not the requirement for honest runtime proof.

- Reels now use public, ready canonical video posts (same post ID, media, saved/reaction/comment state). Greenfield attachment/Stories regressions: 9 passing tests; contracts and API/worker Docker builds passed. Live health, discover, stories, reels, post detail and attachment access returned HTTP 200 after deployment.
- Two live production Reels downloaded and decoded through AVFoundation: 8,157,218 bytes each, 14.21-second duration, one video track, decoded 275 × 600 frame. This is network/decoder proof, not pointer-driven iOS playback acceptance. Log: `/tmp/post05-live-video-proof.log`.
- Story photo/caption/audience drafts survive disk reload and unrelated post-draft cleanup. Existing Stories API is reused; video Story creation, filters, music and GIFs are not claimed.
- Eight supported reactions use the real mutation endpoint. Threaded comments use the dedicated replies endpoint. Hashtags and mentions use canonical Search/Profile routes.
- Comment author root cause: Greenfield returned raw database comment rows containing only actor IDs. Batched profile attribution now returns only ID, handle, display name and avatar URI for comments already admitted by the existing visibility/block/mute policy. No private profile fields are exposed. Create/list/reply contract tests (including avatar URI) pass: 8/8. The disposable test database needed its accumulated registration counters cleared before the rerun; production rate limits were untouched.
- Deployed comment attribution proof: ten live public post conversations, 14/14 comments with real profile attribution; one supplied avatar URL fetched HTTP 200, image/jpeg, 171,508 bytes. Health live/ready, discover, Reels and Stories all HTTP 200 on deployed SHA `58fdcd82`. This is API/network proof, not a manual device walkthrough.
- User references 1–4 exposed nested scrolling, duplicate menus/counts, generic comment separators and oversized composer controls. Post Detail now hosts content and comments in one scroll view, with one menu/action row and a safe-area-pinned composer. Root shell chrome is hidden for focused detail and Story creation.
- Media posts lead with content, followed by captions. Author headers show handles instead of repeating feed mode. Reels use a coherent dark viewer canvas. Appearance accent remains user-controlled; no invented badges, engagement counts, permissions or media.
- Inspiration: supplied references 5–14, Apple HIG Playing Video/Accessibility, and Meta's Reels/Stories product descriptions. The mockups' duplicate horizontal tabs and unsupported GIF controls were deliberately not copied.
- First refinement automation: 337 unit tests (3 expected skips), two social UI tests, zero failures. XCTest screenshots inspected at `/tmp/post05-refined-ui-screens`. Fixture Reels were empty; they are not production media evidence. Inspection led to follow-up compact-empty and Light-mode contrast fixes; final rerun is required.
- Final-source canonical Release simulator build passed: `/tmp/post05-refined-canonical-release-final.log`. Native configurations were built sequentially because the feature worktree shares Pods with the canonical checkout.
- Final Debug build/test rerun passed: 337 unit tests (3 documented skips), two targeted social UI tests, zero failures. The UI test sends a comment and verifies it again after opening Detail/fresh GET; it also checks one scroll surface and hidden tab chrome. Log: `/tmp/post05-ui-refinement-final-tests.log`; screenshots: `/tmp/post05-refined-ui-final-screens`. Final Reels contrast, keyboard-safe composer, and focused Detail screenshots were inspected. The separate N1 fixture host still returns raw comment actor IDs and no Reels; these screenshots do not certify production author rendering or video playback. Production attribution is separately verified above.

No editors, OCR, AI media analysis, transcoding farm or separate storage subsystem was added. Onboarding and Product Hub inspiration has not yet been implemented as a whole-app redesign.
