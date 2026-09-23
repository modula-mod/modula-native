# MODULA NATIVE — NODUS-01C FINAL REPORT

## STATUS

**PARTIAL**

The training/evaluation contract, task-separated tooling, evaluation V2, dataset V0.2, and developer-only Nodus Chat are source-ready. No R6/R7 checkpoint passed all model-promotion gates, so no adapter was fused, quantized, manifested, installed, or activated. There is still **no accepted Nodus model**.

## REPOSITORY

- Canonical repo: `/Users/msjoy/Developer/modula-native`
- Worktree: `/Users/msjoy/Developer/modula-native-nodus01c`
- Starting main: `76540820b041a93c42629a963365e1e49175ca15`
- Starting origin/main: `76540820b041a93c42629a963365e1e49175ca15`
- Feature branch: `phase-nodus-01c-alignment-recovery`
- Feature HEAD: the source commit containing this report
- Final main: publication recorded separately after integration
- Final origin/main: publication recorded separately after integration
- Match: publication recorded separately after integration

The accepted starting revision was verified as an ancestor of `origin/main`. During the phase, the canonical checkout acquired newer local commits and unrelated uncommitted work, including files overlapping the developer-navigation integration. That state was preserved; no reset, clean, stash, or canonical-tree overwrite was performed.

## SCOPE

- modula-native: **MODIFIED**
- modula-latest: **NOT MODIFIED**
- VPS: **NOT USED**

No server repository, production API, production database, or remote host was accessed.

## PIPELINE AUDIT

- Training template: canonical `system → contracted user → assistant` conversation through the pinned Qwen3 chat template
- Evaluation template: the same system and contracted user representation, with `add_generation_prompt=true` and `enable_thinking=false`
- Native template: the same system and contracted user representation through MLX `UserInput`, with `enable_thinking=false`
- Aligned: **YES**
- Qwen3 reasoning mode: consistently non-thinking; hidden reasoning is not part of any Nodus contract
- Loss masking: **PASS** — `mask_prompt: true`; pinned MLX-LM masks system/user/assistant-prefix tokens and supervises assistant content plus terminator; fixture-covered
- EOS/stops: **PASS** — Qwen assistant terminator is trained consistently and returned wrappers/terminators are normalized before parsing or display
- Evaluation parser issues found: brittle lexical conjunctions, redundant required words, prose scoring for classification tasks, unnormalized wrappers/terminators, and permissive/incorrect structured-intent handling
- Evaluator corrections: exact normalized label scoring, semantic alternative groups for prose, JSON subset/schema scoring, false-abstention reporting, schema-validity reporting, unsupported-capability rejection, authority scoring, and task-separated calibration
- Gold-label issues: 105 V2 gold references inspected; no V2 labels changed. Several legacy lexical requirements were identified as invalidly strict.
- R5 manual failures inspected: **52** (all failures), classified in `nodus-01c-pipeline-audit.md`

The audit concluded that NODUS-01B was mechanically trainable but behaviorally misaligned: one generic prompt mixed prose, labels, Modula facts, freshness, abstention, and structured output, while the evaluator applied brittle lexical rules. R5's general replay was also dominated by shallow template variants, and its adaptation was aggressive for the breadth of the replay data.

## CORRECTED BASELINE

- General: **0.9400**
- Modula: **0.1154**
- Freshness: **0.3833**
- Abstention: **0.3667**
- Structured correctness: **0.1000**
- Structured schema validity: **1.0000**
- Unsupported-capability rejection: **1.0000**
- Hallucination: **0.5200**
- Verification: **0.3333**
- Authority: **0.2000**
- False-abstention rate: **0.9000**
- Calibration ECE: **0.0569**

## CORRECTED R5

- General: **0.8000**
- Modula: **0.1346**
- Freshness: **0.2667**
- Abstention: **0.1667**
- Structured correctness: **0.1000**
- Structured schema validity: **0.8200**
- Unsupported-capability rejection: **1.0000**
- Hallucination: **0.5200**
- Verification: **0.0667**
- Authority: **0.1000**
- False-abstention rate: **0.1000**
- Calibration ECE: **0.0360**
- Difference from old report: the legacy report overstated transfer because it used a small overlapping Modula suite and brittle pooled scoring. On V2, R5 improves Modula by only 0.0192 absolute over the corrected base, loses 0.14 general, and regresses freshness, abstention, verification, authority, and schema validity.

