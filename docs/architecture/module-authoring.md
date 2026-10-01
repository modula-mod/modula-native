# Native host conformance (modules)

This repository is a **host**, not a module standard. It does not define how modules
are authored, declared, presented in the store, or rendered. The source of truth is the
[modula-product-standard](https://github.com/modula-mod/modula-product-standard)
repository:

- `MPS-1.0.md` — the product contract (identity, assets, frontend, backend, storage,
  permissions, privacy, release, provenance).
- `docs/frontend/*` — the `modula.frontend.1.0` artifact: routes, views, components,
  actions, data binding, theming, accessibility, assets and native capabilities.
- `docs/provenance.md` — how a release is verified.

## What the iOS host must do

- Accept modules only through the verified chain: GitHub release → Modula Registry →
  Product Hub → declarative runtime. `modula.product.json` is the canonical declaration;
  the host never invents manifest fields or reads store copy/artwork from bundled code.
- Load store artwork (icon, cover, screenshots) only from registry URLs. When a source
  is missing, show a neutral placeholder (initial or SF Symbol), never bundled
  module-specific art.
- Render module UI with the generic declarative host implementing the standard host
  components for `modula.frontend.1.0`. The host does not define its own UI node
  vocabulary. Reusable pieces in `runtime/src/ui` (theme, hooks, `kit.tsx`,
  `records.tsx`, accessible components) exist to back those standard components.
- Keep the shell boundary: the native shell owns navigation, presentation, appearance,
  lifecycle, verification and failure isolation; the module owns its routes, views,
  actions and bindings (see `MPS-1.0.md`, "Frontend boundary").

## Temporary exceptions

- The hand-built Vault Notes surface (`runtime/src/modules/vault/*`) is a **temporary
  fallback** until the generic declarative host renders the verified Vault Notes 1.7.0
  frontend. Do not extend it; remove it once the declarative path is in place.
- `runtime/src/registry/manifests.json` is the existing bundled runtime registry for
  development modules. It is not an MPS declaration and must not grow new schema.

When this note and the standard disagree, the standard wins; update this note.
