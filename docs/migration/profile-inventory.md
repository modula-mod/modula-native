# Profile inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

DATA CONTRACT: `src/features/profile/contracts/profile.ts`, `profileTabs.ts`, `src/data/repositories/api/ApiProfileRepository.ts`. ID/handle/displayName/kind/avatar/cover/color/bio/pronouns/location/website, follower/following/module/post counts, joined date, focus, identity claims, links/featured module IDs and viewer relationship. Field visibility public/followers/teams/private; teams currently owner-only fallback. No global profile privacy field is implied by the default public constant.

BEHAVIOUR: owner/public/preview contexts gate edit/customize/follow/message/private controls. Core tabs posts/media/about/modules/links; shop/agents are disabled module previews. Followers/following routes exist. Presentation preferences retain layout, tab order/default, metrics order/visibility/default, halo and count visibility. Local presentation cache and backend data must stay separate.

VISUAL REFERENCE: UnifiedProfileScreen, cover/avatar editors, native tab concepts, metric picker, side rail interactions, docs/design/modula-profile-guidelines.md and docs/architecture/profile-*. Preserve intent, not hierarchy. Cover art is separate from account identity.

RN IMPLEMENTATION: component tree, worklets, Expo image picker/router/native-tab shims are REFERENCE_ONLY. Data and behaviour CARRY; native Profile NATIVE_REWRITE in N3. N1 placeholder must not fabricate a profile or counts.

