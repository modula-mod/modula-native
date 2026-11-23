# Nodus architecture

Nodus is Modula's compact, general-purpose local language-model family. It answers ordinary questions offline, is deliberately strong on Modula, proposes structured actions, and marks answers that need current evidence. Its provider identity is `modula.nodus`; execution is local after an artifact has been installed and verified.

Nodus is not a command parser or an offline FAQ. Its retained general domains include science, history, geography, technology, basic mathematics and computing, writing, summarization, explanation, classification, extraction, and instruction following. Fine-tuning therefore includes substantial general replay data, and promotion fails when a category regresses by more than five percentage points without review.

## NODUS-01D experimental runtime status

NODUS-01D makes the research-best NODUS-01C R7 step-1,200 checkpoint runnable for developer evaluation without promoting it. The developer-facing model is **Nodus R7 Experimental**. It is fused with pinned `Qwen/Qwen3-1.7B@70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`, quantized to 4-bit MLX, and remains `experimentalCandidate` with `shippingAllowed = false`.

Availability and trust are independent. A verified bundle can make `modula.nodus` available while its model stage remains experimental. No build configuration bundles the candidate by default (CORE-SIZE-01: it is ~930 MiB of weights and belongs in a downloadable package). With the explicit developer-only override `MODULA_INCLUDE_EXPERIMENTAL_NODUS=1` (or `MODULA_REQUIRE_EXPERIMENTAL_NODUS=1`), the build copies the candidate from `~/Library/Application Support/Modula/DeveloperModels/Nodus/R7/` only after checking the tracked `Tools/Nodus/manifests/nodus-r7-experimental.json` and every runtime file hash. Builds without a cache still succeed and report `modelNotInstalled`, unless `MODULA_REQUIRE_EXPERIMENTAL_NODUS=1` makes the artifact mandatory for acceptance.

The runtime discovers only app-bundled resources and never a user-specific build-machine path. It remains lazy: bundling does not load weights, and the first real request performs manifest verification and MLX loading. Developer Chat stays on the routed path `NodusChatView → NodusChatViewModel → ModulaIntelligence → IntelligenceRouter → modula.nodus → NodusIntelligenceProvider → MLX` with no fixture or remote fallback after a real-provider failure.

MLX does not support inference in the iOS Simulator. A simulator build may contain and discover the experimental bundle, but the provider reports `unsupportedDevice` before initializing MLX so the process does not hit MLX's documented Metal abort. Real native inference must be accepted on a physical Apple device; host-side MLX diagnostics remain useful for artifact integrity and output checks, but are not a substitute for device acceptance.

R7 is not an accepted release. It passed the abstention gate but failed general retention, Modula generalization, freshness, verification, authority, unsupported-capability, structured correctness, and hallucination gates. Those failures are preserved in the experimental manifest and remain visible policy, not waived promotion criteria.

## Earlier model status

N4X integrates architecture only. There is **no accepted Nodus model** and the provider must report `modelNotInstalled` (or an equivalent unavailable state) until a separately approved artifact is installed. The R2 adapter remains an external experimental artifact and is not committed, bundled, selected by default, or promoted.

NODUS-01B ran the required R3, R4, and R5 recovery experiments against the same pinned Qwen base. None passed the complete promotion scorecard. R5 step 1400 improved the backward-compatible Modula score from 0.4000 to 0.8000, but general accuracy fell to 0.9167, compatible calibrated ECE was 0.5175, freshness behavior was 0.6667, and abstention accuracy was 0.0. On the broader NODUS-01B suites it scored 0.6667 general and 0.3333 Modula, compared with base scores of 0.9000 and 0.2821. That broader Modula gain is only 0.0512, below the required 0.15.

The result is **NODUS-01B PARTIAL**. No checkpoint is an accepted candidate; no checkpoint was fused, quantized, installed, or named Nodus v0.1. `modula.nodus` therefore remains unavailable without a separately accepted artifact, and its normal repository state remains `modelNotInstalled`.

The recorded R2 promotion result is:

| Gate | Result |
| --- | --- |
| General retention | PASS |
| Modula improvement | FAIL |
| Confidence calibration | FAIL |
| Freshness | PASS |
| Abstention | PASS |

This is a rejected experiment, not “Nodus v0.1 accepted.” Its SHA-256 is `058c3be4fa7c79931f0878c0c1f8f18ae84fa4db9bfc6a5a63a9d4a42bdd6403` and its base revision is `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e` of `Qwen/Qwen3-1.7B`.

## Runtime boundary

`NodusIntelligenceProvider` implements the existing Modula intelligence contract. MLX Swift LM is hidden behind `NodusRuntime`; callers do not depend on MLX types. The runtime loads lazily, supports cancellation and unload, and is released on backgrounding or a memory warning. Availability distinguishes installed, downloading, unsupported, insufficient-memory, disabled, and temporarily unavailable states.

The accepted-model installer validates `nodus-manifest.json`, verifies every declared SHA-256 before loading, stages installation atomically, and retains the previous accepted artifact for rollback. The separate experimental path validates `nodus-r7-experimental.json`, including lifecycle and production-exclusion fields. Model weights, caches, adapters, and temporary checkpoints never enter Git.

`localOnly` selection cannot fall through to a remote provider. Nodus does not call Greenfield, a VPS, Apple Foundation Models, or an external model for generation. Structured action output remains a proposal: Modula validates, authorizes, and executes it.

## Separation of responsibilities

- Nodus is a language model and answer system. It may later power parts of GAIA, but Nodus is not GAIA.
- GAIA plans and operates governed missions.
- AKI is a decision and evidence fabric. Nodus is not AKI and cannot label its own answer as truth.
- The Governor remains the authorization boundary. Nodus output never grants authority.

For current-data questions Nodus can provide stable background, but it sets freshness to `current_data_required`, lowers effective confidence, and recommends verification. Native creates a persisted verification-mission draft; it does not perform arbitrary web requests. Future Greenfield work can execute that contract through GAIA and AKI.

Verification never grants training consent. Reconciliation may produce a learning candidate, but it remains ineligible or pending review until privacy eligibility, explicit global-training consent, and a separate human review all pass. Answers and verification results never trigger automatic training.

## Training recovery result

The failed NODUS-01 experiment used 126 examples: 36 Modula, 2 structured-action, 4 confidence, 6 freshness, 2 privacy, and 76 general examples. NODUS-01B replaced it with three reproducible 6,000-example controlled mixtures, complete provenance, exact/normalized/near duplicate removal, semantic-family splits, and held-out exclusions. The recovery established that corpus volume alone is insufficient: the model learned some legacy keyword-shaped Modula cases but did not generalize reliably to the broader architecture, module, capability, structured-intent, hallucination, and abstention suite. Exact results and checkpoint comparisons are recorded in `Tools/Nodus/reports/nodus-01b-training-report.md`.

## Future boundary

NODUS-01 intentionally does not implement full retrieval or unrestricted research. A future runtime may combine Nodus weights with downloaded Knowledge Packs and local retrieval. GAI-02 can execute current-evidence missions; NODUS-02 can add Knowledge Pack and verification sync without redesigning the native contracts introduced here.
