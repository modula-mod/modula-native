# Asset pipeline
- Blender 4.2.3 LTS (Linux tarball sha256 3a64efd1982465395abab4259b4091d5c8c56054c7267e9633e4f702a71ea3f4); scripts in tools/moliboo/.
- `blender -b -P build_pebble.py -- <out>` → Pebble.blend (editable, procedural material graph kept), Pebble_BaseColor.png (2048² bake), Pebble.usdz, Accessory_Cap_MolibooSignature.usdz, clips.json, attachments.json.
- Bake: gradient (mint base → lavender) + cloud overlay + mint flecks baked (Cycles DIFFUSE colour) and wired to Base Color; procedural bump dropped for export (USD preview surface can't carry it).
- Export: Y-up (convert_orientation), metres, UsdPreviewSurface, blend shapes → per-part SkelRoot + SkelAnimation.
- Clips (one 30 fps timeline, frames): idle_bob 1–60, blink 61–72, wobble 73–102, tap 103–130, expression holds expr_idle 131–136, expr_happy 137–142, expr_excited 143–148, expr_surprised 149–154, expr_sleepy 155–160, expr_sad 161–166. Root transform animated; 9 SkelAnimations × 130 samples (usd_inspect.txt).
- Validation: render_validate.py (views/expressions/validation.json) + USD inspection (usd_inspect.txt). RealityKit load/appearance: PENDING (needs Mac/Xcode/simulator).
## Checksums
See FROZEN.md (pebble-v2.2-frozen).
