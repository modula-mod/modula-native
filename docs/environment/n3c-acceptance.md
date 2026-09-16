# N3C acceptance

Branch: `cursor/phase-n3c-ios-home-feed` @ `812a95e`  
Base: N3B `cursor/phase-n3b-ios-discover-6553` @ `b606526`

## Preserved chain

```text
origin/main (N2) → N3A Activity/Auth → N3B Discover → N3C Home
```

N3B was already pushed clean before N3C branched. No reset/rebase onto obsolete main.

## Greenfield (production rebuilt)

- Canonical patch committed and merged: `modula-mod/modula-latest` PR [#98](https://github.com/modula-mod/modula-latest/pull/98) → merge `7dd77c38`
- Deployed immutable images from source SHA `ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65`
  - `modula-greenfield-api:ff228cd…`
  - `modula-greenfield-worker:ff228cd…`
  - compose `--no-deps` replace only (Postgres/Redis untouched)
- Public contract verified:
  - `following` unsigned → empty + `following-graph-v1`
  - `forYou` → `ranking-v1` + score cursor `score|createdAt|id`
  - `modules` → `modules-chrono-v1`
- N1 fixture: `scripts/n1/home-fixture.mjs` (deterministic ranking versions)
- Visibility: `scripts/n1/home-visibility-probe.mjs` PASS (block/mute/delete excluded server-side)

## Native

- Progressive header: large → compact centered crossfade; soft top dissolve under status bar
- Soft-edge path recorded via accessibility value: `native-soft-edge` on iOS 26 simulator
- Fallback masked material remains for Reduce Transparency / pre-iOS 26
- Home tools accessory: Compose / Summary / Feed Tools
- Shared Social post components
- HomeFeedTests + N3CHomeUITests (landmarks + progressive header stages)

## Device

Physical device `modula.digital` (iOS 27) available; Debug install + launch performed. Progressive-header scroll-stage visual evidence captured on iPhone 17 Pro iOS 26 simulator (native soft-edge). Full OLED / Reduce Transparency / Reduce Motion matrix + 120 Hz Instruments frame pacing remain best-effort on device.

## Hermes

Home paths do not mount `ModuleHost` / React Native. Cold launch → Home must not initialize Hermes (same N1/N2 invariant).
