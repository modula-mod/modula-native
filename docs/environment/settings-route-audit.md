# Settings route audit

Updated with the settings-routes-polish branch. **Status** is the registry availability (`SettingsRegistry`). **Reality** says where the data comes from:

- **LIVE**: Greenfield server data
- **SYSTEM**: iOS capability or permission state
- **APPLIED**: local preference that is read by the app
- **LOCAL-ONLY**: stored with `@AppStorage` but not read anywhere outside Settings (no behaviour change yet)
- **EMPTY**: honest empty or “—” state with no data source
- **SCOPED**: unavailable in this version, shown with a plain reason and, where possible, real alternatives (no disabled “Coming soon” rows)
- **NAV**: hub page
- **DEV**: internal builds only

| Route | Status | Reality | Title | Change |
|---|---|---|---|---|
| /settings | IMPLEMENTED | NAV | Settings |  |
| /settings/account | IMPLEMENTED | LIVE | Account |  |
| /settings/account/personal-information | IMPLEMENTED | LIVE | Personal Information |  |
| /settings/account/username | CAPABILITY-UNAVAILABLE | SCOPED | Username |  |
| /settings/account/email | CAPABILITY-UNAVAILABLE | SCOPED | Email |  |
| /settings/account/password | IMPLEMENTED | LIVE | Password |  |
| /settings/account/sessions | IMPLEMENTED | LIVE | Sessions |  |
| /settings/account/delete-account | CAPABILITY-UNAVAILABLE | SCOPED | Delete Account |  |
| /settings/appearance | IMPLEMENTED | APPLIED | Appearance |  |
| /settings/appearance/theme | IMPLEMENTED | APPLIED | Theme |  |
| /settings/appearance/dark-style | IMPLEMENTED | APPLIED | Dark Style |  |
| /settings/appearance/accent | IMPLEMENTED | APPLIED | Accent |  |
| /settings/appearance/typography | IMPLEMENTED | APPLIED | Typography |  |
| /settings/appearance/typography/font-family | IMPLEMENTED | APPLIED | Font Family |  |
| /settings/appearance/typography/text-size | IMPLEMENTED | APPLIED | Text Size |  |
| /settings/appearance/app-icon | IMPLEMENTED | APPLIED | App Icon |  |
| /settings/appearance/density | IMPLEMENTED | APPLIED | Density |  |
| /settings/appearance/motion | IMPLEMENTED | APPLIED | Motion Personality |  |
| /settings/appearance/haptics | IMPLEMENTED | APPLIED | Haptic Intensity |  |
| /settings/appearance/contrast-transparency | IMPLEMENTED | APPLIED | Contrast & Transparency |  |
| /settings/appearance/icon-style | IMPLEMENTED | APPLIED | Icon Style |  |
| /settings/appearance/interface-shape | IMPLEMENTED | APPLIED | Interface Shape |  |
| /settings/appearance/module-branding | IMPLEMENTED | APPLIED | Module Branding |  |
| /settings/appearance/preview | IMPLEMENTED | APPLIED | Appearance Preview |  |
| /settings/personalisation | IMPLEMENTED | NAV | Personalisation |  |
| /settings/personalisation/recommendations | IMPLEMENTED | LOCAL-ONLY | Recommendations |  |
| /settings/personalisation/stories | IMPLEMENTED | APPLIED | Stories prefs |  |
| /settings/personalisation/captions | IMPLEMENTED | LOCAL-ONLY | Captions |  |
| /settings/intelligence | IMPLEMENTED | APPLIED | Intelligence |  |
| /settings/intelligence/models | IMPLEMENTED | APPLIED | Models |  |
| /settings/intelligence/knowledge | IMPLEMENTED | APPLIED | Knowledge |  |
| /settings/intelligence/privacy | IMPLEMENTED | APPLIED | Intelligence Privacy |  |
| /settings/intelligence/tools | IMPLEMENTED | APPLIED | Tools |  |
| /settings/chats | IMPLEMENTED | NAV | Chats |  |
| /settings/chats/composer | IMPLEMENTED | APPLIED | Composer |  |
| /settings/chats/previews | IMPLEMENTED | LOCAL-ONLY | Chat Previews |  |
| /settings/chats/privacy | IMPLEMENTED | LOCAL-ONLY | Chat Privacy |  |
| /settings/audio | IMPLEMENTED | NAV | Audio |  |
| /settings/audio/playback | IMPLEMENTED | LOCAL-ONLY | Playback |  |
| /settings/audio/voice | IMPLEMENTED | LOCAL-ONLY | Voice |  |
| /settings/audio/haptics | IMPLEMENTED | LOCAL-ONLY | Audio Haptics |  |
| /settings/language | IMPLEMENTED | SYSTEM | Language |  |
| /settings/media | IMPLEMENTED | NAV | Media |  |
| /settings/media/video | IMPLEMENTED | LOCAL-ONLY | Video |  |
| /settings/media/images | IMPLEMENTED | LOCAL-ONLY | Images |  |
| /settings/media/downloads | IMPLEMENTED | EMPTY | Media Downloads | Empty state (no offline downloads exist) |
| /settings/feed | IMPLEMENTED | LOCAL-ONLY | Feed |  |
| /settings/battery | IMPLEMENTED | LOCAL-ONLY | Battery & Data |  |
| /settings/safety | IMPLEMENTED | NAV | Safety |  |
| /settings/safety/reporting | CAPABILITY-UNAVAILABLE | SCOPED | Reporting |  |
| /settings/safety/muted | CAPABILITY-UNAVAILABLE | SCOPED | Muted | Empty list; muting works from profiles but there is no list endpoint |
| /settings/safety/sensitive | CAPABILITY-UNAVAILABLE | SCOPED | Sensitive content | Removes the disabled .constant(true) toggle; honest scope + report path |
| /settings/camera | IMPLEMENTED | NAV | Camera |  |
| /settings/camera/capture | IMPLEMENTED | LOCAL-ONLY | Capture |  |
| /settings/camera/permissions | IMPLEMENTED | SYSTEM | Camera Permissions |  |
| /settings/gestures | IMPLEMENTED | LOCAL-ONLY | Gestures |  |
| /settings/finder | IMPLEMENTED | LOCAL-ONLY | Search |  |
| /settings/sharing | IMPLEMENTED | LOCAL-ONLY | Sharing |  |
| /settings/location | CAPABILITY-UNAVAILABLE | SCOPED | Location |  |
| /settings/location/map | CAPABILITY-UNAVAILABLE | SCOPED | Map posts |  |
| /settings/widgets | CAPABILITY-UNAVAILABLE | SCOPED | Widgets |  |
| /settings/widgets/gallery | CAPABILITY-UNAVAILABLE | SCOPED | Widget gallery |  |
| /settings/labs | IMPLEMENTED | LOCAL-ONLY | Labs |  |
| /settings/photos | IMPLEMENTED | LOCAL-ONLY | Photos |  |
| /settings/network | IMPLEMENTED | LOCAL-ONLY | Network |  |
| /settings/digests | IMPLEMENTED | LOCAL-ONLY | Digests |  |
| /settings/help | IMPLEMENTED | NAV | Help | Footnote no longer says “being prepared” |
| /settings/help/guides | IMPLEMENTED | NAV | Guides | Was disabled preview rows → guides that link to the real setting each one covers |
| /settings/help/contact | IMPLEMENTED | LIVE | Contact | Was “Coming surface” → in-app case form (POST /v1/support/cases), server-provided support email, your requests list |
| /settings/help/status | IMPLEMENTED | LIVE | Status | Was “—” chips + static radar → live /v1/status (API, DB, worker heartbeat, jobs, mail), round trip, NWPathMonitor, Metal radar |
| /settings/whats-new | IMPLEMENTED | NAV | What’s New | “This checkout” developer bullets → user-facing highlights |
| /settings/creator | IMPLEMENTED | NAV | Creator |  |
| /settings/creator/studio | IMPLEMENTED | LOCAL-ONLY | Studio defaults |  |
| /settings/creator/insights | CAPABILITY-UNAVAILABLE | SCOPED | Insights | Shows “—” chips; no insights API |
| /settings/focus | IMPLEMENTED | LOCAL-ONLY | Focus |  |
| /settings/passkeys | CAPABILITY-UNAVAILABLE | SCOPED | Passkeys |  |
| /settings/translate | IMPLEMENTED | LOCAL-ONLY | Translate |  |
| /settings/qr-code | IMPLEMENTED | SYSTEM | Modula Code |  |
| /settings/family | CAPABILITY-UNAVAILABLE | SCOPED | Family |  |
| /settings/time-units | IMPLEMENTED | LOCAL-ONLY | Time & Units |  |
| /settings/keyboard | IMPLEMENTED | LOCAL-ONLY | Keyboard |  |
| /settings/connectors | CAPABILITY-UNAVAILABLE | SCOPED | Connectors |  |
| /settings/integrations | CAPABILITY-UNAVAILABLE | SCOPED | Integrations |  |
| /settings/monetisation | CAPABILITY-UNAVAILABLE | SCOPED | Monetisation |  |
| /settings/monetisation/plans | CAPABILITY-UNAVAILABLE | SCOPED | Plans |  |
| /settings/monetisation/payouts | CAPABILITY-UNAVAILABLE | SCOPED | Payouts | Shows “—”; no payouts API |
| /settings/monetisation/invoices | CAPABILITY-UNAVAILABLE | SCOPED | Invoices | Empty; no billing API |
| /settings/notifications | IMPLEMENTED | NAV | Notifications |  |
| /settings/notifications/push | IMPLEMENTED | SYSTEM | Push | Adds “Allow Notifications” when not requested |
| /settings/notifications/social | CAPABILITY-UNAVAILABLE | SCOPED | Social Notifications |  |
| /settings/notifications/modules | CAPABILITY-UNAVAILABLE | SCOPED | Module Notifications |  |
| /settings/notifications/quiet-hours | CAPABILITY-UNAVAILABLE | SCOPED | Quiet Hours |  |
| /settings/privacy-security | IMPLEMENTED | NAV | Privacy & Security |  |
| /settings/privacy-security/privacy | IMPLEMENTED | SYSTEM | Privacy | Drops “coming soon”; links to export and privacy request |
| /settings/privacy-security/security | IMPLEMENTED | SYSTEM | Security |  |
| /settings/privacy-security/glass-privacy | CAPABILITY-UNAVAILABLE | SCOPED | Glass Privacy |  |
| /settings/privacy-security/blocked | CAPABILITY-UNAVAILABLE | SCOPED | Blocked Accounts |  |
| /settings/privacy-security/app-lock | IMPLEMENTED | SYSTEM | App Lock |  |
| /settings/privacy-security/biometrics | IMPLEMENTED | SYSTEM | Face ID & Biometrics | Fixes .modulaCanvas() on a Form (double background) |
| /settings/modules | IMPLEMENTED | LIVE | Modules |  |
| /settings/modules/installed | IMPLEMENTED | LIVE | Installed Modules |  |
| /settings/modules/updates | IMPLEMENTED | LIVE | Module Updates |  |
| /settings/modules/auto-updates | CAPABILITY-UNAVAILABLE | SCOPED | Auto Updates |  |
| /settings/modules/permissions | IMPLEMENTED | LIVE | Module Permissions |  |
| /settings/data-storage | IMPLEMENTED | NAV | Data & Storage | Subtitle no longer says “export honesty” |
| /settings/data-storage/storage | IMPLEMENTED | SYSTEM | Storage |  |
| /settings/data-storage/cache | IMPLEMENTED | SYSTEM | Cache |  |
| /settings/data-storage/downloads | IMPLEMENTED | NAV | Downloads |  |
| /settings/data-storage/backup | CAPABILITY-UNAVAILABLE | SCOPED | Backup |  |
| /settings/data-storage/export | IMPLEMENTED | LIVE | Export | Was unavailable → real export (POST data-exports → advance → artifacts → JSON ShareLink) |
| /settings/accessibility | IMPLEMENTED | SYSTEM | Accessibility | Dynamic Type shows a human label (was String(describing:)); links to contrast, motion and Modula text size |
| /settings/accessibility/text | IMPLEMENTED | SYSTEM | Text |  |
| /settings/accessibility/contrast | IMPLEMENTED | SYSTEM | Contrast |  |
| /settings/accessibility/motion | IMPLEMENTED | SYSTEM | Motion |  |
| /settings/features | IMPLEMENTED | SYSTEM | Features |  |
| /settings/features/enabled | IMPLEMENTED | SYSTEM | Enabled Features |  |
| /settings/features/experimental | IMPLEMENTED | SYSTEM | Experimental Features |  |
| /settings/updates | IMPLEMENTED | SYSTEM | Updates |  |
| /settings/updates/channel | IMPLEMENTED | SYSTEM | Update Channel |  |
| /settings/updates/channel/stable | IMPLEMENTED | SYSTEM | Stable Channel |  |
| /settings/updates/channel/unstable | DEVELOPER-ONLY | DEV | Unstable Channel |  |
| /settings/updates/version-lock | IMPLEMENTED | SYSTEM | Version Lock |  |
| /settings/developer | DEVELOPER-ONLY | DEV | Developer |  |
| /settings/developer/runtime | DEVELOPER-ONLY | DEV | Runtime |  |
| /settings/developer/modules | DEVELOPER-ONLY | DEV | Developer Modules |  |
| /settings/developer/network | DEVELOPER-ONLY | DEV | Network |  |
| /settings/developer/feature-flags | DEVELOPER-ONLY | DEV | Feature Flags |  |
| /settings/developer/environment | DEVELOPER-ONLY | DEV | Environment |  |
| /settings/developer/components | DEVELOPER-ONLY | DEV | Components |  |
| /settings/developer/diagnostics | DEVELOPER-ONLY | DEV | Diagnostics |  |
| /settings/developer/intelligence | DEVELOPER-ONLY | DEV | Local Intelligence |  |
| /settings/about | IMPLEMENTED | SYSTEM | About | Adds Legal (licenses, privacy, terms) and Service (status, what’s new) sections |
| /settings/about/version | IMPLEMENTED | SYSTEM | Version |  |
| /settings/about/licenses | IMPLEMENTED | NAV | Licenses |  |
| /settings/about/privacy | IMPLEMENTED | NAV | Privacy Policy |  |
| /settings/about/terms | IMPLEMENTED | NAV | Terms |  |

