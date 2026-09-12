# Native security boundary

Master credentials remain in the native authenticated client and Keychain with this-device-only accessibility. UserDefaults contains nonsecret device settings only. Modules receive an ephemeral capability identifier, limited user identity and semantic environment. They never receive access/refresh tokens, passwords, raw Keychain objects or private app credentials.

Host-mediated backend access is mandatory for N1. Swift supplies authenticated transport after validating action and module scope. Do not let JavaScript choose raw endpoints/headers. Session capabilities expire on close/logout and cannot authorize a different module. Backend checks installation, enablement, published release and permission grants. No blanket grant follows from a native library being linked.

Greenfield has module backend token machinery, but a safe client-scoped credential flow has not been proven. N1 does not distribute those credentials. A native host capability is not a backend authentication token. One RN runtime is not a hostile-code sandbox: bundled trusted modules could share JS memory; arbitrary third-party executable code remains out of scope.

Errors and OSLog must exclude secrets and record content. Public endpoint configuration lives in xcconfig. Local signing/environment overrides are ignored by Git. Account changes must revoke module sessions and prevent stale request results from crossing into the next account. Never retry a mutation blindly after ambiguous transport failure. Expected revisions protect edits and deletions.
