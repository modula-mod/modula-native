# MOL-01 — Final Report

**Verdict: PARTIAL. Not ready for MOL-02 build start.** One open defect is listed below. The MOL-02 *plan* is written.

- Main baseline: `70084e4` (PR #24: MOL-01 foundation plus the 30-ideas UI batch).
- Acceptance branch: `phase/mol-01-acceptance`. The final SHA is recorded in the PR.
- Environment: Xcode 27.0 (27A266a). iPhone 16 Pro simulator (8AAF71C9…). iPhone 00008150-00043C2A11A3401C (Debug install).

## Gates
| Gate | Result | Evidence |
|---|---|---|
| RealityKit loads real geometry | PASS (sim) | probe: `loaded=1 meshes=12 anims=2`; MOL01Tests.testPebbleLoadsAnimatesAndWearsCap |
| Expressions and baked clips | PASS (sim) | XCUITest testRealGeometryExpressionsAndClips: 6 expressions → `clip:expr_*`; wobble, idle_bob, tap; ≥9 clips played |
| Drag rotation | PASS (sim) | yaw 0.00 → 2.66 after drag |
| Tap react | PASS (sim) after fix: the entity-targeted tap never fired under the custom virtual camera, so a stage tap replaced it | testRotationAndTapGestures |
| Cap equip/remove and restore across relaunch | PASS when the app doesn't crash (passed in 4 of 6 runs) | testCapEquipRemoveAndRestoreAcrossRelaunch |
| Saved outfits and entitlements | PASS (code review) | Signature Cap is `.free`, so `owns()` is always true. Legacy outfit decode test passes. The backend (modula-latest `a211ae7d`) has **no** mascot/wardrobe entitlement API; ownership is client-side only. No backend change was made. |
| Flag off gives 2D (rollback) | PASS (sim) | testFlagOffShows2DStudioOnlyAndFlagOnOffers3D (`-dev.moliboo.native3D NO` hides the 3D entry; the 2D Studio renders) |
| Composer, Studio and wardrobe regression | PASS vs baseline | full unit suite 460 run / 2 failures, both pre-existing (see below) |
| Perf / lifecycle (simulator) | Measured | see below |
| Stability | **FAIL / open** | intermittent app crash ~2 s after a cold launch straight into the 3D preview (3 different stacks: SwiftUI trait update / objc fatal, RealityKit MaterialAssetLoader dealloc, SwiftUI Image release). Seen in ~6 of ~30 app launches across the acceptance runs (acc2–acc6). The most frequent stack is `__swift_closure_destructor.18` in Modula.debug.dylib, which points to an over-released capture in an app closure. Root cause not found yet. Probe churn was reduced (per-frame stats are @ObservationIgnored and sampled at 2 Hz); the crash persisted. An earlier crash was caused by a dropped `EventSubscription` (my probe) and is fixed. The ASan run showed no ASan report, but did show one lost-connection failure. Not reproduced on the iPhone (the user reports Pebble works). |

## Performance (simulator, iPhone 16 Pro, Debug)
- Studio alone: 25 MB footprint at first render.
- Opening 3D Pebble: 292 MB footprint on 1st open, 318 MB on 21st open (+26 MB over 20 open/close cycles). Per-open values plateau around 300–330 MB with noise. No unbounded growth was observed.
- Load time (USDZ to entity): 637–1218 ms, typically ~850 ms.
- Frame timing: avg ~47–50 ms/frame (~20 fps) and max ~110–128 ms in the simulator's software Metal path. This is **not representative of the device**. Measuring on the iPhone with xctrace is still to do.

## Pre-existing failures (identical on 6183b63, before MOL-01)
`PostSystemTests.testOwnVersusOtherContextMenus`; UI: `MCAT02CatalogUITests.testCoreInteractionsInOLEDAndReducedMotion`,
`N2PolishAccessibilityUITests` (2 tests), `N2ShellUITests.testCanonicalShellRailProductHubModuleHostAndAppearance`,
`N3AActivityAuthUITests.testActivityRailAccessoryAccountChromeAndAuthReturn`. None was caused by MOL-01 or the 30 ideas.

## Limitations
- The intermittent launch crash (above) blocks PASS.
- Frame timing and memory were measured on the simulator only.
- The 3D entry exists for Pebble only. 3D is on by default in Debug and off in Release.
