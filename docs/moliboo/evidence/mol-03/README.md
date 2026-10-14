# MOL-03 Workstream A — Living Studio evidence

All behind `dev.moliboo.native3D`. Simulator: iPhone 16 Pro Max (F135986B), Debug build.
Screenshots are real `simctl io screenshot` captures. They were launched with the DEBUG harness
`-MOL03Studio <id> [-MOL03Panel style|play|expressions|photo]`.

| File | Shows |
|---|---|
| studio-pip-meadow.png | Pip, Meadow environment, header (#001 · Bubbly), action rail |
| studio-moss-night.png | Moss, Night sky |
| studio-tofu-cozy.png | Tofu, Cozy room |
| studio-bolt-studio.png | Bolt, Studio backdrop |
| studio-pip-style-sheet.png | Contextual sheet: Style tab (environments + Signature Cap) |
| studio-pip-play-sheet.png | Play tab (pet / hop / dance / peekaboo / nap) |
| studio-pip-expressions-sheet.png | Expressions tab |
| studio-pip-photo.png | Photo mode: chrome hidden (capture comes in Workstream D) |

## Tests
- `ModulaTests/MOL03StudioTests` (7 tests: framing, idle personalities, cooldowns, tap-spam → dizzy gate, Reduced Motion policy): pass.
- §17 scenario `ModulaUITests/MOL03StudioScenarioUITests` (3 tests): pass.
  - `testFullStudioScenarioPip`: 4 environments, cap, expressions, Play, nap/wake, tap spam, sheet close, photo mode, drag, back.
  - `testEveryThreeDCharacterOpensWithItsOwnFraming`
  - `testIdlePersonalityRunsAndReducedMotionSuppressesIt`
- Regression: the MOL01/MOL02 unit tests pass, and so do the MOL01 acceptance UI tests and all MOL02 UI tests.
  - The MOL02 "StudioOffers…" tests now expect the Living Studio title (`Pip`, not `Pip 3D`).

## Flaky (not caused by this change)
In the first full run, three tests crashed the app inside the renderer teardown:
- `MOL01 testStudioLifecycle20x…`
- `MOL02 Moss testStudioOffers…`
- `MOL03 testEveryThreeDCharacter…`

This is the known intermittent crash family: SwiftUI gesture/Image teardown, and Metal/CoreRE dealloc. It is owned by fix/mol-01-3d-crash (PR #32). All three passed on rerun, so they are reported as **flaky**, not fixed.
