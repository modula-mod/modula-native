# Moliboo renderer benchmark (MOL-03 Workstream B)

## How to run
- **Seven-point suite (unit, no UI):** `xcodebuild test -only-testing:ModulaTests/MOL02Tests/testRendererBenchmarkSevenPoints`.
  It prints one `MOLBENCH {json}` line.
- **Frame pacing + 20x open/close memory (UI):** `MOL01AcceptanceUITests/testStudioLifecycle20xMemoryLoadAndFrames`.
  It prints one `MOL01PERF …` line (avg/max frame ms on the first and last open, footprint per open, load ms per open).
- **Background/foreground:** `MOL01AcceptanceUITests/testBackgroundForegroundKeepsSceneRendering`.

## Seven measurement points
| # | Point | Field |
|---|---|---|
| 1 | Cold load (first in process) | `coldLoadMs` |
| 2 | Warm load (same character again, cache hit) | `warmLoadMs` |
| 3 | Character switch (load of a second character) | `switchMs` |
| 4 | Footprint after first open | `openFootprintMB` |
| 5 | Footprint after the Signature Cap is equipped | `afterCapFootprintMB` |
| 6 | Footprint after the switch | `afterSwitchFootprintMB` |
| 7 | Footprint after all controllers are stopped | `closedFootprintMB` |

## Results (iPhone 16 Pro simulator, iOS 27, 2026-10-14)
| Metric | Value | Target |
|---|---|---|
| Cold load Pebble | 1031 ms (unit); 1.1–1.6 s in the UI harness | ≤ 1500 ms (the UI harness is sometimes over) |
| Warm load Pebble | 3 ms | ≤ 750 ms ✅ |
| Switch to Pip (cold, uncached) | 1303 ms | ≤ 1500 ms ✅ |
| Footprint: open / cap / switch / closed | 97.2 / 102.2 / 101.2 / 101.2 MB | no unbounded growth ✅ |
| 20x open/close footprint delta | +12–16 MB, plateaus | < 60 MB ✅ |
| Frame time (simulator, first/last open) | avg 46–50 ms, max 112–128 ms | simulator only, not representative of a device |

Simulator frame pacing is not meaningful for a device. Device numbers are still needed (phone not available).

## Assets (6 USDZs)
| Asset | Meshes | Materials | Texture |
|---|---|---|---|
| Pebble | 12 | 6 UsdPreviewSurface | 1× 2048² base colour |
| Pip | 23 | 9 | 1× 2048² |
| Moss | 16 | 7 | 1× 2048² |
| Tofu | 16 | 7 | 1× 2048² |
| Bolt | 14 | 8 | 1× 2048² |
| Signature Cap | 9 | 3 | none |

Each 2048² RGBA texture is about 21 MB on the GPU with mips. Halving to 1024² would save about 16 MB per active character,
but it needs a visual sign-off, so it is not done yet.

## Lifecycle guarantees (tested)
- Template cache bounded to cosmetics plus the 2 most recent characters (`testTemplateCacheIsBounded`).
- Switching tears down the previous controller (`testCharacterSwitchTearsDownPrevious`).
- A stopped or cancelled load never attaches geometry (`testLoadAfterStopDoesNotAttach`).
- No clip or equip after stop (`testNoPlaybackOrEquipAfterStop`).
- Background → foreground keeps the scene rendering (`testBackgroundForegroundKeepsSceneRendering`).
- No per-frame SwiftUI churn in the 3D preview: frame stats are `@ObservationIgnored`, and the DEBUG probe samples at 2 Hz.
