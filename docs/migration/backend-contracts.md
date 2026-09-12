# Greenfield contracts

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Source authority: `src/data/repositories/api/ApiAuthRepository.ts`, `ApiModuleRepository.ts`, `ApiAppearanceRepository.ts`; `services/greenfield-api/src/modules/routes/index.ts`, `runtime-access.ts`; API envelope contracts. No OpenAPI/Swagger source was found in the tracked file search; focused Codable models are preferable to speculative code generation.

Public environment configuration is `https://api.modula.digital`, verified in runtimeEnvironment.ts. This is configuration, never a Swift literal. Live unauthenticated `curl /v1/meta` returned HTTP 200 on 2026-09-12 and identified production Greenfield v1. Python urllib probe received 403; CLI transport success does not prove iPhone networking.

| N1 operation | Contract |
|---|---|
| Metadata | GET /v1/meta |
| Password session / refresh / account / logout | See auth-inventory.md |
| Catalogue / detail | GET /v1/registry/products; GET /v1/registry/products/{moduleID} |
| Installed products | GET /v1/modules/installed (authenticated) |
| Runtime eligibility | GET /v1/modules/{id}/runtime; backend verifies account installation, enabled state, published/non-quarantined release |
| List records | GET /v1/modules/{id}/records/{collection}; cursor, limit≤100, q, sort, filters, recordState=active/deleted |
| Read record | GET /v1/modules/{id}/records/{collection}/{recordID} |
| Create | POST collection path, body {data} |
| Edit | PATCH record path, body {data,expectedRevision} |
| Delete | DELETE record path, body {expectedRevision}; soft deletion; permanent endpoint separate |
| Settings | GET /settings-schema, GET/PATCH /settings with {values} |
| Module action | POST /actions/{actionID} with {input,idempotencyKey} |
| Install lifecycle | POST /install-preview, /install, /enable, /disable, /update; permission approval belongs to native shell |

All module paths above share `/v1/modules/{id}`. Canonical Vault ID is `digital.modula.vault-notes`; current MPS record type is `note`, not historical `notes`. Do not silently rename collections or create a second product.

Success envelope `{ok:true,data,meta:{requestId,serverTime}}`; failure `{ok:false,error:{code,message,requestId,retryable,...},meta}`. Records expose record_id/data/revision/visibility/createdAt/updatedAt. Preserve revision conflicts instead of blind retries. Authenticated requests use bearer access only inside native client.

RuntimeAccessService resolves account installation/release and granted permissions; records permission grammar is `records:module.{moduleID}.{collection}:{read|write|delete}`. Backend module-to-service token machinery exists but is not evidence of client-scoped credentials suitable for arbitrary RN code. N1 host-mediated requests have allowlisted methods/collections and cannot choose arbitrary URLs, headers or account IDs.


Follow-up live read: catalogue detail returned HTTP 200 with canonical ID `digital.modula.vault-notes`, name Vault Notes, latestVersion **1.7.0**. No authenticated CRUD was claimed from this public probe.
