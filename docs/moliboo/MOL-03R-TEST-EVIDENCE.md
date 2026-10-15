# MOL-03R — Test & Verification Evidence

## 1. Automated Unit & 3D Renderer Suite (`ModulaTests`)
All 64 tests across 10 Moliboo test suites passed (`0 failures`):
- `MOL01Tests`: **9 / 9 passed** (manifest schema, SHA-256 verification, Pebble 3D load/animation/Signature Cap equip, outfit persistence round-trip).
- `MOL02Tests`: **10 / 10 passed** (Pip, Moss, Tofu, Bolt USDZ load, personality clips, Signature Cap attachment, flag-off fallback).
- `MOL03StudioTests`: **7 / 7 passed** (reaction cooldown gate, dizzy spam threshold, idle personality scheduling, reduce-motion policy, per-character framing).
- `MOL03WardrobeTests`: **7 / 7 passed** (search/filter query, preview staging, apply/revert/undo, unowned preview-only blocking, saved outfit presets).
- `MOL03WardrobeRigTests`: **6 / 6 passed** (fit table decoding, LRU template clone cache, equip effects, reduce-motion suppression, teardown cleanup).
- `MOL03WardrobeFitValidationTests`: **3 / 3 passed** (60 / 60 representative 3D item fits across `pebble`, `pip`, `moss`, `tofu`, `bolt` including `bg.*` `[90, 0, 180]` orientation, `cap.moliboo.signature`, hats, glasses, pets, held items, per-axis `stretch`, and equip mote bursts).
- `MOL03CollectionTests`: **2 / 2 passed** (pre-rendered 512² portrait presence for all 3D characters, 25 Originals coverage).
- `MOL03WorldTests`: **9 / 9 passed** (care state persistence, wall-clock decay, sleep/play/clean/feed transitions, time-of-day periods, fail-closed local intelligence chat).
- `MOL03AmbienceTests`: **7 / 7 passed** (time-of-day sky/ambience resolution, deterministic particle painter).
- `MOL04CardsTests`: **4 / 4 passed** (Founding Collection catalogue, rarity ordering/weights, deterministic SplitMix pack roller, welcome pack Legendary guarantee).

## 2. Simulator XCUITest Acceptance Suite (`ModulaUITests`)
- `MOL03StudioScenarioUITests/testFullStudioScenarioPip`: **PASSED** (full end-to-end Studio flow: 4 environments, Signature Cap toggle, all 7 expressions, 5 play interactions, nap & stage-tap wake with sheet open, dizzy tap-spam gate, photo mode chrome hide, drag-to-turn yaw).
- `MOL03WardrobePhotoUITests`: **2 / 2 PASSED** (`testWardrobeSearchPreviewApplyUndoSave` + `testPhotoCaptureShowsCharacterAndShare`).
- `MOL03WorldUITests/testHomeLayoutLogoStatusIdentityComposerAndCollection`: **PASSED** (Moliboos Home layout, wordmark, stage, nav bar, stats row, identity card, composer, quick care actions, activities, collection carousel).
- `MOL03SettingsHubUITests/testHubSelectionPersistsAcrossLaunch`: **PASSED** (Settings Hub layout, character selection persistence across app relaunch).
- `MOL03CollectionUITests/testHubStudioCardOpensTheOneStudio`: **PASSED** (consolidated single Studio entry + `More` stacked sections).
- `MOL04CardsUITests/testBinderPackOpeningAndLegendaryReveal`: **PASSED** (Card Binder → free Founding pack tear → Legendary Pebble reveal → binder slot → interactive tilt inspect).

## 3. Physical iPhone (`modula.digital`) Wi-Fi Build, Install & Launch
- **Target Device**: `modula.digital` (`00008150-00043C2A11A3401C`, iPhone 17 Pro Max, paired over Wi-Fi).
- **Build**: `xcodebuild -workspace Modula.xcworkspace -scheme Modula -configuration Debug -destination generic/platform=iOS MODULA_API_URL=https://api.modula.digital build` → **BUILD SUCCEEDED**.
- **Install**: `xcrun devicectl device install app --device 00008150-00043C2A11A3401C .../Modula.app` → **INSTALLED (`databaseSequenceNumber: 3540`)**.
- **Launch**: `xcrun devicectl device process launch --device 00008150-00043C2A11A3401C digital.modula.app.native` → **LAUNCHED**.
