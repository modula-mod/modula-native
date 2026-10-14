# Wardrobe 3D — Moliboo Signature Cap & attachment contract

## Cosmetic
| Field | Value |
|---|---|
| Stable ID | `cap.moliboo.signature` (new; `MolibooCosmetics.signatureCapID`) |
| Name | Moliboo Signature Cap |
| Slot / rarity | hat / Common |
| Unlock | `.free` ⇒ always owned and available client-side for every user |
| 2D fallback art | existing `cap` style drawing, blue dyes (no new 2D art) |
| 3D asset | `Accessory_Cap_MolibooSignature.usdz` — separate geometry (crown, curved peak, white pom-pom, leafy sprig) |

`hat.party` (Party cone) is NOT modified or reinterpreted, and is not a 3D cosmetic (test-enforced). No other cosmetic is granted; existing ownership, purchases, coin balances and saved outfits are untouched. The only catalog change is one appended `it(...)` line after `hat.halo` in MascotWardrobe.swift (anchor-based idempotent patch).

## Attachment contract (manifest schema 2)
- `cosmetics[]`: wardrobeItemID → asset (+ SHA-256).
- `characters[]`: all 25 Originals in canonical order. Each has `attachments: { itemID: { anchor, offset[3] (m), rotationDegrees[3] (Euler XYZ, authoring Z-up frame), scale, compatible } }`.
- Pebble: `anchor_head`, offset [0,0,-0.0045] m, rotation [-8, 18, -25]°, scale 1, compatible (validated: renders + cap close-ups; native check PENDING).
- Other 24 Originals: no 3D model and no config ⇒ `.notCompatible` (never guessed). Unknown anchor or `compatible:false` ⇒ `.notCompatible`.
- Runtime: cosmetic is parented to the anchor entity ⇒ follows drag-rotation, idle bob, wobble and tap clips. Local orientation = config rotation × Y-up export correction (+90° X).

## Persistence
Through the existing `MascotWardrobeStore` (`composer.mascot.outfit`, `MascotOutfit` unchanged). Save writes only the compatible, owned cap; other outfit slots preserved. Old outfit JSON (incl. `hat.party`) still decodes (test).

## Tests (MOL01Tests)
New ID exists, Common, free, owned; unique ID · hat.party unchanged and not a 3D cosmetic · 25 Originals, only Pebble compatible · incompatible flag/unknown anchor ⇒ not compatible · outfit round-trip with the cap · legacy outfits decode · RealityKit: load, clips present, equip at anchor_head with configured orientation, follows rotation, remove, sync ignores non-3D items.
Status: written + syntax-checked on box; execution PENDING (Mac).
