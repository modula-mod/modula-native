# MOL-03R — Baseline & Surface Map

Date: 2026-10-15 · Base commit: `1b8b92b` (`origin/main`, PR #53 + PR #52 merged) · Branch: `phase/mol-03r-product-consolidation`

## 1. Environment & Repository Truth
- **macOS**: 27.0 (`26A5378n`, `arm64`)
- **Xcode**: 27.0 (`27A266a`), Swift 6.4 (`swiftlang-6.4.0.34.1`)
- **Physical Device**: `modula.digital` (`00008150-00043C2A11A3401C`, iPhone 17 Pro Max, paired over Wi-Fi)
- **Simulators**: `MOL03-settings-26` (`9FBEC14E-8239-4DAD-A546-9460DF93469A`, iPhone 16 Pro Max) & `iPhone 17 Pro` (`1F8BD84E-2432-45A0-B93A-36D7D745860D`)
- **Supporting Backend**: `~/Developer/modula-latest` (Greenfield — zero DB migrations required; Moliboos state is local-first with fail-closed `ModulaIntelligence` chat).

## 2. Twelve-Surface Architecture Map

| # | Surface | SwiftUI View | State / ViewModel Owner | Route / Entry | Persistence | 3D / Shader Dependency |
|---|---|---|---|---|---|---|
| 1 | **Moliboos Home (World)** | `MolibooWorldView` | `MolibooCareStore.shared`, `MolibooStageState`, `MolibooChatModel` | `/settings/moliboo` (`SettingsRoute.moliboo`) | `moliboo.care.v1.<id>`, `composer.mascot.kind` | Pre-rendered 3D portrait + `molibooStageAura`, `molibooNebula`, `molibooSunbeams`, `molibooCaustics`, `molibooRipple`, `molibooJoyPulse` |
| 2 | **Moliboo Collection** | `MolibooCollectionView` | `@AppStorage(ModulaMascotSettings.kindKey)` | World `More → Collection` / `MolibooSettingsView` | `composer.mascot.kind` | Static 512² pre-rendered USDZ portraits (`MolibooPortrait`) + `molibooHoloFoil` on selected |
| 3 | **Character Selection** | `MolibooCollectionView`, `MolibooSettingsView`, `ModulaMascotPicker` | `ModulaMascotSettings.kindKey`, `MascotEntitlements` | World switcher, Hub grid, Composer long-press | `composer.mascot.kind` | Static portraits (`MolibooPortrait`) + 2D fallback (`ModulaMascotFigure`) |
| 4 | **Moliboo Studio** | `MolibooLivingStudioView` | `MolibooSceneController`, `MolibooStudioDirector`, `MolibooWardrobeSession` | `MolibooStudioEntry` / World `Studio` | `moliboo.studio.environment`, `moliboo.studio.pose.<id>` | Single active `RealityView` + `MolibooAssetLoader` LRU + environment shaders |
| 5 | **Studio Wardrobe** | `MolibooWardrobeSheet` | `MolibooWardrobeSession`, `MascotWardrobeStore.shared`, `MolibooWardrobeRig` | Studio `.wardrobe` panel | `composer.mascot.wardrobe.outfit`, `.presets` | `MolibooWardrobeRig` + `moliboo_wardrobe_fits.json` + `MolibooWardrobeThumbs` |
| 6 | **Studio Expressions** | `MolibooLivingStudioView.expressionsSheet` | `MolibooSceneController` | Studio `.expressions` panel (Compact 250pt detent) | Transient stage state | USD `SkelAnimation` blend-shape clips (`expr_*`) + transform fallback |
| 7 | **Studio Play Interactions** | `MolibooLivingStudioView.playSheet` | `MolibooStudioDirector`, `MolibooReactionGate` | Studio `.play` panel (Compact 250pt detent) | Reaction counters | Character personality clips + `molibooJoyPulse` wave |
| 8 | **Cards & Founding Collection** | `MolibooCardBinderView`, `MolibooTradingCardView`, `MolibooPackOpeningView` | `MolibooCardStore.shared`, `MolibooTiltSource` | World `Cards` / Hub `Trading Cards` | `moliboo.cards.owned.v1`, `moliboo.cards.packsOpened.v1` | `molibooHoloFoil` (live tilt), `molibooShimmer`, `molibooPackReveal` |
| 9 | **Rewards & Achievements** | `MascotStudioView.rewardsPanel` | `MascotProgressStore.shared` | Studio `More → Rewards` | `composer.mascot.progress` | SwiftUI symbols + confetti/sparkle bursts |
| 10 | **Moliboo Settings Hub** | `MolibooSettingsView` | `@AppStorage` mascot & 3D flags | World `More → Moliboo settings` (`--debug-moliboo-hub`) | `ModulaMascotSettings.*`, `MolibooFeatureFlags.native3DKey` | `MolibooGardenScene` + `MolibooAmbientBackground` |
| 11 | **Composer & Home Companion** | `ModulaComposerMascot`, `HomeMascotCompanion` | `MascotBrain`, `MascotContext.shared` | `.modulaComposerMascot(...)`, Home bottom edge | `composer.mascot.show.*`, `home.companion.parkX/Y` | `MolibooPortraitCompanion` (3D portrait) or `ModulaLiveMascot` (2D) |
| 12 | **Global Modula Navigation** | `RootView`, `SettingsDestinationHost` | `AppEnvironment`, `ShellChromePolicy` | Global 5-tab bar + leading sidebar → Settings → Moliboo | Canonical route state | Restrained Liquid Glass (`modulaGlass`) |
