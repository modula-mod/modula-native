# MODULA-NATIVE-REALITY-01 — NATIVE-06 Premium StoreKit sandbox

**STATUS: BLOCKED**

The native StoreKit 2 integration is implemented against GreenField PR #158, but this host cannot produce real Apple-signed sandbox evidence. No purchase, restore, App Store Server Notification, simulator, or device result is marked PASS.

## Pinned inputs

- Native base SHA: `ebba415b7285b9cbae51d8851186aee5d9ee3446`
- Backend PR: `modula-mod/modula-latest#158` (draft)
- Backend PR head: `d961481f68a8412a5e18a594f6355711ba67ebc0`
- Disposable backend composition: `a7bd5dd6ef9f0465f9cbbc321b2c99d46010bc42`
- App bundle identifier: `digital.modula.app.native`
- Environment inspected: Linux x86_64, 2026-11-03

The backend composition is an isolated QA composition of unmerged work. It is not a shared QA deployment and was not connected to production.

## Atlas contracts consumed

| Method | Path | Native request | Native use |
| --- | --- | --- | --- |
| `GET` | `/v1/premium/tiers` | none | Refresh server catalogue and purchase availability. |
| `GET` | `/v1/me/membership` | none | Parse the declared schema-version-1 membership projection; this is the native entitlement authority. |
| `GET` | `/v1/me/entitlements` | none | Refresh server capability evaluation after a transaction. |
| `POST` | `/v1/me/membership/apple-purchase-context` | exact empty object `{}` | Obtain the authenticated account's stable `appAccountToken` and confirmed active sandbox mappings. |
| `POST` | `/v1/premium/apple/transactions` | `{ "signedTransaction": "<StoreKit JWS>" }` | Submit StoreKit 2 signed evidence for GreenField verification and projection. |
| `PATCH` | `/v1/me/membership/badge-visibility` | `{ "visible": <boolean> }` | Keep membership-mark visibility separate from entitlement. |

`POST /v1/premium/apple/notifications` is an Apple-to-backend contract. The native app does not call it.

## Native implementation

- Loads product identifiers only from GreenField's authenticated, operator-confirmed sandbox mapping; it does not invent or trust the bundled local StoreKit catalogue.
- Loads `Product` values from the App Store and displays Apple's `displayPrice` on the purchase surface.
- Passes GreenField's UUID as StoreKit's `appAccountToken`.
- Accepts only locally verified `VerificationResult<Transaction>` values.
- Checks product and account binding before submitting StoreKit's JWS to GreenField.
- Refreshes membership and entitlements before finishing an accepted transaction.
- Does not finish evidence that GreenField rejects, allowing StoreKit retry after sign-in, network recovery, or QA configuration repair.
- Handles pending and user-cancelled purchases without granting access.
- Implements explicit user-initiated restore with `AppStore.sync()` and `Transaction.currentEntitlements`.
- Ignores transactions bound to another Modula account and never submits or finishes them.
- Listens for `Transaction.updates` and applies only GreenField-accepted results.
- Opens Apple's subscription-management sheet for cancellation; membership remains server-authoritative.
- Projects expired, revoked, and downgraded membership to Core without deleting user data.
- Keeps the membership badge as a separate visibility preference and never represents it as identity verification.
- Clears account-scoped Premium state on account change.

The existing Debug preview is still visibly labelled as a local presentation preview. It is ignored in Release and is not Apple evidence. The entire Premium surface remains disabled in Release pending explicit product and production-billing approval.

## Tests and evidence

### Native repository gates

- `npm run verify:boundary`: PASS.
- `npm run verify:design`: PASS.
- `npm run typecheck`: PASS.
- `npm test`: PASS, 22/22 tests.
- `git diff --check`: PASS.
- SwiftLint parser on all seven changed Swift files: parsed successfully. Existing repository size/line-length debt remains; the focused Premium controller, hub, and test files have no cyclomatic-complexity, statement-position, trailing-comma, or vertical-whitespace violations after the change.
- Added XCTest coverage for exact routes, strict sandbox context decoding, server-authoritative revocation, transaction response environment validation, and the distinction between local StoreKit configuration and Apple sandbox evidence.
- XCTest execution: BLOCKED (`xcodebuild` is unavailable on this Linux host).

