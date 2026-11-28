# MODULA-NATIVE-REALITY-01 — NATIVE-08 integrated acceptance

Evidence date: 2026-11-03 (Europe/London)

**STATUS: PARTIAL**

The pinned native source, isolated GreenField composition, real PostgreSQL contract paths, signed QA package harness, and every Linux-executable gate pass. This is not simulator, physical-device, real Apple Sandbox, or production acceptance.

## Pinned environment

- Native baseline `main`: `e50fc3916fb4738b7c63b7bed92bef49a8076eb8`.
- Native source under test: `8d58814cf60567a5f4622ea573c2c9724afc039e`.
- Native reporting draft: PR #269, stacked on draft PR #268.
- Final disposable backend composition: `654c513e749d606a914346016af4b7ba267e1681`.
- Functional backend composition under test: `e6728cb93faa230d2ba83671d394075c32184d51`; the final child only updates generated Atlas client coverage for the already committed QA harness.
- Backend feature composition parent: `6157acf650385a0fb94a7d4ef16aa76fded910b1`.
- Vault QA harness commit: `a7bd5dd6ef9f0465f9cbbc321b2c99d46010bc42`.
- Migration 084 corrective commit: `4e4410f657f453bf6651dcdf8f725c55f9eb9d39` (cherry-picked into the disposable composition as `e6728cb93faa230d2ba83671d394075c32184d51`).
- Vault QA product source: `89d73768f95e1c3fb113a967d411f39384409ae9`.
- Candidate Atlas: 827 method routes captured from `qa/greenfield-feature-reality-01-integration`; 103/103 verifier checks pass and the evidence explicitly does not claim production.
- Host: Linux x86_64; Node `24.15.0`, npm `11.12.1`, PostgreSQL `16.9`.
- Native repository declares Node 22. The Node 24 runtime results are useful source evidence, not canonical CI equivalence.
- `xcodebuild`, `xcrun`, iOS Simulator, and Swift compiler are unavailable. SwiftLint is present for parser-level checks only.

The protected backend checkout `/root/modula-latest` was re-inspected and found at `641df8588154cd751df1c3ba39efbc70673b14da`, eight commits ahead of its remote with unresolved conflicts. It was neither used nor changed. Production APIs, data, registry, signing trust, billing, deployment, and release state were untouched.

## Backend composition

The isolated composition pins these unmerged review heads:

| Backend PR | Head SHA | Current review state |
| --- | --- | --- |
| #147 | `64e8429c5e431bde459a91303d87767b3706ca0a` | open, draft |
| #148 | `d99c1470df6e5b9aff8f6bb02174120fcd7bc9b5` | open, draft |
| #149 | `2826b31c3412203514f2113c81cf1c645e718513` | open, draft |
| #150 | `2d2588416aa0dbcdecc81c1adea7e85cf1058e87` | open, draft |
| #151 | `2525cea3bf5e803a207fbe01474fae80ea477a54` | open, draft |
| #157 | `753c3cbcec9f6596351cbe6823969a850fdac493` | open, draft |
| #158 | `d961481f68a8412a5e18a594f6355711ba67ebc0` | open, draft |
| #160 | `4e4410f657f453bf6651dcdf8f725c55f9eb9d39` | open, draft corrective review |

No composition commit was merged, deployed, or published.

## Executed acceptance matrix

| Required evidence | Result | Evidence boundary |
| --- | --- | --- |
| Typecheck/build validation | PASS for GreenField typecheck/build and native TypeScript typecheck | Native Swift build is BLOCKED without Xcode. |
| Native unit tests | PASS, 25/25 Linux runtime tests | XCTest execution is BLOCKED. |
| Service-client contract tests | PASS for 14 backend files / 72 tests against disposable PostgreSQL | Native XCTest bodies exist but were not executed. |
| Module/package security tests | PARTIAL | Backend signature, digest, closure, entitlement, migration and signed Vault paths pass; Swift package security/rollback XCTest is BLOCKED. |
| iOS simulator UI tests | BLOCKED | No macOS/Xcode/Simulator. |
| Real QA API integration | PASS for real Fastify routes, services, workers and PostgreSQL through the isolated app harness | Requests used Fastify injection rather than a simulator/socket-hosted native app, so native end-to-end remains PARTIAL. |
| Offline and retry tests | PARTIAL | Backend idempotency/concurrency and Linux wiring tests pass; native transport-offline UI execution is BLOCKED. |
| App restart/persistence tests | PARTIAL | Cross-session backend persistence passes; native force-quit/relaunch is BLOCKED. |
| Unaffected native regression | PASS for boundary/design/typecheck and 25/25 runtime tests | SwiftUI navigation/rendering still needs simulator acceptance. |

