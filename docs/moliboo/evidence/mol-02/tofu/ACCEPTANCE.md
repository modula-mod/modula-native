# MOL-02 Milestone C — Tofu (#011) acceptance evidence

Simulator: iPhone 16 Pro, iOS 18.2 (8AAF71C9). Date: 2026-10-14.

- Asset: Tofu.usdz sha256 dfcca4619f22d33bdf60f13eb44eb33df663927abc20109aa15b16a494834823, tofu-v1.0, correction pass 1 (final).
  Rounded cube (cube generator, bevel 16 mm, pillowy faces) — stays cube-shaped in every view; unit test checks side ratio < 1.35.
  Pass 0 → 1: feet moved out so they are visible, slightly warmer cream, bigger eyes/cheeks, cap seated lower at full scale.
  Personality: cube_squash (30f squash/stretch), exuberant_bounce (32f), plus shared wobble/tap.
- Run 1 (full set):
  - Test Case '-[ModulaTests.MOL01Tests testFlagDefaultMatchesBuildAndOverrideWins]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testHatPartyUnchanged]' passed (0.013 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testIncompatibleConfigFlagIsRespected]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testLegacyOutfitsStillDecode]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testManifestCoversAll25OriginalsAndOnlyBuiltCharactersAreCompatible]' passed (0.005 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testOutfitPersistenceRoundTripWithSignatureCap]' passed (0.004 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testPebbleLoadsAnimatesAndWearsCap]' passed (6.745 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testRejectsUnknownSchema]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testSignatureCapExistsAsCommonFreeHat]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMissingAssetFailsLoadInsteadOfFallingBackToPebble]' passed (0.270 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMossLoadsAnimatesExpressesAndWearsCap]' passed (3.315 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMossManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipLoadsAnimatesExpressesAndWearsCap]' passed (3.466 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testRegistryIsGenericAndRequiresBundledAsset]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testTofuIsACubeLoadsSquashesAndWearsCap]' passed (3.753 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testTofuManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testCapEquipRemoveAndRestoreAcrossRelaunch]' passed (23.513 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testFlagOffShows2DStudioOnlyAndFlagOnOffers3D]' passed (14.946 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRealGeometryExpressionsAndClips]' passed (33.216 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRotationAndTapGestures]' passed (14.395 seconds).
  - <unknown>:0: error: -[ModulaUITests.MOL01AcceptanceUITests testStudioLifecycle20xMemoryLoadAndFrames] : digital.modula.app.native crashed
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testStudioLifecycle20xMemoryLoadAndFrames]' failed (13.846 seconds).
  - <unknown>:0: error: -[ModulaUITests.MOL02MossAcceptanceUITests testMossLoadsExpressesAnimatesAndWearsCap] : digital.modula.app.native crashed
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testMossLoadsExpressesAnimatesAndWearsCap]' failed (17.992 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testStudioOffersMossIn3DWithFlag]' passed (9.024 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap]' passed (36.687 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testStudioOffersPipIn3DOnlyWithFlagAndBoltStays2D]' passed (23.324 seconds).
  - Test Case '-[ModulaUITests.MOL02TofuAcceptanceUITests testStudioOffersTofuIn3DWithFlag]' passed (10.431 seconds).
  - Test Case '-[ModulaUITests.MOL02TofuAcceptanceUITests testTofuLoadsExpressesAnimatesAndWearsCap]' passed (37.041 seconds).
- Run 2 (rerun of the 2 crashed tests):
  - <unknown>:0: error: -[ModulaUITests.MOL01AcceptanceUITests testStudioLifecycle20xMemoryLoadAndFrames] : digital.modula.app.native crashed
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testStudioLifecycle20xMemoryLoadAndFrames]' failed (68.347 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testMossLoadsExpressesAnimatesAndWearsCap]' passed (36.751 seconds).
- Crash analysis: all crashes are the known intermittent MOL-01 simulator crash (EXC_BAD_ACCESS in
  __swift_closure_destructor during SwiftUI AddGestureModifier teardown; report Modula-2026-10-14-103538.ips).
  The 20x lifecycle test only opens Pebble; Tofu's code path is not involved. Owned by fix/mol-01-3d-crash.
  The 20x lifecycle test passed in Milestone B (148 s) but crashed twice here: the crash is intermittent and NOT fixed.
