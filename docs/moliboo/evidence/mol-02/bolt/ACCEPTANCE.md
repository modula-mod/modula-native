# MOL-02 Milestone D — Bolt (#014) acceptance evidence

Simulator: iPhone 16 Pro, iOS 18.2 (8AAF71C9). Date: 2026-10-14.

- Asset: Bolt.usdz sha256 7565bb3e3f5aad138313c615f254b2b14b7426e98131c95b4d93b33951a54ec3, bolt-v1.0, correction pass 1 (final).
  Graphite rounded-box robot: dark inset screen with emissive cyan pixel eyes/mouth, antenna with glowing teal tip,
  teal hex side bolts (joints), teal seam line, teal feet. Personality: antenna_flash (20f), servo_tilt (30f).
  Pass 0 → 1: body darkened from light grey to graphite, antenna moved right so it clears the cap, cap anchor shifted left, feet moved out.
- Run 1 (full set):
  - Test Case '-[ModulaTests.MOL01Tests testFlagDefaultMatchesBuildAndOverrideWins]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testHatPartyUnchanged]' passed (0.011 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testIncompatibleConfigFlagIsRespected]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testLegacyOutfitsStillDecode]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testManifestCoversAll25OriginalsAndOnlyBuiltCharactersAreCompatible]' passed (0.004 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testOutfitPersistenceRoundTripWithSignatureCap]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testPebbleLoadsAnimatesAndWearsCap]' passed (8.271 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testRejectsUnknownSchema]' passed (0.003 seconds).
  - Test Case '-[ModulaTests.MOL01Tests testSignatureCapExistsAsCommonFreeHat]' passed (0.002 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testBoltManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testBoltRobotPartsLoadAnimateAndWearCap]' passed (3.457 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMissingAssetFailsLoadInsteadOfFallingBackToPebble]' passed (0.239 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMossLoadsAnimatesExpressesAndWearsCap]' passed (2.958 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testMossManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipLoadsAnimatesExpressesAndWearsCap]' passed (5.185 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testPipManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testRegistryIsGenericAndRequiresBundledAsset]' passed (0.001 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testTofuIsACubeLoadsSquashesAndWearsCap]' passed (4.571 seconds).
  - Test Case '-[ModulaTests.MOL02Tests testTofuManifestEntry]' passed (0.001 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testCapEquipRemoveAndRestoreAcrossRelaunch]' passed (24.648 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testFlagOffShows2DStudioOnlyAndFlagOnOffers3D]' passed (15.226 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRealGeometryExpressionsAndClips]' passed (32.573 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testRotationAndTapGestures]' passed (13.374 seconds).
  - Test Case '-[ModulaUITests.MOL01AcceptanceUITests testStudioLifecycle20xMemoryLoadAndFrames]' passed (147.391 seconds).
  - Test Case '-[ModulaUITests.MOL02BoltAcceptanceUITests testBoltLoadsExpressesAnimatesAndWearsCap]' passed (37.521 seconds).
  - Test Case '-[ModulaUITests.MOL02BoltAcceptanceUITests testStudioOffersBoltIn3DWithFlag]' passed (9.916 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testMossLoadsExpressesAnimatesAndWearsCap]' passed (37.004 seconds).
  - Test Case '-[ModulaUITests.MOL02MossAcceptanceUITests testStudioOffersMossIn3DWithFlag]' passed (9.668 seconds).
  - <unknown>:0: error: -[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap] : digital.modula.app.native crashed
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap]' failed (39.115 seconds).
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testStudioOffersPipIn3DOnlyWithFlagAndNimbusStays2D]' passed (21.778 seconds).
  - Test Case '-[ModulaUITests.MOL02TofuAcceptanceUITests testStudioOffersTofuIn3DWithFlag]' passed (9.691 seconds).
  - Test Case '-[ModulaUITests.MOL02TofuAcceptanceUITests testTofuLoadsExpressesAnimatesAndWearsCap]' passed (37.779 seconds).
- Pip cap test crash: known intermittent sim crash, different stack this time (EXC_BAD_ACCESS objc_release in Metal type
  dealloc; report Modula-2026-10-14-104839.ips). Rerun 1 failed on an XCTest interruption ("Happy" button invalid after
  interruption handling, likely the post-crash system alert); rerun 2:
  - Test Case '-[ModulaUITests.MOL02PipAcceptanceUITests testPipLoadsExpressesAnimatesAndWearsCap]' passed (40.130 seconds).
