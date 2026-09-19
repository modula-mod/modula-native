# N3D — Native Profile architecture

**Depends on N3C.** Branch: `cursor/phase-n3d-ios-profile` from `cursor/phase-n3c-ios-home-feed` @ `012f081ee92f20c44fb97b4001974b97e20387a7`.

```text
SwiftUI Profile
  → ProfileStore / GreenfieldProfileRepository
  → Greenfield (/v1/profiles/…)
Posts → shared Social PostCard (N3C)
Modules → featuredModuleIds → Product Hub components
Module execution → RN only after /module/:moduleId
```

## Routes

| Route | Role |
|---|---|
| `/me` | Semantic current-user root (Profile tab) |
| `/profile/:userId/overview\|posts\|modules` | Rail modes |
| `/profile/:userId/followers\|following\|links\|edit` | Secondary |
| `/profile/:userId/connections` | Honest unavailable (not OAuth connectors) |

## Shell

- `/me` root: tab bar + rail visible, Profile selected, no Back, accessory Edit/Share
- Pushed `/profile/:id` from Home/Discover/Activity: **push** (not tab hijack), Back restores stack, rail uses `replaceContextOrTop`, accessory hidden so chrome does not imply a global Profile switch
- Rail items only: Overview / Posts / Modules — **no** horizontal tab row

## Visual composition

```text
full-bleed cover → avatar pocket → identity → actions → metrics → About → content
```

Progressive header reuses `ModulaProgressiveHeader` + soft scroll edge (no rectangular translucent slab).

## Backend truth

See `docs/migration/profile-backend.md`. Edit persists `displayName` / `bio` / `visibility` only. Avatar/cover upload and full PatchProfileInput writes remain OPEN on Greenfield.

## Privacy

Server filters visibility, blocks, and non-public links. Native never shows email/phone/sessions on Profile. Featured modules only — never another user’s installed-module dump.
