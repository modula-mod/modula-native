# MOL-02 Stability Track: intermittent simulator crash with the 3D Moliboo preview open

Status: diagnosed, targeted fix in `fix/mol-01-3d-crash`. Verification is partial (see "Verification").

## Symptom
About 6 of 30 MOL-01 XCUITest launches crashed (EXC_BAD_ACCESS / SIGSEGV) on the main thread, usually
seconds after launching straight into the 3D preview (`-MOL01Scene`) or during the 20x Studio lifecycle
test (`-MOL01Studio`), once after about 28 s. Never seen on the physical (signed-in) iPhone.

## Symbolication (exact UUID match)
| Report | Faulting app frame | Resolved to |
|---|---|---|
| 2026-10-14-031414, 033307.000 | `__swift_closure_destructor.18` +0x279644 (via `destroy for AnyAccessibilityAction`) | context of **`OnboardingLandingView.continueButton` closure #1** |
| 2026-10-14-103538, 103201 (UUID FDDDFA39…, dd-mol02 build) | `__swift_closure_destructor.15` +0x278f10 (via `assignWithCopy for AddGestureModifier`) | context of **`OnboardingLandingView.dragGesture` closure #1** |
| 033307 | no app frame: `destroy for Image.Resolved` during `AG::Subgraph::invalidate_now` | SwiftUI graph teardown (same pattern) |
| 033638, 104839 | no app frame: CoreRE `MaterialBuilder` / `FunctionReflectionCache` dtor freeing Metal reflection objects | heap-corruption victim |
| 100338 | `objc_release` in `_dispatch_last_resort_autorelease_pool_pop` on a worker queue, poisoned pointer `0xbeadde…` | heap-corruption victim |

The addresses are freed-memory or PAC-poisoned values: an over-release / use-after-free.
`0x2795e8` and `0x278eb4` were looked up with `nm -n` in the matching `Modula.debug.dylib`.

## Root cause
The two crashes with app frames are both in **OnboardingLandingView**, not in the Moliboo3D code:
- Launch path: a signed-out simulator shows `PreShellAuthHost` → `OnboardingLandingView`. The MOL-01 debug
  harnesses (`MOL01DebugCover` / `MOL01StudioCover`) present the 3D preview or Studio as a `fullScreenCover`
  **over** the landing, so the landing stays alive and animating underneath for the whole test.
