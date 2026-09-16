# Stories backend audit (N4C)

Audit date: 2026-09-16. **`ssh modula-vps` not completed.**

## Known

| Method | Path | Role |
|---|---|---|
| GET | `/v1/media/stories/:file` | Media file serve (profile-backend.md). Not a story group list. |

Expo inventory lists `ApiStoriesRepository.ts` as source presence only.

## Not verified

Story groups, expiry authority, viewers list, publish, privacy (`Public` / `Followers` / `Connections` / Close Friends), replies into messaging, reactions, ranking.

Native N4C therefore:

- Builds tray / ring / viewer / progress / create **architecture**
- Treats expiry as a server field when present; never as the client authority
- Does **not** ship production Home tray rows from fixtures
- Leaves `CREATE STORY: OPEN — BACKEND`
- Does not query generic media endpoints to “find” hidden stories
- Story reactions reuse `SocialReaction` if a contract appears; no separate taxonomy

`StoryBackendCapabilities.production` keeps list/create/viewers/reply/react **false**.
