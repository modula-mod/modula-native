# Signed QA registry simulator acceptance

The simulator PNGs here are XCTest screenshots from the iPhone 17 Pro Max simulator,
running the same generic `WebGameHost` in Modula Native. They are not desktop
browser captures. The QA registry is restricted to a separate account and
database; the games were installed through the Native permission review and
verified artifact download flow.

| Game | Initial signed package SHA-256 | Updated signed package SHA-256 | Visible update |
| --- | --- | --- | --- |
| Orbit Arena 2D (Phaser) | `0d2773e7f59a4d238e30bf05b5db0339b3fd9ad54d453d76b045749226ae4cc8` | `e33f2cdc41e68ec2a5a02e5c171836c7142dc78ac7a8194bfdb3c4f084176c75` | NOVA arena palette and obstacle pattern |
| Orbit Arena 3D Web (PlayCanvas) | `8495557ba122e547fec9a6170911d57b1f15bab7b04e1661b4d04ffc61186494` | `b82624066e8903dfe4d460fffade919be2ea809bc3d11eb9ca123fd08ac6053b` | Purple 3D arena and orange obstacles |

The installed Modula executable was SHA-256
`0a9484ac0f5b5f51b5ecf046fa036f370487b15e8a146f97f1d089874642ac63`
for both the 0.1.0 installs and the 0.1.1 updates. The update test used
`xcodebuild test-without-building`; no Native rebuild occurred between releases.
`WebGameRegistryUITests.testInstallBothSignedRegistryGames` and
`testUpdateBothRegistryGamesInSameBinary` passed. After the test, the QA API
reported both installations `enabled` at 0.1.1 with permission review clear.

The compressed game archives were 355,189 and 355,182 bytes for Phaser 0.1.0
and 0.1.1, and 276,706 and 276,779 bytes for PlayCanvas 0.1.0 and 0.1.1.
The simulator's 0.1.1 ACTIVE slots occupied 1,720 KiB (Phaser) and 1,344 KiB
(PlayCanvas), including the archive, extracted content, and metadata. Each
0.1.0 PREVIOUS_GOOD slot was retained at the same corresponding size.

The signer was `modula-game-platform-02-qa`, public key fingerprint
`sha256:2337f823a608c91d5970383462801b23322963246b9e5be0bceb5d219f437d73`.
The private test key stays outside this repository and outside production
signing custody. Production registry and production user data were not changed.

`WebGameRegistryUITests.testPlayBothInstalledRegistryGamesThroughRoundCompletion`
also passed in 192.158 seconds with the host's CSP response policy enabled.
The six additional simulator captures show touch movement, round completion,
and restart for each engine. Both round-complete frames show a score of 10;
the restart frames show score 0 and a fresh 60-second timer. The test exercised
host pause/resume, PlayCanvas in-game pause/resume, exit, and game switching.
After merging Native main through `15e24e1`, the same live QA gameplay test
passed again in 193.271 seconds. The account-bound offline restore unit test
also passed on that merged build.

`WebGameRegistryUITests.testInstalledRegistryGamesLaunchWithAppTransportIsolated`
passed in 179.801 seconds after a force quit and cold relaunch with the app's
API transport denied. The four `*-isolated-*-simulator.png` captures show both
verified cached games loading and completing a round with score 10. Native used
an account-bound keychain record to restore local cache access only while the
session's refresh token remained valid. The Product Hub restored only games
whose ACTIVE package bytes reverified under that account; registry install,
update, and revocation decisions remained unavailable while isolated. This
proves app transport isolation, not full device offline operation: the simulator
still had network connectivity outside the injected application transport.

The paired physical iPhone 17 Pro Max received a signed Debug build under the
existing `digital.modula.app.native.qa` bundle ID. The build used the QA API URL
`https://192.168.4.21:8443`, was signed by team `M29V4ZGUNK`, installed in
place, and launched to the Modula onboarding screen; `physical-qa-app-launch.png`
is the device screenshot. The app executable SHA-256 was
`cdc2b9af6f50ff6385710e34087a17f85834359addb4070e4bd969169395068f`.
The iPhone later became unavailable to Xcode, and the QA certificate profile
still required completion in iOS Settings. No game was installed or played on
that physical device, so physical gameplay remains deferred.

True device offline, physical game acceptance, and the game-specific rollback
matrix require separate evidence.
