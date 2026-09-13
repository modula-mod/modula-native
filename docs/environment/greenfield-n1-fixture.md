# Greenfield N1 integration fixture

The N1 fixture is isolated from production data. It uses the existing `greenfield-backend-v1-database-fixture.mjs` helper against the VPS preview Postgres container, producing a dedicated database whose name begins `modula_gbv1_native_n1`. The API and worker use ordinary non-superuser Greenfield roles against that database. They listen on VPS loopback. The Mac harness uses an authenticated SSH tunnel and a simulator-trusted local test CA. `native-n1.modula.digital` is a Cloudflare-terminated device-test edge which proxies only to the same loopback N1 service; its checked-in nginx definition contains no credential and never targets the production API process or database.

`scripts/n1/provision-vps.mjs` is the bootstrap mechanism. It runs the complete migration chain, pins the canonical Vault repository to immutable tag `vault-notes-v1.7.0`, verifies the release artifact/provenance through the existing MPS publication CLI, and publishes it into the isolated registry. Provisioning is state-aware and reuses the existing database and service credentials. It is not part of normal app startup.

`scripts/n1/fixture.mjs` uses public Greenfield contracts. The dedicated account was created with `/v1/accounts/register`, activated with the normal development verification token through `/v1/accounts/verify-email`, and subsequently authenticated through `/v1/sessions`. No account rows were inserted directly. Vault installation uses install-preview, install, the existing outbox/worker job flow, and enable. The reconciler preserves exactly four deterministic active notes titled `N1 Fixture 1` through `N1 Fixture 4`, removes abandoned RN UI test notes, and runs a create/read/update/delete persistence probe. Re-running it is the routine data reset.

The Mac credential file is `.env.n1.local`, mode 0600 and covered by `.gitignore` before creation. It is read only by the local fixture harness and hosted native integration test. The physical UI harness generates a mode-0600 ignored `.local.xcscheme`; its build-for-testing output is also ignored. Greenfield tokens are stored by the native client in a Keychain item namespaced to the configured API origin. No credential, token, database URL, or authorization header is committed or printed by the fixture scripts.

The VPS keeps its database/service configuration under `/root/modula-native-n1` with directory mode 0700 and files mode 0600. The transient units are `modula-native-n1.service` and `modula-native-n1-worker.service`. Stopping the worker demonstrates that queued install transitions pause without changing record CRUD; restarting it resumes the existing outbox. Dropping the isolated database and its dedicated roles is the full reset path and must be done deliberately from the VPS fixture owner, followed by a fresh provision. Production database and production API state are never targets of these scripts.

Observed installation path:

1. install preview reported Vault 1.7.0 compatible;
2. install returned an asynchronous installation plan;
3. the isolated worker consumed `module.install` and moved the installation to installed;
4. enable queued `module.enable`;
5. the worker moved the installation to enabled;
6. record access succeeded only after the enabled state.

This is backend behavior for the later Product Hub installation UI. N1 only consumes the already-enabled result.

Worker-loss acceptance stopped `modula-native-n1-worker`, confirmed that the already-enabled Vault and its authenticated record CRUD remained healthy, and restored the worker to active. Transport-loss acceptance stopped the Mac TLS edge after Vault loaded, confirmed a safe module error, and continued through native Close, Product Hub, and Profile before restoring the edge.
