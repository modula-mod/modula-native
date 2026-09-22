# Nodus architecture

Nodus is Modula's compact, general-purpose local language-model family. It answers ordinary questions offline, is deliberately strong on Modula, proposes structured actions, and marks answers that need current evidence. Its provider identity is `modula.nodus`; execution is local after an artifact has been installed and verified.

Nodus is not a command parser or an offline FAQ. Its retained general domains include science, history, geography, technology, basic mathematics and computing, writing, summarization, explanation, classification, extraction, and instruction following. Fine-tuning therefore includes substantial general replay data, and promotion fails when a category regresses by more than five percentage points without review.

## N4X model status

N4X integrates architecture only. There is **no accepted Nodus model** and the provider must report `modelNotInstalled` (or an equivalent unavailable state) until a separately approved artifact is installed. The R2 adapter remains an external experimental artifact and is not committed, bundled, selected by default, or promoted.

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

The developer installer accepts a pinned directory artifact, validates `nodus-manifest.json`, verifies every declared SHA-256 before loading, stages installation atomically, and retains the previous accepted artifact for rollback. Model weights, caches, adapters, and temporary checkpoints never enter Git.

`localOnly` selection cannot fall through to a remote provider. Nodus does not call Greenfield, a VPS, Apple Foundation Models, or an external model for generation. Structured action output remains a proposal: Modula validates, authorizes, and executes it.

## Separation of responsibilities

- Nodus is a language model and answer system. It may later power parts of GAIA, but Nodus is not GAIA.
- GAIA plans and operates governed missions.
- AKI is a decision and evidence fabric. Nodus is not AKI and cannot label its own answer as truth.
- The Governor remains the authorization boundary. Nodus output never grants authority.

For current-data questions Nodus can provide stable background, but it sets freshness to `current_data_required`, lowers effective confidence, and recommends verification. Native creates a persisted verification-mission draft; it does not perform arbitrary web requests. Future Greenfield work can execute that contract through GAIA and AKI.

Verification never grants training consent. Reconciliation may produce a learning candidate, but it remains ineligible or pending review until privacy eligibility, explicit global-training consent, and a separate human review all pass. Answers and verification results never trigger automatic training.

## Training recovery hypothesis

The failed experiment used 126 examples: 36 Modula, 2 structured-action, 4 confidence, 6 freshness, 2 privacy, and 76 general examples. That is too small to expect reliable Modula specialization and calibrated confidence from a 1.7B model. NODUS-01B should test a substantially larger, curated and synthetic corpus with correction examples, hard negatives, structured intents, privacy, freshness, abstention, verification, and fake-capability cases. Dataset size and LoRA choices remain experimental; N4X performs no training, quantization, or promotion.

## Future boundary

NODUS-01 intentionally does not implement full retrieval or unrestricted research. A future runtime may combine Nodus weights with downloaded Knowledge Packs and local retrieval. GAI-02 can execute current-evidence missions; NODUS-02 can add Knowledge Pack and verification sync without redesigning the native contracts introduced here.
