# MODULA NATIVE — EDGE PICKER REFINEMENT 02 FINAL REPORT

STARTING BRANCH: `phase-n4-integration-closeout`
STARTING HEAD: `df2b96627d0965af0b3f2de1f1f1c01672502763`
FINAL BRANCH: `phase-n4-integration-closeout`
FINAL HEAD: `df2b96627d0965af0b3f2de1f1f1c01672502763` (uncommitted refinement-02 source; no commit requested)
WORKTREE: Dirty with Edge Picker Refinement 02 + prior N4G/refinement lineage. Start truth: `docs/environment/edge-picker-refinement-02.md`.

## 1. CANONICAL GEOMETRY

Reference preserved: Yes — narrow channel + long S-curves targeted; broad mid-bulb / expanding waist removed.
Continuous shape: Yes — single `EdgeLoopShape` / `EdgePickerCarvedShape` path (cubics + straight channel wall).
Central channel: Straight wall between ~33–67% of rail height.
Upper curve: Long cubic from edge → channel (control points hold near-edge then straighten).
Lower curve: Mirrored cubic exit.
Compact / Standard / Large: Channel depths ~40 / 46 / 54pt (density-scaled); selection widths ≤ channel.

## 2. LIQUID GLASS

Body: `modulaChrome` on the carved silhouette + intensity sink (OLED near-black).
Selected aperture: Separate capsule glass + ~20–30% accent tint.
OLED: Near-black sink / opaque fallback ~0.92–0.96.
Dark / Dim / Light: Intensity recipes via `ModulaMaterial.edgeLoopBody`; Light uses stronger material for readability.
Reduce Transparency: Opaque semantic fill; same silhouette.

## 3. SELECTION APERTURE

Collapsed width: ~38–50pt (size-scaled, inside channel).
Collapsed height: ~46–54pt.
Expanded min / max: ~84–104 / ~112–132pt (Dynamic Type scaled).
Integrated with channel: Yes — expands vertically only; outer carve unchanged.
Accent treatment: Glass-primary + restrained accent stroke/fill (~70/30).

## 4. VERTICAL LABELS

Whole-text rotation: Yes (`Text` + `rotationEffect`, never stacked letters).
Right-edge rotation: `-90°`.
Left-edge rotation: `+90°` (no negative-scale glyph flip).
On Change / Always / Icons Only: Preserved; drag suppresses transient expand.
Adaptive height: From unrotated text width + padding, clamped.
Dynamic Type: Caption style measurement; capsule grows.
Timer cancellation: Generation token on collapse task.

## 5. REEL

Fixed selection: Centre aperture fixed; items move.
Virtual window: `visibleRadius = 1` (three visible).
Curve clipping: Reel masked to carved shape.
Duplicate suppression: Far slots not emphasised; fade into curves while dragging.
Neighbour hierarchy: Opacity / scale from metrics.

## 6. INTERACTION

Tap: Disabled (scrub-only; short travel cancels). Matches learned Edge Picker preference.
Drag / Snap: Local engine state; crisp spring settle (stiffer damping).
Threshold: `commitThreshold = 0.55` stride; sensitivity `0.78`.
Scroll conflict: Hit testing bound to hit-shaped silhouette (not full column spacers).
Rapid scrub: Coast ticks capped; fling ≤ 1.5 items.

## 7. HAPTICS

Boundary: One selection haptic + tick per crossed item.
Snap: No extra snap haptic.
Tap: N/A (no tap select); VoiceOver adjust still haptics on commit.
Physical tuning: Installed on `modula.digital` — user feel review still required for PASS.

## 8. POSITION / SIZE / SIDE

Up / Middle / Down: Spacer positioning unchanged (non-hit-testable).
Compact / Standard / Large: Via `EdgeLoopMetrics.resolve`.
Right / Left: Mirrored path + side-aware label rotation.
Safe-area clamping: Existing RootView top/bottom padding + `EdgeInteractionSafeArea` side insets.

## 9. HOME / 10. ACTIVITY / 11. PROFILE

Code paths unchanged (ShellEdgeLoop destinations). Physical visual review pending on device (app launched after install).

## 12. POST ACTION RAIL

Collision: `EdgeInteractionSafeArea` / `TrailingInteractionSafeArea` unchanged contract (side-aware leading/trailing clearance).
Leading Picker: Clearance moves to leading; trailing rail stays.
Trailing Picker: Trailing clearance reserved.

## 13. ACCESSIBILITY

VoiceOver: Full phrase labels; adjustable increment/decrement; clones `accessibilityHidden`.
Dynamic Type: Capsule height tracks text; clamped.
Reduce Motion: Short ease snaps / minimal expand.
Reduce Transparency: Opaque carved body.
Increase Contrast: Stronger strokes / icon opacity.
Differentiate Without Colour: Size + material + vertical label carry selection.

## 14. PERFORMANCE

Shape metrics stable during scrub (depth/fractions not per-frame store churn).
Materials not swapped per drag frame (position/opacity/scale only).
Instruments / whole-feed invalidation: Not profiled this run — deferred to Mac closeout.

## 15. PHYSICAL DEVICE

iPhone: `modula.digital` (iPhone 17 Pro Max) — connected, Debug build installed, app launched.
iOS: Device OS as paired.
Right / Left / Haptics / Screenshots: Pending hands-on acceptance with user.

## 16. TESTS

Geometry: `EdgePickerCarvedShapeTests` (bounds, monotonic landmarks, mirror, size presets) — PASS.
Loop / prefs / metrics / materials: 21 selected unit tests — PASS (`** TEST SUCCEEDED **`).
UI / snapshot / Instruments: Not run this pass.

## 17. DOCUMENTATION

- `docs/environment/edge-picker-refinement-02.md` (start truth)
- `docs/design/edge-picker.md` (canonical carved contract)
- `docs/architecture/n4g-surface-system.md` (geometry/material contract)
- Developer catalog Edge Picker blurb updated
- This report

## 18. WARNINGS

- No git commit created (not requested).
- Physical silhouette / haptic / left-hand acceptance still needs human eyes on `modula.digital`.
- Snapshot tests and Instruments not executed in this run.

## 19. KNOWN LIMITATIONS

- Curve control-point tuning may still need on-device nudge toward the orange reference.
- ContainedLoopPicker intentionally does not use the shell carve.
- Auto-hide only quiets depth/opacity — silhouette family unchanged by design.

## 20. VERDICT

**PARTIAL**

Source geometry, materials, vertical labels, reel clipping, metrics, unit tests, docs, and physical install are in place. Full **PASS** requires completed on-device visual/haptic acceptance (Home / Activity / Profile / left-hand) and optional Instruments confirmation.
