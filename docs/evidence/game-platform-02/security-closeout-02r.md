# GAME-PLATFORM-02R Native validation

On 2026-10-23, Xcode 27.1 built the GameHost on an iOS Simulator and ran
`ModulaTests/WebGameInstalledIsolationTests`: 3 tests passed, 0 failed. The
latest result is `Test-Modula-2026.10.23_15-48-33-+0100.xcresult` in the
task's temporary DerivedData directory. The tests exercise the actual
`VerifiedGameSchemeHandler` through a Debug-only probe. A listed digest
resource is served with the expected bytes and host CSP response. Parent
paths, encoded paths, another digest, query URLs, `file://` and `https://`
requests fail the handler's response path. The same test loads the verified
minimal package in a simulator WKWebView for both module identities. The page
has no Native message handlers or game-origin cookies; a loopback fetch
produces a `connect-src` violation and an external script produces a
`script-src` violation. This checks browser enforcement of
the host CSP without putting tokens in the fixture or contacting an external
asset host.
Xcode stalled in a macOS file-coordination read when opening the source
workspace under Documents, so the latest run used a temporary local copy;
`cmp` confirmed the GameHost and test source files matched the branch.
The parser rejects traversal, links, native payloads, case-colliding members,
truncated gzip and wrong digests. Installed assets reject symlinks, modified
bytes and unexpected files. Both game identities retain ACTIVE after
rejected staging and restore PREVIOUS_GOOD after a synthetic activation
failure, including the persisted audit reason.

The generic host now shows the game name, a generic game icon, verified-package state,
WebKit estimated navigation progress, and an Exit action while loading. It
transitions to gameplay when WebKit finishes the document navigation. This
progress is not a first-playable-frame measurement. After this presentation
change, `WebGameRegistryUITests/testPlayBothInstalledRegistryGamesThroughRoundCompletion`
passed on the iPhone 17 Pro Max simulator (iOS 26.3.1) against the restricted
signed QA registry. It opened the installed Phaser and PlayCanvas releases,
exercised touch and host pause/resume, completed a round in each game,
restarted each, and returned to Modula. The result bundle is
`Test-Modula-2026.10.23_21-36-10-+0100.xcresult` (1 passed, 0 failed);
the task evidence directory contains its exported round-complete screenshots.
The Mac reached the QA API through a temporary SSH tunnel and a known local
QA TLS proxy. This was a simulator run; it did not establish physical GPU,
audio, or thermal acceptance. An earlier attempt encountered an intermittent
simulator `AURemoteIO::Cleanup` crash before game presentation; the clean
rerun above passed. The crash remains a simulator reliability observation,
not an established GameHost fault.
The host also returns `.deny` from WebKit's media-capture, device-motion, and
(on iOS 27+) geolocation permission callbacks. The focused Swift suite was
rebuilt after that source change and passed 3/3 in
`Test-Modula-2026.10.23_21-42-58-+0100.xcresult`. The preceding live-game
UI run used the same host presentation but predates these permission callbacks.

`WebGameRegistryUITests/testInstalledRegistryGamesLaunchWithAppTransportIsolated`
also passed (1/1) in `Test-Modula-2026.10.23_21-39-44-+0100.xcresult`.
It completed a cached round in each game while the app's registry transport
was isolated. This is `APP_TRANSPORT_OFFLINE` evidence only. It does not show
that all simulator radios or external WebKit network paths were disabled;
`FULL_DEVICE_OFFLINE` still needs a physical Airplane Mode run.

Reproduce on a Mac with Xcode 27.1, Node 22, CocoaPods and an available
iOS Simulator:

```sh
npm ci
(cd ios && pod install)
npm run verify:boundary
npm run verify:design
npm run typecheck
npm test
xcodebuild test -workspace ios/Modula.xcworkspace -scheme Modula \
  -configuration Debug -destination 'platform=iOS Simulator,id=<available UDID>' \
  -only-testing:ModulaTests/WebGameInstalledIsolationTests CODE_SIGNING_ALLOWED=NO
```

The new `native-boundaries.yml` workflow covers the Node and source-boundary
steps. GitHub CI does not yet run Xcode or a physical device. The Swift and
signed QA simulator tests above remain mandatory manual gates for this PR.
Iframe and popup behavior,
real signed-release rollback, full-device offline operation, first playable
frame performance, and physical iPhone GPU/audio/thermal acceptance remain
unverified. The older QA registry README records the existing simulator gameplay and
app-transport-isolated evidence; these scopes must not be conflated.

Size audit: a fresh **Debug simulator** build measured 1,622,908 KiB. The
Debug build script copied a verified Nodus model from the local developer
cache into the app (947 MiB `Nodus/`, including a 923 MiB model file), and
the debug dylib occupied 435 MiB. This is not a production download-size
measurement. Native main PR #167 removed the Xcode Release override that
forced that experimental model into Release.

A fresh **unsigned Release iPhone** build after that fix occupied 188,456 KiB
as an app bundle. A local ZIP of that bundle was 62,672,384 bytes. This ZIP
is a compression proxy, not an App Store download or signed IPA. The build
reported `Nodus R7 experimental bundling disabled for Release`; neither
`model.safetensors` nor `game.tgz` was present in the app. The Release
executable SHA-256 was
`07c27f2ac44300e182902e7e8a2a147c3656a90f09b2c6590738ed12f82bb160`.
The simulator test app's data container occupied 35,600 KiB, separate from
the app bundle; it includes test/runtime data and is not a clean optional
package baseline. Signed distribution and a fresh-install data container
still need measurement.
