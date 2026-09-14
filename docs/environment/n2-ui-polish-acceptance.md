# N2 native iOS UI polish acceptance

Date: 2026-09-14

Branch: `phase-n2-ios-ui-polish`

Base: exact frozen N2 commit `75e4b3a788cdb2a54eee995ae43c1365d6892d5c`

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

Simulator captures are stored under ignored `artifacts/ui-polish/final/` for Light, Standard Dark, Dim, OLED, compact density, accessibility Dynamic Type, increased contrast, and reduced transparency. The same-size baseline is under `artifacts/ui-polish/baseline/`.

The compact shell labels intentionally retain the system Large visual size to preserve all five stable destinations; VoiceOver retains full labels and every control preserves at least a 44-point target. Page content continues scaling through accessibility sizes and remains scrollable.

## Automated checks

`N2PolishAccessibilityUITests` verifies:

- all five tab destinations, Search, and More are visible and hittable in compact density;
- the rail wraps from Following to Modules and back without changing the global tab architecture;
- the accessory menu exposes truthful Settings and Appearance actions;
- OLED, large text, and reduced transparency retain stable shell and Appearance landmarks.
- the native tab bar minimizes during scrolling and Settings retains its native large-title/search landmarks.

The existing `N2ShellUITests`, native foundation tests, module authorization tests, HostBridge boundary tests, N1 runtime tests, design-contract verification, boundary verification, and optimized Metro-free Release acceptance remain the regression gates.

## Acceptance evidence

- TypeScript typecheck, package tests, native-boundary verification, and design-contract verification passed.
- Native foundation, module authorization, and HostBridge boundary suites passed (16 tests, zero failures).
- The three polish/accessibility tests passed on the iPhone 17 Pro simulator after the native-tab correction (3 tests, zero failures).
- The canonical N2 shell UI regression passed after adopting the system tab-bar accessibility surface (1 test, zero failures).
- The isolated Greenfield fixture passed its harness and authenticated native CRUD integration without exposing fixture credentials.
- Vault runtime acceptance passed authenticated CRUD, native appearance/navigation, ten open/close cycles, and the single lazy Hermes runtime assertion.
- The optimized Release UI acceptance passed with local port 8081 clear, demonstrating authenticated Vault create/edit/delete and native Profile return without Metro (1 test, zero failures).
- A generic-device Release build signed successfully for `digital.modula.app.native`. Physical installation requires the paired `modula.digital` device to be connected, unlocked, and available to CoreDevice; the last acceptance attempt found the paired device unavailable.
