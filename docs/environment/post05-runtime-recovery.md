# POST-05 runtime recovery — acceptance ledger

Updated 2026-09-30. Status: **PARTIAL**, not production acceptance PASS.

## Repository truth

- Native start/base: `f6d35c68f9bb867654a0deacc12da38a0f97ad04`.
- Greenfield start/base: `fc96af0a0ff5ce454d70bda7608ea2c535e04e34`.
- Both feature branches: `phase-post-05-runtime-recovery-immersive-feed`.
- Greenfield feature deployed to API and worker: `ebaa8884e8cb4aefe806eb9110aa37742c934795`.
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

- Native unit run: 334 tests, 3 documented environment/model skips, zero failures. Includes profile/attachment mapping, ordered content, shell policies, draft loss/resurrection, disk failures and Appearance round trips.
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

No Stories/Reels backend, editors, OCR, AI media analysis, transcoding farm or new storage subsystem was added.
