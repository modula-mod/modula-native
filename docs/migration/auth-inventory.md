# Authentication inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Authoritative executable evidence: `src/data/repositories/api/ApiAuthRepository.ts`, `src/auth/contracts/AuthCredentials.ts`, `src/api/decoding/decodeSession.ts`, `src/auth/runtime/SessionRefreshCoordinator.ts`, `src/auth/storage/NativeSecureSessionStorage.ts`, `services/greenfield-api/src/sessions/service.ts`.

Password login POST `/v1/sessions` body `{email,password}` returns accessToken, refreshToken, sessionId, accessExpiresAt, refreshExpiresAt. Hydration calls authenticated `/v1/accounts/me`; public profile lookup is optional and must not erase a valid account. Bearer access is used by the client. Native storage currently wraps Expo SecureStore; N1 rewrites this with Keychain and no JS token storage. Sessions are opaque tokens (not client-decodable JWTs). Server stores hashes, rotates refresh tokens and revokes a family on reuse. Native refresh must coalesce concurrent requests and persist rotated tokens atomically before reuse.

Registration POST `/v1/accounts/register`: email, password, handle, inviteCode?, displayName?, acceptedTerms. Pending verification includes challengeId/expiry/delivery. Verify `/v1/accounts/verify-email` accepts token or challengeId+code. Resend `/v1/accounts/resend-verification`. Password reset uses `/v1/accounts/forgot-password` and `/v1/accounts/reset-password`. Email sign-in requests `/v1/sessions/email-code/request` then `/v1/sessions/email-code`. These current source methods supersede older docs that call email login unwired; live acceptance remains separate.

Refresh POST `/v1/sessions/refresh` `{refreshToken}`. Logout DELETE `/v1/sessions/current`. Session list `/v1/accounts/me/sessions`; revoke `/v1/sessions/{sessionId}`; revoke others DELETE `/v1/accounts/me/sessions`. Device metadata is session userAgent/platform; no independent native identity protocol is needed. Offline logout must clear local credentials even when server revocation fails, and report that distinction.

Passkeys, TOTP, recovery codes and Apple login are not assumed enabled. Live `/v1/meta` reports Apple unconfigured. Existing UI marks passkeys/TOTP/recovery setup unavailable. Browser persistence/cookies are not the native protocol. No existing user's credentials or Keychain contents were harvested for acceptance.

CARRY endpoint/response contracts and scenarios; NATIVE_REWRITE session lifecycle/storage/UI; RETIRE Expo storage adapter. Master secrets remain Swift-only. ModuleSession is an ephemeral host capability handle and user context, never a backend credential.