### Backend PR #158 gates

Against disposable PostgreSQL, the focused backend suite passed 16/16 tests:

- `premium.apple-sandbox.integration.test.ts`: 3/3.
- `premium.apple-verifier.test.ts`: 3/3.
- `premium.integration.test.ts`: 7/7.
- `premium.config.test.ts`: 3/3.

These tests validate the backend contract, signature-verifier fixtures, idempotent restoration, concurrent transaction handling, account binding, revocation/downgrade projection, and fail-closed configuration. Their signed test fixtures are not real Apple sandbox purchase evidence.

## Apple acceptance gate

Observed configuration status (values were not printed):

- `MODULA_PREMIUM_APPLE_SANDBOX_ENABLED`: MISSING.
- `MODULA_PREMIUM_APPLE_BUNDLE_ID`: MISSING.
- `MODULA_PREMIUM_APPLE_ROOT_CA_FILES`: MISSING.
- App Store Connect key ID: MISSING.
- App Store Connect issuer ID: MISSING.
- App Store Connect private key: MISSING.
- `xcodebuild`: MISSING.
- `xcrun`: MISSING.
- iOS Simulator tooling: MISSING.
- Authorized physical iPhone: unavailable on this host.
- Confirmed App Store Connect product mapping: unavailable; GreenField correctly returns no products until an operator configures them.

Required before NATIVE-06 can pass:

1. Confirm App Store Connect subscription product IDs, tiers, billing periods and availability for `digital.modula.app.native`.
2. Enable PR #158's sandbox verifier in the isolated QA runtime with the approved Apple root certificate files and exact bundle ID.
3. Provide a macOS/Xcode runner or approved TestFlight build and Apple sandbox tester account.
4. Perform purchase, pending/cancel, restart, restore, renewal, upgrade/downgrade and revoke scenarios using Apple-signed evidence.
5. Configure the QA App Store Server Notification URL and capture a verified sandbox notification reaching `POST /v1/premium/apple/notifications`.
6. Recheck membership, capabilities, badge preference and retained user data after each server-confirmed state change.

Apple references used for the gate definition:

- Sandbox testing: <https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox>
- StoreKit verification/JWS: <https://developer.apple.com/documentation/storekit/verificationresult>
- `appAccountToken` purchase option: <https://developer.apple.com/documentation/storekit/product/purchase%28options%3A%29>
- Current entitlements: <https://developer.apple.com/documentation/storekit/transaction/currententitlements>
- Explicit restore synchronization: <https://developer.apple.com/documentation/storekit/appstore/sync%28%29>

## Results

- Source implementation: PASS for the isolated sandbox integration slice.
- Backend QA runtime: PARTIAL; focused disposable-database tests pass, but no live Apple configuration was installed.
- Native contract integration: PASS by source review and contract tests; XCTest execution remains blocked.
- Simulator result: BLOCKED — no macOS/Xcode/simulator.
- Real Apple sandbox result: BLOCKED — no confirmed products, verifier credentials/root configuration, sandbox account or Apple-signed run.
- Device result: DEFERRED — no authorized physical iPhone.
- Production release: NOT STARTED and not authorized.

## Security and rollback

No signing trust, production API, production database, package registry, billing configuration or Apple credential was changed. No secret was printed or committed. Local StoreKit fixtures are explicitly excluded from Apple acceptance evidence.

Rollback the native source slice by reverting its single NATIVE-06 commit. The backend draft PR remains independent and unmerged. Disabling the Debug Premium feature flag leaves current free functionality unchanged; Release already fails closed with the feature surface disabled.