## Exact test results

Native repository at `8d58814cf60567a5f4622ea573c2c9724afc039e`:

- `npm run verify:boundary`: PASS.
- `npm run verify:design`: PASS.
- `npm run typecheck`: PASS.
- `npm test`: PASS, 25/25.
- `git diff --check`: PASS.

Backend repository at final composition `654c513e749d606a914346016af4b7ba267e1681`:

- GreenField API typecheck: PASS.
- GreenField API build: PASS.
- Selected integrated suite: PASS, 14 files / 72 tests.
- Atlas candidate verification: PASS, 103/103 against the preserved 827-route candidate evidence.

Selected backend test counts:

| Test file | Count |
| --- | ---: |
| `api-fix-01.migration.test.ts` | 3 |
| `moliboo-signed-packs.integration.test.ts` | 7 |
| `sticker-packs.integration.test.ts` | 4 |
| `messaging.integration.test.ts` | 8 |
| `story-dm-replies.integration.test.ts` | 3 |
| `communities.integration.test.ts` | 3 |
| `communities.qa-seed.test.ts` | 2 |
| `collections-drafts.integration.test.ts` | 4 |
| `premium.apple-sandbox.integration.test.ts` | 3 |
| `premium.apple-verifier.test.ts` | 3 |
| `premium.integration.test.ts` | 7 |
| `premium.config.test.ts` | 3 |
| `package-closure-resolver.test.ts` | 11 |
| `phase7e.vault-notes-platform.test.ts` | 11 |

All database suites used new databases owned by `modula_migrator` in the loopback-only `modula-feature-reality-01-pg` container. The final selected run used `modula_native_reality_08_final_654c513`. No test used a production or shared QA database.

## Signed Vault package acceptance

An independent empty database, `modula_native_reality_08_vault_qa_e6728cb`, was migrated from 001 through 087. The QA harness then observed:

- ephemeral Ed25519 release signing and all nine provenance/package checks;
- package-install plan HTTP 200 with a `module` root and exact content digest;
- install and enable HTTP 202 with both workers completing;
- `launchEligible: true` and `signatureState: verified`;
- authenticated artifact download HTTP 200, 11,493 bytes, SHA-256 `5c33724eac69a65750e12495160d14913de544664e1f2464aefb0bd67fae73f8`;
- Vault note create/edit/read HTTP 201/200/200, ending at revision 2.

The release was published only inside the disposable database. Its ephemeral private key was not persisted and no public registry was touched.

## Gate separation

| Gate | Status |
| --- | --- |
| Source implementation | PASS for NATIVE-01 through NATIVE-07 |
| Backend QA runtime | PASS for the pinned disposable contract/package suite; Premium has no real Apple configuration |
| Native contract integration | PASS by source wiring and Linux-executable checks; Swift XCTest remains BLOCKED |
| Simulator acceptance | BLOCKED |
| Real Apple Sandbox acceptance | BLOCKED |
| Physical-device acceptance | DEFERRED |
| Production release | NOT STARTED / NOT AUTHORIZED |

The mission is not QA READY because complete PackageManager XCTest/UI lifecycle proof, simulator journeys, native offline/relaunch behavior, and real Apple Sandbox evidence remain open.

## Changed files and rollback

NATIVE-08 draft PR #269 changes reports only:

- `NATIVE-REALITY-NATIVE-08.md`
- `NATIVE-REALITY-FINAL-REPORT.md`

Rollback is to revert the NATIVE-08 reporting commits. Do not delete the disposable databases or review branches without separate authorization; they contain reproducible QA evidence. No production rollback exists because production was not changed.
