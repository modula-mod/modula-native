# Local Intelligence (Native)

Native Modula owns on-device intelligence. Greenfield Mission 01 defined shared **protocol semantics**; Mission 02 established the Swift foundation, and Mission 03 adds Apple Foundation Models as one local provider.

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
apple.system       modula.test.local
LOCAL              DEBUG fixture
  │
FoundationModels
  │
SystemLanguageModel.default
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

## Routing

Deterministic; no cost/quality scoring. Among eligible candidates, the first provider in **registry registration order** wins.

| Privacy | Policy |
| --- | --- |
| `localOnly` | Available local only; else fail closed |
| `preferLocal` | Available local first; else remote only if `remoteIntelligencePermitted` |
| `allowRemote` | Still prefer available local; else available remote |

The application registers `apple.system` first. DEBUG builds also register `modula.test.local` for its explicit diagnostic action; Release builds do not register the fixture. Apple failure or unavailability is never presented as a fixture success.

## Providers

| Field | Value |
| --- | --- |
| ID | `modula.test.local` |
| Kind | local |
| Role | Deterministic fixture — **not** a real model |
| Network | none |
| Weights | none |

### Apple System Provider

| Field | Value |
| --- | --- |
| ID | `apple.system` |
| Kind | local |
| Model | `SystemLanguageModel.default` |
| OS boundary | iOS 26.0 API, runtime-gated; app minimum remains iOS 18.0 |
| Capabilities | generate, rewrite, summarize, classify, extract, intent |
| Sessions | one fresh `LanguageModelSession` per request |
| Network | none |

The framework import is compile-gated with `canImport(FoundationModels)`. iOS versions before 26 return `unsupportedOS`; they do not instantiate or link-call model APIs. Apple runtime availability maps as follows:

| Apple | Modula |
| --- | --- |
| available | available |
| device not eligible | unsupported device |
| Apple Intelligence not enabled | disabled |
| model not ready | model not installed |
| unknown future reason | temporarily unavailable |

`modelNotReady` can mean the system is downloading or preparing assets rather than that they are permanently absent. The existing `modelNotInstalled` state is the closest provider-neutral Mission 02 state, and diagnostics label it “Model not ready.”

Instructions contain only short, trusted capability policy. User text remains in the prompt. The provider explicitly adapts supported `IntelligenceValue` shapes and never uses `String(describing:)` to serialize arbitrary values.

Classification proves guided generation using a private `@Generable` Swift type, then maps the result back to `IntelligenceValue`. No Foundation Models type crosses the Modula façade.

Foundation Models is a provider, not the intelligence architecture:

```swift
struct AppleSystemIntelligenceProvider: IntelligenceProvider { ... }
```

without rewriting:

- `IntelligenceRequest` / `IntelligencePrivacy` / `IntelligenceResponse`
- `IntelligenceRouter`
- `IntelligenceProviderRegistry`
- `IntelligenceToolRegistry`
- `ModulaIntelligence` façade

This leaves the Mission 04 slot independent:

```text
ProviderRegistry
  ├── apple.system
  └── modula.local.nano   (future)
```

## Runtime and error boundaries

- A request creates one session, produces one response, and releases the session. There is no persistent transcript, conversation memory, or shared-session race.
- Apple context limits map to `contextLimitExceeded`; unsupported language and safety refusal have typed Modula errors; cancellation maps to `requestCancelled`.
- The iOS 27 Foundation Models error surface and the legacy iOS 26 generation errors are both mapped.
- Prompt, input, generated output, and tool arguments are never written to diagnostics logs.
- Tool calling is unsupported. The provider cannot execute settings, navigation, files, notes, or other native actions.
- Private Cloud Compute is not used and is not a fallback.

## Network independence

`apple.system` contains no `URLSession`, HTTP URL, API key, VPS, Greenfield, GAIA, or AKI path. `localOnly` remains fail-closed: if Apple is unavailable and only a remote provider is available, remote `execute()` is never called.

## Explicitly out of scope

- CoreML weights / llama.cpp / MLX / remote LLM APIs
- Token streaming, model downloads, convenience `summarize()` feature APIs
- Hosted-module intelligence bridge
- Tool *execution* into native actions (validation only)

## Diagnostics

`ModulaLog.intelligence` records structural metadata only (request ID, capability, provider ID, execution kind, duration, status, error code). Prompt/input/output and tool argument content are not logged by default.
