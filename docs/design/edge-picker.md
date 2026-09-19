# Modula Edge Picker

The Edge Picker is the shell context control for Home, Activity, and Profile.

> The canonical shell geometry is a narrow edge-carved channel with long
> S-shaped entry/exit curves. Vertical labels are rendered by rotating complete
> text labels, never by stacking characters.

It is carved into the physical screen edge: a fixed selection aperture with a
vertical reel of destinations and Liquid Glass material on the carved body
itself. The selected control expands **vertically inside the channel**; the
outer cutout does not swell with the label.

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

One continuous `EdgeLoopShape` / `EdgePickerCarvedShape` path. Left mirrors the
path mathematically; content is never flipped with a negative scale.

Canonical silhouette (orange reference):

- Narrow straight central channel (most of the active height)
- Long cubic upper / lower transitions (not a broad mid bulb)
- Selected aperture lives **inside** the channel
- Outer carved silhouette stays stable when the label reveals

Size resolves through `EdgeLoopMetrics` (channel depth, selection width/heights,
curve fractions, spacing, hit slop ≥ 44pt). Typical Standard channel depth is
~44–48pt.

## Labels

Vertical whole-phrase rotation:

- Right edge ≈ `-90°` (reads naturally along the edge)
- Left edge ≈ `+90°` (readable from the screen interior)
- Never stack individual characters (`F` / `o` / `r`…)

On Change expands the aperture after commit (~1.75s), then collapses.
Always keeps the selected capsule expanded. Icons Only never expands for text.
VoiceOver always speaks the full semantic label.

## Loop presentation

Finite virtual window around selection (`index ± 1` → three visible). Far slots
fade into the carved curves — with three Home/Activity/Profile destinations this
avoids reading as five duplicate icons. Accessibility exposes only the real
semantic destinations; loop clones are not accessibility elements.

## Materials

Semantic tokens: `edgeLoopBody`, `edgeLoopSelection`, `edgeLoopReveal`.

- Body = quiet Liquid Glass on the carved shape itself
- Selection aperture = stronger glass + accent tint (~70% material / 30% accent)
- OLED body ≈ near-black refractive glass
- Reduce Transparency → opaque semantic surface, same silhouette

Inactive icons sit directly in the channel with no per-icon capsules.

## Interaction

- Vertical scrub/drag only; local drag state. Icons are not tappable — short
  presses cancel without changing selection. VoiceOver uses the adjustable action.
- Hit testing is silhouette-bound (not the full screen-edge column), with a
  modest inward hit extension for Compact / one-handed use. Spacers that position
  Up/Middle/Down do not accept gestures.
- Selection aperture uses interactive Liquid Glass (`modulaChrome`), matching
  Profile floating glass controls.
- One haptic (+ tick) per semantic boundary; no duplicate snap haptic
- Auto-hide may quiet opacity / depth slightly but must not replace the carved
  silhouette; VoiceOver keeps the control stable

## Contained vs shell

`ContainedLoopPicker` shares the engine and selection capsule. It does **not**
use the shell carved-edge silhouette. Shell-only prefs (Position, Side,
Auto-hide) do not apply to contained pickers.
