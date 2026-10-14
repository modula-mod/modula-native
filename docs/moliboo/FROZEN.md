# Pebble — FROZEN: `pebble-v2.2-frozen`
Frozen 2026-10-14 (BST) after user visual approval of v2.1 + v2.2 polish. No further redesign unless a technical defect is found.

v2.2 changes: happy-eye artifact removed at all angles (iris collapses to a zero-area point; shines collapse), Signature Cap leaves rebuilt as folded leaf blades on a stem + snug fit (offset z −4.5 mm), stone polish (softer coat highlight, deep-slate + mint mineral specks, faint veins). Identity unchanged.

Tag appears in: `moliboo_manifest.json` (`characters[pebble].sourceVersion`, `cosmetics[cap.moliboo.signature].sourceVersion`), this file, build_pebble.py header. Test-enforced.

## Reproducible export
`blender -b -P tools/moliboo/build_pebble.py -- <out>` (Blender 4.2.3 LTS) then
`<blender>/4.2/python/bin/python3.11 tools/moliboo/verify_reproducible.py <frozen> <out>` ⇒ REPRODUCIBLE.
Blender 4.2 output is not byte-identical run-to-run (USD prim order, Cycles bake jitter at UV margins: mean |Δ| ≈ 0.001/255), so the frozen artifacts are pinned by SHA-256 and rebuilds are verified for semantic equivalence (prim set, point/face counts, bounds ±10 µm, blend shapes, time range, clips, attachments). Verified on the box: REPRODUCIBLE.

## Artifacts (SHA-256)
```
3a4c3da998a86b85d551695bb52eccd53efb036e3993e0762d52dc62acfa2303  Pebble.usdz
359fd73011bee9310bc7d7faaf79c40e6ae859a4cebe29d5517fcca8bda3b531  Accessory_Cap_MolibooSignature.usdz
4b18fa10075852de9e227917d30b5608929283506f2885ec2cd207cc96f2c37d  Pebble.blend
0f88b9fdd27133446f695fa7e3e00b04e03f8ecdbad7c2ce0f6f0c703621ff7b  Pebble_BaseColor.png
ce9b5496401ef73eccd8e420c1a3d22a40319544a8444a6a1fdfd60fe3ac1b78  clips.json
bca48226e1ebc92b387865e9f2f2d0b7b69020488fee4642e43280b73bcfbc38  attachments.json
```
## Scripts (SHA-256)
```
263c4a956fd95f77f1649828058f2aebc93734f0d48f7241a9120cad2378f738  build_pebble.py
d2142c83fa1acd54e4ec2fe213e059af30cd94d4a998714e7d1d758afa089ffa  render_validate.py
7f6552646949184e0f3038ccc54481e160c91abc9eede20d7db429e6b33b4256  verify_reproducible.py
```
## Clips (30 fps)
- idle_bob: 1–60
- blink: 61–72
- wobble: 73–102
- tap: 103–130
- expr_idle: 131–136
- expr_happy: 137–142
- expr_excited: 143–148
- expr_surprised: 149–154
- expr_sleepy: 155–160
- expr_sad: 161–166
## Anchors
anchor_head, anchor_face, anchor_back, anchor_neck, anchor_base (positions in usd_inspect.txt).
## Signature Cap fit (Pebble only; other Originals not compatible)
anchor_head · offset [0, 0, −0.0045] m · rotation [−8, 18, −25]° · scale 1.
## Known cosmetic nit (not a defect)
Seen from directly behind/side, the sprig's folded leaves read as angular. Recorded for a future art pass, not changed after freeze.
