# MODULA-NATIVE-REALITY-01 — Baseline

Audit date: 2026-11-02 (Europe/London)

Status: BASELINE VERIFIED; implementation and acceptance remain open.

This document records the read-only starting point for the native mission. It does not claim that any unmerged backend work is deployed, that any Apple sandbox transaction has occurred, or that any native device gate has passed.

## Safety boundary

- Native implementation worktree: `/root/modula-worktrees/modula-native-reality-01`
- Native implementation branch: `codex/native-reality-01-package-lifecycle`
- Protected native reference worktree: `/root/modula-worktrees/modula-native-vps-reference`; clean and preserved at `be679c8672a9cb0a857087e3e90ab7df644b1899` (233 commits behind the audited remote main when the mission began).
- Protected backend checkout: `/root/modula-latest`; clean and untouched at `f4f70bfa761556ce9460cbd7ade2c2dfabf9c38c`.
- Backend review composition: `/root/modula-worktrees/greenfield-feature-reality-01-integration`; detached, clean, and read-only for the baseline.
- Disposable PostgreSQL: container `modula-feature-reality-01-pg`, labelled `digital.modula.mission=GREENFIELD-FEATURE-REALITY-01` and `digital.modula.scope=qa-disposable`, bound to loopback only.
- Production API, database, package registry, signing keys, billing, deployment and release state were not changed. No SSH command, merge, publication or production request was made.

## Exact source identities

### Native

- Remote `main`: `e50fc3916fb4738b7c63b7bed92bef49a8076eb8`
- Commit: `Merge pull request #261 from modula-mod/design/messaging-v2-r2`
- Mission branch starting SHA: `e50fc3916fb4738b7c63b7bed92bef49a8076eb8`

Open native pull requests at baseline:

| PR | Draft | Head SHA | Scope |
| --- | --- | --- | --- |
| #113 | No | `cae757832285afd782393a661daf7b6f1c6f6257` | Shell chrome test alignment |
| #77 | Yes | `95bfc6b75ff0b6588dd05365f96bd6d06f9fa235` | Generic Product UI polish |

Neither open PR is a Native Reality implementation PR. Relevant historical remote heads were inspected rather than merged: `feat/share-message-direct` (`c4cc7f3f5b9c94c0772e6a178a7ec6a3a9ae982f`), `feat/premium-entitlements` (`5c020488e9a04eb25b08ae4378a3f87e969c674a`), `fix/moliboo-outfit-sync` (`d4835012112b391e89cf02c27eb07cd286150e07`), `mol03/package-hooks` (`1522cc454634dc73f1ed2d08738a6f286ac75c51`) and `codex/on-demand-packages-02` (`40f14aeecb08591194e90d39ca4e63b1b13298de`). They are evidence/reference branches only; current remote `main` is the implementation baseline.

### GreenField

- Remote `main` and protected checkout: `f4f70bfa761556ce9460cbd7ade2c2dfabf9c38c`
- Existing disposable composition: `14ca92351e0746d64fcdb268fad91b9cd2ad596c`
- Mission QA composition: `6157acf650385a0fb94a7d4ef16aa76fded910b1` in `/root/modula-worktrees/native-reality-01-backend` on local-only branch `qa/native-reality-01-backend-composition`.

Live draft PR heads resolved from GitHub at baseline:

| PR | Branch | Exact head SHA | Composition status |
| --- | --- | --- | --- |
| #147 | `feat/qa-moliboo-series2-packs` | `64e8429c5e431bde459a91303d87767b3706ca0a` | Functional parent `376c96c7` is present; live head adds a report-only commit and is not an ancestor of the existing composition. |
| #148 | `fix/qa-conversation-create-contract` | `d99c1470df6e5b9aff8f6bb02174120fcd7bc9b5` | Present. |
| #149 | `feat/qa-story-dm-replies` | `2826b31c3412203514f2113c81cf1c645e718513` | Present. |
| #150 | `feat/qa-communities` | `2d2588416aa0dbcdecc81c1adea7e85cf1058e87` | Present. |
| #151 | `feat/qa-collections-and-drafts` | `2525cea3bf5e803a207fbe01474fae80ea477a54` | Present. |
| #157 | `test/qa-vault-package-install-plan` | `753c3cbcec9f6596351cbe6823969a850fdac493` | Present. |
| #158 | `feat/qa-premium-entitlements` | `d961481f68a8412a5e18a594f6355711ba67ebc0` | Present. |

