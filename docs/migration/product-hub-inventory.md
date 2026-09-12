# Product Hub inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Evidence: `src/data/repositories/api/ApiModuleRepository.ts`, `src/features/modules/screens/ProductHubMarketplaceScreen.tsx`, `ModulePreScreen.tsx`, `ModuleManagementScreen.tsx`, `src/features/modules/components/product-detail/*`, `productHubCatalogueState.ts`.

Catalogue/details/publisher/version/permissions/compatibility/installability/ratings/releases and installed state come from Greenfield registry/modules APIs. Runtime supplies health and available views/settings. Immutable manifest supplies product identity, release metadata, screenshots and declarations. Search/category/tab/scroll state is local UI. `LOCAL_CATALOGUE` and local Map records exist only for explicit local mode; remote failures must not substitute them. `preserveAuthoritativeCatalogue` keeps catalogue available when installation enrichment fails. Product Hub is not the older seeded marketplace catalog under features/marketplace/data/catalog.ts.

Install preview shows permissions and compatibility before install; enable/disable/update/uninstall are authenticated operations. Data retention/export/delete choices exist on uninstall. Product metadata must not claim installed from bundle presence alone. N1 can list bundled launchers but must label that distinction and let Greenfield enforce actual eligibility. Native runtime manifest is not a replacement for server registry truth. Health errors, unavailable release and permission increases remain explicit states.

CARRY contracts/metadata/state meanings; NATIVE_REWRITE Product Hub; REFERENCE_ONLY current component geometry and seeded marketplace; RETIRE local fake records from production acceptance.

