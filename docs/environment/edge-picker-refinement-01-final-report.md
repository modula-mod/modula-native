# MODULA NATIVE — EDGE PICKER REFINEMENT 01 FINAL REPORT

STARTING BRANCH: phase-n4-integration-closeout
STARTING HEAD: b85c42b0e38aa79abe58f86b9144806e02c2ee89
FINAL BRANCH: phase-n4-integration-closeout
FINAL HEAD: 0e7f5a7 (feat(edge-picker): Liquid Glass body, prefs, and horizontal reveal)
WORKTREE: product changes committed; local `.cursor/*` / `AGENTS.md` noise left uncommitted

## 1. ARCHITECTURE
EdgeLoopEngine: continuous anchor + configurable stride; looping / bounded unchanged
ModulaEdgeLoop: Liquid Glass body, horizontal reveal, metrics, auto-hide, a11y adjustable
ShellEdgeLoop: reads Appearance.edgePicker; left/right; Up/Middle/Down anchor; preview binding
ContainedLoopPicker: shared engine; shell Position/Side/Auto-hide do not apply
Route semantics changed: NO

## 2. PREFERENCES
Storage: AppearanceStore `modula.native.appearance.v2` nested `edgePicker` (optional decode → defaults)
Migration: yes — missing field → `.default`
Position: Up / Middle / Down — default Middle
Size: Compact / Standard / Large — default Standard
Side: Left / Right — default Right
Labels: On Change / Always / Icons Only — default On Change
Glass: Subtle / Standard / Strong — default Standard
Visibility: Always / Auto-hide — default Always
Motion: Follow Appearance / Reduced / Fluid — default Follow Appearance
Haptics: Follow Appearance / Off / Light / Standard — default Follow Appearance
Reset: `resetEdgePicker()` only — confirmation dialog
Persistence: tested via UserDefaults suite unit tests

## 3. LIVE PREVIEW
Uses real component: YES (`ShellEdgeLoop` + previewSelection)
Drag / Haptics / Position / Size / Side / Glass / Label / Visibility: YES (prefs bind live)

## 4. MATERIAL
Liquid Glass body: YES (`edgeLoopBody` recipes)
Selection / Reveal: accent-tinted glass capsules
Subtle / Standard / Strong: semantic material recipes
OLED: near-black sink overlay
Light / Dark / Dim: scheme-aware
Reduce Transparency: solid secondarySystemBackground fallback
Increase Contrast: stronger edge stroke

## 5. GEOMETRY
Continuous shape: YES (`EdgeLoopShape` single path, mirrored L/R)
Compact / Standard / Large resting depths: ~40 / 46 / 54
Reveal min/max Standard: 84–126 (scaled by size / Dynamic Type)
Right / Left geometry: mirrored paths + inward reveal
Up / Middle / Down: semantic frame alignment (clamped by top/bottom padding)
Safe-area clamping: bottom pad 80 + top 48; preference not rewritten

## 6. LOOP PRESENTATION
Visible window: ±2 slots; far opacity ~0.28
Duplicate suppression: decorative clones not buttons / not a11y
Neighbour hierarchy: scale + opacity
Looping / Bounded: preserved

## 7. LABELS
On Change / Always / Icons Only: implemented
Orientation: horizontal inward (vertical text removed)
Adaptive width: measured + clamped
Reveal timing: ~1.75s hold; generation-cancelled
Rapid-selection cancellation: generation token

## 8. INTERACTION
Tap / Drag / Snap: yes
Gesture threshold: 10pt; momentum only past half stride
Scroll conflict: hit region = control frame
Auto-hide: retreats depth/opacity; VoiceOver disables auto-hide
Wake: first touch restores full state
Background: collapses On Change reveal

## 9. HAPTICS
Follow Appearance / Off / Light / Standard: wired via `HapticEngine`
Boundary: one per crossing (+ tick when enabled)
Tap: confirmation when not from drag
Duplicate snap haptic: avoided
Physical-device result: build+install succeeded on `modula.digital`; haptic feel still needs hands-on PASS note

## 10–12. HOME / ACTIVITY / PROFILE
Routing unchanged; state preservation via existing replaceContextOrTop
Position/Size/Side: preference-driven; screen-specific absolute Y still coarse (frame alignment) — Profile cover-aware absolute geometry is PARTIAL

## 13. POST ACTION RAIL
Architecture separate: YES
Side-aware insets: `EdgeInteractionSafeArea` + leading/trailing environment

## 14. ACCESSIBILITY
VoiceOver: single adjustable element; clones hidden
Dynamic Type: reveal widths scale; DynamicTypeSize capped at accessibility3
Reduce Motion / Transparency: override prefs
Differentiate Without Colour: scale + material + label remain
Switch Control / Voice Control: destination names retained in Icons Only

## 15. APPEARANCE INTEGRATION
Theme / OLED / Accent / Density / Motion / Haptics: yes
Module Branding: does not recolor Edge Picker
Preference precedence: documented in `docs/design/edge-picker.md`

## 16. PERFORMANCE
Local drag rendering: engine local state
Material: one body + selection/reveal region
Task cleanup: collapse + auto-hide cancelled on disappear
Time Profiler / feed invalidation: NOT fully instrumented this run (PARTIAL)

## 17. DEVICE ACCEPTANCE
iPhone: modula.digital (27.0) online
Debug install: SUCCEEDED (`digital.modula.app.native`)
Hands-on Home / Activity / Profile / left-hand / haptic tuning screenshots: PENDING user review

## 18. TESTS
Engine + prefs + metrics + materials + chrome contracts: PASS (19 selected)
UITests for new prefs: not expanded this commit

## 19. DOCUMENTATION
Surface system: updated
Edge Picker design doc: `docs/design/edge-picker.md`
Component Catalog: Edge Picker section renamed
Start truth: `docs/environment/edge-picker-refinement-01.md`

## 20. WARNINGS
- Profile absolute Y still uses shared Up/Middle/Down frame alignment, not cover/identity-specific math
- Physical haptic / left-hand review not yet signed off by a human pass
- Instruments Time Profiler not captured

## 21. KNOWN LIMITATIONS
- Contained picker ignores shell Position/Side/Auto-hide by design
- Auto-hide quiet state is depth+opacity retreat, not a second silhouette design
- PostActionRail material hierarchy differentiation is light (shared tokens)

## 22. FINAL VERDICT
PARTIAL

Reason: core product refinement is landed, unit-tested, documented, and installed on the physical device, but mandatory hands-on physical acceptance (haptics, left-hand, Profile geometry) and Instruments review remain open.
