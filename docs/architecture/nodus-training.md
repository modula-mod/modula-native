# Nodus training

Nodus v0 is adapted from an open-weight foundation model; it is not pretrained from zero. The reproducible tooling boundary lives under `Tools/Nodus` and is isolated from Xcode dependencies. Exact Python, MLX, MLX-LM, tokenizer, and dataset versions are pinned in `pyproject.toml`; experiments are pinned in YAML.

## Candidate and license gate

NODUS-01 benchmarks Qwen3-1.7B and SmolLM2-1.7B-Instruct at exact upstream revisions before selection. `licenses/base-models.json` records publisher, license, commercial status, redistribution and derivative obligations, attribution, naming restrictions, and acceptable-use restrictions. Public Nodus branding never removes upstream provenance.

Initial adaptation uses LoRA on Apple silicon. A pilot run proves loss reporting, validation, adapter reload, and generation before the full experiment. Base and tuned variants receive the exact same held-out general, Modula, and freshness evaluations. The accepted mobile artifact is exported at 4-bit only after comparative evaluation; the manifest retains base revision, dataset revision, method, quantization, hashes, and evaluation revision.

## Corpus governance

Every source example has an ID, semantic group, source and revision, license, creation method, privacy class, eligibility state, timestamp, and computed content hash. The builder rejects:

- missing or unknown provenance;
- non-approved examples;
- private, personal, secret, or production-user data;
- duplicate IDs, prompts, or content;
- semantic groups crossing splits;
- any prompt duplicated in held-out evaluation.

Splits are deterministic by semantic group. The experimental mixture emphasizes general replay, with smaller Modula, structured-action, uncertainty, freshness, and privacy portions. Mixture percentages are measurements, not permanent policy.

`training-manifest.json` identifies the revision, parent, approval state, split and category counts, learning-candidate count, licenses, file hashes, and manifest hash. Approved revisions are append-only artifacts of the governed process.

## Promotion and rollback

Artifacts move through `experimental`, `candidate`, `accepted`, `deprecated`, or `quarantined`. Promotion is fail-closed on general retention, measurable Modula improvement, confidence calibration, freshness, privacy, runtime, integrity, and licensing. A failed gate cannot publish a model. The previously accepted directory is retained so rollback does not depend on reconstructing an older model.

No training process rewrites Swift, Python tooling, security policy, AKI policy, Governor policy, or deployment logic. Generated examples are data proposals; source modification remains separately governed.