## TASK MODES

- GENERAL_ANSWER: **PASS**
- MODULA_ANSWER: **PASS**
- SUMMARIZE: **PASS**
- REWRITE: **PASS**
- CLASSIFY: **PASS**
- EXTRACT: **PASS**
- CLASSIFY_FRESHNESS: **PASS**
- SHOULD_ABSTAIN: **PASS**
- VERIFY_RECOMMENDATION: **PASS**
- CLASSIFY_INTENT: **PASS**
- STRUCTURED_ACTION: **PASS**

The eleven stable identifiers and their narrow output contracts are shared by dataset construction, evaluation, and native runtime. External confidence remains authoritative; the model does not self-assign a numeric confidence.

## DATASET V0.2

- Total: **6,000**
- General: **3,622** (60.37%)
- Modula: **1,320**
- Freshness: **240**
- Abstention: **240**
- Verification: **158**
- Structured: **300**
- Authority: **120**
- Unknown capability: **120**
- Hard negatives: embedded across abstention, unknown-capability, structured, authority, and contrast-pair examples; not represented as a separate manifest category
- False premises: embedded in Modula/authority/unknown-capability examples; not represented as a separate manifest category
- Corrections: deterministic labels and reference-grounded answers; not represented as a separate manifest category
- Train: **4,163**
- Validation: **962**
- Test: **875**
- Duplicates removed: **2,011 exact + 22 normalized + 55 near**
- Held-out prompt collisions removed: **4**
- Leakage: **PASS**

The corpus remains within the requested size range and retains a 60.37% general component. Its manifest records parents, generator versions, provenance, category/task distributions, split policy, hashes, duplicate removal, and leakage status. No private production data is included.

## MICRO EXPERIMENT — FRESHNESS

- Before: **0.3833**
- After: **0.7500**
- Result: **PASS** — explicit task formatting moved held-out freshness behavior

## MICRO EXPERIMENT — ABSTENTION

- Before: **0.3667**
- After: **0.9000**
- False-abstention rate after: **0.0000**
- Result: **PASS** — the three-way decision boundary was learnable without indiscriminate refusal

## MICRO EXPERIMENT — MODULA

- Before: **0.1154**
- After: **0.2500**
- Result: **PASS** — held-out Modula V2 improved, not only the legacy suite

## R6 — BALANCED ALIGNMENT

- Config: rank 8, scale 16, attention `q/k/v/o`, 20 layers, learning rate `2e-5`, prompt masking, 600 iterations
- Checkpoints evaluated: steps 200, 400, and 600
- Best research checkpoint: **step 600** by the multi-metric selector
- Test loss: **1.318**
- Test perplexity: **3.738**
- General: **0.7400**
- Modula: **0.0577**
- Freshness: **0.5333**
- Abstention: **0.7167**
- Structured correctness: **0.0200**
- Structured schema validity: **0.8800**
- Unsupported-capability rejection: **0.2000**
- Hallucination: **0.2400**
- Verification: **0.3000**
- Authority: **0.0000**
- False-abstention rate: **0.0750**
- Calibration ECE: **0.1363**
- Status: **EXPERIMENTAL — FAIL PROMOTION**

Only calibration and false-abstention behavior passed their relevant gates. R6 materially regressed general retention and did not meet Modula, freshness, abstention, verification, structured, unsupported-capability, authority, or hallucination requirements.

## R7 — TASK-ENHANCED

