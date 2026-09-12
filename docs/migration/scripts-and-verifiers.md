# Scripts and verification inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Verifiers were inventoried, not run in the read-only checkout. Source-pattern checks do not establish simulator/device acceptance. Carry business assertions and failure scenarios into native tests; Expo prebuild/export/web/PWA scripts are reference-only. Backend verifiers run only against authorized environments; scripts may mutate data, so do not bulk-run archaeological scripts.

| Script | Existing command |
|---|---|
| verify:greenfield-images | `node scripts/verify-greenfield-image-build-graph.mjs` |
| verify:web-build | `node scripts/verify-web-build.mjs` |
| verify:web-dist-routes | `node scripts/resolve-web-dist-file.mjs` |
| verify:mdhs-0.1 | `node scripts/verify-mdhs-0.1.mjs` |
| verify:phase7k | `node scripts/verify-mdhs-0.1.mjs --phase7k` |
| verify:phase7l-a | `node scripts/verify-phase7l-a.mjs` |
| verify:phase7l-b:session | `node scripts/verify-phase7l-b-session.mjs` |
| verify:phase7l-b:hydration | `playwright test tests/phase7l-b-public-routes.test.ts` |
| verify:phase7l-b:auth | `node scripts/verify-phase7l-b-auth-regression.mjs` |
| verify:phase7l-b | `node scripts/verify-phase7l-b.mjs` |
| verify:phase7m-b | `node scripts/verify-phase7m-b.mjs` |
| verify:phase7m-b3-evidence | `node scripts/verify-phase7m-b3-evidence.mjs` |
| verify:phase7m-b6 | `node scripts/verify-phase7m-b6.mjs` |
| verify:phase7m-b7 | `node scripts/verify-phase7m-b7.mjs` |
| verify:phase7m-b7:web | `playwright test tests/phase7m-b7-web.test.ts` |
| verify:vault-notes-canonical | `node scripts/verify-vault-notes-canonical.mjs` |
| verify:phase1 | `node scripts/verify-phase1-shell.mjs` |
| verify:phase2 | `node scripts/verify-phase2-appearance.mjs` |
| verify:theme | `node scripts/verify-theme-contrast.mjs` |
| verify:phase3 | `node scripts/verify-phase3-profile.mjs` |
| verify:phase4 | `node scripts/verify-phase4-data-auth.mjs` |
| verify:phase4-5 | `node scripts/verify-phase4-5-native-ui.mjs` |
| verify:layout-preferences | `node scripts/verify-layout-preferences.mjs` |
| test:account-panel | `node scripts/test-account-panel-state.mjs` |
| verify:phase5 | `node scripts/verify-phase5-backend.mjs` |
| verify:phase6-backend | `node scripts/verify-phase6-backend.mjs` |
| verify:phase6-greenfield-backend | `node scripts/verify-phase6-greenfield-backend.mjs` |
| verify:phase6-greenfield-frontend | `node scripts/verify-phase6-greenfield-frontend.mjs` |
| verify:phase6s-social-backend | `node scripts/verify-phase6s-social-backend.mjs` |
| verify:phase6s-social-frontend | `node scripts/verify-phase6s-social-frontend.mjs` |
| verify:phase7a:frontend-boundary | `node scripts/verify-phase7a-frontend-boundary.mjs` |
| verify:phase7a-module-platform | `node scripts/verify-phase7a-module-platform.mjs` |
| verify:phase7b-module-runtime | `node scripts/verify-phase7b-module-runtime.mjs` |
| verify:phase7b-module-host | `node scripts/verify-phase7b-module-host.mjs` |
| verify:phase7b-expo-ui-boundary | `node scripts/verify-phase7b-expo-ui-boundary.mjs` |
| verify:phase7b-vault-notes | `node scripts/verify-phase7b-vault-notes.mjs` |
| verify:phase7b-branch-consolidation | `node scripts/verify-phase7b-branch-consolidation.mjs` |
| verify:phase7c-product-shell | `node scripts/verify-phase7c-product-shell.mjs` |
| verify:phase7c-social-core | `node scripts/verify-phase7c-social-core.mjs` |
| verify:phase7c-profile | `node scripts/verify-phase7c-profile.mjs` |
| verify:phase7c-board | `node scripts/verify-phase7c-board.mjs` |
| verify:phase7c-settings | `node scripts/verify-phase7c-settings.mjs` |
| verify:phase7c-native-readiness | `node scripts/verify-phase7c-native-readiness.mjs` |
| verify:phase7c-product-complete | `node scripts/verify-phase7c-product-complete.mjs` |
| verify:phase7c-api-parity | `node scripts/verify-phase7c-api-parity.mjs` |
| verify:phase7c-placeholder-free | `node scripts/verify-phase7c-placeholder-free.mjs` |
| verify:phase7c-release-candidate | `node scripts/verify-phase7c-release-candidate.mjs` |
| verify:phase7c-founder-alpha | `node scripts/verify-phase7c-founder-alpha.mjs` |
| verify:phase7d-runtime-platform | `node scripts/verify-phase7d-runtime-platform.mjs` |
| verify:phase7d-connector-platform | `node scripts/verify-phase7d-connector-platform.mjs` |
| verify:phase7d-connector-security | `node scripts/verify-phase7d-connector-security.mjs` |
| verify:phase7d-connection-lifecycle | `node scripts/verify-phase7d-connection-lifecycle.mjs` |
| verify:phase7e-code-quality | `node scripts/verify-phase7e-code-quality.mjs` |
| verify:phase7e-event-platform | `node scripts/verify-phase7e-event-platform.mjs` |
| verify:phase7e-policy-engine | `node scripts/verify-phase7e-policy-engine.mjs` |
| verify:phase7e-audit-platform | `node scripts/verify-phase7e-audit-platform.mjs` |
| verify:phase7e-notifications | `node scripts/verify-phase7e-notifications.mjs` |
| verify:phase7e-search-platform | `node scripts/verify-phase7e-search-platform.mjs` |
| verify:phase7e-module-standard | `node scripts/verify-phase7e-module-standard.mjs` |
| verify:phase7e-module-validator | `node scripts/verify-phase7e-module-validator.mjs` |
| verify:phase7e-module-sdk | `node scripts/verify-phase7e-module-sdk.mjs` |
| verify:phase7e-module-cli | `node scripts/verify-phase7e-module-cli.mjs` |
| verify:phase7e-module-health | `node scripts/verify-phase7e-module-health.mjs` |
| verify:phase7e-module-security | `node scripts/verify-phase7e-module-security.mjs` |
| verify:phase7e-standard2-normalization | `node scripts/verify-phase7e-standard2-normalization.mjs` |
| verify:phase7e-module-dependency-runtime | `node scripts/verify-phase7e-module-dependency-runtime.mjs` |
| verify:phase7e-module-capability-registry | `node scripts/verify-phase7e-module-capability-registry.mjs` |
| verify:phase7e-module-service-fabric | `node scripts/verify-phase7e-module-service-fabric.mjs` |
| verify:phase7e-module-hooks | `node scripts/verify-phase7e-module-hooks.mjs` |
| verify:phase7e-module-lifecycle | `node scripts/verify-phase7e-module-lifecycle.mjs` |
| verify:phase7e-module-permissions-v2 | `node scripts/verify-phase7e-module-permissions-v2.mjs` |
| verify:phase7e-module-storage-runtime | `node scripts/verify-phase7e-module-storage-runtime.mjs` |
| verify:phase7e-module-jobs-runtime | `node scripts/verify-phase7e-module-jobs-runtime.mjs` |
| verify:phase7e-module-ui-contributions | `node scripts/verify-phase7e-module-ui-contributions.mjs` |
| verify:phase7e-module-runtime-security | `node scripts/verify-phase7e-module-runtime-security.mjs` |
| verify:phase7e-module-runtime-2 | `node scripts/verify-phase7e-module-runtime-2.mjs` |
| verify:phase7e-module-backend-standard | `node scripts/verify-phase7e-module-backend-standard.mjs` |
| verify:phase7e-module-backend-discovery | `node scripts/verify-phase7e-module-backend-discovery.mjs` |
| verify:phase7e-module-backend-auth | `node scripts/verify-phase7e-module-backend-auth.mjs` |
| verify:phase7e-module-backend-gateway | `node scripts/verify-phase7e-module-backend-gateway.mjs` |
| verify:phase7e-module-backend-events | `node scripts/verify-phase7e-module-backend-events.mjs` |
| verify:phase7e-module-backend-webhooks | `node scripts/verify-phase7e-module-backend-webhooks.mjs` |
| verify:phase7e-module-backend-health | `node scripts/verify-phase7e-module-backend-health.mjs` |
| verify:phase7e-module-backend-security | `node scripts/verify-phase7e-module-backend-security.mjs` |
| verify:phase7e-module-backend-conformance | `node scripts/verify-phase7e-module-backend-conformance.mjs` |
| verify:phase7e-module-backend-runtime | `node scripts/verify-phase7e-module-backend-runtime.mjs` |
| verify:phase7e-ai-platform-foundation | `node scripts/verify-phase7e-ai-platform-foundation.mjs` |
| verify:phase7e-ai-provider-registry | `node scripts/verify-phase7e-ai-provider-registry.mjs` |
| verify:phase7e-ai-provider-credentials | `node scripts/verify-phase7e-ai-provider-credentials.mjs` |
| verify:phase7e-ai-routing | `node scripts/verify-phase7e-ai-routing.mjs` |
| verify:phase7e-ai-streaming | `node scripts/verify-phase7e-ai-streaming.mjs` |
| verify:phase7e-ai-structured-output | `node scripts/verify-phase7e-ai-structured-output.mjs` |
| verify:phase7e-ai-usage-ledger | `node scripts/verify-phase7e-ai-usage-ledger.mjs` |
| verify:phase7e-ai-quotas | `node scripts/verify-phase7e-ai-quotas.mjs` |
| verify:phase7e-ai-tools | `node scripts/verify-phase7e-ai-tools.mjs` |
| verify:phase7e-ai-provider-health | `node scripts/verify-phase7e-ai-provider-health.mjs` |
| verify:phase7e-ai-security | `node scripts/verify-phase7e-ai-security.mjs` |
| verify:phase7e-ai-provider-runtime | `node scripts/verify-phase7e-ai-provider-runtime.mjs` |
| verify:phase7e-ai-product-actions | `node scripts/verify-phase7e-ai-product-actions.mjs` |
| verify:phase7e-ai-context-boundaries | `node scripts/verify-phase7e-ai-context-boundaries.mjs` |
| verify:phase7e-ai-product-streaming | `node scripts/verify-phase7e-ai-product-streaming.mjs` |
| verify:phase7e-ai-result-application | `node scripts/verify-phase7e-ai-result-application.mjs` |
| verify:phase7e-ai-product-security | `node scripts/verify-phase7e-ai-product-security.mjs` |
| verify:phase7e-vault-notes-ai-standard | `node scripts/verify-phase7e-vault-notes-ai-standard.mjs` |
| verify:phase7e-vault-notes-ai-integration | `node scripts/verify-phase7e-vault-notes-ai-integration.mjs` |
| verify:phase7e-ai-product-integration | `node scripts/verify-phase7e-ai-product-integration.mjs` |
| verify:phase7e-real-auth | `node scripts/verify-phase7e-real-auth.mjs` |
| verify:phase7e-no-product-mocks | `node scripts/verify-phase7e-no-product-mocks.mjs` |
| verify:phase7e-vault-notes-standard | `node scripts/verify-phase7e-vault-notes-standard.mjs` |
| verify:phase7e-vault-notes-data-integrity | `node scripts/verify-phase7e-vault-notes-data-integrity.mjs` |
| verify:phase7e-vault-notes-lifecycle | `node scripts/verify-phase7e-vault-notes-lifecycle.mjs` |
| verify:phase7e-vault-notes-search | `node scripts/verify-phase7e-vault-notes-search.mjs` |
| verify:phase7e-vault-notes-security | `node scripts/verify-phase7e-vault-notes-security.mjs` |
| verify:phase7e-vault-notes-host | `node scripts/verify-phase7e-vault-notes-host.mjs` |
| verify:phase7e-vault-notes-release | `node scripts/verify-phase7e-vault-notes-release.mjs` |
| verify:phase7e-vault-notes | `node scripts/verify-phase7e-vault-notes.mjs` |
| verify:phase7e-web-production-cutover | `node scripts/verify-phase7e-web-production-cutover.mjs` |
| verify:phase7h-mail | `node scripts/verify-phase7h-mail.mjs` |
| verify:phase7h-registration | `node scripts/verify-phase7h-registration.mjs` |
| verify:phase7h-api-contract-parity | `node scripts/verify-phase7h-api-contract-parity.mjs` |
| verify:phase7i-live-api-parity | `node scripts/verify-phase7i-live-api-parity.mjs` |
| verify:phase7i-canonical-source | `node scripts/verify-phase7i-canonical-source.mjs` |
| verify:phase7i-mail-dns | `node scripts/verify-phase7i-mail-dns.mjs` |
| verify:phase7i-mail-production | `node scripts/verify-phase7i-mail-production.mjs` |
| verify:phase7i-mac-native | `node scripts/verify-phase7i-mac-native.mjs` |
| verify:phase7i-mac-ui-boundary | `node scripts/verify-phase7i-mac-ui-boundary.mjs` |
| verify:phase7i-mac-expo-ui | `node scripts/verify-phase7i-mac-expo-ui.mjs` |
| verify:phase7j | `node scripts/verify-phase7j.mjs` |
| verify:phase7j-mac | `node scripts/verify-phase7j-mac.mjs` |
| verify:phase7j-b | `node scripts/verify-phase7j-b.mjs` |
| verify:phase6-frontend | `node scripts/verify-phase6-atproto-frontend.mjs` |
| verify:phase6-frontend-boundary | `node scripts/verify-phase6-frontend-boundary.mjs` |
| verify:associated-domains | `node scripts/verify-associated-domains.mjs` |
| verify:associated-domains:public | `node scripts/verify-associated-domains.mjs --public` |
| verify:phase7i-f5 | `node scripts/verify-phase7i-f5-auth-foundation.mjs phase7i-f5` |
| verify:auth-password | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-password` |
| verify:auth-email-otp | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-email-otp` |
| verify:auth-totp | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-totp` |
| verify:auth-passkeys | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-passkeys` |
| verify:auth-recovery | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-recovery` |
| verify:auth-sessions | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-sessions` |
| verify:auth-step-up | `node scripts/verify-phase7i-f5-auth-foundation.mjs auth-step-up` |
| verify:transactional-mail | `node scripts/verify-phase7i-f5-auth-foundation.mjs transactional-mail` |
| verify:mail-identity | `node scripts/verify-phase7i-f5-auth-foundation.mjs mail-identity` |
| verify:mail-provisioner | `node scripts/verify-phase7i-f5-auth-foundation.mjs mail-provisioner` |
| verify:social | `node scripts/verify-phase7i-f5-auth-foundation.mjs social` |
| verify:stories | `node scripts/verify-phase7i-f5-auth-foundation.mjs stories` |
| verify:marketplace | `node scripts/verify-phase7i-f5-auth-foundation.mjs marketplace` |
| verify:live-web-release | `node scripts/verify-phase7i-f5-auth-foundation.mjs live-web-release` |
| verify:mainline | `node scripts/verify-phase7i-f5-auth-foundation.mjs mainline` |
| verify:shell-ui-v1 | `node scripts/shell-ui-v1-presentation.test.mjs && node scripts/shell-ui-v1-catalogue-state.test.mjs` |
| verify:shell-ui-v2 | `node scripts/verify-shell-ui-v2.mjs && pnpm --filter @modula/greenfield-api exec tsx --tsconfig ../../tsconfig.json ../../scripts/test-modula-icon-registry.ts` |
| verify:phase7m-b8 | `node scripts/verify-phase7m-b8.mjs` |
| verify:phase7m-b9 | `node scripts/verify-phase7m-b9.mjs` |
| verify:phase7m-b10 | `node scripts/verify-phase7m-b10.mjs` |
| verify:phase7n-a | `node scripts/verify-phase7n-a.mjs` |
| verify:pvp-ui-1 | `node scripts/verify-pvp-ui-1.mjs` |
| verify:pvp-ui-1r | `node scripts/verify-pvp-ui-1r.mjs` |
| verify:extension-contracts | `node scripts/verify-pvp-platform-2.mjs contracts` |
| verify:extension-manifest | `node scripts/verify-pvp-platform-2.mjs manifest` |
| verify:extension-points | `node scripts/verify-pvp-platform-2.mjs points` |
| verify:extension-dependency-graph | `node scripts/verify-pvp-platform-2.mjs graph` |
| verify:extension-lifecycle | `node scripts/verify-pvp-platform-2.mjs lifecycle` |
| verify:extension-capabilities | `node scripts/verify-pvp-platform-2.mjs capabilities` |
| verify:extension-contributions | `node scripts/verify-pvp-platform-2.mjs contributions` |
| verify:extension-isolation | `node scripts/verify-pvp-platform-2.mjs isolation` |
| verify:extension-events | `node scripts/verify-pvp-platform-2.mjs events` |
| verify:extension-jobs | `node scripts/verify-pvp-platform-2.mjs jobs` |
| verify:extension-service-fabric | `node scripts/verify-pvp-platform-2.mjs service-fabric` |
| verify:extension-provenance | `node scripts/verify-pvp-platform-2.mjs provenance` |
| verify:extension-security | `node scripts/verify-pvp-platform-2.mjs security` |
| verify:vault-notes-reference | `node scripts/verify-pvp-platform-2.mjs vault-notes` |
| verify:vault-ai-reference | `node scripts/verify-pvp-platform-2.mjs vault-ai` |
| verify:vault-voice-reference | `node scripts/verify-pvp-platform-2.mjs vault-voice` |
| verify:extension-cross-account-isolation | `node scripts/verify-pvp-platform-2.mjs cross-account` |
| verify:pvp-platform-2 | `node scripts/verify-pvp-platform-2.mjs all` |
| verify:greenfield-backend-v1:data-ledger | `node scripts/verify-greenfield-backend-v1-data-ledger.mjs` |
| verify:greenfield-backend-v1:service-fabric | `node scripts/verify-greenfield-backend-v1-service-fabric.mjs` |
| verify:greenfield-backend-v1:secret-fabric | `node scripts/verify-greenfield-backend-v1-secret-fabric.mjs` |
| verify:greenfield-backend-v1:ai-engine | `node scripts/verify-greenfield-backend-v1-ai-engine.mjs` |
| verify:greenfield-backend-v1:event-job-fabric | `node scripts/verify-greenfield-backend-v1-event-job-fabric.mjs` |
| verify:greenfield-backend-v1:engine-fabric | `node scripts/verify-greenfield-backend-v1-engine-fabric.mjs` |
| verify:greenfield-backend-v1:auth | `node scripts/verify-greenfield-backend-v1-auth.mjs` |
| verify:greenfield-backend-v1:social | `node scripts/verify-greenfield-backend-v1-social.mjs` |
| verify:greenfield-backend-v1:developer | `node scripts/verify-greenfield-backend-v1-developer.mjs` |
| verify:greenfield-backend-v1:build-release | `node scripts/verify-greenfield-backend-v1-build-release.mjs` |
| verify:greenfield-backend-v1:entitlements | `node scripts/verify-greenfield-backend-v1-entitlements.mjs` |
| verify:greenfield-backend-v1:account-data | `node scripts/verify-greenfield-backend-v1-account-data.mjs` |
| verify:greenfield-backend-v1:recovery | `node scripts/verify-greenfield-backend-v1-recovery.mjs` |
| verify:greenfield-backend-v1:security | `node scripts/verify-greenfield-backend-v1-security.mjs` |
| verify:greenfield-backend-v1:reference-products | `node scripts/verify-greenfield-backend-v1-reference-products.mjs` |
| verify:greenfield-backend-v1 | `node scripts/verify-greenfield-backend-v1.mjs` |
| verify:greenfield-mps-v1 | `node scripts/verify-greenfield-mps-v1.mjs` |
| verify:product-frontend-v1 | `node scripts/verify-product-frontend-v1.mjs` |
| verify:reference-tasks-zero-core | `node scripts/verify-reference-tasks-zero-core.mjs` |
| verify:vault-products | `node scripts/verify-vault-mps-releases.mjs` |
| verify:platform-foundation-v1 | `node scripts/verify-platform-foundation-v1.mjs` |
| verify:ui-system-v1 | `node scripts/verify-ui-system-v1.mjs` |
| verify:web-ui-adapter-v1 | `node scripts/verify-web-ui-adapter-v1.mjs` |
| verify:web-ui-adapter-v1:browser | `playwright test --config playwright.web-ui-adapter.config.ts` |
| verify:konsta-web-presentation | `node scripts/verify-konsta-web-presentation.mjs` |
| verify:konsta-web-presentation:browser | `playwright test --config playwright.konsta-web-presentation.config.ts` |

