# Phase N2 acceptance — 2026-09-13

## Baseline and repository

- Starting main HEAD: `22f34ddf247ae25656ae6c8dbe3d68082e83d18d`
- Starting branch: `phase-n2-ios-sovereign-shell`
- Starting HEAD: `22f34ddf247ae25656ae6c8dbe3d68082e83d18d`
- N1 was fast-forwarded into `main`, tagged `native-n1`, and pushed before N2 was created.

## Routing and shell

`AppRoute` is the typed global route authority. `RouteRegistry`, `RouteParser`, and `RouteSerializer` cover the canonical map, default routes, query values, deep-link origins, malformed input, and lossless module-local paths. The parser accepts path strings, registered `modula://` links, and future `https://modula.digital` universal-link input. Production universal-link entitlements remain future infrastructure work.

The five native destinations are Home, Discover, Modules/Product Hub, Activity, and Profile. Each owns an independent typed navigation path. `ShellChromePolicy` centralizes tab bar, contextual rail, top bar, back/close, immersive, and keyboard policy. `PresentationCoordinator` owns shell sheets and banners. The Home, Activity, and Profile rails use one native `ModulaContextRail`, bind directly to contextual routes, preserve accessible names while visually collapsed, respect Reduce Motion and safe areas, use semantic haptics, and collapse their transient label after two seconds. Home has no duplicate mode selector.

## Design system and Appearance

The native design system contains semantic palette, typography, spacing, density, radius, icon, motion, haptic, material, and layout definitions plus the N2 component set. A versioned neutral design contract in `packages/design-contracts` generates synchronized Swift and TypeScript representations; `npm run verify:design` fails on drift. The development-only `/developer/components` catalog is the interactive reference for future agents.

`AppearanceStore` is the single device-local authority. Theme, Standard/Dim/OLED dark styles, curated accent, semantic font family, Modula text scale, density, motion personality, haptic intensity, contrast/transparency, icon style, interface shape, and module branding persist and update the shell live. Reset Appearance clears only appearance preferences. The App Icon picker is a visual grid and truthfully exposes only the production Default asset; additional variants are not claimed. System Dynamic Type, Reduce Motion, increased contrast, and reduced transparency continue to constrain user preferences.

The module environment is additive and versioned with `designContractVersion: 1`. Vault remains compatible with the N1 fields and receives only presentation semantics it can safely use. It receives no credential or account identifier through the appearance environment.

## Product Hub and ModuleHost

The Product Hub is native SwiftUI and reads the public Greenfield registry. Authenticated installed state comes from `/v1/modules/installed`; bundled executable availability is displayed separately and never implies installation. The Greenfield response on 2026-09-13 identified Vault Notes `digital.modula.vault-notes` version `1.7.0` as published and installable.

Vault's native Module Detail provides the cover, artwork, publisher identity, install/open state, metadata, Overview, What's New, permissions, privacy, screenshots, compatibility, information, version routes, and related-product area. Missing catalogue claims use explicit unavailable states; ratings, screenshots, permissions, privacy details, and release notes are not fabricated. Open transitions from native Module Detail to native ModuleHost, then to the existing bundled RN Vault. Close returns to the same native detail stack. A Vault request for Profile changes the global native destination while the Modules stack remains preserved.

Module-local input such as `/module/digital.modula.vault-notes/note/123` enters ModuleHost with `/note/123`; Vault resolves it internally. Swift does not interpret the relative path.

## Automated acceptance

- Native/security: 15 tests passed, covering route round trips/defaults/hostile input, independent tab state, chrome policy, appearance persistence/reset, installed-state decoding, session rejection, host capability enforcement, and credential-free initial properties.
- Real Greenfield bridge: authenticated list/create/read/update/delete and post-unmount rejection passed in 0.757 seconds against the isolated N1 service through the SSH/TLS harness.
- Debug shell: the complete Home rail → Discover → Product Hub → Vault detail → ModuleHost/Close → Activity rail → Profile rail → Settings/Appearance path passed.
- Debug Vault: real CRUD, persistence, light/dark/OLED propagation, background/foreground, semantic haptic request, native Profile navigation, close/reopen, and deleted-state persistence passed.
- Lifecycle: ten open/close cycles passed with runtime initialization count `1`.
- Release: the optimized `ModulaReleaseAcceptance` scheme passed both the N2 shell flow and real bundled Vault CRUD/native ownership with Metro stopped.
- TypeScript: typecheck passed and 2 runtime contract tests passed.
- Ownership/design checks: `verify:boundary`, `verify:design`, and `git diff --check` passed.