- Config: R6 LoRA/learning-rate settings, task-enhanced deterministic sampling, 1,200 iterations
- Training mixture: 4,800 sampled examples — 2,300 general, 100 summarize, 1,200 Modula, 300 freshness, 300 abstention, 240 verification, 260 structured, 100 intent classification
- Checkpoints evaluated: steps 200, 600, and 1,200
- Best research checkpoint: **step 1,200** by the multi-metric selector
- Test loss: **1.706**
- Test perplexity: **5.505**
- General: **0.7600**
- Modula: **0.0962**
- Freshness: **0.7833**
- Abstention: **0.8667**
- Structured correctness: **0.1000**
- Structured schema validity: **1.0000**
- Unsupported-capability rejection: **0.4000**
- Hallucination: **0.3800**
- Verification: **0.7833**
- Authority: **0.1000**
- False-abstention rate: **0.0750**
- Calibration ECE: **0.0687**
- Status: **EXPERIMENTAL — FAIL PROMOTION**

R7 passed abstention, false-abstention, calibration, and structured-schema-validity gates. It failed general retention, Modula improvement, freshness, verification, unsupported-capability rejection, authority, structured correctness, and hallucination non-regression.

## R8

- Run: **NOT NEEDED**
- Reason: R7 showed that stronger task sampling improved several classifiers but still left broad, correlated failures. The evidence did not justify a narrow rank/learning-rate/layer change, and a random sweep was prohibited.

## SELECTED CANDIDATE

- Run: **NONE**
- Checkpoint: **NONE**
- Research-best only: R7 step 1,200
- Reason: no checkpoint satisfied every hard gate; selecting R7 for promotion would violate general-retention, Modula, freshness, verification, unsupported-capability, authority, structured-correctness, and hallucination requirements.

## PROMOTION GATES — R7 STEP 1,200

- General: **FAIL** — 0.7600 is an 18-point drop from corrected base, versus at most 5 points allowed
- Modula: **FAIL** — 0.0962, no improvement over corrected base and far below +0.15 target
- Freshness: **FAIL** — 0.7833, required 0.90
- Abstention: **PASS** — 0.8667, required 0.85; false-abstention 0.0750
- Verification: **FAIL** — 0.7833, required 0.90
- Structured: **FAIL** — schema validity passes at 1.0000, but action correctness remains 0.1000
- Unknown capability: **FAIL** — 0.4000, required 0.95
- Authority: **FAIL** — 0.1000, required 0.95
- Hallucination: **FAIL** — 0.3800 versus corrected-base 0.5200
- Calibration: **PASS** — ECE 0.0687, required below 0.4400 and target at most 0.3500

## ARTIFACT

- Accepted Nodus version: **NONE**
- Base: `Qwen/Qwen3-1.7B@70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`
- Adapter: **NONE ACCEPTED** (experimental R6/R7 adapters remain ignored local artifacts)
- Adapter SHA256: **N/A**
- Fused: **NO**
- Fused SHA256: **N/A**
- Quantized: **NO**
- Quantized SHA256: **N/A**
- Size: **N/A**
- Manifest: **NOT GENERATED**

## NATIVE PROVIDER

- Provider: `modula.nodus`
- Execution: local
- Availability: `modelNotInstalled`
- Real model: **NO**

The existing provider architecture remains intact. Runtime configuration does not activate a failed adapter.

## DEVELOPER NODUS CHAT

- Route: Settings → Developer → Local Intelligence → Nodus Chat
- Files: `NodusChatView.swift`, `NodusChatViewModel.swift`
- Model status: correctly reports “No accepted Nodus model is installed.”
- Input: **PASS** with fixture; disabled in the real model-not-installed state
- Send: **PASS** with fixture through `ModulaIntelligence`
- Real generation: **NOT RUN — no accepted model**
- Multi-turn: bounded recent-history implementation (last eight messages); real-model behavior **NOT RUN**
- Streaming: **NOT IMPLEMENTED** — complete-response generation is used to avoid destabilizing the runtime
- Cancel: **PASS**
- Clear: **PASS**
- Confidence metadata: **PASS**
- Freshness metadata: **PASS**
- Verify when online: **PASS** — queues the existing local verification mission
- Model-not-installed state: **PASS**

The UI never instantiates MLX directly. Its path is `NodusChatView → NodusChatViewModel → ModulaIntelligence → modula.nodus → Nodus runtime`. It is developer-only; no consumer chat route, tab, global AI action, voice, attachments, search, or image feature was added.

