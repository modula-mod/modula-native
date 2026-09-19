# Motion and haptics

Motion roles are selection, navigation, morph, reveal, dismiss, rail expand, rail collapse, and sheet present. Calm uses short restrained easing; Standard uses a controlled spring; Expressive permits more spring response. The design system chooses parameters and iOS Reduce Motion constrains all personalities.

Haptic roles are selection, navigation, confirmation, warning, success, failure, and impact. `HapticEngine` maps them to the user's Off/Light/Standard/Strong intent. Native views and N1 HostBridge requests use this engine; feature code must not create raw feedback generators.
