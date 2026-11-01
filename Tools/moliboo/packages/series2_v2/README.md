# Series 2 v2 (#116–215) — native rig

Series 2 is drawn in-app by the same code-drawn rig as #001–115 (`ios/Modula/DesignSystem/Mascot/MolibooSeries2.swift`):
`MolibooSpec` body/size/palette + signature parts + `MascotRig` anchors, so wardrobe, expressions and motion behave identically.

* `gen_swift.py` — writes the 100 `MolibooSpec` lines + profiles (from the poster palettes/features) pasted into MolibooSeries2.swift.
* `parts.swift.txt` — reference copy of the Series 2 parts kit (toppers hide under hats, props, body marks, stubby `nubs`).
* `render.py` + `feats_*.py`, `core.py` — the glossy 2D poster art. Output `portrait.png` is a **package thumbnail/fallback only**.
* `fitsheet_native.py` — rig-true fit sheet: spec silhouettes via MascotRig formulas + pack-2 wearables placed only from anchors.
* `../../registry/series2_fit_profiles.py` — adds `fit/<key>` profiles (validated:false until the on-device measured export runs).

Packs `../wardrobe2/` (24 wearables) and `../scenes2/` (10 family scenes) are drafts for the server: no price, unlock or ownership.
