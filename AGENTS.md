## Learned User Preferences

- Prefer autonomous execution once a mission or plan is approved; short go-aheads like "build it" / "do it" mean continue without re-asking.
- When implementing an attached plan, do not edit the plan file; use the existing todos and mark them in progress rather than recreating them.
- Prefer real production Greenfield sign-in for day-to-day Debug auth work when asked for "real" login; keep N1 fixture hosts for acceptance harnesses only.
- When `modula.digital` is online, prefer physical-device install and walkthrough before more source work on acceptance/closeout gates.
- Visual direction: high-end native iOS, restrained Liquid Glass, image-led hierarchy, Modula Teal `#369CAA`; never generic, cyberpunk, or glass-everywhere.
- Inspect `/developer/components` before adding design-system components; improve existing Modula components rather than inventing parallel ones.
- Never print, commit, or ask in chat for secrets (`.env.n1.local`, passwords, tokens, fixture credentials); use existing SSH/env configuration.
- Never fabricate ratings, screenshots, permissions, privacy claims, or catalogue/release data; preserve real Greenfield truth.
- Home/Activity/Profile mode switching must use the contextual Edge Picker / right rail only—no horizontal duplicate tab menus or second segmented controls.
- Edge Picker should feel edge-carved into the screen (not an attached sidebar): exactly 3 visible items (no duplicate loop icons), vertical labels, Modula glass buttons, scroll/scrub selection only (not tap), deliberate less-sensitive drag, hit testing bound to the silhouette (not an expanded off-rail column), and no top/bottom fades.
- Do not restart the project or return to Expo; preserve N1 ModuleHost ownership and the native shell architecture.
- Keep N4 closeout and N5 Object OS workstreams separate; do not mix N5 into incomplete N4 recovery/acceptance.

## Learned Workspace Facts

- `modula-native` is a Swift/SwiftUI iOS app; React Native exists only inside ModuleHost for module execution after `/module/:moduleId`.
- Backend is Greenfield; authorized VPS access is via SSH host `modula-vps`.
- Five global destinations: Home, Discover, Modules, Activity, Profile; typed canonical routes are authoritative.
- `AppearanceStore` is the sole theme authority; `ShellChromePolicy` and `PresentationCoordinator` govern shell chrome.
- Edge Picker stack is `EdgeLoopEngine` → `ModulaEdgeLoop` → `ShellEdgeLoop` (Home/Activity/Profile) and `ContainedLoopPicker`; preferences persist under Appearance (`/settings/appearance/edge-picker`).
- Module runtime constraints: credential-free modules (JS gets no account credentials), HostBridge validation, ModuleSession security, one lazy Hermes runtime, Release operation without Metro.
- Appearance modes to verify include Light, Standard Dark, Dim, and OLED (plus density/Dynamic Type/contrast/transparency when polishing UI).
- Component Catalog at `/developer/components` is the canonical visual reference for the design system.
- Common physical test device alias is `modula.digital` (iPhone 17 Pro Max); Developer Mode enabled for device installs.
- Debug API base URL is commonly overridden via gitignored local xcconfig (`Debug.local.xcconfig`); N1 fixture host is `native-n1.modula.digital`, production is `api.modula.digital`.
- UITests under AppGate should traverse gate → auth/onboarding → shell via shared fixture helpers; prefer fixture sign-in over fake `.ready` shortcuts, and never disable App Lock permanently or bake secrets into the binary.
- N5 Object OS direction: native shell owns object transport, privacy, and cross-module mediation; modules declare capabilities and the shell mediates; Living Posts/Profiles use constrained declarative surfaces (not arbitrary RN/WebView); Greenfield enforces shared privacy/state.
