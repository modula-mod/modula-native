# MOL-02 — Five Living Moliboos — Final Report (§23)

Date: 2026-10-14 · main at the end of MOL-02: see the wrap-up PR · Flag: `dev.moliboo.native3D` (default ON in DEBUG only)

## 1. Statuses (reported separately)

| Track | Status | Why |
|---|---|---|
| **Asset** | **PASS (pending user sign-off, G2)** | Pip, Moss, Tofu and Bolt built with the shared engine, one correction pass each, review sheets and a five-character group render. Pebble is unchanged. |
| **Integration** | **PASS (dev-flagged)** | Generic manifest-driven registry, per-character entries, unit and simulator acceptance tests pass. It remains dev-flagged. |
| **Release** | **NOT PASS / BLOCKED** | The intermittent 3D simulator crash (MOL-01) is unresolved, the iPhone install did not happen (device unavailable), and the simulator perf budget (G8) is not met. Multi-character 3D must stay behind the dev flag. |

## 2. Characters

| # | Character | sourceVersion | USDZ sha256 | Personality clips | Signature Cap | Correction passes |
|---|---|---|---|---|---|---|
| 001 | Pip | pip-v1.0 | 2c6a54a9…a08ef | gill_flutter, exuberant_bounce | compatible (anchor_head) | 1 |
| 002 | Moss | moss-v1.0 | 9bb82d67…25cd | slow_blink, cheek_puff, measured_hop | compatible | 1 |
| 010 | Pebble | pebble-v2.2-frozen | 3a4c3da9…2303 (unchanged) | — (MOL-01) | compatible (unchanged) | — |
| 011 | Tofu | tofu-v1.0 | dfcca461…4823 | cube_squash, exuberant_bounce | compatible | 1 |
| 014 | Bolt | bolt-v1.0 | 7565bb3e…4ec3 | antenna_flash, servo_tilt | compatible (clear of antenna) | 1 |

All characters share: 7 expressions (idle, blink, happy, excited, surprised, sleepy, sad) as baked `expr_*` clips; idle_bob,
blink, wobble and tap; anchors anchor_head/face/back/neck/base. Signature Cap asset is unchanged (359fd730…b531); no other
wardrobe items, purchases or outfits were touched.

## 3. Gates

| Gate | Result | Evidence |
|---|---|---|
| G0 repo truth | PASS | worked from origin/main, PRs #27–#30 |
| G1 Pebble parity via the engine | DEFERRED | docs/moliboo/MOL-02-PEBBLE-PARITY.md |
| G2 per-character model approval | PENDING USER | `evidence/mol-02/<char>/<Char>_review_sheet.png`, `evidence/mol-02/group/` |
| G3 USDZ structure / checksums | PASS | SHA256SUMS per character, MOL02Tests manifest checks |
| G4 manifest + unit tests | PASS | MOL02Tests 10/10, MOL01Tests 9/9 |
| G5 RealityKit load + clips | PASS | MOL02Tests per-character load/clip/cap tests |
| G6 XCUITest per character | PASS with reruns | Pip/Moss/Tofu/Bolt UI 2/2 each; crash-affected tests passed on rerun (see ACCEPTANCE.md files) |
| G7 flag-off rollback | PASS | testStudioOffersPipIn3DOnlyWithFlag…, testFlagOffShows2DStudioOnly… |
| G8 perf budget | NOT MET (simulator) | probe: load ≈1.8–2.1 s, avg frame ≈56 ms on the simulator (budget <500 ms / ≤16.7 ms); device not measured |
| G9 MOL-01 regression | PASS with intermittent crash | 5/5 in Milestone D run; the lifecycle test crashed 2× in Milestone C |
| G10 iPhone install + user approval | NOT DONE | Debug build succeeded; install failed: CoreDevice error 4016 (device unavailable) |

## 4. Known issue: intermittent 3D crash (owned by fix/mol-01-3d-crash)
- Modula-2026-10-14-103538.ips: EXC_BAD_ACCESS in `__swift_closure_destructor` during SwiftUI AddGestureModifier teardown.
- Modula-2026-10-14-104839.ips: EXC_BAD_ACCESS in objc_release / Metal type dealloc.
- Copies are in `~/Developer/.agent-xfer/mol02/` on the Mac. It is not fixed in MOL-02.

## 5. iPhone (G10)
- Build: `xcodebuild -configuration Debug -destination generic/platform=iOS MODULA_API_URL=https://api.modula.digital` → BUILD SUCCEEDED
  (signed digital.modula.app.native, team M29V4ZGUNK; it bundles all six USDZs).
- Install: `devicectl device install app --device 00008150-00043C2A11A3401C` → ERROR 4016 "device is not able to fulfill the requested
  usage assertion requirements"; devicectl lists the iPhone as `unavailable`. It was not installed and not launched.
  Retry when the phone is unlocked and connected or on the same network.

## 6. Deviations / not done
- No screenshots, video or stress runs (user override). The renders are Blender renders of the shipped USDZs, not device captures.
- G1 Pebble parity deferred; Pebble stays on build_pebble.py.
- Moss/Tofu/Bolt sim tests include reruns after the known crash; the logs record both runs.
- No backend changes, no VPS, no production writes.

## 7. Next
1. The crash worker lands the 3D teardown fix; then rerun the full MOL-01 and MOL-02 UI suites 3× clean.
2. Install on the iPhone, measure perf on device (G8), and get user approval of the models (G2, G10).
3. Only then consider Release (flag default change). Until then multi-character 3D stays dev-flagged.
