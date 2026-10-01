# Module authoring contract

This page is for people writing a Modula module (Vault Notes today, a CRM tomorrow).
It covers what a module declares, what it can call, and which UI building blocks it
gets. Runtime internals are in [module-runtime.md](module-runtime.md), and the bridge
wire format is in [host-bridge.md](host-bridge.md).

## 1. Manifest

Manifests live in `runtime/src/registry/manifests.json`. The file ships both in the JS
bundle and as an app resource that Swift reads (`ModuleManifest` in
`ios/Modula/ModuleRuntime/ModuleSession.swift`). It is typed by `ModuleManifest` in
`packages/module-contracts/src/index.ts`.

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Reverse-DNS id, `^[a-z][a-z0-9.-]+$`. It must match the server registry id. |
| `name`, `version` | yes | Display name and semver of the bundled code. |
| `runtime` | yes | Always `react-native`. |
| `entry` | yes | Key in the `entries` map in `runtime/src/registry/ModuleRegistry.ts`. |
| `permissions` | yes | The host actions the module may call (see §2). Anything not listed here is rejected natively. |
| `collections` | for data | Record collections the module owns, e.g. `["note"]` or `["contact","deal"]`. Requests for any other collection are rejected. |
| `minHostVersion`, `minBridgeVersion` | yes | `validateManifest` refuses to mount the module when these are not met. |
| `presentation` | no | Store artwork and copy (`subtitle`, `tint`, `icon`, `cover`, `screenshots`). See §5. |

Unknown fields are ignored, so new fields can be added in a backwards-compatible way.

## 2. Host actions (`host.request`)

The module's only capability surface is `host.request(action, params)` from
`@modula/module-sdk`. The native side checks every action against the manifest.

- `navigation.open {route: 'profile'|..., ...}`: opens an allow-listed native route.
- `haptics.selection`.
- `diagnostics.ready`, `diagnostics.dataReady`, `diagnostics.fail`: lifecycle signals that the host uses for loading and crash UI.
- `backend.records.list {collection, cursor?, limit?, query?, sort?: 'updatedAt'|'createdAt'|'title', direction?: 'asc'|'desc'}`
- `backend.records.get | create | update | delete {collection, id?, data?}`

Records are scoped to the signed-in user, the installation and the collection by the
server. Modules never see tokens or URLs. Parameters are strictly validated and
percent-encoded natively (`ModuleBackendRequest`), and unknown values are rejected
rather than passed through.

The module receives a `ModuleContext` (`moduleID`, `userID`, and `environment`:
appearance, accent, density, font, contrast, motion). It also receives the lifecycle
(`active`, `inactive`, `background`).

## 3. UI building blocks

Everything is themed from `moduleTheme(context.environment)` (`runtime/src/ui/theme.ts`),
so modules automatically follow light/dark/OLED, accent, density, font, higher contrast
and reduce-motion settings. Don't hard-code colours.

| Layer | File | Use it for |
| --- | --- | --- |
| Primitives | `ui/components.tsx` | `ThemedText`, `ModuleButton`, `ModuleCard`, `LoadingRow`, `ModuleFallback` (error/empty with action), `DocumentBlocks`. |
| Kit | `ui/kit.tsx` | `Badge`, `SearchField`, `SegmentedControl`, `RecordRow`, `SkeletonRows`, `InlineNotice`, `ToggleRow`, `Toolbar`. |
| Records | `ui/records.tsx` | `Section`, `DetailHeader`, `KeyValueList`, `DataTable`, `FormField`, `SpecForm`. |
| Rich text | `ui/blocks.ts` + `DocumentBlocks` | Notes-style documents (heading, paragraph, list, quote, code, checklist, divider). They are normalised and capped at `MAX_RENDERED_BLOCKS`. |
| Declarative | `ui/nodes.ts` + `ui/NodeRenderer.tsx` | Whole screens described as data (below). |
| Hooks | `ui/hooks.ts` | `useDebounced` (search), `useAlive` (ignore late async results after unmount). |

### Declarative nodes

`NodeRenderer({theme, nodes, actions})` renders a closed vocabulary. The node types are
`stack`, `section`, `heading`, `text`, `badge`, `notice`, `button`, `keyValue`, `list`,
`table`, `form`, `empty`, and `unsupported`. Interactive nodes reference an action **by
name** (`{action: 'openDeal', payload: {id}}`). Only names registered in `actions` work,
and payloads are scalar.

`normalizeNodes` is the trust boundary, so screens can safely come from server data:
- It never throws.
- It caps size and depth (`NODE_LIMITS`).
- It drops unknown properties.
- It renders unknown node types as a visible "Unsupported: x" placeholder instead of crashing.

The other built-in behaviours:
- **Forms** are validated (`validateForm`) before the action fires.
- **Tables** size their columns from content (`columnWidths`) and scroll horizontally.
- **Accessibility:** each table or list row is one accessible element ("Deal: Annual renewal, Stage: Proposal, …"). Headings use the header role, and form inputs carry labels.
- **Performance:** long lists in custom screens should use `FlatList` with `RecordRow`, as Vault does. The node renderer is memoised and bounded.

The reference screen is `runtime/src/modules/gallery/crmSample.ts`. Runtime Diagnostic →
"Component gallery" renders it on device.

## 4. Building a CRM module

1. **Manifest:** `id: "digital.modula.crm"`, `entry: "crm"`, `collections: ["contact","deal","activity"]`, plus the `backend.records.*`, `navigation.open` and `haptics.selection` permissions and `diagnostics.*`.
2. **Code:** add `runtime/src/modules/crm/`:
   - `model.ts`: pure mapping from record rows to view models, plus tests in `runtime/tests/`.
   - `Crm.tsx`: a small in-module router (list → detail → form), like Vault's `screen` state.
   - Register `crm: Crm` in `ModuleRegistry.ts`.
3. **Screens:**
   - Lists: `SearchField` + `SegmentedControl` + `FlatList` of `RecordRow`, with `SkeletonRows`, an empty `ModuleFallback` and a load-more `InlineNotice`. Pass `query`, `sort` and `direction` to `backend.records.list`, and page with `cursor`.
   - Detail: `DetailHeader` + `KeyValueList` + `DataTable` of related deals, or the same thing as `NodeRenderer` nodes.
   - Forms: `SpecForm` with `FieldSpec[]`. Save with `backend.records.create`/`update`, and keep the record schema in `data`.
4. **Server:** register the module and its collections in the greenfield registry, along with the release (version, permissions with reasons, release notes, size) and marketplace artwork. Without that it can't be installed. The client doesn't need native changes for a new module beyond the bundled code.
5. **Tests:** pure model tests (`npm test`), `npm run typecheck`, `python3 scripts/verify-boundaries.py`, and a UI test that opens it through Product Hub.

## 5. Store presentation

Product Hub builds the detail page from the server registry
(`GET /v1/registry/modules/:id`). That covers description, version, publisher,
permissions, rating, installs, release notes, size and previews. It merges in the
optional manifest `presentation` block for artwork:

```json
"presentation": {
  "subtitle": "Private notes, beautifully kept",
  "tint": "#1F8A84",
  "icon": "asset:ModuleArt/VaultNotesIcon",
  "cover": "asset:ModuleArt/VaultNotesCover",
  "screenshots": [{"source": "asset:ModuleArt/VaultNotesShot1", "alt": "Notes list"}]
}
```

- `asset:` sources resolve to images bundled in the app's asset catalogue.
- `https:` sources load remotely.
- Server `marketplace.previews` take precedence over manifest screenshots.
- Missing artwork falls back to a generated, tinted placeholder.
