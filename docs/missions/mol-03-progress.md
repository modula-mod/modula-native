# MOL-03 — Moliverse Production & Distribution — progress

Owner: MSJoY Andy · Executor: Grok Bot · Scope: all 115 Moliboos (001–100 wearable + Legends 101–115, non-wearable by design)

## Phase A — inventory, canonical registry (in progress)
- Branch `mol03/registry` from origin/main 587b5e8 (includes #185 Legends).
- `Tools/moliboo/registry/generate_registry.py` derives `ios/Modula/Resources/Moliboo/moliboo_registry.json`
  (schema `modula.moliboo.registry.1`) from the Swift roster; `--check` guards drift in CI (`runtime/tests/moliboo-registry.test.ts`).
- 115 characters: 25 Originals, 15 each Angels/Underground/Enchanted/Stardust/Dreamers/Legends.
- Native model `MolibooCharacterRegistry` (renamed from MolibooRegistry to avoid the dormant 3D type), validator, 116th-character extensibility test.
- Release baseline build queued (detached worktree at ce3cc53, CODE_SIGNING_ALLOWED=NO).

## Phase B — fits / visual acceptance (code ready, awaiting run)
- `MolibooFitProfiles` + pixel-diff acceptance for the Signature Cap across still + 4 animated poses for all 100 wearables; Legends assert no cap.

## Phase C — expressions / motion (code ready, awaiting run)
- 7-state expression contract, `MolibooMotionEngine` (pure, Reduce Motion = opacity/blink only), `MolibooAnimatedFigure`, single active renderer budget.

## Phase E — packages (code ready, awaiting run)
- Reuses `ModuleReleaseTrust` (Ed25519 over sha256 hex, `modula sign` format). JSON asset-pack container (no archives, no code), atomic stage→rename activation, rollback, offline cache.

## Blockers / notes
- #186 (home clipping) still open → renderer hook wiring + Studio integration wait for it.
- GreenField `modula.package.1` descriptor lives on draft #137 (CI failing) → QA served from a local signed static server; GreenField integration will be reported PARTIAL.
