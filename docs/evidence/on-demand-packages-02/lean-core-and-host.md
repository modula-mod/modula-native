# On-demand packages 02: lean core and GameHost evidence

2026-10-24. This is feature-branch evidence, not release acceptance.

## Native Release size

An unsigned Release iPhone build of the `Modula` workspace succeeded with
`CODE_SIGNING_ALLOWED=NO` and `MODULA_INCLUDE_EXPERIMENTAL_NODUS` unset. The
build log reported `Nodus R7 experimental bundling disabled for Release`.

| Measurement | Earlier Release baseline | Package branch | Change |
| --- | ---: | ---: | ---: |
| App bundle (`du -sk`) | 188,456 KiB | 188,856 KiB | +400 KiB (+0.391 MiB) |
| Local compressed ZIP proxy | 62,672,384 bytes | 62,818,198 bytes | +145,814 bytes |

The new ZIP was made with `ditto -c -k --sequesterRsrc --keepParent`. The
earlier evidence does not record its compression command, so the ZIP change
is indicative rather than a controlled compression comparison. Neither ZIP
is an App Store download-size measurement. The new Release executable SHA-256
is `e4da90d106a59849cf467ea8fb618318db9b39f64facfc125dc546a909ea90b1`.

The built app bundle contains no `game.tgz`, `engine.mjs`, `model.safetensors`,
Phaser, PlayCanvas, or UnityFramework matching the bundle inventory scan.
The bundle growth accompanies the package UI, shared-runtime storage and
GameHost code; this measurement does not attribute individual bytes to a
single component.

## Focused simulator evidence

The iPhone 17 Pro Max iOS 26.3 simulator ran all four
`WebGameInstalledIsolationTests` successfully after the final GameHost
permission change. The live WKWebView test checked media, motion, location,
popup and prototype-call denial, off-origin script/network controls,
iframe blocking, cross-account origin isolation, synthetic-token access
denial and rollback. Its WebSocket probe uses a reachable local TCP listener
with a native positive control, then checks that game JavaScript makes no
connection.
The same suite also checked malformed archives, tampering and one-copy
runtime ownership with synthetic installations. This does not substitute for
signed QA installations of two independent Phaser games.

The optional Debug Nodus developer cache on this Mac did not match its
tracked manifest. Focused tests used
`MODULA_INCLUDE_EXPERIMENTAL_NODUS=0`, which is supported by the project's
development-model build script. No model bytes were copied into that test
build or the Release build.

## Open acceptance work

Signed QA package installation, a generated second Phaser game, actual
transfer/reclaim measurements, generic support for model and asset packages,
pause/resume, live signed-QA rollback, full device-permission matrix,
first-frame/FPS/memory measurements and physical iPhone acceptance remain
open. GameHost PR #99 must remain unmerged until its security gate passes.
