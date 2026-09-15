# N3C acceptance

Branch: `cursor/phase-n3c-ios-home-feed`  
Base: N3B `cursor/phase-n3b-ios-discover-6553` @ `b606526`

## Preserved chain

```text
origin/main (N2) → N3A Activity/Auth → N3B Discover → N3C Home
```

N3B was already pushed clean before N3C branched. No reset/rebase onto obsolete main.

## Greenfield

- Audited via `ssh modula-vps`
- Contract: `GET /v1/feed/home` (not bare `/v1/feed`)
- N1 `listHome` patched for `following-graph-v1`, `ranking-v1`, `modules-chrono-v1`
- Fixture: `scripts/n1/home-fixture.mjs` against isolated N1 (verified following/forYou/modules item counts)
- Production Docker image still on pre-N3C `listHome` until rebuilt — documented

## Native

- Placeholder Home removed
- Progressive header + soft scroll edge
- Home tools accessory
- Shared Social post components
- HomeFeedTests (7) passed on simulator

## Device

Physical progressive-blur / 120 Hz check: **OPEN** until device tooling confirms.

## Hermes

Home paths do not mount `ModuleHost` / React Native. Cold launch → Home must not initialize Hermes (same N1/N2 invariant).
