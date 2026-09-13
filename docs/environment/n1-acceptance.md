# Phase N1 acceptance — 2026-09-13

## Repository boundary

- Starting branch: `phase-n1-ios-native-foundation`
- Starting HEAD: `26d71cc`
- Starting unfinished work was preserved; no reset, rebase, archaeology repeat, or fixture reprovision occurred.
- Canonical Vault: `digital.modula.vault-notes`, immutable source tag/version `1.7.0`.
- React Native: `0.87.1`; Node major: 22; integration: CocoaPods and `RCTReactNativeFactory`.

## Authenticated host proof

The custom React Native Vault calls typed host actions. `ModulaBridge` validates bridge version, live native-issued ModuleSession, matching module identity, manifest capability, exact payload keys, declared collection, identifiers, and expected revision. `GreenfieldClient` then sends the URLSession request with credentials held in native memory/Keychain. JavaScript never selects an endpoint or header and receives only sanitized record data or structured safe errors.

Ten native tests pass, including valid, expired, foreign-module, logged-out, unmounted, malformed, URL-injection, cross-collection, invalid-revision, unknown-module, appearance, no-RN-launch, persistence, real Greenfield CRUD, and no-credential initial-property assertions. The real bridge integration listed the four fixture notes; rejected an invalid record safely; recovered; created, read, updated, re-read, deleted, and confirmed deletion; then rejected the unmounted session.

The final Release bundle is 1,285,492 bytes and includes `hermesvm.framework`. A binary scan found no `localhost:8081`, test-account identity, `accessToken`, `refreshToken`, or bearer-header marker. Runtime source contains no Vault `fetch`/Axios bypass.

## Vault and lifecycle proof

The Vault surface is genuine React Native UI with Notes List, New Note, Detail/Editor, loading, empty, loaded, saving, saved, and error states. It reuses the canonical 1.7.0 note/document types, schemas, validation, projection, IDs, and revision semantics while replacing the declarative presentation. Rich documents remain structurally intact; the modest N1 editor only rewrites paragraph-only notes.

Simulator acceptance proved real list/create/read/update/delete persistence through Swift, native Profile navigation, haptic requests on saves, live light/dark/OLED/accent propagation, background/foreground delivery, native Close and reopen, deleted-state persistence, and runtime initialization count one. The diagnostic module proved invalid-action rejection, render-exception containment, native failure UI, Retry with a replacement session, and native Profile routing. A missing runtime bundle is contained by native failure/Close UI. Ten Vault open/close cycles passed without additional runtime creation or a linear per-open memory climb.

Deliberate Greenfield transport loss produced `Greenfield connection unavailable.` inside Vault; native Close, Product Hub, and Profile remained operational. Invalid note IDs and backend errors are structured bridge failures. Stale asynchronous results are discarded after session revocation.

## Commands and evidence

Debug simulator suite, excluding the separately orchestrated transport-cut test:

```sh
xcodebuild -workspace ios/Modula.xcworkspace -scheme Modula -configuration Debug -destination 'platform=iOS Simulator,id=439E8DF1-EA4F-4028-98A0-32CA9469EAE0' -derivedDataPath artifacts/DerivedData -skip-testing:ModulaUITests/VaultNetworkFailureUITests test
```

Result: 10 native tests and 6 UI tests passed. Result bundle: `artifacts/DerivedData/Logs/Test/Test-Modula-2026.09.12_22-20-53-+0100.xcresult`.

The live transport-cut UI test passed separately with 1 test, 0 failures: `artifacts/DerivedData/Logs/Test/Test-Modula-2026.09.12_22-16-41-+0100.xcresult`.

Metro was stopped and no process listened on port 8081. The optimized Release-only acceptance scheme avoids weakening the production target with `ENABLE_TESTABILITY`:

```sh
xcodebuild -workspace ios/Modula.xcworkspace -scheme ModulaReleaseAcceptance -destination 'platform=iOS Simulator,id=439E8DF1-EA4F-4028-98A0-32CA9469EAE0' -derivedDataPath artifacts/DerivedDataRelease -only-testing:ModulaUITests/ReleaseVaultUITests/testBundledVaultCRUDAndNativeOwnership test
```

Result: bundled Release Vault loaded real records, created, read, updated, reloaded, deleted, confirmed persistence, and requested native Profile with Metro absent. Result bundle: `artifacts/DerivedDataRelease/Logs/Test/Test-ModulaReleaseAcceptance-2026.09.12_22-19-41-+0100.xcresult`.

TypeScript: 2 tests passed; typecheck and native/runtime boundary verification passed. `npm audit` reports eight high findings inherited through React Native/Metro's `image-size` chain. npm's offered remediation downgrades React Native to 0.86.3, which violates the pinned 0.87.1 architecture; there is no supported in-family fix in the resolved graph.

## Performance baseline

These are iPhone 17 Pro iOS 26.5 simulator Debug measurements. XCTest launch-to-navigation includes automation startup and is shown separately from the in-process native mark.

| Measurement | Result |
|---|---:|
| XCTest cold launch to native navigation | 4,571.8 ms |
| In-process native usable mark | 602.6 ms |
| Runtime factory setup | 0.3 ms |
| First Vault RN ready | 149.7 ms |
| First Vault data ready | 262.3 ms |
| Second Vault RN ready | 58.2 ms |
| UI-driven second open through loaded state | 3,371.8 ms |
| Ten UI-driven opens, mean | 3,358.8 ms |
| Ten UI-driven opens, min–max | 3,305.7–3,482.3 ms |
| Resident memory before RN initialization | 324.0 MB |
| Resident memory with Vault | 377.2 MB |
| Resident memory after the tenth close | 377.9 MB |
| Runtime initialization count after ten opens | 1 |

Simulator/test-runner overhead and allocator retention make these a comparative baseline, not physical-device production numbers. The 53.9 MB retained delta includes the intentionally resident shared RN/Hermes runtime. No evidence supports prewarming; strict lazy initialization remains the N1 decision.

## Physical device status

The paired iPhone 17 Pro Max built and signed with the existing Apple Development identity and provisioning profile. `devicectl` installed `digital.modula.app.native` and launched it successfully. Full UI acceptance remains **OPEN**: the phone runs iOS 27.0 while Xcode 26.6 has only the iOS 26.5 SDK/device support. Xcode launched the UI-test runner but could not determine the target app process and reported missing DeviceSupport; the device subsequently returned to unavailable. No tool upgrade was performed merely to force this gate. Re-run the ignored physical scheme when compatible device support is installed and the phone is available.

## Warning classification

- Modula source: none remaining in the accepted build.
- Modula configuration: the bundle script intentionally runs every build; this is a note, not a compiler warning.
- React Native/Hermes: Hermes bytecode compiler emits known undeclared web/devtools-global and direct-`eval` warnings from framework code.
- CocoaPods generated: Hermes replacement script has no declared outputs; RN dependency replacement/check scripts intentionally run each build.
- SDK/Xcode: AppIntents metadata skips because the app has no AppIntents dependency; iOS 26.5 Simulator reports duplicate WebCore/WebKit accessibility loader classes; device automation lacks iOS 27 DeviceSupport.

No generated Pod source was edited to hide dependency warnings.

## Verdict

**PASS**, with the explicitly permitted physical interaction gate open for device/Xcode availability. All native ownership, security, real-data, lifecycle, simulator, failure-containment, bundled Release, performance, warning, and documentation gates are closed. N2 and Android have not started.
