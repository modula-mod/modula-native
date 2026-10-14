# MOL-02 Milestone A — Pip (#001) acceptance evidence

Simulator: iPhone 16 Pro, iOS 18.2 (8AAF71C9). Date: 2026-10-14.

- Asset: Pip.usdz sha256 2c6a54a9a8b6bc690f41bb9afe1355ec30d73b3cf752b73b6a6f5ad9644a08ef, sourceVersion pip-v1.0,
  correction pass 1 (final). Review sheet: Pip_review_sheet.png (7 expressions × 3 views, rear, cap off/on/close-up).
- Unit (ModulaTests): MOL02Tests 4/4 passed, MOL01Tests 9/9 passed (regression), 13/13 total.
  - Test Case '-[ModulaTests.MOL01Tests testFlagDefaultMatchesBuildAndOverrideWins]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testHatPartyUnchanged]' passed (0.010 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testIncompatibleConfigFlagIsRespected]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testLegacyOutfitsStillDecode]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testManifestCoversAll25OriginalsAndOnlyBuiltCharactersAreCompatible]' passed (0.005 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testOutfitPersistenceRoundTripWithSignatureCap]' passed (0.005 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testPebbleLoadsAnimatesAndWearsCap]' passed (7.070 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testRejectsUnknownSchema]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testSignatureCapExistsAsCommonFreeHat]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMissingAssetFailsLoadInsteadOfFallingBackToPebble]' passed (0.177 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipLoadsAnimatesExpressesAndWearsCap]' passed (3.879 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testRegistryIsGenericAndRequiresBundledAsset]' passed (0.001 seconds).
- UI (ModulaUITests): MOL02PipAcceptanceUITests 2/2 passed; MOL01 regression subset 3/3 passed.
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testCapEquipRemoveAndRestoreAcrossRelaunch]' passed (25.564 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testFlagOffShows2DStudioOnlyAndFlagOnOffers3D]' passed (19.966 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRealGeometryExpressionsAndClips]' passed (30.884 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap]' passed (34.351 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testStudioOffersPipIn3DOnlyWithFlagAndMossStays2D]' passed (23.677 seconds).

Covered: Pip loads (not Pebble), ≥10 meshes, baked clips; all expressions play baked expr_* clips; wobble/bounce/tap-react;
Signature Cap on/off at anchor_head; Studio shows 3D entry for Pip only with dev flag; Moss (no asset) stays 2D with no
Pebble substitute; missing asset ⇒ load fails ⇒ 2D fallback.
Not covered (by user override / out of scope): screenshots, video, stress; intermittent MOL-01 sim crash is owned by the crash worker.
