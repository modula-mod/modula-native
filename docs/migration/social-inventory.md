# Social inventory

Audit date: 2026-09-12. Expo source: `modula-mod/modula-latest@7876379948cb382aab5cf8692686354e7646a769`. Paths below are relative to that read-only checkout unless a separate repository is named. “Implemented” means present in source, not a fresh runtime pass.

Evidence: `src/domain/social/SocialPost.ts`, `src/domain/social/media.ts`, `src/features/social/posts/types/post.ts`, `src/features/composer/screens/ComposerScreen.tsx`, `src/data/repositories/api/Api{Feed,Post,Activity,SocialGraph,Moderation,Stories,Reels}Repository.ts`.

Feed modes following/forYou/modules. Base posts carry ID, author, version, creation time, engagement, optional quote and optimistic pending/confirmed/failed state. Reactions: like/love/laugh/fire/celebrate/insightful/support/curious. Thread comments include parent/root/depth/version/deletion. Creates carry audience/reply permission/media/link/poll/idempotency key; edits carry expectedVersion. Public-only opt-in AT publishing is distinct from Greenfield identity.

Rendered content types include image, text, carousel, video, music, link, poll, movie and event. Presence of music/movie/event view types does not prove full publishing/backend support. Domain SocialPost union is narrower (text/media/link/module). InnerCircle/modules audiences are explicitly previews. Save/repost/reaction/comment/sharing/composer/activity/media upload contracts deserve carry; RN gesture rails, drawers, player surfaces and shell presentation are reference only.

Seeded surfaces and demo author/profile records exist separately and must not become final native acceptance data. N1 reserves typed post/profile destinations; full Feed/Composer/Activity/Search move to N3.

