# N2 native iOS UI polish acceptance

Date: 2026-09-13

Branch: `phase-n2-ios-ui-polish`

Base: exact frozen N2 commit `75e4b3a788cdb2a54eee995ae43c1365d6892d5c`

## Scope

This pass refines the SwiftUI-owned shell, floating bottom navigation and accessory, looping contextual rail, Home, Discover and Activity foundations, Product Hub, Vault Module Detail, Profile foundation, Settings, Appearance, and `/developer/components`. React Native remains confined to `ModuleHost`; routing, `ShellChromePolicy`, `PresentationCoordinator`, `AppearanceStore`, catalogue truth, HostBridge validation, ModuleSession security, and the lazy single-Hermes-runtime boundary are unchanged.

## Visual decisions

- Home has one visible `Modula` navigation title and an image-led native vector hero.
- The bottom chrome floats above content. It uses Liquid Glass only for its convex navigation and accessory capsules on iOS 26+, with an opaque accessibility fallback.
- The accessory contains Search and a More menu; it is not a sixth tab and does not duplicate contextual mode selection.
- The edge rail is a continuous custom loop shape. Its three-item reel wraps both directions; 46-point selected geometry reveals to 96 points, with persistent 12-point gaps.
- Home, Product Hub, Module Detail, and Profile replace gradient/SF Symbol placeholder art with deterministic Modula vector compositions.
- Product state, metadata, installation, publisher, permissions, privacy, screenshots, compatibility, and release messaging continue to come from existing authoritative data or explicit unavailable states.
- Settings and Appearance use native scroll, menus, buttons, confirmation dialogs, Dynamic Type, and semantic cards instead of depending on default `List`/`Picker` composition.
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

The existing `N2ShellUITests`, native foundation tests, module authorization tests, HostBridge boundary tests, N1 runtime tests, design-contract verification, boundary verification, and optimized Metro-free Release acceptance remain the regression gates.

## Acceptance evidence

- TypeScript typecheck, package tests, native-boundary verification, and design-contract verification passed.
- Native foundation, module authorization, and HostBridge boundary suites passed (16 tests, zero failures).
- The canonical N2 shell test and both new polish/accessibility tests passed on the iPhone 17 Pro simulator (3 tests, zero failures).
- The isolated Greenfield fixture passed its harness and authenticated native CRUD integration without exposing fixture credentials.
- Vault runtime acceptance passed authenticated CRUD, native appearance/navigation, ten open/close cycles, and the single lazy Hermes runtime assertion.
- The optimized Release UI acceptance passed with local port 8081 clear, demonstrating launch and Vault operation without Metro.
- A generic-device Release build signed successfully for `digital.modula.app.native`. Physical installation requires the paired `modula.digital` device to be connected, unlocked, and available to CoreDevice; the last acceptance attempt found the paired device unavailable.