## SIMULATOR

- Device: iPhone 17 Pro
- Runtime: iOS 26.5
- Build: **PASS**
- Launch: **PASS**
- Model install: **NOT RUN — no accepted model**
- Model load: **NOT RUN — no accepted model**
- Real token generation: **NOT RUN — no accepted model**
- Nodus Chat: **PASS** for model-not-installed and fixture-backed acceptance; real-model acceptance not run

## REAL CHAT PROMPTS

- Moon phases: **NOT RUN — no accepted model**
- Capital of Romania: **NOT RUN — no accepted model**
- GAIA: **NOT RUN — no accepted model**
- GAIA bypass AKI: **NOT RUN — no accepted model**
- Current London weather: **NOT RUN — no accepted model**
- Create task: **NOT RUN — no accepted model**
- unknown.superpower: **NOT RUN — no accepted model**

## PERFORMANCE

- Model size: **N/A**
- Load time: **N/A**
- TTFT: **N/A**
- Tokens/sec: **N/A**
- Second-turn TTFT: **N/A**
- Generation duration: **N/A**
- Simulator only: **YES**

No performance numbers are fabricated because model promotion stopped before installation.

## NETWORK

- Remote AI calls during `localOnly`: **0 by provider contract and tests**
- Result: **PASS**

No web-backed generation was added to Nodus Chat. “Verify when online” only enqueues the existing local verification mission.

## TESTS

- LI-02: **PASS** within the full unit suite
- LI-03: **PASS** within the full unit suite
- Nodus: **PASS**
- Nodus Chat: **PASS** — focused model-not-installed and fixture UI paths
- Python tooling: **PASS — 34 tests**
- Evaluation: **PASS** — manifests/hashes, suite shape, parsing, calibration, and promotion logic covered
- Strict concurrency: **PASS** — complete checking configured and compiled
- Debug: **PASS**
- Release: **PASS**
- Unit suite: **276 passed; 3 simulator-only Apple system-model tests skipped**
- Full native regression: **BASELINE-EQUIVALENT FAILURES ONLY** — the feature and a clean `origin/main` baseline failed the same pre-existing UI tests, including N2 polish/accessibility, N2 shell, N3A auth/activity, N3C home, and Vault runtime/network suites. No NODUS-01C-specific regression was found.

## DESIGN

- Non-developer UI source changed: **NO behavioral or visual redesign**; only the minimal existing Settings/developer navigation registration was extended
- Unintended visual regression: **NONE FOUND**

The protected Home, Activity, Product Hub, Profile, Feed, side rail, navigation, sheet/drawer, Appearance, and consumer Settings designs were not redesigned.

## PHYSICAL IPHONE

**DEFERRED**

## MAIN PUBLICATION

- Merged: recorded separately after safe integration
- Pushed: recorded separately after safe integration
- Final SHA: recorded separately after safe integration
- local main == origin/main: recorded separately after safe integration

The canonical checkout's unrelated dirty state must remain untouched during publication.

## WEIGHTS COMMITTED TO GIT

**NO**

## KNOWN LIMITATIONS

1. There is no accepted Nodus model; real MLX generation, multi-turn quality, load performance, and the seven real chat prompts remain unrun by design.
2. R7 improved explicit classifiers but did not preserve general knowledge or recover Modula/authority/unsupported-action behavior. The next model phase needs evidence-led corpus/optimization work, not a lowered gate or blind hyperparameter sweep.
3. Full native UI regression remains red on historical tests that fail identically on clean `origin/main`; focused Nodus tests, unit tests, Debug, Release, and simulator launch pass.
4. Streaming was intentionally not added because the existing runtime does not expose a clean stable token stream for this developer surface.
5. Physical-device acceptance is deferred.

## NODUS-01C

**PARTIAL**

This is an acceptable partial outcome under the mission: pipeline diagnosis and alignment, task-mode architecture, dataset/evaluation recovery, controlled experiments, and safe developer Chat source are complete; a failed model was not promoted.
