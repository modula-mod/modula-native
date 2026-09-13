# Appearance

`AppearanceStore` is the sole owner of device-local presentation preferences. It persists a versioned snapshot in `UserDefaults` and applies changes live. N2 does not claim Greenfield account synchronization.

Supported axes are System/Light/Dark theme; Standard/Dim/OLED dark style; curated accent; curated semantic font family; Modula text-size intent; Default app icon; Compact/Standard/Comfortable density; Calm/Standard/Expressive motion; Off/Light/Standard/Strong haptics; Standard/Higher Contrast/Reduce Transparency; Outline/Balanced/Filled icons; Soft/Balanced/Precise interface shape; and Module Identity/Blend/Prefer My Accent module branding.

System Dynamic Type and accessibility settings remain authoritative. Reduce Motion constrains design-system animations. Increase Contrast and Reduce Transparency combine with the Modula preference. OLED uses black for the canvas and sparse elevation instead of placing every component on an opaque grey rectangle. Only the production Default icon is selectable until approved alternate icon assets exist.

Reset Appearance restores only these preferences. The live preview and `/developer/components` are the acceptance surfaces.