All seven PRs were open and draft. After the read-only baseline, the local mission QA composition above was created with the verified integration commit and live PR #147 as parents. `git merge-base --is-ancestor` passes for every exact head in the table. It is local QA source only: it has not been pushed, deployed, merged to `main`, or used as production evidence.

## Atlas and migrations

The combined candidate Atlas identifies branch `qa/greenfield-feature-reality-01-integration`, candidate capture time `2026-11-02T15:53:53.358Z`, and 827 method routes. It explicitly identifies itself as local candidate evidence, not public-edge or production evidence.

Verification command:

```bash
CI=true GITHUB_HEAD_REF=qa/greenfield-feature-reality-01-integration API_ATLAS_RUNTIME_EVIDENCE=candidate pnpm api:atlas:verify
```

Result: 103/103 checks passed. Running the detached checkout without the explicit branch label correctly failed the branch-identity check at 102/103; no evidence was weakened to make the detached checkout pass.

The preserved disposable integration database `modula_feature_reality_01_integration3_20261102` reports schema version 087 and the following canonical ledger entries:

```text
084_moliboo_signed_packs
085_greenfield_communities
086_greenfield_collections_and_drafts
087_greenfield_premium_apple_sandbox
```

Migration source and SHA-256 were recorded for all eight up/down files. Migration 084 preserves all pre-existing GUBIC/game media types while adding `application/vnd.modula.moliboo-asset-pack+json`; its down migration restores the prior media set and refuses rollback when signed-pack, ownership, active outfit or signature evidence exists. Migration 087 similarly refuses lossy rollback after verified Premium audit events. These are backup/restore recovery boundaries once real evidence exists, not general production rollback plans.

No fresh migration mutation was run during this read-only phase. Up/down/up and legacy-upgrade tests must be rerun against the newly pinned mission composition before QA acceptance.

## Contract inventory from the combined Atlas

### NATIVE-01 — signed Moliboo and sticker packages

- `GET /v1/moliboos/packs`
- `GET /v1/moliboos/packs/catalog.json`
- `GET /v1/moliboos/packs/:packId/manifest`
- `GET /v1/moliboos/packs/:packId/download`
- `GET /v1/me/moliboos/ownership`
- `GET /v1/me/moliboos/outfit`
- `PUT /v1/me/moliboos/outfit`
- `GET /v1/stickers/packs`

### NATIVE-02 — conversations and story reply

- `POST /v1/conversations` with exact body `{ "handle": string, "text"?: string }`; returns the canonical conversation and a created/reused result.
- `POST /v1/stories/:storyId/replies` with exact body `{ "text": string, "idempotencyKey": string }`; the server resolves the author and returns the conversation/message identity.

### NATIVE-03 — Communities

- `GET|POST /v1/communities`
- `GET|PATCH /v1/communities/:communityId`
- `POST /v1/communities/:communityId/join`
- `POST /v1/communities/:communityId/leave`
- `GET /v1/communities/:communityId/members`
- `GET|POST /v1/communities/:communityId/posts`
- `GET|PATCH /v1/communities/:communityId/settings`
- Community event list/create/read/update and `PUT .../response`
- Community poll list/create/read/update and `PUT .../vote`

### NATIVE-04 — Collections and Drafts

- Eight `/v1/me/collections...` routes for list/create/read/update/delete and item membership.
- Six `/v1/me/drafts...` routes for list/create/read/update/delete/publish.
- Collection and draft mutations carry server versions. Stale mutations return conflict rather than silently overwriting.
- Draft creation/publish has server-side idempotency and attachment reservation; local media must be uploaded into valid server attachment references before synchronization.

### NATIVE-05 — module package plan

