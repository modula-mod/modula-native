# MOL-02 — Pebble parity check (G1): deferred

**Status: DEFERRED, not run. Pebble is unaffected.**

## Context
MOL-02 adds a shared, data-driven builder (`Tools/moliboo/engine/build_moliboo.py` + one JSON spec per
character in `Tools/moliboo/engine/characters/`). Pebble is **not** built by this engine: it stays on its frozen
MOL-01 script `Tools/moliboo/build_pebble.py` (source tag `pebble-v2.2-frozen`), and the shipped
`Pebble.usdz` (sha256 `3a4c3da9…2303`) and `Accessory_Cap_MolibooSignature.usdz` (sha256 `359fd730…b531`) are
byte-identical to main. Nothing in MOL-02 regenerates or replaces them.

## What G1 would prove
That the shared engine, fed a `pebble.json` spec, reproduces Pebble within tolerance
(same object/anchor names, clip frame ranges, anchor positions within 0.5 mm, silhouette IoU ≥ 0.98 in the
front/three-quarter/side renders, cap fit unchanged).

## Why deferred
- Pebble's v2.2 geometry has hand-tuned steps that are not expressed in the engine's generators, so
  writing `pebble.json` is a porting task rather than a check.
- Porting Pebble carries risk to a frozen, shipped asset with no user-facing gain in MOL-02.

## Consequences / guard rails
- Pebble must keep using `build_pebble.py` until G1 passes; do not rebuild Pebble with the engine.
- Shared conventions the runtime relies on are the same in both builders and are covered by tests:
  `<Name>_` part prefix, anchors `anchor_head/face/back/neck/base`, clip names and frame ranges
  (`idle_bob 1–60, blink 61–72, wobble 73–102, tap 103–130, expr_* 131–166`), Z-up → Y-up export.
- Revisit G1 after MOL-02 (candidate: MOL-03), before any Pebble change.
