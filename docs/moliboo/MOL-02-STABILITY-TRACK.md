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
