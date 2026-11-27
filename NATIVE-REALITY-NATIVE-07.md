# MODULA-NATIVE-REALITY-01 — NATIVE-07 package/GUBIC regression

**STATUS: PARTIAL**

Source implementation and every Linux/disposable-database gate pass. The permanent iOS XCTest cases are present and statically verified, but cannot be executed on this Linux host; simulator/device acceptance remains part of NATIVE-08.

## Pinned inputs

- Native base SHA: `aae0823e3a93e455b778aa3a2cc74d6156ac3b83` (draft PR #267)
- Backend GreenField PR #147 head: `64e8429c5e431bde459a91303d87767b3706ca0a`
- Backend corrective draft PR: #160
- Backend corrective SHA: `4e4410f657f453bf6651dcdf8f725c55f9eb9d39`
- Backend QA database: disposable PostgreSQL on loopback; no production database was used.

## Native dispatch matrix

Package dispatch now has one authority keyed by exact schema version, category and media type:

| Surface | Schema | Category | Media type | Native behavior |
| --- | --- | --- | --- | --- |
| Moliboo content pack | `modula.package.1` | `asset-pack` | `application/vnd.modula.moliboo-asset-pack+json` | Verify signed JSON container and data-only inventory. |
| Sticker manifest | `modula.sticker-pack.1` | internal `sticker-manifest` dispatch | `application/json` | Verify signed manifest before trusting sticker facts. |
| Sticker asset | `modula.sticker-pack.1` | internal `sticker-asset` dispatch | `image/png` | Require manifest/response digest, size, path and PNG signature agreement. |
| Vault Notes/module content | `modula.package.1` | `module` | `application/gzip` | Strict content-only archive verifier; only declarative Product UI is hosted. |
| GUBIC game | `modula.package.1` | `game-content` | `application/vnd.modula.game-web+tgz` | Strict web-game archive verifier and isolated game host. |
| GUBIC shared runtime | `modula.package.1` | `web-runtime` | `application/vnd.modula.web-runtime+tgz` | Strict shared-runtime verifier. |

Installed GUBIC distribution descriptors continue to read the historical `application/gzip` game artifact type as well as the vendor type. New package-install plans remain exact and require the reviewed vendor type.

`application/vnd.modula.asset-pack+tgz` remains valid database storage inherited from migration 077, but native dispatch deliberately rejects it because this host has no verifier for the generic archive. Unknown media types, wrong category/media combinations, and `modula.package.2` remain unsupported.

## Backend defect and correction

Migration 077 introduced three optional package media types:

- `application/vnd.modula.game-web+tgz`
- `application/vnd.modula.web-runtime+tgz`
- `application/vnd.modula.asset-pack+tgz`

Migration 084 replaced the blob constraint but retained only the first two, silently removing generic asset-pack storage. Its down migration had the same omission.

Draft backend PR #160, based directly on draft PR #147, restores the missing type in both directions. The permanent migration-chain assertions now require:

- all three pre-084 types after rolling 084 down; and
- all three plus `application/vnd.modula.moliboo-asset-pack+json` after applying 084/latest.

If a future migration replaces the constraint and removes one of these media types without updating the explicit reviewed set, the fresh-chain/legacy-upgrade test fails.

## Permanent regression coverage

The new Linux-executable test verifies:

- every supported native package shape is declared once;
- vendor media strings and sticker schema have one native authority;
- Product Hub, Moliboo, stickers and the download client consume that authority;
- the security and rollback XCTest cases remain wired.

The extended XCTest matrix covers:

- exact dispatch for Moliboo, stickers, Vault/module content and GUBIC game/runtime packages;
- unknown media types, unsupported schema versions and category substitution;
- invalid package signature shape;
- Moliboo tamper, forged signature, unsafe extraction and interrupted installation;
- Vault content tamper and failed-update rollback;
- GUBIC game/runtime revocation, digest mismatch, archive isolation and failed-update rollback;
- relaunch validation and verified previous-version recovery.

## Tests and outcomes

Native repository:

- `npm run verify:boundary`: PASS.
- `npm run verify:design`: PASS.
- `npm run typecheck`: PASS.
- `npm test`: PASS, 25/25 tests (three package-media regression tests).
- `git diff --check`: PASS.
- SwiftLint parsed all seven changed Swift files with zero parser failures. Existing file-size/complexity/line-length debt remains and is not claimed as a clean lint gate.
- iOS XCTest execution: BLOCKED — `xcodebuild` is unavailable on Linux.

Backend corrective branch:

- `pnpm --filter @modula/greenfield-api typecheck`: PASS.
- `api-fix-01.migration.test.ts`: PASS, 3/3 against a new empty disposable PostgreSQL base, including migration 084 up and down.
- `package-closure-resolver.test.ts`: PASS, 11/11.
- `git diff --check`: PASS.

An initial database attempt executed zero test cases because the global cleanup lacked DELETE permission on an already-migrated base database. It is not counted. The reported 3/3 result is the rerun using a new empty database owned by `modula_migrator`, matching the intended test isolation.

## Security, limitations and rollback

Downloaded package content remains data-only. This work does not add native-code execution, a generic archive handler, signing trust, production keys, production data, registry publication or GUBIC redesign.

Simulator result: BLOCKED pending macOS/Xcode. Physical-device result: DEFERRED. Production result: NOT STARTED / NOT AUTHORIZED.

Rollback the native slice by reverting its NATIVE-07 commit after it is created. Roll back the backend correction by reverting `4e4410f657f453bf6651dcdf8f725c55f9eb9d39`; that would reintroduce the identified constraint regression and therefore requires an explicitly approved replacement migration path.
