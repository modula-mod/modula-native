# Moliboo game systems: native integration notes (design/moliboo-game)

**Flag:** `MolibooGameFlags.enabled` (UserDefaults `dev.moliboo.gameSystems`, or launch arg `-MolibooGameSystems`). It is OFF by default.
Turn it on once modula-latest `feature/moliboo-game-systems` (migration 080 + `/v1/moliboo/*`) is deployed.
While the flag is off, the new Studio panels show a "coming" state and make no network calls.

## What's wired (real routes only)
| UI | File | Routes |
|---|---|---|
| Studio rail → **Outfits** (full outfits, my outfits, save current) | `Features/MolibooGame/MolibooGameViews.swift` `MolibooOutfitsPanel` | `GET catalogue/outfits`, `GET/POST/DELETE outfits`, `POST characters/:id/equip` |
| **Inventory** (from Outfits → grid button) | `MolibooInventoryView` | `GET inventory` |
| Studio rail → **Care** (skills, buffs, care, quests, mini-activities) | `MolibooCareQuestsPanel`, `MolibooSkillsBuffsCard`, `MolibooQuestsPanel` | `GET characters/:id/state`, `POST care`, `POST skills/:skill/use`, `GET quests`, `POST quests/:q/claim`, `POST activities/complete` |

`MolibooSkillsBuffsCard(store:)` can also be dropped into any Moliboo detail screen (e.g. Collection detail) with a `MolibooGameStore`.

## Rig interface (for the ModulaMascot / Series 2 stream)
* `MolibooOutfitSet { characterId, slots: [{slot, itemId?}] }` comes from the server as `state.outfitSet`.
* `MolibooWearableSlot.drawOrder` is the suggested back-to-front order.
* Game code never edits `ModulaMascot.swift` or the rig. Rendering equipped game items on the figure is up to the rig stream:
  map `itemId` → art (the icons in `MolibooItems.xcassets` are flat previews, not fitted wearables).
  After that, call `MolibooGameStore.state?.outfitSet` from `MolibooLivingStudioView` and pass it to the figure.
* Buff and set-bonus FX keys live in `effects.fx` (e.g. `cheek_glow`, `signature_angels`, `set_halo_choir`). Map them to the asset-kit FX rewards.

## Character ids
`MolibooGameCharacterID.server(for:)` maps `pip` → `moliboo.originals.pip` and `moliboo.027` → `moliboo.angels.soli`, using the bundled registry.

## Assets
`Resources/MolibooGame/MolibooItems.xcassets` holds 103 glossy 2D icons (88 items + 15 outfits) generated from SVG
(`Tools/moliboo/game-items/`). The catalogue seed `moliboo_game_catalogue.v1.json` is a copy of the backend seed and is kept only for tooling and the contact sheet.
The app does not read ownership from it.

## Rebase note: PR #243 (design/moliboo-redraw, full code rig for all 215)
The public figure there is `ModulaMascotFigure(kind:pose:size:outfit: MascotOutfit)`, defined in ModulaMascot.swift, which this branch does not edit.
For integration, add a small adapter in the rig stream: `extension MascotOutfit { init(gameSet: MolibooOutfitSet) }`.
It should map each game `itemId` to that rig's wearable ids, or to new fitted art, and skip slots it can't fit.
Then the Studio stage renders `ModulaMascotFigure(kind:, outfit: MascotOutfit(gameSet: store.state!.outfitSet))`.
Until that adapter exists, the game UI shows the server-equipped set as icons, and the figure keeps the local wardrobe look.
