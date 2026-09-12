# Navigation and failure lessons

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Evidence: `src/app/_layout.tsx`, `src/app/(tabs)`, `src/shell/RootLayout.tsx`, `NavigationDrawer.tsx`, `ShellDrawerContext.tsx`, `src/platform/ui/navigation/platform-tabs.native.tsx`, `src/platform/ui/overlays/modula-overlay-stack.tsx`, `docs/architecture/adr/ADR-014-modula-root-navigation.md`, `docs/design/phase7m-b8-overlay-map.md`.

Expo Router file routes own shell stacks/tabs and module paths. NativeTabs uses expo-router/unstable-native-tabs; web uses rail/bottom adaptation. Drawer/secondary header/presentation adapters own overlay state. Profile subroutes, composer sheets, module route interpolation, deep links and safe auth returnTo form multiple interacting routing layers.

Mainline merge #97 (`7876379`) replaces Konsta overlay behaviour with passive surfaces under Base UI, adjusts drawer state/navigation and separates native document-head handling. tests/konsta-web-presentation.test.ts adds regressions. Prior transparent/missing/frozen/unresponsive drawer reports are mission evidence; this audit did not reproduce each historical failure. Do not assert all remain broken or all were fixed by one merge.

Prevention in native: one NavigationCoordinator typed path; a single presentation owner; disposable module surface cannot replace the root window; SwiftUI Back/Close remain outside RN; no stacked web/RN gesture portal owner; validate unknown routes; test close/reopen/background/failure and transition ordering. Module-local list→editor stays local; profile/post/settings actions cross the host bridge. Future native three-item rail uses native gestures/haptics and a transient active label.

RETIRE Expo Router/React Navigation shell/old drawers from new application; CARRY route semantics and regression scenarios; NATIVE_REWRITE coordinator and presentation.

