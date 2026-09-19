# N2 native iOS UI polish acceptance

Date: 2026-09-14  
Re-verified: 2026-09-15

Branch: `phase-n2-ios-ui-polish`  
HEAD at acceptance close: `3b63c4f12a3932968d623ebe3c11a6757fd9d48c`

Base: exact frozen N2 commit `75e4b3a788cdb2a54eee995ae43c1365d6892d5c`  
Frozen branch `phase-n2-ios-sovereign-shell` remains untouched at that SHA.

## Scope

This pass refines the SwiftUI-owned shell, floating bottom navigation and accessory, looping contextual rail, Home, Discover and Activity foundations, Product Hub, Vault Module Detail, Profile foundation, Settings, Appearance, and `/developer/components`. React Native remains confined to `ModuleHost`; routing, `ShellChromePolicy`, `PresentationCoordinator`, `AppearanceStore`, catalogue truth, HostBridge validation, ModuleSession security, and the lazy single-Hermes-runtime boundary are unchanged.

## Visual decisions

- Home has one native large `Modula` navigation title. It collapses to the inline title while scrolling and never renders a duplicate in page content.
- iOS 26+ uses the native Liquid Glass tab bar, native bottom accessory, and system `onScrollDown` minimization. This removes the stacked third surface visible in the first polish capture. iOS 18 retains the compact custom fallback.
- The accessory contains Search and a sectioned More menu; it is not a sixth tab and does not duplicate contextual mode selection.
- The edge rail is a continuous custom loop shape. Its three-item reel wraps both directions; 46-point selected geometry reveals to 96 points, with persistent 12-point gaps.
- Home, Product Hub, Module Detail, and Profile replace gradient/SF Symbol placeholder art with deterministic Modula vector compositions.
- Product state, metadata, installation, publisher, permissions, privacy, screenshots, compatibility, and release messaging continue to come from existing authoritative data or explicit unavailable states.
- Settings uses one native large-to-inline title, native minimized search, sectioned context menus, descriptive status rows, and a `ControlGroup` for common destinations. Appearance retains semantic cards, native menus, confirmation dialogs, and Dynamic Type.
- The Component Catalog remains the canonical visual reference and contains the polished chrome, accessory, rail, vector artwork, and state components.

## Visual matrix

Simulator captures are stored under ignored `artifacts/ui-polish/`:

- Fresh 2026-09-15 matrix: `artifacts/ui-polish/final-2026-09-15/` (also synced into `artifacts/ui-polish/final/`)
- Modes captured: Light, Standard Dark, Dim, OLED, compact density, large Dynamic Type, increased contrast, reduced transparency, OLED + large type + reduced transparency
- Key surfaces: Home, Product Hub, Settings, Appearance
- Same-size baseline: `artifacts/ui-polish/baseline/`

The original nine design reference attachments from the earlier chat were not durable in the workspace; polish continued from this handoff, the design-system docs, and the described visual direction.

The compact shell labels intentionally retain the system Large visual size to preserve all five stable destinations; VoiceOver retains full labels and every control preserves at least a 44-point target. Page content continues scaling through accessibility sizes and remains scrollable.

## Automated checks

`N2PolishAccessibilityUITests` verifies:

- all five tab destinations, Search, and More are visible and hittable in compact density;
- the rail wraps from Following to Modules and back without changing the global tab architecture;
- the accessory menu exposes truthful Settings and Appearance actions;
- OLED, large text, and reduced transparency retain stable shell and Appearance landmarks;
- the native tab bar minimizes during scrolling and Settings retains its native large-title/search landmarks.

The existing `N2ShellUITests`, native foundation tests, module authorization tests, HostBridge boundary tests, N1 runtime tests, design-contract verification, boundary verification, and optimized Metro-free Release acceptance remain the regression gates.

## Acceptance evidence

### 2026-09-14 (initial polish close)

- TypeScript typecheck, package tests, native-boundary verification, and design-contract verification passed.
- Native foundation, module authorization, and HostBridge boundary suites passed (16 tests, zero failures).
- The three polish/accessibility tests passed on the iPhone 17 Pro simulator after the native-tab correction (3 tests, zero failures).
- The canonical N2 shell UI regression passed after adopting the system tab-bar accessibility surface (1 test, zero failures).
- The isolated Greenfield fixture passed its harness and authenticated native CRUD integration without exposing fixture credentials.
- Vault runtime acceptance passed authenticated CRUD, native appearance/navigation, ten open/close cycles, and the single lazy Hermes runtime assertion.
- The optimized Release UI acceptance passed with local port 8081 clear, demonstrating authenticated Vault create/edit/delete and native Profile return without Metro (1 test, zero failures).
- A generic-device Release build signed successfully for `digital.modula.app.native`. The paired physical device was unavailable during that first attempt.

### 2026-09-15 (finish / re-verification)

- JS gates re-ran clean: `npm run typecheck`, `npm test`, `npm run verify:boundary`, `npm run verify:design`.
- Native unit suites re-passed: HostBoundary, ModuleAuthorization, NativeFoundation (16 tests, zero failures). Log: `artifacts/ui-polish/unit-regression-2026-09-15.log`.
- N2 polish accessibility + shell UI regressions re-passed on simulator `439E8DF1-EA4F-4028-98A0-32CA9469EAE0` (4 tests, zero failures). Log: `artifacts/ui-polish/ui-regression-2026-09-15.log`.
- Optimized Metro-free Release acceptance re-passed with port 8081 clear (`ReleaseVaultUITests/testBundledVaultCRUDAndNativeOwnership`). Log: `artifacts/ui-polish/release-acceptance-2026-09-15.log`.
- Signed Release build for device succeeded. Log: `artifacts/ui-polish/device-release-build-2026-09-15.log`.
- Physical install and launch succeeded on `modula.digital` (iPhone 17 Pro Max, UDID `00008150-00043C2A11A3401C`, iOS 27.0, Developer Mode enabled) for `digital.modula.app.native`. Log: `artifacts/ui-polish/device-install-2026-09-15.log`.

## Commits on this branch (beyond frozen N2)

1. `762541c` — refine shell chrome and looping rail
2. `4538f04` — polish product and appearance surfaces
3. `3b63c4f` — adopt native minimizing tab chrome

## Remaining non-blocking notes

- Reattach the nine original design references in a follow-up chat if pixel-perfect comparison against those boards is required.
- Untracked local `.cursor/` state is intentionally not committed.
- Do not modify frozen `phase-n2-ios-sovereign-shell`.
