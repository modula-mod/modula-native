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

# MOL-03 Workstream C — collection, companions, Settings

| File | Shows |
|---|---|
| settings-moliboo-links.png | Settings → Moliboo: "Open Pip's Studio" + "Collection" links |
| collection-top.png | Collection: 25 Originals, pre-rendered portraits + "3D" badge for Pip/Moss/Pebble/Tofu/Bolt, "Coming later" for the rest |
| collection-scrolled.png | Collection, scrolled |

These screenshots were written by `MOL03CollectionUITests` with `TEST_RUNNER_MOL03_SHOTS` set, using real XCUIScreen captures.

Composer and Home companions use the portrait with a gentle bob when the flag is on. They don't load RealityKit, and the portrait stays static under Reduced Motion.

Portraits come from `Tools/moliboo/engine/render_portraits.py`. They are rendered in Blender from the shipped USDZs: 512², transparent, AgX.

## Tests (C)
These 35 tests passed in one run, with 0 failures:
- `MOL03CollectionTests` (portrait for every 3D character, none for the others; all 25 Originals)
- `MOL03CollectionUITests` (Settings → Collection badges → tap Pip opens the Studio; Settings → "Open Studio")
- `MOL03StudioTests`, `MOL02Tests`, `MOL01Tests`
- `MOL03StudioScenarioUITests`, `MOL02PipAcceptanceUITests`

# MOL-03 Workstream D: Wardrobe 2.0 + Photo

| File | Shows |
|---|---|
| wardrobe-search-party.png | Wardrobe tab: search "party" narrows the grid to the Party cone |
| wardrobe-3d-preview-cap.png | 3D filter, Signature Cap previewed live on Pip (no reload); camera raises Pip above the sheet |
| wardrobe-saved-outfit.png | Saved outfits row |
| photo-mode-shutter.png | Photo mode: chrome hidden, shutter |
| photo-preview-share.png | Captured frame (contains the 3D character) + Share |

**Wardrobe**
- Search covers item names, blurbs, ids and slots. There are slot chips, an All/Owned filter and a 3D-only filter.
- Tapping an item tries it on as a preview only. The 3D stage syncs to the preview through `controller.sync` and the fit-table rig, and the character is never reloaded (the UI test asserts `loadms` stays unchanged).
- Apply is ownership-checked and can be undone through `MascotWardrobeStore`. Revert drops the preview, and Save stores the current look as an outfit preset.
- IDs and ownership are unchanged. `cap.moliboo.signature` and `hat.party` stay separate items in the same hat slot, so one replaces the other.

**Generic 3D wardrobe loader** (`MolibooWardrobeRig`, contract in `docs/moliboo/WARDROBE_FIT_TABLE.md`)
- Each item has its own asset, plus a fit table per character and per slot (anchor, offset, rotation, scale, variant, hidden).
- Equip effects are data-driven (pop_in, sparkle, bounce, shimmer), transform-only, and turn off under Reduced Motion.
- Items load lazily, through a 6-entry LRU of templates with deduplicated loads.
- The generated assets are not bundled yet; until they are, only the Signature Cap renders in 3D.

**Photo**
- The shutter hides the chrome and snapshots the window, including the RealityKit layer.
- The preview sheet has a ShareLink.
- `MolibooPhotoCapture.showsSubject` checks that the character is actually in the frame, and the UI test asserts `subject=1`.

## Tests (D)
- Unit tests:
  - `MOL03WardrobeTests` (6): search/filters, preview/apply/undo/slot swap, saved outfits, unowned items are preview-only, cap kept separate from the Party cone, photo subject detection.
  - `MOL03WardrobeRigTests` (5): fit resolution order, variants, hidden, effect fallback, LRU/dedupe/clone, lazy attach and sync, no work after stop.
- `MOL03WardrobePhotoUITests` (2): pass.
- Regression with D (one run): 51 passed and 3 crashed. The 3 crashes are the known RealityKit/SwiftUI crash family tracked in `MOL-02-STABILITY-TRACK.md`:
  - MOL01 lifecycle 20x
  - Moss loads/expresses
  - MOL03 every-character framing

  All 3 passed on rerun, so they are **flaky**. In a later run the MOL03 idle/Reduced Motion test also crashed once, then passed on rerun.
