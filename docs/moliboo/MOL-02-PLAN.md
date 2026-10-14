# MOL-02 — Five Living Moliboos (plan, not started)

Status: PLAN ONLY. No MOL-02 assets are built yet. No backend migrations. No characters other than the five below.
Reference implementation: Pebble `pebble-v2.2-frozen` (MOL-01). Sources: *Moliboo Master Bible & Product Specification v1.0*
(§ Canonical character profiles, § 11.2 rig families, § 11.3 IDs) and the "Moliboos — 100 Magical Companions" poster (Originals 001–025).

## 1. Cast and anatomy

| # | Character | Bible identity | Rig family (Bible 11.2) | Anatomy to model (poster + Bible) | Palette | Signature animation |
|---|---|---|---|---|---|---|
| 010 | **Pebble** (reference, frozen) | Living stone, "Quiet Guardian" | Squashable / solid — stone sway | Wide, low, asymmetric stone, flat base, face on front plane, pink cheeks, mineral flecks | Slate blue / grey / mint flecks | Tiny wobble, micro-smile |
| 001 | **Pip** | Pink axolotl, "Social Spark" | Round organic | Round body; 3 feathery gill fronds per side (strong side silhouette); tiny tail; stubby limbs; big glossy eyes; small smile | Bubblegum pink / coral / magenta gills | Gills flutter; exuberant bounce |
| 002 | **Moss** | Pond frog, "The Unbothered One" | Round organic | Squat rounded torso; raised eye domes on top of the head; wide mouth line; inflatable cheeks; short webbed feet | Moss green / mint / cream belly | Slow blink, cheeks inflate, measured hop |
| 011 | **Tofu** | Soft cube, "Wobbly Optimist" | Squashable / solid — cube squash | Rounded, slightly translucent cube (bevelled, subsurface); face on front face; nubs for feet. The square silhouette must survive outfits | Cream / vanilla / peach blush | Squash and stretch like a soft cube |
| 014 | **Bolt** | Pocket robot, "Pocket Inventor" | Mechanical | Rounded rectangular case; inset rectangular **pixel-face screen** (emissive); antenna with a tip light; side bolts/panels; short legs | Graphite / teal / silver / cyan glow | Pixel eyes change; antenna flashes |

