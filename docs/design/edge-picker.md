# Modula Edge Picker

The Edge Picker is the shell context control for Home, Activity, and Profile.
It is carved into the physical screen edge: a fixed selection aperture with a
vertical reel of destinations, Liquid Glass material, and an inward horizontal
label reveal.

## Purpose

Switch semantic context modes without duplicate horizontal tab menus:

| Screen | Destinations |
| --- | --- |
| Home | Following · For You · Modules |
| Activity | All · Mentions · Requests |
| Profile / Me | Overview · Posts · Modules |

## Non-usage

Do not use the Edge Picker for:

- Post / content actions (use `PostActionRail`)
- Global tab destinations (Home / Discover / Modules / Activity / Profile)
- Arbitrary continuous lists or settings enums (use `ContainedLoopPicker` for local bounded pickers)

## Architecture

```text
EdgeLoopEngine          pure reel math / drag / snap
ModulaEdgeLoop          visual + gestures + materials
ShellEdgeLoop           shell routes + Appearance preferences + placement
ContainedLoopPicker     typography / local bounded selector
```

Route ownership stays with `NavigationCoordinator.replaceContextOrTop`.
The engine never routes.

## Preferences

Persisted under Appearance (`modula.native.appearance.v2` → nested `edgePicker`).
Missing field migrates to canonical defaults.

| Preference | Options | Default |
| --- | --- | --- |
| Position | Up · Middle · Down | Middle |
| Size | Compact · Standard · Large | Standard |
| Side | Left · Right | Right |
| Labels | On Change · Always · Icons Only | On Change |
| Glass | Subtle · Standard · Strong | Standard |
| Visibility | Always Visible · Auto-hide | Always Visible |
| Motion | Follow Appearance · Reduced · Fluid | Follow Appearance |
| Haptics | Follow Appearance · Off · Light · Standard | Follow Appearance |

`Reset Edge Picker` restores only these fields.

Settings surface: `/settings/appearance/edge-picker` with a live preview that
uses the real `ShellEdgeLoop`.

## Precedence

```text
SYSTEM ACCESSIBILITY
  wins over
EDGE PICKER OVERRIDE
  wins over
GLOBAL APPEARANCE DEFAULT
```

Examples:

- Reduce Motion ON + Edge Motion Fluid → reduced path
- Reduce Transparency ON + Glass Strong → solid semantic surface
- Edge Haptics Off + Global Strong → no Edge Picker haptic

## Geometry

One continuous `EdgeLoopShape` path. Left mirrors the path; it is never a 180°
rotation. Label reveal grows the selection pill along the rail with rotated text.
Size resolves through `EdgeLoopMetrics` (depth, aperture, spacing, reveal
widths, hit slop ≥ 44pt).

## Loop presentation

Finite virtual window around selection (`index ± 2`). Far previews are quiet
(opacity / scale). Accessibility exposes only the real semantic destinations —
loop clones are not accessibility elements.

## Materials

Semantic tokens: `edgeLoopBody`, `edgeLoopSelection`, `edgeLoopReveal`.
Selection is accent-tinted glass, not a flat solid capsule. OLED stays near-black.

## Interaction

- Vertical drag only; local drag state
- One haptic (+ tick) per semantic boundary; no duplicate snap haptic
- Tap animates destination into the aperture
- Auto-hide retreats toward the edge but never to zero discoverability;
  VoiceOver keeps the control stable

## Contained vs shell

`ContainedLoopPicker` shares the engine. Shell-only prefs (Position, Side,
Auto-hide) do not apply to contained pickers.
