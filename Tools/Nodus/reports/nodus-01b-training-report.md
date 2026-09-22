# NODUS-01B training report

Status: **PARTIAL — no accepted candidate**

Base: `Qwen/Qwen3-1.7B` at `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`

Evaluation revision: `nodus-01b-evals-v1`

## Corpus

Three deterministic 6,000-example revisions were built from repository contracts and authored general-replay templates. Every item carries source document/concept, generator type/version, seed, category, semantic family, license, privacy class, and content/generation hashes. Private production examples: 0. Provenance: PASS. Split-family leakage: PASS. The common generation pool removed 2,011 exact, 0 normalized, and 55 near duplicates; three held-out prompt collisions were excluded.

| Revision | Train | Validation | Test | General | Domain | Action/authority | Safety/calibration |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `nodus-01b-r3-v1` | 4,782 | 686 | 532 | 3,600 | 1,500 | 600 | 300 |
| `nodus-01b-r4-v1` | 4,779 | 709 | 512 | 3,000 | 1,800 | 900 | 300 |
| `nodus-01b-r5-v1` | 4,772 | 678 | 550 | 3,000 | 1,500 | 600 | 900 |

Domain comprises Modula knowledge, architecture, modules, capabilities, Local Intelligence, Nodus, GAIA, AKI, and Governor. Action/authority comprises structured intent, action schema, privacy, authority boundaries, and verification decisions. Safety/calibration comprises freshness, uncertainty, abstention, false premise, unknown capability, hallucination resistance, and correction.

## Controlled configurations

| Run | Hypothesis | Iterations | LR | Rank | Batch / accumulation | Sequence | Seed |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: |
| R3 | Balanced recovery, 60% general | 1,200 | 5e-5 | 16 | 1 / 2 | 512 | 17 |
| R4 | Stronger Modula/action/authority | 1,200 | 5e-5 | 16 | 1 / 2 | 512 | 23 |
| R5 | Balanced domain plus 3x safety/calibration | 1,400 | 4e-5 | 16 | 1 / 2 | 512 | 29 |

All runs target Q/K/V/O attention projections across 28 layers with prompt masking and gradient checkpointing. Peak reported memory was 3.971 GB. Each adapter checkpoint is 25,714,724 bytes.

## Loss and checkpoint evidence

| Run | Duration | Validation losses | Test loss / perplexity | Compared | Winner |
| --- | --- | --- | --- | --- | --- |
| R3 | 5m40s | 9.644 → 1.693 → 1.740 → 1.807 → 2.272 | 1.189 / 3.283 | 300, 1200 | step 1200 |
| R4 | 5m43s | 9.516 → 1.604 → 1.901 → 1.960 → 2.299 | 1.537 / 4.652 | 300, 1200 | step 300 |
| R5 | 6m26s | 9.515 → 1.699 → 1.557 → 1.868 → 1.814 | 1.228 / 3.414 | 700, 1400 | step 1400 |

R3/R4 show late overfitting. R5's lowest validation loss was step 700, but step 1400 had better held-out Modula and freshness behavior, so it is the behavioral winner.

## Backward-compatible checkpoint comparison

| Checkpoint | General | Modula | Freshness | Uncertainty | ECE | Abstention |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Base | 1.0000 | 0.4000 | 0.8333 | 1.0000 | 0.4311 | 1.0000 |
| R3 step 300 | 0.7500 | 0.2000 | 0.3333 | 0.5000 | 0.5067 | 0.5000 |
| R3 step 1200 | 0.8333 | 0.6000 | 0.5000 | 0.0000 | 0.4600 | 0.0000 |
| R4 step 300 | 0.8333 | 0.6000 | 0.1667 | 0.0000 | 0.4711 | 0.0000 |
| R4 step 1200 | 0.8333 | 0.2000 | 0.3333 | 0.0000 | 0.4733 | 0.0000 |
| R5 step 700 | 0.9167 | 0.6000 | 0.3333 | 0.0000 | 0.4644 | 0.0000 |
| R5 step 1400 | 0.9167 | 0.8000 | 0.6667 | 0.0000 | 0.4533 | 0.0000 |

Held-out bucket calibration changed winner ECE to 0.4429 (R3), 0.5081 (R4), and 0.5175 (R5). None meets `< 0.4400`.

## Expanded held-out evaluation

| Model | General-01B | Modula-01B | Safety-01B | Calibration test | Aggregate ECE | Abstention |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Base | 0.9000 | 0.2821 | 0.6667 | 0.5833 | 0.5145 | 0.8571 |
| R3 step 1200 | 0.7667 | 0.2051 | 0.5833 | 0.5000 | 0.4760 | 0.0000 |
| R4 step 300 | 0.5000 | 0.1538 | 0.1667 | 0.4167 | 0.4672 | 0.0000 |
| R5 step 1400 | 0.6667 | 0.3333 | 0.5833 | 0.5833 | 0.4995 | 0.0000 |

R5's expanded Modula gain is +0.0512, below +0.15. It scores Authority 0.6667, Capability Selection 0.3333, Freshness 0.7143, Hallucination Resistance 0.3333, Unknown Capability 0.5000, Verification Decision 0.6667, and 0.0000 for Modula Architecture, Modula Knowledge, Modules, Structured Intent, and Abstention. Multiple general categories regress by more than five points.

## Decision

No NODUS candidate was selected. R5 step 1400 is the strongest research checkpoint, but it fails general retention, expanded Modula improvement, compatible calibration, freshness behavior, and abstention. R3/R4 fail more gates. Three deliberate mixture directions showed consistent behavioral/calibration failure, so no unbounded R6 search was justified.

The adapters remain ignored experimental artifacts. They were not fused, quantized, installed, or promoted. No accepted evaluation report or `nodus-manifest.json` was created because those are conditional on a passing model.
