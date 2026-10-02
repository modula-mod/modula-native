# Native security boundary

Master credentials remain in the native authenticated client and Keychain with this-device-only accessibility. UserDefaults contains nonsecret device settings only. Modules receive an ephemeral capability identifier, limited user identity and semantic environment. They never receive access/refresh tokens, passwords, raw Keychain objects or private app credentials.

Host-mediated backend access is mandatory for N1. Swift supplies authenticated transport after validating action and module scope. Do not let JavaScript choose raw endpoints/headers. Session capabilities expire on close/logout and cannot authorize a different module. Backend checks installation, enablement, published release and permission grants. No blanket grant follows from a native library being linked.

Greenfield has module backend token machinery, but a safe client-scoped credential flow has not been proven. N1 does not distribute those credentials. A native host capability is not a backend authentication token. One RN runtime is not a hostile-code sandbox: bundled trusted modules could share JS memory; arbitrary third-party executable code remains out of scope.

Errors and OSLog must exclude secrets and record content. Public endpoint configuration lives in xcconfig. Local signing/environment overrides are ignored by Git. Account changes must revoke module sessions and prevent stale request results from crossing into the next account. Never retry a mutation blindly after ambiguous transport failure. Expected revisions protect edits and deletions.

The accepted JS root-prop schema (`packages/module-contracts/schemas/module-context.schema.json`) is exactly `surfaceToken`, `moduleID`, `bridgeVersion`, semantic `environment`, `userID` (null unless the module declares and is granted `identity.userID`), the non-identifying `signedIn` flag, `initialPath`, `lifecycle` and `eventSequence`. The native session ID is never exposed; the surface token is bound natively to one module, one account and one surface and is never included in events. A native unit assertion rejects credential-shaped keys or values. Runtime source has no module `fetch` path, and the Release Hermes bundle scan found no account identifier, access/refresh-token markers, authorization header, or Metro URL. The native URLSession layer adds authorization after ModuleSession, module identity, manifest action, collection, and payload validation.

## Module sessions and authentication

A 401 from a module records call does not sign the app out. `GreenfieldClient` refreshes once. If that refresh succeeds, the shell session is valid, and a repeated 401 is treated as a module-scoped rejection (`BACKEND_UNAUTHENTICATED` to the module). The app signs out only when the shell's own session is gone, meaning the refresh was definitively rejected and the client invalidated itself.

## Installation gate when the catalogue isn't loaded (decision, 2026-10-02)

`/module/<id>` requires a runnable installation for the signed-in account. Product Hub supplies it from `GET /v1/modules/installed`. **Decision: if the catalogue hasn't loaded yet (offline or early launch), the host does not block the module.** The surface opens, and Greenfield still refuses every records request for a module that isn't installed or enabled, so no data crosses. Once the catalogue has loaded, a missing or non-runnable installation shows the native `notInstalled` state before any module JavaScript runs. In DEBUG builds the bundled `modula.runtime-diagnostic` developer surface is exempt, because it is not a catalogue product.

## Deferred

- **Per-module JS isolation.** This needs a separate runtime per module or process isolation.
- **Bundled code digest.** The registry doesn't yet publish a per-platform digest of the iOS-bundled manifest or JS. The host already honours `manifest.bundledManifestSha256` when it is present.
- **Identity permission mapping.** `identity.userID` has no registry permission mapping yet, so the manifest declaration alone grants it.
