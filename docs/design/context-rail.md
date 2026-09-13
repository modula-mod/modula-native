# Context rail

`ModulaContextRail` is native edge-docked shell chrome. Home configures Following, For You, and Modules. Activity configures All, Mentions, and Requests. Profile configures Overview, Posts, and Modules. These destinations must not duplicate the rail with horizontal mode tabs.

The UI-polish rail is a three-position reel. The item before the selection, the selection, and the item after it are always visible; indexing wraps in both directions, so dragging or accessibility increment/decrement actions never hit a dead end. A vertical drag advances the reel after a deliberate threshold. Tapping any visible item selects it directly.

`ModulaRailShape` draws the edge cut as one continuous custom Bézier loop with a straight device-edge side. It replaces the N2 `UnevenRoundedRectangle` approximation. The visible control is 62 points wide, selected icons rest in a 46-point circle, neighboring icons retain 46-point targets, gaps stay at 12 points, and the selected object reveals to a 96-point vertical capsule. The icon-plus-label treatment rotates as one unit to preserve the narrow edge footprint. The rail uses restrained clipped material rather than applying a nonconvex custom Liquid Glass effect, which can create an unintended refractive region outside the silhouette.

Selection binds directly to the typed contextual route, plays a semantic selection haptic, reveals icon plus label, and collapses the visual label after about two seconds. The accessible name and selected trait remain when the label is hidden. Reduce Motion shortens the transition and Reduce Transparency replaces material with an opaque system surface. The rail also exposes a single adjustable accessibility element with an explicit looping hint.

The rail API is route based today and leaves room for scroll, keyboard, and immersive-state input when Feed arrives. N2 does not guess feed scrolling behavior.
