# MODULEHOST-NATIVE-01 handoff

Status: implementation handoff from `NATIVE-CONSOLIDATION-00`. This document does not claim that downloaded module execution or the universal Product UI renderer exists.

## Verified baseline

- Native source baseline: `modula-mod/modula-native@8f2fa522e32a11a694772e216d08fbdbfca44ebd` before consolidation fixes.
- GreenField contract baseline: `modula-mod/modula-latest@d536d5141e8d9a4762a1a2d67097fd4bb0355fe7`.
- Current host/bridge contract: `0.1.0`; one lazy `RCTReactNativeFactory`; disposable module surfaces; one bundled `main.jsbundle` owned by the app.
- The current executable registry is `manifests.json` in the app bundle. `ModuleRuntimeController` does not download, cache, activate, or execute a release artifact selected by an installation descriptor.
- Vault Notes 2.0 candidate inspected at `12f12e96af83ce66ba7ac737ce344a6282acef84`, version `2.0.0-rc.2`, declarative Product UI frontend. Its required `ui.richText@1` capability and `host >=1.0.0` contract are not implemented by the current `0.1.0` host.

Consequently, the current app can run only bundled registered React Native modules. Vault Notes 2.0 is not compatible with this host yet and must not be represented as running natively.

## Target launch pipeline

1. Fetch the canonical installation descriptor conditionally using its ETag and `descriptorRevision`.
2. Reject disabled, revoked, untrusted, incompatible, or permission-review-incomplete installations before artifact work.
3. Download every artifact marked `requiredForOfflineLaunch` with the declared authorization, ETag, size, range, and content-range rules.
4. Verify the descriptor version and canonical Ed25519 release statement against the trusted publisher/key inventory.
5. Hash every complete artifact locally and require exact SHA-256 equality. Delete partial or mismatched bytes.
6. Validate module, package, frontend, resource, release, SDK, Product UI, platform, and host-capability identities as a single release.
7. Commit verified immutable bytes to `STAGED`; never write into `ACTIVE` in place.
8. Atomically activate `STAGED`, retain the prior healthy activation as `PREVIOUS_GOOD`, and run the Native health gate.
9. Launch cache-first from verified `ACTIVE`; refresh descriptors, data, revocations, and update feed in the background.
10. On activation/runtime failure, atomically restore `PREVIOUS_GOOD` without altering module records or permission grants.

## Native components

### Distribution and trust

- `ModuleDistributionClient`: install/update plans, descriptors, feed, ETag, range/resume, bearer authorization, and idempotency.
- `ModuleReleaseVerifier`: descriptor schema, canonical signature payload v1, Ed25519 key lookup/revocation, artifact digests, and provenance coherence.
- `ModuleArtifactStore`: per-account/per-module/per-release immutable directories plus an atomic cache index. No secret or bearer token is persisted with an artifact.
- `ModuleActivationController`: `ACTIVE`, `PREVIOUS_GOOD`, `STAGED`, activation health gate, rollback, quarantine, and bounded non-sensitive diagnostics.
- `ModulePermissionReviewStore`: exact release ID, reviewed capability set, descriptor revision, and review result. Grants never carry forward across an added or changed permission.

### Runtime and rendering

- Keep the existing bundled React Native path for trusted bundled modules during migration.
- Add an explicit runtime selector keyed by the verified frontend artifact type; never infer a runtime from a filename.
- Declarative `application/vnd.modula.frontend+json` artifacts are parsed as bounded data and rendered by a host-owned Product UI renderer. They are not evaluated as JavaScript.
- If a future downloaded JavaScript profile is approved, it needs a separately reviewed executor and Apple distribution policy gate. The current architecture and this handoff do not authorize arbitrary downloaded JavaScript or native code.
- `ProductUIRenderer` maps semantic primitives to SwiftUI/UIKit/Expo UI implementations and reports provenance (`native`, `fallback`, `emulated`, or `unavailable`) plus constraints.
- A required unavailable capability blocks with `CAPABILITY_UNAVAILABLE`. An optional capability uses only the fallback declared by the module.
- Advanced renderers such as rich text, properties, attachments, revisions, table/board, graph, and reference picker remain generic host capabilities. No Vault-specific rendering branch is permitted.

### Data, system capabilities, and lifecycle

- Extend the session broker beyond the current record CRUD subset to versioned record/history/sync/media/share/search/settings/function/action/intelligence contracts.
- Keep surface-token binding, module-ID binding, account binding, TTL, cancellation, timeouts, duplicate-completion defense, and permission checks at every request.
- `localOnly` requests terminate in the local broker. If no compatible local provider exists, return `CAPABILITY_UNAVAILABLE` without sending content to GreenField.
- Provide offline record and presentation caches scoped to account, module, release, and schema. Incremental sync must preserve mutation IDs, expected revisions, cursors, conflicts, and tombstones.
- Quiesce unsafe local mutation before activation. Background sync and release staging must not keep an invalid surface alive.
- Retain Native error/close/retry/rollback controls outside the module renderer. A module exception cannot take ownership of shell navigation.

## Product UI implementation order

1. Contract decoder, structural limits, forbidden-field rejection, route/view/action identity, and capability negotiation.
2. Baseline primitives: text, stack/row/grid/scroll, icon/image, divider, badges, empty/error/loading, button/menu, search/filter/sort, tabs/picker, toolbar, sheet, form, list, and record row.
3. Binding/action engine for route, record CRUD/query/restore/purge, settings, functions/services/extensions, capability invocation, share, and dismiss.
4. Required Vault renderer `ui.richText@1` with lossless block round-tripping and plain-text projection generated only by the declared transform.
5. Optional generic capabilities and truthful fallbacks: rich-text commands, reference picker, property editor, attachment gallery, revision browser, table, board, graph, share, and local intelligence.
6. Accessibility and restoration: scalable text, VoiceOver semantics, keyboard navigation, Reduce Motion, route restoration, and offline launch.

## Acceptance gates

- Signature, revoked-key, revoked-release, digest, path traversal, oversized artifact, malformed JSON, forbidden executable field, and identity-mismatch negative tests.
- Atomic activation fault injection at every write/rename boundary; power-loss recovery always selects a complete verified slot.
- Permission delta and descriptor-revision race tests; no stale review can grant new capabilities.
- Cold and warm cache-first launches without network, plus refresh and revocation behavior.
- Ten activate/open/close cycles with one intended runtime per profile, bounded memory, no leaked sessions/listeners, and deterministic rollback.
- Runtime failure isolation, background/foreground, force-quit/relaunch, account switch, and expiry.
- Product UI contract snapshots and renderer provenance for every primitive/fallback.
- Vault Notes 2.0 RC.2 end-to-end only after the exact candidate artifacts, signed release descriptor, permission review, and required renderer pass. Stable `2.0.0` publication is outside this phase.

## Vault Notes 2.0 blocker

The current Native host advertises neither the required `ui.richText@1` Product UI renderer nor the `>=1.0.0` host runtime, and it always boots the app-bundled `main.jsbundle`. The minimum truthful change is the generic verified artifact/cache pipeline plus the declarative Product UI runtime described above. Downloading the RC package alone cannot make it execute or become SwiftUI.