- `POST /v1/modules/:moduleId/package-install-plan`
- Request identity is server-bound and the response is a signed, locked dependency closure.
- Vault Notes 2.0.2 is a valid signed standard module release, but it does not declare `distribution.schema = modula.package.1`; its optional package plan therefore returns `404 NOT_FOUND` by design.

### NATIVE-06 — Premium Apple sandbox

- `POST /v1/me/membership/apple-purchase-context`
- `POST /v1/premium/apple/transactions`
- `POST /v1/premium/apple/notifications`
- Existing membership, tier, entitlement and badge-visibility reads remain authoritative.
- Product mappings are disabled until confirmed App Store Connect identifiers and billing periods are configured in isolated QA.

## Native architecture and current gaps

The audited app is SwiftUI. React Native remains confined to the existing `ModuleHost` boundary. `GreenfieldClient` supplies authenticated HTTPS requests, Keychain-backed session state, idempotency headers, signed artifact verification and install-plan decoding. Private local state uses `PrivateFileStore`; the app already has offline-aware messaging and media upload conventions.

### Package lifecycle

`ios/Modula/Features/MolibooRegistry/MolibooPackages.swift` already implements a data-only `modula.moliboo.assetpack.1` container with bounded decoding, strict relative paths, allowed extensions, SHA-256 verification, Ed25519 verification through the shared trust store, atomic staging/activation, a previous-version pointer and rollback. The gaps are GreenField discovery/manifest wiring, a complete lifecycle state machine, server-authoritative ownership/equipped state, and signed sticker consumption. The current Debug base URL expects a standalone `catalog.json` and does not use the GreenField route family.

### Messaging and Story Reply

`GreenfieldMessagingRepository.startConversation` already matches `POST /v1/conversations`. The universal share sheet bypasses it and emits “No chat yet” when no existing conversation is found. Story reply currently opens a new-message surface without calling the story-reply route.

### Communities

The Community hub/detail/settings/poll/event UI exists, but its state is Debug/UserDefaults preview state. There is no live Community repository/store and Release gating disables the surface.

### Collections and Drafts

Saved posts already use `/v1/saves`. Named `CollectionStore` and composer `DraftStore` are private-file-only. They have no server revision model, conflict recovery or authenticated replay queue for the new contracts.

### Vault Notes module runtime

The generic Product Hub and `ModuleHost` are present. Native install-plan validation recognizes a `module` category but activation accepts only a `game-content` root plus one `web-runtime` dependency. A generic content-only module closure needs the same signature, digest, archive safety, atomic activation, permissions and last-known-good semantics; no Vault-specific hardcoding is permitted. Server-side release creation remains blocked on an approved signed QA-only Vault package declaration.

### Premium

Premium server reads and separate badge/verification semantics exist. `PremiumStoreKitLocal.livePurchases` is false and local product identifiers are placeholders. There is no StoreKit 2 purchase/restore submission using the server-issued `appAccountToken` and no live Apple sandbox acceptance evidence.

## Baseline acceptance status

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| Source identity | PASS | Native and backend heads pinned above. |
| Existing backend candidate composition | PARTIAL | The original read-only composition differs from live PR #147. The local mission composition pins all seven exact heads but still requires its own disposable runtime and migration proof. |
| Combined Atlas | PASS | 103/103 with explicit candidate branch identity; 827 method routes. |
| Migrations 084–087 source/ledger | PASS | Disposable DB is at 087 with the four canonical entries; fresh mission up/down/up remains required. |
| Native contract implementation | FAIL | Multiple required surfaces are local-only or disconnected at baseline. |
| Vault signed QA package | BLOCKED | No approved signed `modula.package.1` Vault release exists. |
| Apple sandbox | BLOCKED | Confirmed products, credentials/root material and live signed transactions are unavailable. |
| iOS simulator | DEFERRED | No simulator acceptance has been run for this mission. |
| Physical iPhone | DEFERRED | No authorized device has been established. |
| Production release | BLOCKED | Explicitly outside mission authority. |

## Next controlled action

Implement and verify NATIVE-01 in the isolated native worktree, then build the disposable runtime from mission composition `6157acf650385a0fb94a7d4ef16aa76fded910b1` for contract/security/integration tests. Draft native PRs remain separate and unmerged until Andy approves.
