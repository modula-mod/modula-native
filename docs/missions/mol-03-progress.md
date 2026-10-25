# MOL-03 — Moliverse Production & Distribution — progress

Owner: MSJoY Andy · Executor: Grok Bot · Scope: all 115 Moliboos (001–100 wearable + Legends 101–115, non-wearable by design)
Branch: `mol03/registry` (from origin/main 587b5e8, includes #185 Legends). Pushed WIP commits: 2deeaa7, bf93957.

## Baselines (Phase A)
- Release-iphoneos baseline (ce3cc53, CODE_SIGNING_ALLOWED=NO): **154,675,792 B** app payload (ditto zip 39,432,441 B). Copy kept at ~/agent-tools/mol03/baseline/Modula.app.
- Simulator metrics (unit run 3, busy shared Mac): Studio footprint 131→134 MB over 20 open/close cycles; 115 static thumbnails 241 ms (2.1 ms each, +4.4 MB); Nodus coexistence delta +1.0 MB; Studio preview 16.9 fps in simulator under load (device not measured yet).

## Unit run 3 (03:19 Europe/London) — 45 tests, 40 passed, 5 failed (fixed, rerun queued as run 4)
- PASS: registry (9), motion (7), packages (12 of 13), Signature Cap fit for all 100 wearables across still + 4 animated phases, Legends draw no cap, small-scale avatars, reactions, contact sheets, MOL05 Legends (6), Nodus coexistence, Studio 20-cycle memory.
- Fixed: committed fit file was a placeholder → replaced with the validated export (100 profiles); expressions only 4/6 distinct because `.still(mood)` leaves gaze/lids/mouth at rest → added `MolibooSemanticExpression.stillPose`/`applyFace`; package paths now ASCII-only; simulator fps gate is a collapse floor (12 fps) with metrics reported.

## Contact sheets
~/agent-tools/mol03/sheets/ on the Mac, mirrored to /workspace/mol03/ (base-capped, difficult-fittings, small-scale, expressions per family, reactions).

## QA package pipeline (Phase E)
- QA signing key ~/.config/modula-dev/mol03-moliboo-qa-ed25519(.pub).pem (QA fixture, Debug trust only, never committed).
- Published Somna (moliboo.100) packages: serve-v1 (1.0.1), serve-v2 (1.0.1 + 2.0.0 recolour), serve-v3 (+2.0.1 tampered after signing).
- Debug-only `-MolibooPackageAutoUpdate` QA auto-updater polls the source and installs newer signed releases into a running app.

## Unit run 4 (03:48 Europe/London) — 45/45 passed, 0 failed (with renderer hooks applied)
- Metrics: Studio 129.5→131.6 MB over 20 cycles (no sustained growth); 115 thumbnails 242 ms; Nodus coexistence +1.5 MB; simulator Studio 15.5 fps (busy shared Mac; collapse floor only).

## Merged
- **#190** MOL-03 foundation (registry 115, fits 100, expressions/motion, packages, catalogue views, tests) → merged into main as **bdd4033** (CI boundary-and-runtime pass).

## In progress
- `mol03/package-hooks` (f41bff9): 2-line renderer hooks in ModulaMascot.swift (spec + palette), no overlap with #186 / outfit-sync hunks. Simulator Debug build running for the hot-update demo (QA server http://127.0.0.1:8787 → serve-v1/v2/v3).

## Hot update demo — Simulator Test G/H (04:00–04:02 Europe/London) — PASS
Somna #100 in the Studio on simulator 8ED397E0, Debug build, local signed QA source http://127.0.0.1:8787 (loopback http allowed by ATS):
built-in → 1.0.1 installed → **2.0.0 recolour applied live, no relaunch, no rebuild** → tampered 2.0.1 rejected (digest mismatch), stays 2.0.0 → server stopped + relaunch offline: still 2.0.0. Index {"active":"2.0.0","previous":"1.0.1"}. Found + fixed: URLSession heuristic cache hid new catalogues.
Sequence image: /workspace/mol03/sim/mol03-hot-update-sequence.png. QA package removed from the simulator afterwards.

## Merged
- **#192** renderer hooks + catalogue revalidation → main **5b09771** (CI pass; 45/45 MOL-03 unit tests with hooks).

## In progress
- `mol03/acceptance` (55fc1cb): Studio entry "All Moliboos" → collection browser (family filter, search, download status) → character detail. Combined unit + Nodus + legacy Moliboo regression run (smoke2) queued.

## Batch smoke2 (04:25 Europe/London) — 98 tests: 92 passed, 5 skipped, 5 failed (all unrelated, untouched suites)
- All new MOL-03 suites + MOL05/Collection/Wardrobe*/Ambience/MOL04/NodusRelease passed.
- Failures: MOL03Originals ×3 + MOL03Studio ×1 (dormant 3D descriptors removed by CORE-SIZE-01), MOL03World testTooTiredToPlay (care logic) — not touched by MOL-03.

## Merged
- **#195** Studio "All Moliboos" entry → collection browser → character detail → main **59331ed**. Screens: /workspace/mol03/sim/mol03-studio-collection-detail.png.

## In progress
- `mol03/finish`: Debug-only developer fitting lab (`-MOL03FitLab`, live scale/width/lift via the package fit path, exports fits.1 JSON). Batch3 (MOL-03 + full Nodus/Intelligence suites) queued.

## Batch3 (04:55 Europe/London): 118 tests, 117 passed, 1 skipped, 0 failed
- All MOL-03 suites and MOL05, plus the full Nodus suites (Nodus01*, Nodus02A*, Artifact, InstalledRuntimeIntegration, Release) and Intelligence Router/Privacy/ProviderRegistry/Acceptance.
- Metrics: Studio 104→106 MB over 20 cycles; Nodus coexistence +0.2 MB; 115 thumbnails 269 ms.

## Merged
- **#197**: Debug-only fitting lab, merged to main as **4dba186**. Screenshot: /workspace/mol03/sim/B1-fit-lab.png.

## In progress (around 05:00)
- Final Release build of main 4dba186 is queued: /tmp/mol03-dd/release, log ~/agent-tools/mol03/release-final.log.
- `mol03/report` holds the docs plus Test E, a rapid-switching perf test across all 115.

## Pending
- Renderer hooks in ModulaMascot.swift + Studio/collection integration wait for #186 (open).
- Simulator Tests A–J and hot update demo after hooks land.
- GreenField: descriptor contract lives on draft #137 → PARTIAL.
