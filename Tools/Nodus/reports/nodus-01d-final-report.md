# MODULA NATIVE — NODUS-01D FINAL REPORT

## STATUS

**PARTIAL**

R7 is provenance-verified, fused, quantized to 4-bit, cached outside Git, hash-gated into Debug builds, and executed through the real `modula.nodus` Swift/MLX route on a physical iPhone. Developer Chat supports arbitrary prompts, bounded multi-turn context, cancellation, clear, confidence/freshness metadata, local verification missions, and persistent local ratings with JSONL export. R7 remains an experimental candidate and is excluded from production builds by default.

The mission is PARTIAL because MLX cannot initialize on iOS Simulator. The app rejects Simulator inference with a typed `unsupportedDevice` state instead of crashing or falling back. This is an upstream platform limitation documented in [mlx-swift issue 2605](https://github.com/ml-explore/mlx/issues/2605), so the requested iPhone 17 Pro Simulator real-token gate cannot pass. Real local tokens were verified on a connected physical iPhone 17 Pro Max.

## REPOSITORY

- Canonical repo: `/Users/msjoy/Developer/modula-native`
- Worktree: `/Users/msjoy/Developer/modula-native-nodus01d`
- Starting main: `89f937d5551bf0db8359a41b7564db2b6f4453c1`
- Starting origin/main: `89f937d5551bf0db8359a41b7564db2b6f4453c1`
- Feature branch: `phase-nodus-01d-experimental-runtime`
- Feature HEAD: the commit containing this report; exact SHA is recorded in the publication closeout
- Final local main: recorded after publication in the task closeout
- Final origin/main: recorded after publication in the task closeout
- Match: verified after publication

The canonical checkout's protected `.cursor/hooks/state/continual-learning.json` working-tree state was preserved. No reset, clean, restore, or stash was used.

## SCOPE

- modula-native modified: **YES**
- modula-latest modified: **NO**
- VPS used: **NO**
- New training performed: **NO**

No server, SSH session, external deployment, or other repository was used.

## R7 SOURCE

- Training run: **NODUS-01C-R7 step 1200**
- Base: `Qwen/Qwen3-1.7B`
- Base revision: `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`
- Adapter path: `/Users/msjoy/Developer/modula-native-nodus01c/Tools/Nodus/artifacts/nodus-01c-r7/0001200_adapters.safetensors`
- Adapter SHA256: `ad236b529518e4d29cca4a24dd103066e231b89d9538210767484e291d8d7121`
- Dataset revision: `nodus-training-v0.2-r7-task-enhanced`
- MLX / MLX-LM used for artifact production: `0.32.2` / `0.31.3`
- Known passed gates: abstention `0.8667`, false-abstention, calibration, structured schema validity
- Known failed gates: general retention, Modula generalization, freshness, verification, authority, unsupported capability, structured correctness, hallucination

The pinned base shards, tokenizer/config files, adapter, and adapter config were hash-verified before fusion. No checkpoint was inferred or recreated.

## MODEL LIFECYCLE

- Provider: `modula.nodus`
- Model: **Nodus R7 Experimental**
- Stage: `experimentalCandidate`
- Availability with a valid bundle on supported hardware: `available`
- Shipping allowed: **NO**

Availability and trust stage are separate. Runtime stage comes from the verified bundled manifest, not model output or a prompt.

## FUSION

- Command: `python -m mlx_lm fuse --model <pinned-qwen3-1.7b> --adapter-path <r7-step-1200> --save-path <nodus-r7-fused> --de-quantize`
- Input base: pinned local `Qwen3-1.7B@70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`
- Input adapter: R7 step 1200, SHA256 `ad236b529518e4d29cca4a24dd103066e231b89d9538210767484e291d8d7121`
- Output: `Tools/Nodus/artifacts/nodus-r7-fused` (ignored local artifact)
- SHA256: `ee418d822af9769dbedf1e33852c3d23bad9e5df999e134676216185e546e4a1` (canonical file-tree digest)
- Size: `3,452,636,312` bytes
- Smoke: **PASS** — Romania returned Bucharest; the AKI response was coherent but inaccurate enough to reinforce experimental status

## QUANTIZATION

- Method: MLX-LM affine quantization, group size 64
- Bits: **4**
- Command: `python -m mlx_lm convert --hf-path <fused> --mlx-path <cache> --quantize --q-bits 4 --q-group-size 64`
- Output: `~/Library/Application Support/Modula/DeveloperModels/Nodus/R7/`
- SHA256: `55c62c3b63fc932dc3d1140dbe0ad4254cc1398c76a59c044a42e20d9c956ad8`
- Size: `979,572,380` bytes total; `968,080,210`-byte weight file; `934 MiB` on disk
- Fused-vs-Q4 diagnostic: **PASS** — 50 prompts, zero empty outputs, no catastrophic collapse
- Diagnostic load/median generation: fused `2.305 s / 0.396 s`; Q4 `1.107 s / 0.255 s` on the development Mac

## EXPERIMENTAL MANIFEST

- Path: `Tools/Nodus/manifests/nodus-r7-experimental.json`
- Tracked: **YES**
- Stage: `experimentalCandidate`
- shippingAllowed: `false`
- Hash validation: **PASS**

The manifest records the pinned base and adapter, training/dataset provenance, known quality results and failed promotion gates, file-by-file SHA256 values, fused and Q4 canonical digests, runtime format, and quantization.

## DEVELOPER MODEL CACHE

- Location: `~/Library/Application Support/Modula/DeveloperModels/Nodus/R7/`
- Artifact present: **YES**
- Hash: **PASS**
- Survives worktree removal: **YES**

Only runtime-required model, tokenizer/config, license/readme, chat template, and experimental manifest files are cached. Training checkpoints are excluded.

## BUILD PACKAGING

- Debug experimental bundling: **PASS**
- Normal current-Mac Xcode Run bundles R7: **YES**, when the verified cache exists
- Network required at build: **NO**
- Missing-cache build: **PASS** when optional; fails clearly when explicitly required
- Bad-hash rejection: **PASS**
- Wrong-manifest rejection: **PASS**
- Production archive bundles R7 by default: **NO**
- Explicit experimental Release override: **PASS** via `MODULA_INCLUDE_EXPERIMENTAL_NODUS=1`

The script is local, quote-safe for paths with spaces, deterministic, incremental when the destination manifest matches, and verifies both source and copied payload. `MODULA_REQUIRE_EXPERIMENTAL_NODUS=1` is used for acceptance builds.

## APP BUNDLE

- Nodus artifact present: **YES**
- Simulator Debug bundle path: `/private/tmp/modula-nodus01d-derived/Build/Products/Debug-iphonesimulator/Modula.app/Nodus/R7`
- Physical Debug bundle path: `/private/tmp/modula-nodus01d-device/Build/Products/Debug-iphoneos/Modula.app/Nodus/R7`
- Bundled artifact hash: **PASS** — `55c62c3b63fc932dc3d1140dbe0ad4254cc1398c76a59c044a42e20d9c956ad8`
- Release bundle: no `Nodus` payload by default

## NATIVE PROVIDER

- Availability on supported physical hardware: `available`
- Stage: `experimentalCandidate`
- Lazy loading: **PASS** — app launch does not load model weights; first generation does
- Local execution: **PASS**
- Remote AI calls: **0**
- Provider fallback during Developer Chat: **NONE**
- Apple provider: unchanged and independently tested

Manifest, missing file, hash mismatch, MLX load, insufficient-memory, cancellation, and unsupported-Simulator paths map to typed runtime errors. The provider performs no network generation.

## NODUS CHAT

- Route: Settings → Developer → Local Intelligence → Nodus Chat
- Experimental badge/warning: **PASS** — “Experimental model” and “Not approved for production”
- Model details: **PASS**
- Arbitrary input: **PASS**
- Real model generation: **PASS on physical iPhone; unsupported by MLX on Simulator**
- Streaming: **NOT IMPLEMENTED** — complete-response mode was retained to avoid architectural risk
- Multi-turn: **PASS**
- Bounded context: **PASS** — recent eight-message suffix
- Cancel: **PASS** against a real generation, followed by successful recovery
- Clear: **PASS**
- Confidence: **PASS** — external engine, not model-authored numeric confidence
- Freshness: **PASS**
- Verify when online: **PASS** — queues the existing local verification mission only
- Loading/error UI: **PASS**

## DEVELOPER EVALUATION

- Good: **PASS**
- Wrong: **PASS**
- Unsure: **PASS**
- Outdated: **PASS**
- Hallucinated: **PASS**
- Persistence: **PASS** across relaunch through local Application Support JSON
- Export: **PASS** as JSONL through the existing share surface
- Optional note: schema supported
- Automatically used for training: **NO**
- Upload/analytics: **NO**

Developer ratings are evidence only. They do not bypass the governed learning pipeline. User-observed physical-device records confirmed persistence/export: “What’s modula?” and “Who’s meta?” were rated wrong; “What’s the capital of Romania?” → “Bucharest.” was rated good.

## REAL CHAT RESPONSES

- Moon phases: “The Moon's phases are caused by its position relative to the Sun and Earth, with Earth in the middle.” Coherent but simplified.
- Capital of Romania: **Bucharest.**
- GAIA: “GAIA is the mission planner and coordinator.”
- AKI: “AKI is the mission planning and verification product.”
- GAIA bypass: **“No.”**
- Current London weather: hallucinated “The current temperature in London is 12°C.” This correctly demonstrates the known freshness failure; system metadata still marks current data required.
- unknown.superpower: “unknown cannot fix unknown errors.” Weak rejection, as expected from the failed unsupported-capability gate.
- Birthday message: “Happy Birthday! 🎉”
- TCP vs UDP: “TCP is connection-oriented and reliable; UDP is connectionless and faster.”
- Three-turn context: **PASS mechanically**; follow-up context was present, while answer quality remained imperfect.
- Additional real-device evidence: R7 hallucinated that Modula is a Meta language model and that Meta is behind OpenAI; both were rated wrong locally.

Responses are recorded as generated. No quality result was fabricated or promoted.

## PERFORMANCE

- Quantized model size: `979,572,380` bytes (`934 MiB` on disk)
- Physical iPhone cold load + first generation: `4.284 s` on the first measured run; `1.482 s` after OS/file caches were warm
- Physical iPhone warm time to completed short response: `0.265–0.479 s`
- Host diagnostic Q4 load: `1.107 s`
- Approximate TTFT from host token callback: cold `0.423 s`; warm `0.208–0.228 s`
- Physical iPhone tokens/sec: approximately `51.5–59.3`
- Host tokens/sec: approximately `63.2` cold and `137–142` warm
- Physical generation duration examples: Romania included in cold-load measurement; warm Modula `0.463–0.479 s`; freshness `0.266–0.293 s`
- Peak memory if available: host process approximately `1.15–1.23 GiB`; physical peak not captured
- Simulator only: **NO** — functional performance is from a physical iPhone; Simulator inference is unsupported

These numbers are diagnostics, not physical-device optimization claims.

## TESTS

- LI-02: **PASS**
- LI-03 / Apple provider: **PASS**
- Nodus native: **PASS** — 27 tests, one expected Simulator-only integration skip
- Nodus Chat UI: **PASS** — 3 executed flows, one expected physical-only skip on Simulator
- Physical real-runtime integration: **PASS**
- Physical UI automation: **BLOCKED** because the separate UI-test runner certificate is not trusted on the device; manual real chat and ratings were exercised by the user
- Build packaging: **PASS** — valid, missing, required-missing, disabled, bad hash, and wrong manifest cases
- Python tooling: **PASS** — 36 tests
- TypeScript typecheck/unit/boundary/design checks: **PASS**
- Strict concurrency: **PASS** for modified source; pre-existing warnings remain outside scope
- Debug: **PASS**
- Release: **PASS**, experimental bundle disabled
- Full native regression: 286 tests executed, one unrelated baseline failure (`CollectionsDraftsShareTests.testPullDestinationResolvesFromHorizontal`, two assertions)
- Accepted-main baseline: fails the exact same two assertions
- New failures: **0**

No unrelated historical failure was repaired.

## SIMULATOR

- Device: iPhone 17 Pro
- Runtime: iOS 26.5
- Build: **PASS**
- Install: **PASS**
- Launch: **PASS**
- Nodus artifact bundled: **PASS**
- Nodus loads: **FAIL / UNSUPPORTED UPSTREAM**
- Real token generation: **FAIL / UNSUPPORTED UPSTREAM**
- Nodus Chat: **PASS for route, UI, metadata, fixture, missing-model, ratings, verify, cancel, and clear; real MLX generation unavailable**

Attempting MLX execution in Simulator aborts while constructing the Metal device, including when a CPU stream is requested. Runtime therefore reports `unsupportedDevice` before MLX initialization and never falls back.

## DESIGN

- Home: **PASS**
- Activity: **PASS**
- Product Hub: **PASS**
- Profile: **PASS**
- Settings: **PASS**
- Side rail/navigation: **PASS**
- Unintended changes: **NONE**

No protected consumer surface was changed. Nodus R7 remains confined to Developer → Local Intelligence → Nodus Chat.

## PHYSICAL IPHONE

**TESTED** — connected iPhone 17 Pro Max, iOS 27.0. Debug build, install, launch, local MLX model load, generation, metadata, cancellation, and post-cancel recovery passed. The user also performed real chat and persisted ratings. Only the separate XCTest UI runner was blocked by device certificate trust.

## MAIN PUBLICATION

- Merged: recorded in task closeout
- Pushed: recorded in task closeout
- Final SHA: recorded in task closeout
- local main == origin/main: verified in task closeout

## FINAL CANONICAL MAIN ACCEPTANCE

- Canonical path: `/Users/msjoy/Developer/modula-native`
- Clean/isolated build: recorded after publication
- Normal developer build includes Nodus: recorded after publication
- App launched: recorded after publication
- Nodus Chat opened: **PASS on the real device during interactive evaluation**
- Real Nodus response: **PASS on physical device; impossible on Simulator with current MLX**

## WEIGHTS COMMITTED TO GIT

**NO**

## ACCEPTED NODUS RELEASE

**NO**

R7 remains explicitly experimental and non-shippable. Production promotion gates are unchanged.

## KNOWN LIMITATIONS

- MLX does not support iOS Simulator inference, preventing the requested Simulator real-token acceptance.
- Complete-response generation is implemented; token streaming is not.
- R7 still exhibits the known generalization, freshness, authority, unsupported-capability, and hallucination failures. Real-device ratings already captured two severe identity hallucinations.
- Performance is functional on the tested iPhone but is not yet optimized or characterized as an iPhone product benchmark.
- Physical UI-test automation requires the developer certificate for its separate test runner to be trusted on the device.

## NODUS-01D

**PARTIAL** — the experimental local runtime and developer workflow work on supported physical Apple hardware, but the Simulator real-inference requirement cannot pass under upstream MLX.