Stable IDs (manifest `id` keeps the existing short form; the Bible's long form is recorded as `canonicalId`):
`pip`/`moliboo.originals.pip`, `moss`/`moliboo.originals.moss`, `tofu`/`moliboo.originals.tofu`, `bolt`/`moliboo.originals.bolt`.

## 2. Shared Blender pipeline (one engine, parameterised)
- Refactor `Tools/moliboo/blender/build_pebble.py` into `build_moliboo.py` plus **one data file per character**
  (`characters/<id>.json`: body primitive + deformation params, part list, palette, face layout, anchors, shape-key
  recipes, clip list, cap fit). Pebble becomes `characters/pebble.json` and must rebuild **semantically identical**
  to v2.2-frozen (verified with `verify_reproducible.py`). That proves the refactor before any new character.
- Shared modules: `body.py` (stone / sphere-blob / bevel-cube / rounded-box generators + asymmetry noise), `face.py`
  (surface-conformed eyes/irises/shines/cheeks by ray-cast; mouth curve; Bolt uses `face_screen.py`, an emissive
  texture-atlas screen instead of mesh eyes), `parts.py` (gills, eye domes, feet, tail, antenna, bolts),
  `materials.py` (principled helper, baked base colour, Tofu SSS approximated by a baked gradient plus low-roughness coat,
  Bolt emissive), `rig.py` (shape keys and transform clips), `export.py` (USDZ Y-up, metres, clips.json, attachments.json, checksums).
- No per-character engines or scripts. Character differences live only in data and in reusable part generators.
- Outputs per character: `<Name>.blend` (editable), `<Name>.usdz`, `<Name>_BaseColor.png`, renders, checksums. Each is
  tagged `<id>-v1.0-frozen` after approval.

## 3. Facial states and personality clips
Shared expression set (the same names as Pebble, so `MolibooExpression` needs no changes): idle, blink, happy (^ arcs), excited, surprised, sleepy, sad.
Shared clips: `idle_bob`, `blink`, `wobble`, `tap`, plus one hold clip per expression (6 frames).
Personality clips (new, optional per character, declared in the manifest `clips`):
- Pip: `gill_flutter` (gill fronds rotate about their roots, 0.6 s loop), `exuberant_bounce`.
- Moss: `slow_blink` (long eyelid close), `cheek_puff` (cheek shape key), `measured_hop`.
- Tofu: `cube_squash` (non-uniform scale with volume preservation; the silhouette stays square).
- Bolt: `pixel_*` face states rendered as **screen texture swaps** (an atlas UV-offset per expression, driven by baked
  per-face material selection or a `PixelFace` component). Plus `antenna_flash` (emissive pulse) and `servo_tilt`.
Runtime: `MolibooSceneController.playClip` already plays any named clip. Bolt needs a small `MolibooFaceProvider`
protocol (mesh blend shapes vs pixel screen). That is the only planned runtime abstraction.

## 4. Anchors and Signature Cap attachment configs
Every character exports `anchor_head`, `anchor_face`, `anchor_back` and `anchor_ground`. The cap uses `anchor_head`.
The fit is authored per character in `attachments.json`, then copied into the manifest. A cap is not compatible until fitted and validated.

| Character | anchor_head placement | Cap offset / rotation (deg) / scale, initial estimate to tune in Blender | Notes |
|---|---|---|---|
| Pebble | top of stone, left-high side | [0,0,-0.0045] / [-8,18,-25] / 1.0 | frozen, validated |
| Pip | crown between gill roots | ~[0,0,-0.003] / [-6,0,-12] / 0.9 | must clear gills; gill silhouette stays visible |
| Moss | between the eye domes, behind them | ~[0,-0.01,-0.004] / [-14,0,-8] / 0.85 | eyes must not be occluded |
| Tofu | top face centre | ~[0,0,-0.002] / [0,0,-15] / 1.0 | sits flat; keep the square silhouette |
| Bolt | beside the antenna base | ~[0.012,0,-0.002] / [0,0,-20] / 0.8 | the antenna must not intersect the cap (collision check in tests) |

## 5. Manifest entries (schema 2, no schema bump needed)
For each of pip, moss, tofu and bolt, fill the existing placeholder entry with `asset`, `assetSHA256`, `sourceVersion`,
`fps`, `expressions`, `clips` (shared plus personality) and `attachments["cap.moliboo.signature"]` with `compatible: true`.
Optionally add `canonicalId` and `rigFamily` (they decode as optional fields, so older builds ignore them). The cosmetics list is unchanged.

## 6. iOS rendering evidence (simulator first, then the iPhone)
- Studio 3D entry shown for any character with an `asset` (not Pebble-only). The 2D fallback stays for the rest.
- Generalise the XCUITest acceptance suite from MOL-01 (`MOL01AcceptanceUITests`) into a per-character
  parameterised suite covering: loaded and real meshes, every expression and clip, drag yaw, tap react, cap
  equip/remove/relaunch, and flag-off gives 2D.
- Perf per character on the simulator and the iPhone: load ms, footprint after 20 open/close cycles, and frame timing via the probe.
- Evidence files (renders, test logs, perf lines) are stored under `docs/moliboo/evidence/mol-02/`. Screenshots are taken only if the user asks.

## 7. Tests and gates
G0 repo truth · G1 refactored pipeline rebuilds Pebble identically · G2 per-character model approval (renders and contact sheet: user sign-off) ·
G3 USDZ structure (blend shapes, clips, anchors, checksums) · G4 manifest and unit tests (decode, compatibility, cap configs,
legacy outfits) · G5 RealityKit load and clips (XCTest) · G6 XCUITest interaction, cap and persistence per character · G7 flag-off
rollback · G8 perf budget (≤ 25 MB footprint growth per character scene, load < 500 ms on simulator, avg frame ≤ 16.7 ms) ·
G9 regression baseline unchanged vs MOL-01 (known pre-existing failures documented) · G10 iPhone Debug install and user visual approval.

## 8. Risks
- Pip gill fronds: thin geometry can alias and needs cap clearance. Mitigation: thicker fronds and an LOD-free silhouette check from the side.
- Tofu translucency: RealityKit has no true SSS. Mitigation: a baked gradient plus coat, accepting an approximation.
- Bolt pixel face: a different expression mechanism. Mitigation: the `MolibooFaceProvider` abstraction, with emissive atlas tested on device.
- Moss raised eyes: cap occlusion. Mitigation: a per-character offset and an automated bounds-overlap test.
- Blender exports are not byte-identical: semantic reproducibility checks remain the standard.
- Bundle size: 4 × ~5–8 MB USDZ. Track this, and consider on-demand resources at MOL-03.
- Scope creep: no other characters, no backend changes and no new cosmetics in MOL-02.
