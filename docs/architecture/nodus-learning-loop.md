# Nodus governed learning loop

Nodus never edits its production weights. Self-improvement means governed dataset evolution followed by offline training, evaluation, approval, and an explicit artifact promotion.

The pipeline is:

`capture → verify → classify → sanitize → deduplicate → review → approve → dataset revision → train → evaluate → promote or reject`

## Verification missions

When confidence or freshness indicates a need, native persists a `VerificationMissionDraft` containing the question, original answer, Nodus version, confidence, freshness, reason, timestamps, and queue state. Offline drafts survive app termination. Connectivity may transition them from `queued_offline` to `ready_to_sync`; NODUS-01 does not bypass Greenfield governance with native web access.

The verified-result ingestion contract accepts confirmed, corrected, partially correct, unverifiable, or conflicting-evidence outcomes and retains evidence sources plus Greenfield/AKI provenance. “Verified” means checked against current evidence, not guaranteed truth. Results must pass schema, mission, question, confidence, evidence, signer, and P-256 signature checks before reconciliation.

## Reconciliation and candidates

The native pipeline compares the verified answer with the original and records confirmed, corrected, partially correct, stale, unverifiable, or conflicting-evidence. Only a corrective eligible outcome can create a learning candidate. New candidates default to pending review only when consent and privacy policy permit, otherwise ineligible; neither state is approved.

Verification is not training consent. Personal or private corrections default to globally ineligible. An unverified Nodus answer, a low-confidence guess, invalid provenance, a malicious payload, or a user request to verify cannot enter the approved corpus. Confidence locates uncertainty; evidence establishes a correction.

Each approved candidate preserves the original answer and confidence, verified answer, verification ID, privacy class, and approval state. Dataset revisions record their parent, additions/removals, candidate IDs, sources, hashes, and approval. Kaizen may later group failures or propose examples, mixture changes, calibration work, and new evaluations; it cannot publish a model.

The deterministic NODUS-01 fixture proves the loop from low-confidence answer through a persisted mission, signed correction, reconciliation, pending candidate, explicit test approval, and a hashed dataset revision. Production approval and model promotion remain separate operations.

NODUS-01B adds deterministic confirmed, corrected, stale, and partial correction examples without ingesting private verification history. They use the same provenance and split controls as the corpus. Verification queue and reconciliation tests remain local fixtures: no mission is submitted over the network, and no candidate is automatically approved or trained. Because no model passed promotion, runtime and learning-loop defaults do not change.

## Developer evaluation evidence

NODUS-01D adds local ratings for experimental answers: `good`, `wrong`, `unsure`, `outdated`, and `hallucinated`. Each record binds the prompt, response, model ID, lifecycle stage, externally derived confidence/freshness, timestamp, and optional note. Records persist in local application support and can be explicitly exported as JSONL; they are not uploaded or sent to analytics.

A rating is evaluation evidence, not training consent. It can inform a future reviewed dataset proposal, but it never changes weights, creates an approved learning candidate, or bypasses verification, privacy review, dataset versioning, retraining, evaluation, and promotion.
