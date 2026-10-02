# Host bridge 0.1.0

Modules submit versioned requests with a native-issued surface/session identifier. Swift validates session validity, module manifest grants, action name, typed parameters and permitted destination before dispatch. A module never supplies a URL, authorization header, account selector or arbitrary native method name. Responses are JSON values or structured safe error codes. A disposed session cannot continue issuing actions; asynchronous responses must be discarded after revocation.

Contract families: navigation, presentation, appearance, lifecycle, permissions, haptics, sharing, clipboard, files, module settings, authentication context, backend access and diagnostics. N1 implements only the operations needed for diagnostic proof and real records. Unsupported families return an explicit unsupported/denied result; a contract declaration does not imply a native implementation.

Semantic appearance snapshot: colorScheme, oled, accent, surfacePreference, reduceMotion, textScale. Lifecycle includes mounted, active, inactive, backgrounded, foregrounded, unmounted, memoryPressure and appearanceChanged. Events include a surface/session identity to prevent cross-surface delivery.

Host navigation resolves profile/post/product/module/settings/home through one coordinator. Presentation requests are governed by native UI. Record requests are limited to the current module's declared collection, operation and session account. The backend still performs its own installation/permission/revision checks. No false assertion of third-party isolation: bundled modules share JS memory.

N1 Vault implements a closed record vocabulary: `backend.records.list`, `get`, `create`, `update`, and `delete`. JavaScript supplies the declared `note` collection and operation-specific values only. Swift constructs the fixed Greenfield path, HTTP method, revision body, and authenticated request. Exact-key validation rejects URL/header injection, foreign collections, Boolean/fractional/out-of-range revisions, unknown operations, malformed payloads, expired sessions, unmounted sessions, and module-identity mismatches.

The custom Vault surface owns only `/`, `/new`, and note/editor state within its React tree. Product Hub enters `AppRoute.module("digital.modula.vault-notes")`; profile requests cross the bridge and become a native `AppRoute.profile`. Native Back, Close, Retry, failure presentation, and global navigation remain outside the React surface.

## Bridge 0.1.0 security model (module-security-and-l10n)

Wire shapes are JSON Schemas in `packages/module-contracts/schemas/` (`host-request`, `host-reply`, `module-context`, `module-manifest`, `host-state`). Shared vectors are in `packages/module-contracts/test-vectors/`. The iOS unit tests (`ModuleSecurityTests`) and the TypeScript tests (`runtime/tests/contracts.test.ts`) both assert them, and a Kotlin host must pass the same files.

- **Surface-bound capability.** Each surface gets a 256-bit `surfaceToken` from `SecRandomCopyBytes`. It is placed only in that surface's root props. Native code resolves `token → session` (`ModuleRuntimeController.session(forToken:moduleID:)`) and requires `moduleID` to equal the bound module. The native session ID never reaches JavaScript. Requests carrying `sessionID` fail the exact-key check with `REQUEST_DENIED`.
- **Per-surface events.** Lifecycle and appearance updates are delivered by setting that surface's `RCTSurfaceHostingProxyRootView.appProperties` with `lifecycle` and `eventSequence`. `ModulaModuleRoot` forwards them to `host.subscribe` listeners. The shared `onHostEvent` emitter stays in the codegen spec but is never fired, and events never contain a token.
- **Residual risk.** Bundled modules still share one Hermes realm. Hostile JavaScript could in principle reach another root's props through React internals. True isolation needs a runtime per module or process isolation, which is deferred. Only trusted, first-party bundled modules may ship until then.
- **Native gates before any module JavaScript runs.** They are checked in this order:
  1. Compatibility. A failure gives `updateRequired`.
  2. Installation. The account's installation must be runnable (`ProductHubStore.installGate`), otherwise `notInstalled`.
  3. Integrity. The verified install descriptor must recompute its own digest, name the module, and not be revoked or quarantined. If the descriptor carries `manifest.bundledManifestSha256` (reserved, not published by the registry yet), the canonical SHA-256 of the bundled manifest must equal it. A failure gives `integrityFailed`.
  4. Permissions. If the registry withheld a declared registry-gated capability, the state is `permissionDenied`.
  5. Bundle present. Otherwise the state is `unavailable`.
- **Versions.** `minHostVersion` and `minBridgeVersion` are semver ranges. A bare version means caret, so `0.1.0` = `>=0.1.0 <0.2.0`. Unparseable ranges fail closed.
- **Sessions.** The TTL is 15 minutes. Each authorized request and each resume renews it, but a suspended session is not renewed. Expiry ends the session in the `expired` state, and requests get `SESSION_EXPIRED`.
- **Permissions.** The effective grant is manifest ∩ host-supported ∩ registry grant, where `backend.records.*` requires the registry permission `storage:records`. A denied call returns `PERMISSION_DENIED`. `userID` is null unless `identity.userID` is granted. Modules get the non-identifying `signedIn` flag instead.
- **Errors.** Backend and transport failures map to fixed codes (`BACKEND_*`, `NETWORK_UNAVAILABLE`, `SESSION_REVOKED`) with host-written text. Backend text never reaches JavaScript.
