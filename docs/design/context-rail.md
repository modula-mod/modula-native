# Context rail

`ModulaContextRail` is native edge-docked shell chrome. Home configures Following, For You, and Modules. Activity configures All, Mentions, and Requests. Profile configures Overview, Posts, and Modules. These destinations must not duplicate the rail with horizontal mode tabs.

The UI-polish rail is a three-position reel. The item before the selection, the selection, and the item after it are always visible; indexing wraps in both directions, so dragging or accessibility increment/decrement actions never hit a dead end. A vertical drag advances the reel after a deliberate threshold. Tapping any visible item selects it directly.

`ModulaRailShape` draws the edge cut as one continuous custom Bézier loop with a straight device-edge side. It replaces the N2 `UnevenRoundedRectangle` approximation. The visible cut is 54 points wide and opaque black, selected icons rest in a 46-point circle, neighboring icons retain 46-point targets, gaps stay at 12 points, and the selected object reveals to a 96-point vertical capsule. The contents sit two points toward the screen edge to compensate for the asymmetric belly. While revealed, the selected icon is replaced by the rotated word so it cannot ghost through the capsule. The custom shape is explicitly nonisolated for Swift 6 off-main rendering.

Selection binds directly to the typed contextual route, plays a semantic selection haptic, morphs from icon to label, and collapses the visual label after about two seconds. The accessible name and selected trait remain when the label is hidden. Reduce Motion shortens the transition. The rail also exposes a single adjustable accessibility element with an explicit looping hint.

The rail API is route based today and leaves room for scroll, keyboard, and immersive-state input when Feed arrives. N2 does not guess feed scrolling behavior.
