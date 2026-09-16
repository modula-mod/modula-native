# Settings route audit (N4E)

Zero PLACEHOLDER entries. Status is one of IMPLEMENTED, CAPABILITY-UNAVAILABLE, DEVELOPER-ONLY.

Live VPS verification remains OPEN. CAPABILITY-UNAVAILABLE screens are truthful, with no dead controls.

| Route | Status | Title |
|---|---|---|
| /settings | IMPLEMENTED | Settings |
| /settings/account | IMPLEMENTED | Account |
| /settings/account/personal-information | IMPLEMENTED | Personal Information |
| /settings/account/username | CAPABILITY-UNAVAILABLE | Username |
| /settings/account/email | CAPABILITY-UNAVAILABLE | Email |
| /settings/account/password | IMPLEMENTED | Password |
| /settings/account/sessions | IMPLEMENTED | Sessions |
| /settings/account/delete-account | CAPABILITY-UNAVAILABLE | Delete Account |
| /settings/appearance | IMPLEMENTED | Appearance |
| /settings/appearance/theme | IMPLEMENTED | Theme |
| /settings/appearance/dark-style | IMPLEMENTED | Dark Style |
| /settings/appearance/accent | IMPLEMENTED | Accent |
| /settings/appearance/typography | IMPLEMENTED | Typography |
| /settings/appearance/typography/font-family | IMPLEMENTED | Font Family |
| /settings/appearance/typography/text-size | IMPLEMENTED | Text Size |
| /settings/appearance/app-icon | IMPLEMENTED | App Icon |
| /settings/appearance/density | IMPLEMENTED | Density |
| /settings/appearance/motion | IMPLEMENTED | Motion Personality |
| /settings/appearance/haptics | IMPLEMENTED | Haptic Intensity |
| /settings/appearance/contrast-transparency | IMPLEMENTED | Contrast & Transparency |
| /settings/appearance/icon-style | IMPLEMENTED | Icon Style |
| /settings/appearance/interface-shape | IMPLEMENTED | Interface Shape |
| /settings/appearance/module-branding | IMPLEMENTED | Module Branding |
| /settings/appearance/preview | IMPLEMENTED | Appearance Preview |
| /settings/notifications | IMPLEMENTED | Notifications |
| /settings/notifications/push | IMPLEMENTED | Push |
| /settings/notifications/social | CAPABILITY-UNAVAILABLE | Social Notifications |
| /settings/notifications/modules | CAPABILITY-UNAVAILABLE | Module Notifications |
| /settings/notifications/quiet-hours | CAPABILITY-UNAVAILABLE | Quiet Hours |
| /settings/privacy-security | IMPLEMENTED | Privacy & Security |
| /settings/privacy-security/privacy | IMPLEMENTED | Privacy |
| /settings/privacy-security/security | IMPLEMENTED | Security |
| /settings/privacy-security/glass-privacy | CAPABILITY-UNAVAILABLE | Glass Privacy |
| /settings/privacy-security/blocked | CAPABILITY-UNAVAILABLE | Blocked Accounts |
| /settings/privacy-security/app-lock | IMPLEMENTED | App Lock |
| /settings/privacy-security/biometrics | IMPLEMENTED | Face ID & Biometrics |
| /settings/modules | IMPLEMENTED | Modules |
| /settings/modules/installed | IMPLEMENTED | Installed Modules |
| /settings/modules/updates | IMPLEMENTED | Module Updates |
| /settings/modules/auto-updates | CAPABILITY-UNAVAILABLE | Auto Updates |
| /settings/modules/permissions | IMPLEMENTED | Module Permissions |
| /settings/data-storage | IMPLEMENTED | Data & Storage |
| /settings/data-storage/storage | IMPLEMENTED | Storage |
| /settings/data-storage/cache | IMPLEMENTED | Cache |
| /settings/data-storage/downloads | IMPLEMENTED | Downloads |
| /settings/data-storage/backup | CAPABILITY-UNAVAILABLE | Backup |
| /settings/data-storage/export | CAPABILITY-UNAVAILABLE | Export |
| /settings/accessibility | IMPLEMENTED | Accessibility |
| /settings/accessibility/text | IMPLEMENTED | Text |
| /settings/accessibility/contrast | IMPLEMENTED | Contrast |
| /settings/accessibility/motion | IMPLEMENTED | Motion |
| /settings/features | IMPLEMENTED | Features |
| /settings/features/enabled | IMPLEMENTED | Enabled Features |
| /settings/features/experimental | IMPLEMENTED | Experimental Features |
| /settings/updates | IMPLEMENTED | Updates |
| /settings/updates/channel | IMPLEMENTED | Update Channel |
| /settings/updates/channel/stable | IMPLEMENTED | Stable Channel |
| /settings/updates/channel/unstable | DEVELOPER-ONLY | Unstable Channel |
| /settings/updates/version-lock | IMPLEMENTED | Version Lock |
| /settings/developer | DEVELOPER-ONLY | Developer |
| /settings/developer/runtime | DEVELOPER-ONLY | Runtime |
| /settings/developer/modules | DEVELOPER-ONLY | Developer Modules |
| /settings/developer/network | DEVELOPER-ONLY | Network |
| /settings/developer/feature-flags | DEVELOPER-ONLY | Feature Flags |
| /settings/developer/environment | DEVELOPER-ONLY | Environment |
| /settings/developer/components | DEVELOPER-ONLY | Components |
| /settings/developer/diagnostics | DEVELOPER-ONLY | Diagnostics |
| /settings/about | IMPLEMENTED | About |
| /settings/about/version | IMPLEMENTED | Version |
| /settings/about/licenses | IMPLEMENTED | Licenses |
| /settings/about/privacy | IMPLEMENTED | Privacy Policy |
| /settings/about/terms | IMPLEMENTED | Terms |

Installed module detail routes (`/settings/modules/:moduleId/…`) are IMPLEMENTED dynamically from catalogue + HostBridge manifests. They are not duplicated as static registry rows.

PLACEHOLDER count: **0**
