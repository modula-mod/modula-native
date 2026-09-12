# Appearance inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Source: `src/theme/contracts/appearance.ts`, `data/defaults.ts`, `data/accents.json`, `runtime/resolveAppearance.ts`, `storage/appearanceStorage.ts`, `src/data/repositories/api/ApiAppearanceRepository.ts`.

- Modes: system/light/dim/dark/oled. Families: standard/forest/ocean/plum/espresso/spaceGray. Surface: native/solid/glass/glay/minimalSpatial/skeuomorphic/neomorphic.
- Default system + standard + modulaTeal + native. Verified accent `#369CAA`. Custom accent validation and contrast resolution exist. Family palettes and OLED canvas are semantically meaningful; old geometry and blur formulas do not carry.
- Local cache `modula.appearance.preferences.v1` contains schemaVersion 2 and server version. Account GET/PATCH `/v1/accounts/me/appearance` maps family→variant, surfaceType→surface; optimistic `expectedVersion` prevents blind overwrite.
- Synced fields: mode, variant, surface, accentId, customAccent, textScale, boldText, reduceMotion, reduceTransparency, increaseContrast. Adapter encodes system-following accessibility values.
- Device-only: webPresentation (browser rendering axis), differentiateWithoutColor, showSwitchLabels, advancedChromeEffect cameraMaskedBlur. They are not in the appearance PATCH. Camera effect is a preview, not a native requirement.
- RN system accessibility lacks some public OS signals; do not preserve false defaults as native truth. SwiftUI can read native environment values.

CARRY semantic names/brand/contracts; NATIVE_REWRITE store and rendering; RETIRE webPresentation from iOS; REFERENCE_ONLY speculative surface treatments and camera chrome. N1 proves system/light/dark/OLED semantics and environment propagation. Full account appearance synchronization belongs to N2; do not label local settings account-synced until implemented.

