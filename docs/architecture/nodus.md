# Nodus architecture

Nodus is Modula's compact, general-purpose local language-model family. It answers ordinary questions offline, is deliberately strong on Modula, proposes structured actions, and marks answers that need current evidence. Its provider identity is `modula.nodus`; execution is local after an artifact has been installed and verified.

Nodus is not a command parser or an offline FAQ. Its retained general domains include science, history, geography, technology, basic mathematics and computing, writing, summarization, explanation, classification, extraction, and instruction following. Fine-tuning therefore includes substantial general replay data, and promotion fails when a category regresses by more than five percentage points without review.

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

## Future boundary

NODUS-01 intentionally does not implement full retrieval or unrestricted research. A future runtime may combine Nodus weights with downloaded Knowledge Packs and local retrieval. GAI-02 can execute current-evidence missions; NODUS-02 can add Knowledge Pack and verification sync without redesigning the native contracts introduced here.