Totals: APPLIED 23, DEV 10, EMPTY 1, LIVE 11, LOCAL-ONLY 24, NAV 18, SCOPED 26, SYSTEM 23

Installed module detail routes (`/settings/modules/:moduleId/…`) are LIVE, built dynamically from catalogue and HostBridge manifests.

## Open decision: LOCAL-ONLY preferences

59 of the 62 `@AppStorage("settings.*")` keys in Settings are not read anywhere else in the app. Only `chats.enterToSend`, `chats.spellCheck` and `personalisation.storyAutoAdvance` change behaviour today. The LOCAL-ONLY pages above say “Saved on this device”, which is accurate, but the toggles have no effect yet. Options:

1. Wire the cheap ones (feed default mode, data saver, haptic on play, autoplay).
2. Hide pages whose toggles have no consumer.
3. Relabel them as “Preferences for upcoming features”.

## Server endpoints added for Settings

- `GET /v1/status`: public live component health
- `GET /v1/support/contact`: support mailbox, categories, limits and allowed diagnostic keys
- `GET /v1/support/cases`, `POST /v1/support/cases`: authenticated, `Idempotency-Key`, 5 per hour
- Existing: `POST /v1/account/data-exports`, `POST /v1/account/data-requests/:id/advance`, `GET /v1/account/data-requests/:id/artifacts`
