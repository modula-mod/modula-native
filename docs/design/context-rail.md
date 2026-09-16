# Context rail / Edge Loop

`ModulaEdgeLoop` is the N4G signature control. `ShellEdgeLoop` is the route-backed adapter for Home, Activity, and Profile. `ModulaContextRail` remains a compatibility wrapper around `ShellEdgeLoop`.

Home configures Following, For You, and Modules. Activity configures All, Mentions, and Requests. Profile configures Overview, Posts, and Modules. These destinations must not duplicate the loop with horizontal mode tabs.

The loop is a reel: the selection aperture stays spatially stable while items move through it. Behavior is `.looping` for Home / Activity / Profile modes and `.bounded` for contained pickers such as typography samples. Drag scrubs; release snaps to the nearest item; each boundary plays one selection haptic. Tapping an item commits the same selection. VoiceOver increment/decrement must work without dragging.

Selected cells expand from the resting ~46pt depth toward ~96pt with a transient label, then retract after about 1.75 seconds. The outer cut-in silhouette does not change height on every selection. Reduce Motion uses a short fade instead of kinetic travel.

`PostActionRail` is a related-looking but distinct right-edge control. It operates on a post object (React / Comment / Save / Share), never screen context. `TrailingInteractionSafeArea` keeps the two from colliding.

Do not use Edge Loop for Settings lists, Product Hub catalogues, search results, or message conversations.
