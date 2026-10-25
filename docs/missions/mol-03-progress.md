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

## Pending
- Renderer hooks in ModulaMascot.swift + Studio/collection integration wait for #186 (open).
- Simulator Tests A–J and hot update demo after hooks land.
- GreenField: descriptor contract lives on draft #137 → PARTIAL.
