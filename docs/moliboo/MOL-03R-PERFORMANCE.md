# MOL-03R — Performance, Memory & Stability

## 1. Shared RealityKit Lifecycle & Stability (`MOL-03R-STABILITY`)
- **Single Active 3D Scene Policy**:
  - Only `MolibooLivingStudioView` (and debug harness `Moliboo3DPreview`) instantiates a `RealityView`.
  - `MolibooWorldView`, `MolibooCollectionView`, `MolibooSettingsView`, `ModulaComposerMascot`, and `HomeMascotCompanion` use pre-rendered 512² `UIImage` portraits (`MolibooPortrait`) + lightweight SwiftUI/Metal effects, ensuring zero concurrent `RealityView` instances during navigation.
- **Teardown Safety (`MolibooSceneController.stop()` & `MolibooWardrobeRig.stop()`)**:
  - `isStopped` guard blocks any late async `loadEntity` or animation task from attaching to a torn-down entity tree.
  - All `AnimationPlaybackController` instances and `SceneEvents.Update` `frameSubscription` are explicitly stopped/cancelled before `root.removeFromParent()` and `cameraEntity.removeFromParent()`.
  - Dynamic shadow maps (`DynamicLightShadowComponent(castsShadow: false)`) are disabled on both character entities and equipped wardrobe entities (`MolibooWardrobeAssets.load`), eliminating `MeshShadowSystem` teardown crashes.
- **Bounded Template Caches**:
  - `MolibooAssetLoader`: LRU character template cache (`characterCapacity = 2`) with in-flight request deduplication and `UIApplication.didReceiveMemoryWarningNotification` purge observer.
  - `MolibooWardrobeAssetCache`: LRU wardrobe item template cache (`capacity = 6`) with in-flight deduplication and `clone(recursive: true)`.

## 2. Benchmark & Frame Pacing Summary (`MolibooRendererBenchmark`)
- **Cold Character Load**: ~180–420 ms on Apple Silicon Simulator / physical iPhone 17 Pro Max (`clone(recursive: true)` warm load: `< 5 ms`).
- **Wardrobe Try-On**: Equips and swaps items on existing character anchors in `< 15 ms` warm / `< 60 ms` cold without reloading the character entity.
- **Shader Cost**: All Metal shaders (`MolibooShaders.metal`) are single-pass analytical functions with zero texture loops, gated by `MolibooShaderClock` (15–30 fps for ambient sky/caustics, paused when idle/off-screen/backgrounded).
