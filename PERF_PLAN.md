# Modula iOS — speed plan (andy/speed-enhancements-1)

Nothing in this branch has been measured yet. It was written without a Swift toolchain, and the
Mac was offline. The "expected" column is the direction and rough size we expect, not a measurement.
Measure before and after on the same device, same build configuration (Release), same account.

## Signposts (subsystem `digital.modula.app.native`, category Points of Interest)

| Name | Kind | From → to |
|---|---|---|
| `Launch` | interval | `AppEnvironment.init` → first frame (`ModulaPerf.mark("firstFrame")`) |
| `EnvironmentInit` | interval | `AppEnvironment.init` body |
| `LaunchToFeed` | interval | `AppEnvironment.init` → first Home feed row on screen |
| `Bootstrap` | interval | `bootstrapLaunch()` → bootstrap done / gate ready |
| `FeedFirstPaint` | interval | first `HomeStore.refresh` → first feed row |
| `ChatOpen` | interval (key = conversation id) | `ConversationView` appears → first messages scrolled into place |
| `Request` | interval | every Greenfield call (method + path without query, byte count) |
| `ImageDecode` | interval | each downsample (target px) |
| `SheetOpen` / `SheetClose` | event | any sheet using `modulaSheetStyle()` appears / disappears |
| `SpatialSheet` | event | sidebar / profile / dock layer changes |
| `VideoAttach`, `VideoFirstFrame` | event | player attached, first decoded frame ready |
| `Mark` | event | the existing `MODULA_PERF` marks (firstFrame, bootstrapDone, gateReady, firstFeedRow) |

## How to measure

1. **Instruments, interactive:** Product → Profile (Release), and pick the *Time Profiler* template.
   Add *Points of Interest*, *Hitches* and *SwiftUI* (View Body / View Properties). Record a cold
   launch, then a 10 s Home scroll, opening a chat, opening and closing the sidebar 5×, and opening
   a sheet 5×. Read the signpost intervals in Points of Interest; check hitches against
   `SpatialSheet` and `SheetOpen` events.
2. **Command line, repeatable:**
   ```sh
   xcrun xctrace record --template 'Time Profiler' --instrument 'Points of Interest' \
     --device <udid> --launch -- /path/Modula.app --output launch.trace
   xcrun xctrace export --input launch.trace --xpath '/trace-toc/run/data/table[@schema="os-signpost"]'
   ```
3. **XCTest metrics, CI-friendly:** a UI test using `measure(metrics: [XCTApplicationLaunchMetric(),
   XCTOSSignpostMetric(subsystem: "digital.modula.app.native", category: "PointsOfInterest", name: "LaunchToFeed")])`
   and, for scrolling, `XCTOSSignpostMetric.scrollDecelerationMetric` with `XCTHitchMetric`. Run with
   `xcodebuild test -scheme Modula -destination 'id=<udid>' -only-testing:ModulaUITests/<PerfTests>`.
   That test isn't added here (it would need a new target file).
4. **Console:** `MODULA_PERF <mark> <ms>` lines still print (`devicectl device process launch --console`).
   Settings → About → Performance shows the last launch.

## Changes and expected wins

| Area | Change | Expected |
|---|---|---|
| Network | Identical concurrent GETs share one round trip (`GreenfieldClient.transfer`) | fewer duplicate requests at launch / tab switch |
| Network | Bodies > 32 KB decode off the client actor | parallel requests no longer queue behind a large feed decode |
| Network | `URLCache` 16 MB / 96 MB (server ETag / Cache-Control honoured); cleared on sign-out | 304s instead of full bodies where the server sends validators (none if it doesn't) |
| Launch | Duplicate quick-action refresh removed from the first-frame path | small |
| Feed | Following-author Set memoised on feed revision (was rebuilt every body pass) | less main-thread work per scroll-triggered body pass |
| Images | Size-aware memory cache, one tier per key (also fixes blurry upscaled reuse) | fewer wrong-size hits; sharp images |
| Video | `AVPlayerLayer` host instead of AVKit `VideoPlayer` in feed / reel cells | lighter cells, less view-graph work |
| Video | Attach no longer starts playback (`rate` → `defaultRate`) | off-screen neighbours stop decoding / playing audio |
| Video | 2.5 s forward buffer for streams | faster first frame on remote video |
| Sheets | Sidebar / profile sheet: material overlay with drag-driven opacity replaces a whole-app `.blur` | big cut in GPU / offscreen cost while dragging (check Hitches) |
| Glass | Opaque path automatically in Low Power Mode and serious / critical thermal state | stable frame rate when the device is constrained |
| Chat | Thread + capability probe together; pins / group / presence / call history in parallel | shorter `ChatOpen` on cold threads |
| Profile | First posts page and featured modules fetched in parallel | shorter profile settle |
| Reactions | Picker commits after 0.1 s instead of 0.28 s | snappier optimistic update |

## What to check after

- `Launch` / `LaunchToFeed` medians over 5 cold launches, before vs after.
- Hitch ratio (ms/s) during a 10 s Home fling, and during sidebar and profile-sheet drags.
- Count of `Request` intervals in the first 5 s after launch (coalescing should drop duplicates).
- Memory: the image cache stays inside 160 MB + 40 MB during a long feed scroll.
