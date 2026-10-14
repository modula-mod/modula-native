# MOL-02 Milestone B — Moss (#002) acceptance evidence

Simulator: iPhone 16 Pro, iOS 18.2 (8AAF71C9). Date: 2026-10-14.

- Asset: Moss.usdz sha256 9bb82d67d154d166f3e478ebb1d9de5525e1206ed13ef93174fff3c3828225cd, moss-v1.0, correction pass 1 (final).
  Pass 0 → 1 (single consolidated pass): eyes moved up onto the raised eye domes, greener palette/feet, cap raised and tilted.
  Personality clips: slow_blink (40f), cheek_puff (36f, cheek blend shape), measured_hop (32f: anticipation squash → hop → landing squash).
- Run 1 (full set):
  - Test Case '-[ModulaTests.MOL01Tests testFlagDefaultMatchesBuildAndOverrideWins]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testHatPartyUnchanged]' passed (0.010 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testIncompatibleConfigFlagIsRespected]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testLegacyOutfitsStillDecode]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testManifestCoversAll25OriginalsAndOnlyBuiltCharactersAreCompatible]' passed (0.004 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testOutfitPersistenceRoundTripWithSignatureCap]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testPebbleLoadsAnimatesAndWearsCap]' passed (6.233 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testRejectsUnknownSchema]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testSignatureCapExistsAsCommonFreeHat]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMissingAssetFailsLoadInsteadOfFallingBackToPebble]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMossLoadsAnimatesExpressesAndWearsCap]' passed (3.869 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMossManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipLoadsAnimatesExpressesAndWearsCap]' passed (4.655 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testRegistryIsGenericAndRequiresBundledAsset]' passed (0.001 seconds).
  - <unknown>:0: error: -[ModulaUITests.MOL01AcceptanceUITests testCapEquipRemoveAndRestoreAcrossRelaunch] : digital.modula.app.native crashed
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testCapEquipRemoveAndRestoreAcrossRelaunch]' failed (26.206 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testFlagOffShows2DStudioOnlyAndFlagOnOffers3D]' passed (21.420 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRealGeometryExpressionsAndClips]' passed (32.318 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRotationAndTapGestures]' passed (14.056 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testStudioLifecycle20xMemoryLoadAndFrames]' passed (148.136 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testMossLoadsExpressesAnimatesAndWearsCap]' failed (44.974 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testStudioOffersMossIn3DWithFlag]' passed (8.793 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap]' failed (42.009 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testStudioOffersPipIn3DOnlyWithFlagAndTofuStays2D]' passed (22.082 seconds).
- Run 1 analysis: MOL01 cap test hit the known intermittent simulator crash (owned by the crash worker, fix/mol-01-3d-crash)
  after saving the cap, which left saved=1; the two MOL-02 cap checks assumed cap starts off and failed on that leaked state.
  Fix: MOL-02 cap checks now round-trip from the restored state.
- Run 2 (rerun of the 3 affected tests after the fix):
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testCapEquipRemoveAndRestoreAcrossRelaunch]' passed (28.074 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testMossLoadsExpressesAnimatesAndWearsCap]' passed (37.730 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap]' passed (38.743 seconds).
