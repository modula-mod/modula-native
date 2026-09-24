# Nodus training

Nodus v0 is adapted from an open-weight foundation model; it is not pretrained from zero. The reproducible tooling boundary lives under `Tools/Nodus` and is isolated from Xcode dependencies. Exact Python, MLX, MLX-LM, tokenizer, and dataset versions are pinned in `pyproject.toml`; experiments are pinned in YAML.

## Candidate and license gate

NODUS-01 benchmarks Qwen3-1.7B and SmolLM2-1.7B-Instruct at exact upstream revisions before selection. `licenses/base-models.json` records publisher, license, commercial status, redistribution and derivative obligations, attribution, naming restrictions, and acceptable-use restrictions. Public Nodus branding never removes upstream provenance.

Initial adaptation uses LoRA on Apple silicon. A pilot run proves loss reporting, validation, adapter reload, and generation before the full experiment. Base and tuned variants receive the same held-out evaluation. A promising failed-promotion checkpoint may now be exported at 4-bit as an experimental candidate for real developer evaluation, but only an artifact passing every production gate may become accepted. Manifests retain base revision, dataset revision, method, quantization, hashes, evaluation evidence, lifecycle stage, and shipping policy.

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

## NODUS-01B controlled corpus

NODUS-01B adds `nodus-01b-r3-v1`, `nodus-01b-r4-v1`, and `nodus-01b-r5-v1`. Each has 6,000 examples with category, generator type/version, source concept/document, seed, semantic family, privacy class, license, and hashes. Exact, normalized, and near duplicates are removed before semantic families enter deterministic 80/10/10 splits; held-out prompts are excluded. Private production data count is zero.

R3 retains 60% general replay. R4 increases Modula and action/authority weighting. R5 retains 50% general replay and raises freshness, uncertainty, abstention, false-premise, unknown-capability, hallucination-resistance, and correction coverage. Labels and reference answers derive from repository contracts or deterministic general templates, not unreviewed model output.

All runs pin Qwen3-1.7B revision `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`, LoRA rank 16, all 28 layers' attention projections, prompt masking, sequence length 512, gradient accumulation 2, and fixed seeds. R3/R4 use 1,200 iterations at `5e-5`; R5 uses 1,400 at `4e-5`.

## NODUS-01B outcome

R3 step 1200, R4 step 300, and R5 step 1400 were the per-run behavioral winners. All failed promotion. R5 had the strongest legacy Modula result but regressed general categories, missed the expanded +0.15 Modula gate, exceeded the 0.4400 compatible ECE ceiling, and failed abstention. No unbounded R6 search was justified. No adapter was fused, quantized, installed, or manifested as accepted. Full evidence is in `Tools/Nodus/reports/nodus-01b-training-report.md`.

## Promotion and rollback

Artifacts move through `experimental`, `candidate`, `accepted`, `deprecated`, or `quarantined`. Promotion is fail-closed on general retention, measurable Modula improvement, confidence calibration, freshness, privacy, runtime, integrity, and licensing. A failed gate cannot publish a model. The previously accepted directory is retained so rollback does not depend on reconstructing an older model.

For NODUS-01B, measurable Modula improvement is at least +0.15 absolute on comparable legacy and expanded suites. Compatible calibration must be below 0.4400; approximately 0.374 is the preferred 15% improvement target. General aggregate and each measured category may regress by no more than five points. Freshness, abstention, hallucination resistance, unknown capability, and false premise remain independent gates.

No training process rewrites Swift, Python tooling, security policy, AKI policy, Governor policy, or deployment logic. Generated examples are data proposals; source modification remains separately governed.

## Fast candidate workflow

The iteration loop is now `train → fast diagnostic evaluation → experimental candidate → real Developer Nodus Chat → human/developer evaluation → full promotion suite → accepted`. A weak run is discarded before packaging; a promising run can be made runnable without being called shippable. Full promotion remains fail-closed and is never replaced by the diagnostic suite or human ratings.

NODUS-01D performs no new training. It packages the preserved NODUS-01C R7 checkpoint, records its known failures, and uses a compact fused-versus-Q4 diagnostic only to detect runtime or quantization collapse.
