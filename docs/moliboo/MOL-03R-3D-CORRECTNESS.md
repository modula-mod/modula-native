# MOL-03R — 3D Visual Correctness & Wardrobe Fit Audit

## 1. Root Cause & Resolution of the "See-Through Dome" & Facial Artifacts
1. **Background Dome Orientation (`bg.*`)**:
   - In `Item_bg_*.usdz`, the backdrop dome shell (`Item_bg_*_part01` / `Item_bg_neon_part00`) was exported with a `-180°` X-axis flip that placed the dome hemisphere in `-Y` (front of the character) when `rotationDegrees` was `[90, 0, 0]`.
   - Updating all `bg.*` and `slot:background` entries in `moliboo_wardrobe_fits.json` to `rotationDegrees: [90.0, 0.0, 180.0]` rotates the dome 180° around the vertical axis so it opens toward the camera behind the character across all 10 Originals.
2. **Unrequested Auto-Equipped Items (`applyOutfitOfTheDayIfNeeded`)**:
   - Previously, `MascotWardrobeStore.applyOutfitOfTheDayIfNeeded()` auto-equipped a random hat, neck accessory, and aura whenever `outfit.isEmpty` was true on first visit, causing random items (e.g., `face.bandaid`, `acc.scarf`, `aura.bubbles`) to appear on Pebble in Studio.
   - `applyOutfitOfTheDayIfNeeded()` now returns `false` when `MolibooFeatureFlags.native3DEnabled` is enabled, preserving a clean canonical character until the user explicitly equips or saves an outfit.
3. **Pebble Head & Body Fit (`moliboo_wardrobe_fits.json` + `MolibooWardrobeRig.swift`)**:
   - Pebble's `anchor_head` sits at `(+0.04, +0.004, +0.090)` for its tilted Signature Cap (`cap.moliboo.signature`). Generic hats (`hat.*`) now apply `offset.x = -0.04` so they sit centered on Pebble's crown with `< 2 mm` gap.
   - Added optional per-axis `stretch: [Float]?` to `MolibooWardrobeFit` (`scaleVector`) so wrap garments (`top.*`, `out.*`, `bot.*`, `acc.*`, `back.*`) conform to Pebble's wider `0.176 × 0.120 m` body without clipping inside.
   - Added `MolibooWardrobeRig.burst` so equipping any 3D cosmetic or the Signature Cap spawns a lightweight 8–12 mote sparkle/pop burst (disabled under Reduce Motion).

## 2. Five-Character 3D Regression Matrix (`Pebble`, `Pip`, `Moss`, `Tofu`, `Bolt` + 5 Originals)
- **Canonical USDZ Assets**: All 10 bundled character USDZs (`Pebble`, `Pip`, `Moss`, `Tofu`, `Bolt`, `Nimbus`, `Mochi`, `Sprout`, `Ember`, `Tuck`) and `Accessory_Cap_MolibooSignature.usdz` pass SHA-256 manifest verification (`MOL01Tests`, `MOL02Tests`, `MOL03OriginalsTests`).
- **Expressions**: All 7 expressions (`idle`, `blink`, `happy`, `excited`, `surprised`, `sleepy`, `sad`) play baked `expr_*` blend-shape clips with procedural transform fallback.
- **Shadows & Grounding**: Dynamic light shadows are disabled on both character and wardrobe entities (`MolibooSceneController.disableShadows`), replaced by the cached 64×64 radial alpha `ContactShadow` plane (`0.14 × 0.09 m`).
