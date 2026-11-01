# perf/pass-1 — static performance findings (base: design/ui-pass-1)

Ranked by expected impact. [FIXED] = patched in this branch; others need Instruments or owner-stream changes.

1. **Very large single-file views (ModulaMascot 189KB, StoryViews 178KB, ProfileComponents 124KB, ProductHub 96KB, ImmersivePostCard 83KB, PostCommentsView 83KB, HomeView 54KB).** These mostly slow down compiles and type-checking. At runtime they matter only when one big `body` reads many observable properties, so any change re-evaluates the whole body. Fix: split into child `View` structs that take value inputs (owner streams, after their UI work lands). Check with `-Xfrontend -warn-long-function-bodies=200` and the SwiftUI Instruments "View Body" lane.
2. **Home feed recomputed the filtered list 3–4× per body pass** (`HomeStore.visiblePosts` = filter + `posts.resolved` map + display filter, O(n) each) and again inside every row's `onAppear` → `prefetchAhead` (O(n²) while scrolling). [FIXED: computed once per pass in `feedContent`.] Follow-up: memoize `visiblePosts` in HomeStore, or pass the index into `prefetchAhead`.
3. **Per-row cost in the feed:** `app.posts.resolved` + `ModulaPostMapper.map` run per row per pass, plus `.modulaEdgeFlow`, `.modulaScrollReveal` (scrollTransition), `onScrollVisibilityChange` and `GeometryReader` frame tracking for video rows (`onChange(of: frame(in: .global))` fires every scroll frame). Profile scroll hitches on device. Consider throttling `reportVisibility`, or switching to `onScrollVisibilityChange`.
4. **ModulaRadarScope ran a 60 fps Metal shader TimelineView even when off-screen or with the app inactive.** [FIXED: pauses using scenePhase and scroll visibility, the same rule as `ModulaEffectClock`.]
5. **ModulaImageTint had no in-flight de-duplication.** N avatars/headers for the same account each fetched and decoded the image. [FIXED: shared Task per cacheKey.]
6. **RootView ran `ModulaRuntimePreferences.apply()` on every `UserDefaults.didChangeNotification`** (any defaults write in the app), touching UIKit and walking every nav probe each time. [FIXED: no-op unless shakeToUndo or edgeSwipeBack changed.]
7. **Images have no disk cache.** `ModulaRemoteImage` has a good memory NSCache (260 items / 160MB), downsampling off-main and in-flight de-dupe. But every cold launch refetches all media over the network, and `URLSession.shared`'s URLCache is too small for 2000px media. Proposal: a protected-file disk cache keyed by cacheKey, purged on sign-out (privacy review needed, so not done blind).
8. **Feed images decode at up to 2000px** (≈16MB each), so the 160MB cache holds only ~10 feed images. Consider clamping to the rendered width × scale. Check with the Allocations instrument.
9. Minor: `DownloadedMediaIndex.read()` does a JSON decode plus disk IO on the caller's thread for each record/list. `ModulaPreferences.*` reads UserDefaults inside many `body`s. `ModulaImageTint.cache` and `ModulaImagePrefetcher.requested` are unbounded or crudely bounded.

Already good: GreenfieldClient is an actor, so JSON decoding is off-main. Home uses LazyVStack. Mascot ambient background and ModulaEffectClock pause off-screen.

## Needs on-device Instruments
SwiftUI View Body/Updates on the Home scroll; Time Profiler on cold launch (RootView `.task` runs catalogue load, then profile, then avatar, then Spotlight serially); Allocations for image memory; Core Animation FPS with stacked materials and glass in PostContentRenderer overlays and ModulaGlass.
