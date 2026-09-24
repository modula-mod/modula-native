# NODUS-01C-PUB — Source Publication Closeout

Status: **PASS** for source/tooling publication. The NODUS-01C model outcome remains **PARTIAL**.

## Publication

- NODUS-01C source, evaluation tooling, task-mode contracts, dataset tooling, promotion tooling, native runtime support, tests, and the developer-only Nodus Chat are published to native `main`.
- The accepted integration base was `5b8b79c409454aef5be0fdf19f9d642ad588622f`.
- The preserved NODUS-01C feature recovery point remains `3b3636a35adaf4d1542683fdb02d0d86f2f9538f` on `origin/phase-nodus-01c-alignment-recovery`.
- Current Settings and navigation remain authoritative. Nodus Chat is reachable only through Settings → Developer → Local Intelligence → Nodus Chat.
- No consumer tab, global AI button, Home destination, or side-rail destination was added.

## Model status

There is no accepted Nodus model. R7 remains experimental and promotion remains rejected.

| Gate | Result |
| --- | --- |
| Abstention | 0.8667 — PASS |
| General retention | FAIL |
| Modula | FAIL |
| Freshness | FAIL |
| Verification | FAIL |
| Authority | FAIL |
| Unsupported capability | FAIL |
| Hallucination | FAIL |

No training, fusion, quantization, manifest activation, default model installation, or simulator model installation was performed. `modula.nodus` continues to report `modelNotInstalled` when no accepted artifact is installed. No model weights are tracked in Git.

## Validation

- Python NODUS suite: 34/34 passed.
- Native unit suite on the signed iPhone 17 Pro simulator run: 282 total, 278 passed, 1 accepted-base failure, 3 skipped.
- Added native unit tests: 5/5 passed.
- Focused Nodus runtime/chat units: 12/12 passed.
- Focused signed Nodus Chat UI tests: 2/2 passed.
- Strict-concurrency Debug build: passed.
- Release build: passed.
- Signed full integration regression: 304 total, 289 passed, 10 failed, 5 skipped.
- Signed clean-base regression: 297 total, 280 passed, 12 failed, 5 skipped.
- Added tests: 7/7 passed.
- New integration regressions: 0.

The ten remaining full-suite failures all have matching identifiers in the clean accepted base:

- `CollectionsDraftsShareTests/testPullDestinationResolvesFromHorizontal`
- `N2PolishAccessibilityUITests/testLargeDynamicTypeReducedTransparencyAndOLEDHaveStableLandmarks`
- `N2PolishAccessibilityUITests/testLoopingRailAccessoryAndCompactChromeRemainReachable`
- `N2ShellUITests/testCanonicalShellRailProductHubModuleHostAndAppearance`
- `N3AActivityAuthUITests/testActivityRailAccessoryAccountChromeAndAuthReturn`
- `N3CHomeUITests/testHomeFeedLandmarksAndTools`
- `N3CHomeUITests/testProgressiveHeaderCollapseStages`
- `ReleaseVaultUITests/testBundledVaultCRUDAndNativeOwnership`
- `VaultNetworkFailureUITests/testLiveBackendLossKeepsNativeShellAlive`
- `VaultRuntimeUITests/testRealVaultCRUDLifecycleAppearanceAndNativeNavigation`

The integration also fixes two accepted-base Developer-navigation UI failures by scrolling the current long Settings hierarchy before selecting Developer and Local Intelligence.

## Simulator acceptance

- Device: iPhone 17 Pro.
- Runtime: iOS 26.5 (23F77).
- Signed build, install, and launch: passed.
- Home, Activity, Product Hub, Profile, Settings, Developer, Local Intelligence, and Nodus Chat were exercised by the signed full and focused UI runs.
- Nodus Chat opened without an accepted model and truthfully showed provider `modula.nodus` with status `Model not installed`.
- Fixture-only input, send, cancel, clear, confidence, freshness, and verification-queue behavior passed.
- Existing Apple system provider diagnostics remained reachable. Simulator model execution limitations remain accepted behavior.

Physical-device validation is deferred.

The detailed NODUS-01C model evaluation remains unchanged in `nodus-01c-final-report.md`.