- The landing's whole body, including the `.gesture(dragGesture)`, the "Let's go" `Button` and the
  accessibility tree, was built inside `TimelineView(.animation)`. So new gesture and button closure
  contexts (capturing the view's `@State` / `@Environment` storage) were created and destroyed on every
  display-link tick, around 60–120 times a second, even while the landing was covered.
- With XCUITest's accessibility snapshots, the RealityKit load and the main-thread load from the 3D scene,
  SwiftUI sometimes releases one of these per-frame closure contexts after it has already been freed.
  The resulting heap corruption sometimes surfaces later in unrelated frees (Metal/CoreRE, autorelease pool).
  That explains the "different stacks, same teardown" pattern.
- The 3D preview is a bystander that raises load and timing pressure. On the phone the user is signed in,
  so the landing never exists underneath, which matches "never seen on device".

## What was ruled out or checked in Moliboo3D
- `SceneEvents.Update` subscription: retained in `frameSubscription`, `[weak controller]`, cancelled in `stop()`.
- The idle Task is `[weak self]` and cancelled. The short animation Tasks strongly capture the controller for up to about 1.2 s (harmless, no UAF).
- No `unowned` / `Unmanaged` / unsafe pointers in the feature.
- The test-instrumentation crash fixed earlier (dropped EventSubscription) is not involved.
- The prior ASan run (`asan.log`) reported no ASan diagnostic. The crash moved under ASan, which fits a timing-sensitive SwiftUI-internal over-release.

## Fix (targeted, no renderer changes)
`OnboardingLandingView`: only the drawn layers (backdrop, bubble stage) stay inside the per-frame
`TimelineView`s. The drag gesture, the button and the accessibility modifiers now sit outside, so their closures are
built only when state changes. Visuals and behaviour are unchanged (screenshot checked).

## Verification
New simulator `Crash-16Pro` (9F8B55ED…), separate derivedData `build/crash`.
| Run | Before (main) | After (fix) |
|---|---|---|
| Plain `simctl` launches, `-MOL01Scene front`, 12 s each | 0/30 crashes (551eafd) | 0/30 (460f427+fix, also `--uitest-skip-first-run -dev.moliboo.native3D YES`) |
| `testRealGeometryExpressionsAndClips` iterations | 0/10 (551eafd) | not rerun |
| `testStudioLifecycle20xMemoryLoadAndFrames` iterations | 0/6 (b11e922) | 6/6 passed, 0 crashes |

The crash did **not** reproduce on the fresh simulator before the fix. It reproduces on the long-lived,
heavily loaded `iPhone 16 Pro` (8AAF71C9…): the 20x lifecycle test crashed 2/2 there at b11e922. So the decisive
before/after comparison is to rerun the lifecycle test on 8AAF71C9 with this branch.

## Remaining risk
- The underlying over-release is inside SwiftUI. The fix removes the per-frame churn that exposed it, but it
  does not prove that SwiftUI can't do it elsewhere.
- Signed-out users who see the landing in production could in theory hit the same issue. The fix covers them too.
- Keep the 3D flag gated until the 8AAF71C9 rerun shows 0 crashes in at least 10 lifecycle iterations.

## Shared-simulator verification (8AAF71C9, branch at 83a3e98, 2026-10-14 11:42–12:20 BST): NOT CLEAN, PR not merged
- `testStudioLifecycle20xMemoryLoadAndFrames` x10: iterations 1–4 passed. **Iteration 5 crashed** after about 22 s, and the xcodebuild run stopped there.
  Report `Modula-2026-10-14-115200.ips`, from the same build as the fix (UUID 9E6F5B83…). The main thread hit EXC_BAD_ACCESS at 0x0:
  `0x0 ← CMClockGetAnchorTime ← figTimebaseGetMasterTime ← figTimebaseGetTime… ← re::TimebaseManager::beforeFrameUpdate ← re::Engine::executePhase ← re::DisplayLinkClock::update`.
  RealityKit is reading a CoreMedia timebase whose clock has already been freed or nulled. This is a second, RealityKit-side teardown defect
  (an animation-playback timebase that outlives its scene or entity during Studio open/close), separate from the onboarding closure churn.
- Full MOL-01 + MOL-02 UI suites, one run: 13/13 passed, no crash.
- Next: stop the animations (`stopAllAnimations`) and remove the entity graph from the scene before the RealityView goes away (`stop()`/`onDisappear`), and avoid starting a `playAnimation` after teardown. Then rerun the 10x test on 8AAF71C9.

## Round 2: teardown hardening (c97f9ca), shared sim 8AAF71C9, 12:10–12:50 BST: NOT CLEAN, PR not merged
Change: `stop()` now blocks new work (`isStopped`), cancels the queued animation tasks, stops every tracked
playback plus `stopAllAnimations` on the character, the cosmetics and the root, and detaches the root and camera from the scene.
Late `load`/`equip` results are dropped after stop, and the preview builds a fresh controller if it is shown again.

20x lifecycle, 10 separate runs (`test-without-building`): **5 passed, 5 failed**. 3 app crashes (iterations 1, 7, 9),
1 load failure (iteration 4: `failed=1`, so `Entity(contentsOf:)` threw), 1 lost connection to the test runner (iteration 6).
MOL-01 + MOL-02 UI suites: 13/13 passed.

App crash reports in this window:
- 121123, 122146: Metal `MTLStructType`/`MTLBufferBinding` dealloc ← CoreRE `FunctionReflectionResult` / `FunctionReflectionCache` dtor
  (← `MaterialBuilder` ← `MaterialAssetLoader::registerAsset` in earlier reports), with PAC-poisoned or protected addresses.
- 122520: SwiftUICore `destroy for Image.Resolved` ← `objc_release` at 0x420.
- 122106: inside XCTAutomationSupport `XCElementSnapshot recursivelyClearDataSource` in the app process (accessibility snapshot of a freed element).
The TimebaseManager stack did not recur, but the corruption signature (freed objects found during RealityKit material
registration and SwiftUI teardown) persists. Neither fix is sufficient.

Next hypotheses (not yet tested):
- Repeated material compilation for the same USDZ in a fresh RealityKit scene on every Studio open. Cache the loaded entity
  (`Entity(contentsOf:)` once per asset, `clone(recursive:)` per open) so `MaterialAssetLoader` does not re-register.
- Run the same 20x loop with 3D off, to confirm the SwiftUI/accessibility crashes need the 3D view at all.
- ASan/Zombies on the 8AAF71C9 loop.

## Round 3 (2026-10-14 12:40–13:55 BST, shared sim 8AAF71C9)
**3D-off isolation:** the same 21x Studio open/close loop, with the preview forced to the 2D fallback (temporary, uncommitted harness):
**5/5 clean, 0 crash reports.** The RealityView or 3D scene is required for the crash.

**ASan** (`-enableAddressSanitizer YES`, separate derivedData): 2 runs, 3 crashes. ASan printed **no** heap-use-after-free report.
It only caught deadly signals (in SwiftUICore `ContentResponderHelper.update`, `destroy for Image.Resolved`, and the Metal reflection dealloc).
So the bad free happens in uninstrumented system code (CoreRE/Metal/SwiftUI), not in app Swift code. Zombies were not run
(XCUITest launches don't inherit scheme env vars without a test-code change).

**Load-once cache** (676bbf1): `MolibooAssetLoader` keeps USDZ templates (cosmetics plus the 2 most recent characters, LRU, in-flight dedupe,
purged on memory warning) and returns `clone(recursive:)`. Works: cold load 1.1–1.6 s, warm loads **2–4 ms**,
footprint +12–16 MB over 21 opens (bounded).
But stability did not improve: 20x lifecycle, 10 separate runs: **4 passed, 6 failed** (5 app crashes, 1 assertion after the app was lost).
MOL-01 + MOL-02 suites: 11/13 passed. The lifecycle test and `testPipLoadsExpressesAnimatesAndWearsCap` failed in that run;
Pip passed in both earlier suite runs, so treat it as **flaky**.
Crash stacks this round: mostly SwiftUICore `destroy for Image.Resolved` → `objc_release` at 0x420 (AttributeGraph subgraph invalidation
in the display-link render). One CoreRE `MeshShadowSystemStateImpl::didDependentComponentChange` during `addChild` in `MolibooSceneController.load()`.

**Conclusion so far:** crashes need the 3D scene, are not in app-instrumented code, and survive teardown hardening and material caching.
The signature (freed objects in SwiftUI image teardown, Metal reflection, RealityKit ECS) points to memory corruption inside the
RealityKit/Metal simulator stack under rapid RealityView create/destroy. Not yet confirmed on a physical device.
Open options: (a) keep one long-lived RealityView/scene for the app session instead of creating one per Studio open;
(b) disable dynamic shadows (MeshShadowSystem appears in a stack); (c) run the 20x loop on the physical iPhone to tell a simulator-only defect from a product defect.
PR #32 stays unmerged.

## Round 4 (2026-10-14 13:55–14:45 BST, shared sim 8AAF71C9), progress notes
- **Shadows off** (`DynamicLightShadowComponent(castsShadow:false)` on every model; commit "EXPERIMENT: opt Moliboo models out of dynamic shadows"):
  20x lifecycle, 10 separate runs: **8 passed, 2 failed** (2 app crashes: SwiftUICore `destroy for Image.Resolved` at 0x420).
  Better than round 3 (4/10), but the sample is small. The Studio worker's simulator (F135…) logged the same Metal-reflection and
  CMClock-timebase crashes during this window, so the defect is not specific to this harness.
- **Long-lived single view** (`MolibooStage`: one non-AR `ARView` for the whole session, re-parented into each screen; the preview swaps
  `root`/`cameraEntity`; shadows off kept; commit 51898cf): renders correctly (screenshot checked). First 9 of 10 runs: **7 passed, 2 crashed**
  (`destroy for Image.Resolved`; Metal `MTLStructMember` dealloc ← CoreRE `FunctionReflectionResult` dtor). **No clear improvement**: the crash
  survives even with no RealityKit view/scene churn and with materials loaded only once.
- Interpretation: the remaining crashes do not come from Moliboo3D's lifecycle. They look like memory corruption in the simulator's Metal path,
  shared by RealityKit and SwiftUI rendering, and triggered only while a RealityKit renderer is active (3D-off loop: 5/5 clean).
  This has not been tested on a physical device (phone not available).

### MolibooStage API (for MolibooLivingStage)
```swift
MolibooStage.shared.show(controller)    // controller.root + cameraEntity become the stage content (replaces previous)
MolibooStage.shared.clear(controller)   // call from onDisappear; no-op if another controller is showing
MolibooStageView(controller: c)         // SwiftUI host; put gestures/overlays on it like RealityView
```
Frame timing is delivered to the shown controller (`recordFrame`). Grounding shadows are disabled.
**Status: experimental, kept on `fix/mol-01-3d-crash` only (not in PR A)**, because it did not show a stability gain.
