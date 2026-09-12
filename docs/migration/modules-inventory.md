# Module architecture and Vault Notes

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

`src/features/modules/runtime/module-host.tsx` owns generic MPS rendering; `mps-frontend-adapter.ts` adapts immutable `modula.frontend.1.0` artifacts, resolves routes, maps action families and bindings. `ModuleHostScreen.tsx` supplies Expo Router and shell chrome. Backend `getProductFrontend` checks product/release/schema coherence. Contracts, validation and policies carry; Expo route/chrome/renderer implementation does not become native shell code.

`@modula/product-ui` is a TSX authoring DSL supplied by the separate product-standard repository. `defineFrontend`, `screen`, `route`, `action`, `useRecord`, `useRecords`, `useSettings`, `useForm` produce declarative bindings/artifacts; they are not automatically executable React hooks. Keep this optional high-level authoring concept. N1 also permits bespoke bundled RN UI; do not constrain all modules to form primitives.

Canonical Vault source: `modula-mod/modula-vault-notes@106b57d40a456e2812e9b3a6e9f3bb32fb15e11d`, version 1.7.0. `modula.product.json` is authoritative; older manifests are compatibility adapters. Expo canonical constants still say 1.2.0/c62f47a; do not mistake those historical constants for the current product release. Bundled RN adaptation needs its own host-compatibility declaration and provenance, not a rewrite of published releases.

| Layer | Evidence | Disposition |
|---|---|---|
| Identity/permissions/data schemas | modula.product.json, schemas/* | CARRY |
| Custom frontend actions/routes | frontend/index.tsx, components/NoteRow.tsx | MODULE_REUSE semantics; DSL not ordinary RN JSX |
| Document types/conversion/validation | src/types.ts, src/document/index.ts | MODULE_REUSE; isolate Node crypto hash before bundling |
| In-memory VaultNotesStore | src/records/store.ts | REFERENCE_ONLY for business rules, not real-data adapter |
| Search/settings/export logic | src/search, src/settings, src/export | MODULE_REUSE where platform neutral; Node-specific code audited before use |
| Expo ModuleHost | src/features/modules/runtime | NATIVE_REWRITE host; REFERENCE_ONLY renderer |
| Backend engine/registry/contracts | packages/greenfield-module-*, services/greenfield-api/src/modules | CARRY contract, remote ownership |

Vault routes: /, /new (sheet), /note/:noteId, /note/:noteId/edit (sheet), /search, /favourites, /archived, /trash, /folders, /settings. New/edit flows are separate. Create defaults include structured document schema 1.0.0, tags[], pinned/favourite/archived false, dataSchemaVersion. Title max 240. Plain-text projection derives from document, never replaces rich content silently. Update carries expected revision. Delete confirms; restore and permanent delete are separate actions. Forms include folder/tag inputs. List supports query/filter/sort; errors/loading/empty/offline/permission/capability states are declared.

Frontend settings (archiveBeforeDelete/defaultEditor/confirmDestructiveActions) differ from src/settings model (default sort/view, autosave, retention, counts, search, export). This is an open contract discrepancy, not permission to invent working settings. N1 focuses CRUD and preserves document structure. Rich blocks that a limited editor cannot safely modify must be displayed without lossy conversion.

Platform-neutral: IDs, schema, action vocabulary, validation, data projections. React-specific: actual RN components introduced in N1. Expo-specific: old routing, fetch/storage/native adapters. Backend-specific: account record scopes, revisions, installation/permission checks. Bundled first-party modules share one JS runtime and are not an adversarial sandbox.

