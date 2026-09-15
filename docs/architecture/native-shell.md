# Native shell

The Modula application shell is SwiftUI. It owns Home, Discover, Product Hub, Activity, Profile, Search, composer presentation, Settings, Appearance, navigation, shell chrome, native module detail, and `ModuleHost`. React Native begins only below `ModuleHost`.

The five frozen destinations are Home, Discover, Modules, Activity, and Profile. Modules maps to `/product-hub/featured`; Profile maps to `/me`. A native `TabView` retains one `NavigationStack` per destination and supplies the visible global navigation on iOS 26 and later. It uses the system `tabViewBottomAccessory` and `onScrollDown` minimization, allowing the selected tab and accessory to morph into compact native chrome. `ModulaTabBar` and `ModulaBottomChrome` remain the iOS 18 fallback. `NavigationCoordinator` preserves each stack and contextual root independently.

The tab bar remains navigation-only and always contains the same five destinations. Its separate shell accessory (`ShellAccessoryHost`) supplies destination tools. On Activity it exposes Summary, Filter, and Mark All Read — never All/Mentions/Requests, which belong only to `ModulaContextRail`. Other destinations keep Search and More until they define their own tools. `ShellChromePolicy` hides the tab bar, rail, and accessory on `/auth/*` and `/settings/account/*`.

`ShellChromePolicy` is the only route-to-chrome decision point. Feature views must not invent tab bars, rails, or route-specific shell conditionals. `PresentationCoordinator` owns shell-level sheets and banners. Platform sheets use native presentation semantics.

The attached N2 references guide hierarchy: image-led hero regions, restrained material on floating chrome, clean white or true-black canvases, teal as a semantic accent, and an edge-docked contextual rail. They are direction, not permission to fabricate product data or duplicate feed-mode tabs.
