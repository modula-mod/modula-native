# 3D wardrobe fit table (MOL-03 D)

The native loader (`ios/Modula/Features/MolibooStudio/MolibooWardrobeRig.swift`) reads one bundled file,
`ios/Modula/Resources/Moliboo3D/moliboo_wardrobe_fits.json`. The wardrobe pipeline generates it, and the per-item USDZs ship next to it.
While the file is absent the table is empty, and only manifest cosmetics (the Signature Cap) render in 3D.

```json
{
  "version": 1,
  "items": {
    "hat.party": {
      "asset": "Item_hat_party",                 // USDZ base name (bundle resource)
      "slot": "hat",                             // MascotWardrobeSlot rawValue
      "variants": { "wide": "Item_hat_party_wide" },
      "effect": { "effect": "sparkle", "duration": 0.4, "overshoot": 1.2, "pulses": 1 }
    }
  },
  "fits": {
    "pip":  { "slot:hat": { "anchor": "Pip_Anchor_Head", "offset": [0, 0.05, 0], "rotationDegrees": [0, 0, 0], "scale": 0.9 } },
    "moss": { "slot:hat": { "anchor": "Moss_Anchor_Head", "scale": 1.3, "variant": "wide" },
              "pet.duck": { "anchor": "Moss_Anchor_Body", "hidden": true } }
  },
  "slotEffects": { "top": { "effect": "shimmer", "duration": 0.5, "overshoot": 1.05, "pulses": 2 } }
}
```

## Rules
- **IDs** are the existing `MascotWardrobeCatalog` ids, unchanged. `cap.moliboo.signature` and `hat.party` are separate items that share the hat slot, so equipping one replaces the other.
- **Fit lookup** for a character, in order:
  1. `fits[char][itemID]`
  2. `fits[char]["slot:<slot>"]`
  3. otherwise the item is not available in 3D for that character.

  An entry with `"hidden": true` means "doesn't fit".
- **Variant:** the fit's `variant` picks `items[id].variants[variant]`; if it is missing, the base `asset` is used.
- **Transform:** offset and rotation are in the anchor's local space, and scale is uniform. Export assets Y-up with the pivot at the attach point.
- **Effects:** `none | pop_in | sparkle | bounce | shimmer`.
  - Lookup order: item `effect`, then `slotEffects[slot]`, then the default `pop_in`.
  - Effects are transform-only (no particles, no material swaps), so they are cheap and safe at teardown.
  - Under Reduced Motion every effect becomes `none`.
- **Loading:** lazy, so only worn items are loaded. A small LRU of templates (6) gives each equip a `clone(recursive:)`, and concurrent loads of the same asset are deduplicated. The character is never reloaded.

## MOL-03 E — generated assets (trial integration)
- Source: generated wardrobe pack (README in the asset drop); table `moliboo_wardrobe_fits.json` (~290 KB, pruned to the 656 assets actually referenced).
- Anchors: `anchor_head|face|back|neck|base` (USDZ names, used verbatim).
- Offsets are anchor-local, Z-up as authored; `rotationDegrees` already contains the +90° X export correction and is applied as-is (Blender XYZ, R = Rz·Ry·Rx). The rig adds no correction.
- Body garments: per-character `variant` → `items[id].variants[variant]`; unknown labels (e.g. `shift-back`) fall back to the base asset.
- Loading: lazy, per item, small clone cache; the character is never reloaded.
- Size: free/earnable items bundled in `MolibooWardrobe/` (~7 MB); premium items in `MolibooWardrobePremium/` (~7 MB) tagged as On-Demand Resource `moliboo.wardrobe.premium`; loader tries bundle, then ODR (`NSBundleResourceRequest`). ODR delivery is not verified in simulator tests (premium files are reachable locally in Debug).
- Known: Sprout/Ember have table cap fits ("adapted") while the manifest still marks the Signature Cap incompatible for them; 29 fits are being regenerated upstream and will replace the table in place.
