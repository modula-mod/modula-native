# Local Intelligence (Native)

Native Modula owns on-device intelligence. Greenfield Mission 01 defined shared **protocol semantics**; this document describes the Swift foundation in `modula-native` (Local Intelligence Mission 02).

> There is no JavaScript or Expo bridge between Greenfield and native intelligence.

```text
Greenfield
@modula/intelligence-core
        │
        │ semantic specification only
        ▼
Native Swift equivalents (ModulaIntelligence)
```

## Ownership

```text
Modula Native Feature
        │
        ▼
ModulaIntelligenceService  (ModulaIntelligence actor)
        │
        ▼
IntelligenceRouter
        │
        ▼
ProviderRegistry
        │
  ┌─────┴──────────────────┐
  │                        │
Local providers        Remote providers
  │                        │
DeterministicLocal     (none in Mission 02)
Mission 03+: Apple     Future GAIA/AKI
```

## Location

```text
ios/Modula/Core/Intelligence/
```

Wired through `AppEnvironment.intelligence`. Developer diagnostics live at Settings → Developer → Local Intelligence (DEBUG only).

## Security invariant

> **AI proposes. Modula validates. Modula authorizes. Modula executes.**

The intelligence subsystem must never directly execute arbitrary Swift, shell commands, JavaScript, SQL, filesystem operations, HTTP calls, deep links, native selectors, or URLs because a model emitted them. Everything crosses an explicit capability / tool boundary.

## Privacy P1

For `privacy = localOnly`:

- Only providers with `executionKind == local` are eligible
- If none are available → typed failure (`noEligibleProvider` or `localProviderUnavailable`)
- Remote providers must never receive `execute()`
- No upload, remote preprocessing, silent privacy downgrade, or queued cloud execution

## Routing (Mission 02)

Deterministic; no cost/quality scoring. Among eligible candidates, the first provider in **registry registration order** wins.

| Privacy | Policy |
| --- | --- |
| `localOnly` | Available local only; else fail closed |
| `preferLocal` | Available local first; else remote only if `remoteIntelligencePermitted` |
| `allowRemote` | Still prefer available local; else available remote |

## Mission 02 provider

| Field | Value |
| --- | --- |
| ID | `modula.test.local` |
| Kind | local |
| Role | Deterministic fixture — **not** a real model |
| Network | none |
| Weights | none |

## Mission 03 boundary

Mission 03 should be able to add:

```swift
struct AppleSystemIntelligenceProvider: IntelligenceProvider { ... }
```

without rewriting:

- `IntelligenceRequest` / `IntelligencePrivacy` / `IntelligenceResponse`
- `IntelligenceRouter`
- `IntelligenceProviderRegistry`
- `IntelligenceToolRegistry`
- `ModulaIntelligence` façade

## Explicitly out of scope (Mission 02)

- FoundationModels / CoreML weights / llama.cpp / MLX / remote LLM APIs
- Token streaming, model downloads, convenience `summarize()` feature APIs
- Hosted-module intelligence bridge
- Tool *execution* into native actions (validation only)

## Diagnostics

`ModulaLog.intelligence` records structural metadata only (request ID, capability, provider ID, execution kind, duration, status, error code). Prompt/input/output and tool argument content are not logged by default.
