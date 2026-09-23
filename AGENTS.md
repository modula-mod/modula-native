## Learned User Preferences

- Prefer autonomous execution once a mission or plan is approved; short go-aheads like "build it" / "do it" mean continue without re-asking.
- When implementing an attached plan, do not edit the plan file; use the existing todos and mark them in progress rather than recreating them.
- Prefer real production Greenfield sign-in for day-to-day Debug auth work when asked for "real" login; keep N1 fixture hosts for acceptance harnesses only.
- When `modula.digital` is online, prefer physical-device install and walkthrough before more source work on acceptance/closeout gates.
- Visual direction: high-end native iOS, restrained Liquid Glass, image-led hierarchy, Modula Teal `#369CAA`; never generic, cyberpunk, or glass-everywhere.
- Inspect `/developer/components` before adding design-system components; improve existing Modula components rather than inventing parallel ones.
- Never print, commit, or ask in chat for secrets (`.env.n1.local`, passwords, tokens, fixture credentials); never fabricate ratings, screenshots, permissions, privacy claims, or catalogue/release data; unavailable Settings capabilities get designed UI with honest API footnotes rather than invented catalogue/billing/privacy data—preserve real Greenfield truth.
- Home/Activity/Profile mode switching must use the contextual Edge Picker / right rail only—no horizontal duplicate tab menus or second segmented controls.
- Edge Picker should feel edge-carved into the screen (not an attached sidebar): exactly 3 visible items (no duplicate loop icons), vertical labels, Modula glass buttons with accent tint, scroll/scrub selection only (not tap), deliberate less-sensitive drag, hit testing bound to the silhouette (not an expanded off-rail column), and no top/bottom fades.
- Do not restart the project or return to Expo; preserve N1 ModuleHost ownership and the native shell architecture.
- Keep N4 closeout and N5 Object OS workstreams separate; do not mix N5 into incomplete N4 recovery/acceptance.
- Work only in `/Users/msjoy/Developer/modula-native` (not sibling clones like `modula-native-main`); Saved/Drafts/Settings open from the leading hamburger sidebar (`line.3.horizontal`), not the profile photo; Settings progressive identity collapses toward the island region (not Live Activities) and must not duplicate rows that open the same Appearance destinations; AI entry is a detached `pencil.and.scribble` circle with rim-only shimmer—never `TabRole.prominent`; never present `DeterministicLocalProvider` as a real model.

## Learned Workspace Facts

- `modula-native` is a Swift/SwiftUI iOS app; React Native exists only inside ModuleHost for module execution after `/module/:moduleId`.
- Backend is Greenfield; authorized VPS access is via SSH host `modula-vps`.
- Five global destinations: Home, Discover, Modules, Activity, Profile; typed canonical routes are authoritative; Saved/Drafts/Settings live in the leading sidebar.
- `AppearanceStore` is the sole theme authority; `ShellChromePolicy` and `PresentationCoordinator` govern shell chrome; top chrome should match the Settings system toolbar (capsule share/options, no duplicate status-bar controls).
- Edge Picker stack is `EdgeLoopEngine` → `ModulaEdgeLoop` → `ShellEdgeLoop` (Home/Activity/Profile) and `ContainedLoopPicker`; preferences persist under Appearance (`/settings/appearance/edge-picker`).
- Module runtime constraints: credential-free modules (JS gets no account credentials), HostBridge validation, ModuleSession security, one lazy Hermes runtime, Release operation without Metro.
- Local Intelligence (`ModulaIntelligence`) is on-device fail-closed Swift: IntelligenceRouter, ProviderRegistry, ToolRegistry, privacy policy, and DeterministicLocalProvider; shares protocol semantics with Greenfield, not runtime code.
- Bottom Tools row uses system `tabViewBottomAccessory` and minimizes with the tab bar; Discover uses one Liquid Glass search bar with inline Customise/Options and glass scope chips; Home hashtag accessory opens Feeds while Compose stays on top `+`.
- Common physical test device alias is `modula.digital` (iPhone 17 Pro Max); Developer Mode enabled for device installs.
- Debug API base URL is commonly overridden via gitignored local xcconfig (`Debug.local.xcconfig`); N1 fixture host is `native-n1.modula.digital`, production is `api.modula.digital`.
- UITests under AppGate should traverse gate → auth/onboarding → shell via shared fixture helpers; prefer fixture sign-in over fake `.ready` shortcuts, and never disable App Lock permanently or bake secrets into the binary.
- N5 Object OS direction: native shell owns object transport, privacy, and cross-module mediation; modules declare capabilities and the shell mediates; Living Posts/Profiles use constrained declarative surfaces (not arbitrary RN/WebView); Greenfield enforces shared privacy/state.
