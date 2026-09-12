# Feature inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Significant system ownership is classified in migration-matrix.md. Source areas include account/session, appearance/accessibility, profile/presentation, social/feed/composer/activity, Product Hub/registry, module runtime, security/app lock, board/layout, connectors/AT Protocol, developer diagnostics, product previews and web presentation. Backend packages/services stay remote. Existing product previews (Gaia/DIMON/agents/forge/automations) are not completed capabilities. N1 deliberately implements only native destinations and runtime proof.

The Settings route list below provides a complete discovered entry-point index; route presence does not establish functionality.

- `src/app/settings/_layout.tsx`
- `src/app/settings/about.tsx`
- `src/app/settings/accessibility/index.tsx`
- `src/app/settings/account/email.tsx`
- `src/app/settings/account/export.tsx`
- `src/app/settings/account/handle.tsx`
- `src/app/settings/account/mail.tsx`
- `src/app/settings/account/password.tsx`
- `src/app/settings/account/sessions.tsx`
- `src/app/settings/account.tsx`
- `src/app/settings/app-lock-unlock.tsx`
- `src/app/settings/app-lock.tsx`
- `src/app/settings/appearance-lab.tsx`
- `src/app/settings/appearance.tsx`
- `src/app/settings/blocked.tsx`
- `src/app/settings/connections/atproto.tsx`
- `src/app/settings/connections/index.tsx`
- `src/app/settings/content.tsx`
- `src/app/settings/data.tsx`
- `src/app/settings/developer/data-runtime.tsx`
- `src/app/settings/developer/expo-ui/[section].tsx`
- `src/app/settings/developer/expo-ui/index.tsx`
- `src/app/settings/developer/expo-ui/playground.tsx`
- `src/app/settings/developer/index.tsx`
- `src/app/settings/developer/modula-ui-lab.tsx`
- `src/app/settings/developer/pvp-native-experiments.tsx`
- `src/app/settings/developer/session.tsx`
- `src/app/settings/dimon.tsx`
- `src/app/settings/display-and-text/index.tsx`
- `src/app/settings/display-and-text/larger-text.tsx`
- `src/app/settings/extensions/[extensionId].tsx`
- `src/app/settings/extensions/index.tsx`
- `src/app/settings/help.tsx`
- `src/app/settings/index.tsx`
- `src/app/settings/inner-circle.tsx`
- `src/app/settings/language.tsx`
- `src/app/settings/marketplace.tsx`
- `src/app/settings/modules/[moduleId].tsx`
- `src/app/settings/modules/index.tsx`
- `src/app/settings/motion.tsx`
- `src/app/settings/mute-words.tsx`
- `src/app/settings/notifications.tsx`
- `src/app/settings/privacy.tsx`
- `src/app/settings/security.tsx`