The N1 transport-loss acceptance remains the accepted baseline. N2 additionally exercises missing-runtime containment in both Debug and optimized Release: the native failure UI retains Retry and Close, and the shell remains navigable.

## Performance evidence

These are iPhone 17 Pro iOS 26.5 simulator measurements. Shell-route values are optimized Release XCTest wall times and include automation lookup/wait overhead. Runtime marks are measured inside the application during the Debug lifecycle test.

| Measurement | Result |
|---|---:|
| XCTest launch to native shell | 4,695.3 ms |
| In-process native usable mark | 833.5 ms |
| Home rail route switch | 378.7 ms |
| Global tab switch | 2,302.5 ms |
| Product Hub ready through UI harness | 4,811.7 ms |
| Module Detail ready | 2,747.5 ms |
| ModuleHost contained transition | 2,071.2 ms |
| Appearance mutation assertion | 701.2 ms |
| Runtime factory setup | 5.4 ms |
| First Vault RN ready | 312.0 ms |
| First Vault data ready | 386.1 ms |
| Second Vault RN ready | 47.8 ms |
| UI-driven first open through loaded state | 8,526.1 ms |
| UI-driven subsequent opens | 3,435.8–3,510.7 ms |
| Memory before RN | 341.7 MB |
| Memory with Vault | 391.3 MB |
| Memory after tenth close | 393.5 MB |
| Runtime initialization count | 1 |

The retained memory includes the intentionally resident shared RN/Hermes runtime. The tenth-close value is 2.2 MB above the with-module value and does not show linear per-open growth. Simulator and XCTest results are comparative baselines, not physical-device production figures.

## Release integrity and security

The ordinary Release build passed independently. The bundled JavaScript is 1,286,196 bytes and `hermesvm.framework` is packaged. With no listener on port 8081, Release launched the native shell, loaded Product Hub, opened native Module Detail, launched Vault, completed real CRUD, and routed back to native Profile.

A case-insensitive binary scan found zero occurrences of the Metro URL, access/refresh-token markers, bearer authorization markers, password-field markers, or any value loaded from the ignored N1 fixture secret file. Runtime source still contains no Vault network bypass. JavaScript cannot provide arbitrary URLs or headers.

## Accessibility

Native controls use semantic roles and labels, selected traits, Dynamic Type fonts, 44-point minimum targets, safe-area-aware chrome, centralized Reduce Motion behavior, and opaque fallbacks for reduced transparency. Rail labels remain available to VoiceOver while collapsed. Increased contrast and reduced transparency combine the Modula preference with the corresponding iOS environment. The component catalog provides live coverage across appearance variants; physical VoiceOver interaction remains part of the open device gate.

## Physical device

**OPEN — device/Xcode support unavailable.** On final recheck, `modula.digital` reports iOS 27.0 and unavailable while Xcode 26.6 supplies iOS 26.5 device support. N1's earlier signed build, install, and launch proof remains valid; N2 physical interaction was not falsely marked passed.

## Warnings

- Modula-owned compiler warnings: none.
- React Native/Hermes: generated bundle diagnostics for framework-provided globals.
- CocoaPods: generated Hermes/RN dependency replacement script warnings.
- SDK/Xcode: AppIntents metadata skipped because the app has no AppIntents dependency.
- npm audit: four inherited high findings across `image-size`, `metro`, `metro-config`, and `metro-transform-worker`; the proposed dependency change is incompatible with the pinned RN architecture and was not applied.
- Local tooling: the current Node 24.1 executable is outside the repository's declared Node 22 range; all recorded npm checks passed, and dependencies were not repinned around the local executable.

## Known limitations

- Physical-device interaction acceptance remains open.
- Universal-link parsing is ready; production associated-domain entitlements are not configured in N2.
- Only the production Default alternate-icon choice is shipped.
- Social Feed, full Profile, full Activity data, Search, Composer, Messages, Teams, and full Marketplace lifecycle remain later-phase work and use honest route-ready foundations where visible.
- Catalogue sections without backend data show unavailable states.
- Vault's N1 editor edits paragraph-only notes and preserves richer documents without destructive rewriting.
- One shared RN/Hermes runtime provides capability isolation, not independent VM sandboxing per module.

## Verdict

**PASS — with the explicitly permitted physical-device interaction gate OPEN.** N2 establishes the typed native route system, sovereign shell, semantic design language, authoritative Appearance architecture, Settings foundation, live Product Hub, native Module Detail, and stable ModuleHost handoff while preserving N1 ownership and security guarantees.
