# Native Modula architecture

> Modula is a native application.
> Modules are hosted applications.
> The shell owns the platform.
> The runtime owns module rendering.
> The Greenfield backend owns product truth.
> A module may request platform behaviour.
> A module may never silently take ownership
> of the platform application.

## Ownership

SwiftUI composes the iOS application. UIKit hosts React Native surfaces only where necessary. The native shell owns authenticated networking, Keychain, typed global navigation, presentations, appearance, permissions and diagnostics. Greenfield remains the existing remote product backend. There is no native-specific backend and no dependency on the Expo checkout.

`RootView → NavigationCoordinator → ModuleHost → ModuleRuntimeController → RCTReactNativeFactory → ModulaModuleRoot → registered module`.

Home, Product Hub, Profile and Settings launch without starting JavaScript. Runtime creation is lazy and retained once per application environment. A module surface is disposable; closing one does not destroy the shared runtime. Android and Svelte are separate later phases; no Android directory is introduced for symmetry.

## Native infrastructure

One typed route vocabulary serves native screens, deep links and validated module requests. Native presentation has a single owner; module code cannot stack global drawers, own the application window or silently seize navigation. SwiftUI navigation and sheet dismissal remain usable after module failure. No legacy React Navigation, Expo Router or Konsta overlays carry into the shell.

Appearance uses semantic values rather than old RN style objects. Swift owns effective color scheme, OLED depth, accent, native surface preference and accessibility environment. Module snapshots contain portable values. New OS surface treatments are availability-gated. Native Dynamic Type, 44-point actions, labels and Reduce Motion are foundational.

The approved future side rail is small, has three primary items, emphasizes the active icon and only transiently reveals its label. Its native implementation follows shell work; old drawer code is reference only.

## Scope and evidence

N1 is foundation and runtime proof, not complete social/profile/settings migration. Migration classifications and source evidence live in `docs/migration`. Code presence is not runtime acceptance. Simulator, real Greenfield CRUD, Metro-free Release and physical-device evidence must all pass before the phase branch merges.
