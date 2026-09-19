# Edge Picker Refinement 02 — Start Truth

Recorded: 2026-09-19 during Edge Picker carved-edge geometry refinement.

## Repository identity

| Field | Value |
| --- | --- |
| Working directory | `/Users/msjoy/Developer/modula-native` |
| Branch | `phase-n4-integration-closeout` |
| HEAD | `df2b96627d0965af0b3f2de1f1f1c01672502763` |
| Remote tip | up to date with `origin/phase-n4-integration-closeout` |

## Worktree at start

Dirty / untracked (preserved; not reset/stashed):

- Modified: `.cursor/hooks/state/continual-learning.json`
- Modified: `docs/design/edge-picker.md`
- Modified: `ios/Modula/DesignSystem/EdgeLoop/EdgeLoopEngine.swift`
- Modified: `ios/Modula/DesignSystem/EdgeLoop/EdgeLoopMetrics.swift`
- Modified: `ios/Modula/DesignSystem/EdgeLoop/ModulaEdgeLoop.swift`
- Untracked: `.cursor/hooks/state/continual-learning-index.json`, `.cursor/hooks/state/n4b-caf1-trigger.txt`, `AGENTS.md`, `docs/environment/n4-final-acceptance-start.md`

Prior uncommitted lineage on this branch already includes vertical labels, scrub-only selection, silhouette-bound hit testing, and Liquid Glass aperture work from the N4G / Refinement 01 line.

## Mission scope

Correct Edge Picker silhouette toward the orange reference:

- Narrow straight central channel (not a broad bulb / sidebar)
- Long S-shaped upper/lower cubic transitions
- One continuous carved `Shape` path
- Liquid Glass on the carved body itself
- Fixed outer silhouette; selected aperture expands vertically inside the channel
- Vertical labels via whole-text rotation (never stacked characters)
- Left/right mirroring without mirrored glyphs
- Reel fade/clip into curves; three visible destinations
- Size / position / side / a11y / materials polish

## Non-goals

Routing, EdgeLoopEngine rewrite, bottom navigation, new modes, Edge Pocket, N5, PostActionRail redesign, backend.

## Architecture preserved

```text
EdgeLoopEngine
  ├── ModulaEdgeLoop
  ├── ShellEdgeLoop (Home / Activity / Profile)
  └── ContainedLoopPicker (Appearance / Typography)
```
