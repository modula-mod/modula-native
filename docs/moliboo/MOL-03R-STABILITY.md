# MOL-03R — Shared RealityKit Stability Audit

## Lifecycle & Concurrency Protections Verified
1. **No Duplicate Scene Creation**: `MolibooLivingStudioView.setUp()` guards `guard controller == nil else { return }`.
2. **Stale Animation & Subscription Cleanup**: `MolibooSceneController.stop()` cancels `idleTask`, all queued `animationTasks`, all `AnimationPlaybackController` handles, stops recursive animations on `equipped`, `character`, and `root`, cancels `frameSubscription`, and detaches `root` and `cameraEntity`.
3. **Async Load Cancellation**: Both `MolibooSceneController.load()` and `equip(wardrobeItemID:)` re-check `guard !isStopped, !Task.isCancelled` after `await` before mutating the scene graph.
4. **Swift 6 `@MainActor` Isolation**: `MolibooSceneController`, `MolibooStudioDirector`, `MolibooWardrobeRig`, `MolibooWardrobeSession`, `MolibooAssetLoader`, and `MolibooWardrobeAssetCache` are strictly `@MainActor`-isolated; `SceneEvents.Update` callbacks hop via `MainActor.assumeIsolated`.
5. **Background / Foreground Handling**: `MolibooLivingStudioView` pauses `MolibooStudioDirector` when `scenePhase != .active`; `MolibooWorldView` calls `stage.sleepNow()` on backgrounding and `stage.wake(...)` on return to `.active`.
6. **Memory Warning Recovery**: `MolibooAssetLoader` purges cached templates on `UIApplication.didReceiveMemoryWarningNotification` while live clones retain their own resources safely.
