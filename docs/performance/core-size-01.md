# CORE-SIZE-01 — app bundle size

Measured on 2026-10-24 (Xcode, `generic/platform=iOS`, signed device builds). Bytes = sum of regular
file sizes inside `Modula.app`; zip proxy = `ditto -c -k` of the bundle.

| Build | Before (`main` f73da4c) | After (`perf/core-size-01`) | Change |
|---|---|---|---|
| Debug-iphoneos bundle | 1,340,985,330 B (1.25 GiB; Settings showed "1.35 GB") | 324,508,985 B (309 MiB) | −75.8 % |
| Debug zip proxy | 928.5 MiB | 70.0 MiB | −92 % |
| Debug `Nodus/` folder | 934.2 MiB (R7 weights) | absent | −934 MiB |
| Release-iphoneos bundle | 191,810,122 B (183 MiB) | 154,909,619 B (148 MiB) | −19.2 % |
| Release zip proxy | 60.1 MiB | 37.9 MiB | −37 % |
| Assets.car | 9.32 MiB | 5.18 MiB | −4.1 MiB |

Before, Debug top contributors: Nodus 934.2 MiB · Modula.debug.dylib 218.0 · Frameworks 76.3 ·
Assets.car 9.3 · MolibooWardrobe 8.7 · mlx Cmlx bundle 3.7 · main.jsbundle 3.1 · 10 character USDZ
≈ 21.7 · 10 portraits ≈ 2.9. Release main binary (116.9 MiB) and Frameworks (17.8 MiB) are executable
code and were not touched.

## Why Settings said "Modula Core 1.35 GB"
The Storage & Downloads screen (PR #168, not on main) measures `Bundle.main.bundleURL` recursively.
On Debug builds that included the ~930 MiB Nodus R7 weights copied by
`Tools/Nodus/scripts/prepare-development-model.sh` (Debug defaulted to include) plus the 218 MiB
debug dylib. It never included user data or downloaded packages.

## Changes
1. R7 weights are no longer bundled by default in any configuration
   (`MODULA_INCLUDE_EXPERIMENTAL_NODUS=1` / `MODULA_REQUIRE_EXPERIMENTAL_NODUS=1` opt in). Builds without the
   model report `modelNotInstalled`; the weights belong in a GreenField/on-demand model package.
2. Retired Moliboo 3D assets removed (character USDZ, duplicate signature-cap USDZ, 3D portraits,
   3D wardrobe item USDZ, the `moliboo.wardrobe.premium` ODR pack). `native3DEnabled` is hard `false`;
   the 2D renderer, the 2D wardrobe (thumbs + fit-table catalog) and saved outfits (item ids) do not
   reference them. 3D-asset unit tests are skipped with a CORE-SIZE-01 reason.
3. `ModulaAppIcon` in-app image is a 384 px copy instead of a byte duplicate of the 1024 px app icon.
4. Brand SVGs (`MoliboosLogo`, `ModulaWordmark`) get display-scale intrinsic sizes so actool stops
   emitting 4745–14235 px rasters (vector representation is preserved).

## Storage reporting (follow-up on #168)
Main has no Storage & Downloads screen yet. When #168 lands, split `coreBytes` into:
native binary (`Bundle.main.executableURL` + `Frameworks/`), bundled assets (rest of the bundle),
user data (Application Support / Documents excluding `Modula/Packages`), and downloaded packages
(`Modula/Packages/*`, already measured per kind).

## Verification
- Release simulator build installs and cold-launches to the signed-out landing (iPhone 17 Pro sim,
  iOS 26.3); `simctl launch` spawn 0.28–0.42 s over 3 cold launches. Signed-in navigation (Moliboo,
  Vault, Nodus UI) was not driven on the Release simulator because it has no session.
- `npm run verify:boundary`, `verify:design`, `typecheck`, `npm test` (16/16) pass.
