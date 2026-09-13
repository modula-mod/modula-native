# Native shell

The Modula application shell is SwiftUI. It owns Home, Discover, Product Hub, Activity, Profile, Search, composer presentation, Settings, Appearance, navigation, shell chrome, native module detail, and `ModuleHost`. React Native begins only below `ModuleHost`.

The five frozen destinations are Home, Discover, Modules, Activity, and Profile. Modules maps to `/product-hub/featured`; Profile maps to `/me`. A native `TabView` retains one `NavigationStack` per destination while `ModulaTabBar` supplies the visible global navigation. `NavigationCoordinator` preserves each stack and contextual root independently.

`ShellChromePolicy` is the only route-to-chrome decision point. Feature views must not invent tab bars, rails, or route-specific shell conditionals. `PresentationCoordinator` owns shell-level sheets and banners. Platform sheets use native presentation semantics.

The attached N2 references guide hierarchy: image-led hero regions, restrained material on floating chrome, clean white or true-black canvases, teal as a semantic accent, and an edge-docked contextual rail. They are direction, not permission to fabricate product data or duplicate feed-mode tabs.
