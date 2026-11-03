# MODULA-NATIVE-REALITY-01 — NATIVE-05 Vault Notes

Evidence date: 2026-11-03 (Europe/London)

Status: PARTIAL. The QA-only package, disposable GreenField acceptance, and native source implementation are verified. Swift/Xcode, Product Hub simulator, and physical-device acceptance remain open and are not represented as passing.

## Pinned sources

- Native base: `6669fafb7f196806a64b4bdfc249a98b84dbb155` on `codex/native-reality-05-vault-notes-module-runtime`.
- GreenField review dependency: draft PR #157 at `753c3cbcec9f6596351cbe6823969a850fdac493`.
- Disposable GreenField composition: `a7bd5dd6ef9f0465f9cbbc321b2c99d46010bc42`; its parent `6157acf650385a0fb94a7d4ef16aa76fded910b1` pins all GreenField Reality PR heads.
- Vault Notes QA product source: `89d73768f95e1c3fb113a967d411f39384409ae9`, with functional package source at parent `c528dfd7291d9622fc60df5d5c535496178390f3`.
- Protected backend `/root/modula-latest` was not changed. No production registry, key, database, billing state, deployment, public release, or existing GreenField PR was modified.

## Contract implemented

The native client consumes `POST /v1/modules/:moduleId/package-install-plan` and requires:

- lock schema `modula.package-lock.1` and a locally recomputed canonical lock digest;
- package schema `modula.package.1`;
- one `module` root using `application/gzip` for the supported content-only module shape;
- iOS compatibility, bounded sizes, a complete dependency closure, and supported required capabilities;
- verified publisher and release trust with no revocation;
- an exact Ed25519 signature encoded as backend-compatible unpadded base64url, a signer key ID, and a 64-character signed-statement digest;
- account-private downloads to require bearer authorization and immutable public downloads to require no authorization.

The install path also consumes the existing installation descriptor and binds the downloaded package to the exact release ID, version, signer key ID, signed-statement digest, frontend digest, artifact digest, media type, size, access class, permission review, and launch-eligibility result.

## Native implementation

- `ModuleContentPackage` reuses the existing strict ustar parser and enforces compressed, expanded, and member-count bounds; safe relative paths; no links; no native or executable payload types; exact `package.files.json` membership; and SHA-256 for every member.
- The only host-consumed entry is `frontend/frontend.manifest.json`, which is parsed by the existing declarative Product UI runtime. Downloaded native code is never loaded or executed.
- Staging is account-scoped and atomic. `release.json` records the package digest only after extraction succeeds. ACTIVE and PREVIOUS_GOOD slot behavior remains owned by the existing `ModuleActivationController`.
- Every launch revalidates the immutable archive, extracted inventory, file types, member set, member checksums, and packaged frontend equality. Partial, substituted, extra, linked, or digest-mismatched installs fail closed.
- Update activation preserves PREVIOUS_GOOD and automatically restores it after failed activation health. Uninstall uses the existing module-cache removal path.
- Product Hub accepts only the supported single-package module graph or the existing exact game/runtime graph. Unknown media types, categories, dependencies, capabilities, and malformed signatures remain rejected.
- Online launch rechecks the exact signed module release against GreenField. Offline launch is limited to the already verified account-scoped cache.
- Existing SwiftUI Product Hub and ModuleHost architecture are preserved; Vault Notes was not converted into a hardcoded native screen.

## QA-only Vault package

Vault Notes `2.0.0-qa.1` declares a content-only `modula.package.1` distribution and is reproducibly assembled with `pnpm qa:native-package` followed by `pnpm release:package`.

| Artifact | SHA-256 | Bytes |
| --- | --- | ---: |
| `distribution/vault-notes-content-2.0.0-qa.1.tgz` | `5c33724eac69a65750e12495160d14913de544664e1f2464aefb0bd67fae73f8` | 11,493 |
| `frontend/frontend.manifest.json` | `34092f1adad72c78451dd0b5623899df1503fb60aab03e6f6abc54ce5c255b91` | 147,239 |
| `release/modula-vault-notes-2.0.0-qa.1.tgz` | `12c95d390e85776f1e8f2ce2bde2cb42b60d36a8fec53519c4502355365397c2` | 308,434 |

This candidate has not been publicly published. The acceptance harness creates an ephemeral Ed25519 keypair, registers only its public key in a disposable registry, signs the release provenance in memory, and never persists the private key.

## Disposable backend acceptance

Database `modula_native_reality_05_qa_6157acf_retry5` was created in the loopback-only `modula-feature-reality-01-pg` container and migrated through 087. The harness itself refuses production mode, non-loopback database hosts, and database names without an explicit `qa` or `test` marker.

Observed real service results:

| Operation | Result |
| --- | --- |
| Standard release sync into disposable registry | published in disposable scope; all 9 provenance/package checks passed |
| Package install plan | HTTP 200; signed `module` root; account-private `application/gzip` artifact |
| Install request | HTTP 202 |
| Install worker | completed |
| Enable request and worker | HTTP 202; completed |
| Installation descriptor | `launchEligible: true`; `signatureState: verified` |
| Exact artifact download | HTTP 200; 11,493 bytes; digest `5c33724e...73f8` |
| Vault note create | HTTP 201 |
| Vault note edit | HTTP 200; revision 2 |
| Vault note read | HTTP 200; edited title persisted |

Backend checks:

- GreenField typecheck: PASS.
- PR #157 focused signed package entitlement/tamper test: 1 passed, 17 skipped by the exact test filter.
- QA Vault package harness: PASS.
- Vault product verification: 7 files and 27 tests passed.
- Vault preview verification: 8 checks passed.

## Native verification

- Ownership-boundary verifier: PASS.
- Generated design-contract verifier: PASS.
- TypeScript runtime typecheck: PASS.
- Runtime tests: 22/22 passed.
- `git diff --check`: PASS.
- SwiftLint parsed all seven changed Swift files. Strict lint remains nonzero because these files already carry project-wide line-length/file-length/complexity findings and the expanded package dispatcher adds complexity; this is not treated as a Swift compiler result.
- Swift/Xcode unit tests: BLOCKED on this Linux host because neither Swift nor Xcode is installed.
- iOS simulator Product Hub install/launch/note flow: DEFERRED to an authorized macOS/Xcode runner.
- Physical iPhone: DEFERRED; no authorized device is available here.

## Acceptance status

| Gate | Status |
| --- | --- |
| QA-only `modula.package.1` artifact | PASS |
| GreenField signed plan/install/enable/artifact/note lifecycle | PASS in disposable QA |
| Native source implementation and Linux-available gates | PASS |
| Native XCTest package lifecycle/security cases | BLOCKED pending macOS/Xcode execution |
| Product Hub → install → launch → create/edit/read note in simulator | DEFERRED |
| Physical-device persistence/update/uninstall | DEFERRED |
| Public package publication | BLOCKED by design; not authorized |
| Production release | BLOCKED; outside mission authority |

## Rollback

Before merge, revert the NATIVE-05 native commit and discard the local QA product/backend branches. At runtime, a failed update retains and restores PREVIOUS_GOOD; uninstall removes the account-scoped module cache through the existing store. No production data or registry rollback is required because all server acceptance occurred in a disposable database.
