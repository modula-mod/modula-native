# Universal ModuleHost

Status: implemented on `phase/module-ecosystem-01`.

## Execution model

The host is **hybrid, contract-first**:

1. **Declarative Product UI** (`application/vnd.modula.frontend+json`) is the generic path. Verified JSON is parsed as data and rendered by a host-owned SwiftUI renderer. It is never evaluated as JavaScript.
2. **Bundled React Native** remains for modules already compiled into `main.jsbundle` (`modula.runtime-diagnostic` and the Vault 1.7 fallback).
3. **Downloaded JavaScript is not authorized.** Replacing `main.jsbundle` with an arbitrary file is not a multi-module runtime. A future downloaded-JS profile needs a separate executor review and Apple Guideline 4.7 / 4.7.2 permission.

Host versions advertised to manifests:

- `0.1.0` — bundled React Native contract
- `1.0.0` — Product UI / MPS host (`ModulaHost.version`)

## Launch pipeline

Resolve descriptor → trust + compatibility + permission review → download required artifacts → SHA-256 equality → inventory validation → write `STAGED` → activate → `ACTIVE` with `PREVIOUS_GOOD` retained → cache-first open.

A defective module cannot own shell navigation. Shared Hermes is still one process for bundled RN modules; that residual crash boundary is documented, not claimed as a sandbox.

## What this is not

There is no `if moduleId == "digital.modula.vault-notes"` renderer. Vault Notes 2.0 and generated modules use the same `ProductUIHostView`.

Inter-module actions go through `ModuleActionBroker`: source and target installations, exact-release permission review, target-owned mutation, idempotent retry. Vault never writes the Tasks collection directly.

Developer Studio inside the app is Product Hub → Developer Studio, the sidebar Developer item, and `/developer/studio`. It generates `modula.product.json` and `frontend/frontend.manifest.json`, edits the home copy and record fields, previews with the native Product UI renderer, then installs into the local module cache. Web Studio remains available at `http://127.0.0.1:8787`.

Live GreenField `d536d514` accepted the in-app basic, records, dashboard, document, and intelligence products and frontends, including SHA-256 equality. The deployed frontend capability grammar is `ui|audio|camera|media|file|share|map|game`. `intelligence.local` stays a host-broker failure, not a publishable capability id.
