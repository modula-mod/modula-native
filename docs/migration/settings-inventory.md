# Settings inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Mandatory search covered Settings, Appearance, Theme, ColorScheme, OLED, Dark, Accent, Surface, Glass, Liquid, Material, Feature, Version Lock, Stable, Unstable, Update, Backup, Privacy, Notification, Security, Module, Developer, Experimental and Accessibility across `src`, contracts and docs. No product release-channel/version-lock preference implementation was found; `unstable` hits primarily reference Expo APIs, not a user preference.

| Setting/group | Source | Actual status and persistence | Backend/account | Modules/native effect | Classification |
|---|---|---|---|---|---|
| Appearance mode/family/accent/surface | theme contracts + AppearanceScreen | Implemented; AsyncStorage cache and optimistic remote patch | Account appearance API | Both rendering environments | NATIVE_REWRITE |
| Text scale, bold, motion, transparency, contrast | DisplayAndTextScreen, MotionScreen, LargerTextScreen | System/on/off or custom scale; cached, selected fields synced | Account appearance API | Typography/motion/accessibility | NATIVE_REWRITE |
| Differentiate without color; switch labels | theme/contracts/appearance.ts | Local preferences; OS detection incomplete in RN | No wire fields | Semantic accessibility | NATIVE_REWRITE |
| Camera masked blur | AppearanceScreen, AdvancedCameraMaskedBlurPreview | Local preview only | No | Shell experiment | REFERENCE_ONLY |
| Web Liquid/Material presentation | web-presentation-settings-section.web.tsx | Browser-only theme axis | No appearance wire field | No native meaning | RETIRE |
| Notifications follow/like/reaction/repost/quote/reply/comment/mention/moduleEvent/extension; bundleStyle | SettingsExtraScreens + ApiActivityRepository | Signed-in GET/PATCH; optimistic version; anonymous values temporary component state | /v1/accounts/me/notification-preferences | Module event delivery; push explicitly off | NATIVE_REWRITE |
| Private account / sensitive media warning | SettingsExtraScreens PrivacySafetyScreen | useState only; marked Preview, not persisted | No | Intended audience/media, not enforced | REFERENCE_ONLY |
| Mute words / blocked list | SettingsExtraScreens | Unavailable labels; post-level block/mute operations do exist | ApiModerationRepository block/mute, no list UI contract | Moderation later | UNKNOWN |
| Inner circle | settings/inner-circle route | Preview concept | No proven preference | Future audiences | REFERENCE_ONLY |
| Autoplay/data saver/quality | ContentMediaScreen | useState only, Preview | No | Intended playback only | REFERENCE_ONLY |
| Language/prefer original | LanguageTranslateScreen | useState only; no translation API | No | None implemented | REFERENCE_ONLY |
| Marketplace sort/featured/creators | MarketplacePreferencesScreen | useState seeded catalogue Preview | No | None authoritative | REFERENCE_ONLY |
| Feature Control enabled/locked | product/storage/productPreferencesStorage.ts; featureControl.ts | AsyncStorage modula.product.preferences.v1; preview lock is NOT version lock | No generic feature API | Some shell preview visibility | REFERENCE_ONLY |
| Focus/merge/layout/board/profile tabs/chrome density | ProductPreferencesProvider, productPreferencesStorage | Local cache; board layout separately syncs; profile tab sync separately | /v1/board/layout for board only | Shell composition later | NATIVE_REWRITE |
| Account handle/email/password/sessions/logout/export | Account*Screen, ApiAuthRepository | Real API calls; email UI availability must follow backend | Account/session/repository APIs | Session invalidation | NATIVE_REWRITE |
| Local App Lock PIN/password/pattern/biometric | features/security/app-lock | SecureStore device secrets, independent from account auth | No | Whole app; native broker later | NATIVE_REWRITE |
| Passkey/TOTP/recovery codes | SecuritySettingsScreen | Coming soon UI despite some backend foundation | Do not infer full support from tables | None in N1 | UNKNOWN |
| Module install/enable/disable/update/settings/permissions | ModuleManagementScreen, ApiModuleRepository | Real account-backed lifecycle and schema settings | modules endpoints | Host policy + module environment | NATIVE_REWRITE |
| Stable/unstable channel; version lock; automatic updates | no setting found in src | Not implemented as user preference | Update endpoint exists, not preference | Do not invent toggles | UNKNOWN |
| Backup/restore | featureAtlas backup-strategy | Planned; export is a distinct existing API | No proven backup workflow | None | REFERENCE_ONLY |
| Developer session/data runtime/labs | DeveloperSettingsScreen, SessionRuntimeScreen | Diagnostic tools / previews | Some read actual services | Replace with native diagnostics | NATIVE_REWRITE |
| Expo UI lab, Konsta lab | ExpoUi*Screen, ModulaUiLabScreen | Framework-specific tests/specimens | No product truth | No native dependency | RETIRE |
| DIMON, help/about previews | DimonPlaceholderScreen; SettingsExtraScreens | Inactive/reserved; about version metadata | No active wallet | No N1 module | REFERENCE_ONLY |

Native destination is one coherent observable SettingsStore with explicit device persistence and a separate account sync adapter when introduced. Credentials never enter that store. N1 exposes only controls that change native state; no nonfunctional preview toggles.

