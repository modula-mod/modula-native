# MOL-03R — Economy, Care, Cards & Achievements Audit

## 1. Care State (`MolibooCareStore` / `MolibooCareState`)
- **Storage**: `UserDefaults` key `moliboo.care.v1.<characterID>` (per-character JSON blob).
- **Mechanics**: Honest wall-clock decay (`advance(to:)`) + deterministic activity deltas (`sleep`, `play`, `clean`, `feed`) and quick care nudges (`Say hi`, stage tap, `Surprise`).
- **Bond Level**: `1 + Int(bondXP / 100)`, persisted immediately on every interaction and verified across app relaunch (`MOL03WorldTests`, `MOL03WorldUITests`).

## 2. Coins, Daily Chest, Streak & Achievements (`MascotProgressStore`)
- **Storage**: `UserDefaults` key `composer.mascot.progress` (`MascotProgressState`).
- **Daily Streak**: `touchDay()` compares `YYYY-MM-DD` local calendar keys (`lastActiveDay`); increments once per calendar day and unlocks `streak_7` (`On a roll`, +150 coins + `back.streakcape`) at 7 consecutive days.
- **Daily Chest**: `openChest()` is gated by `canOpenChest` (`lastChestDay != Self.dayKey()`), making it strictly idempotent once per calendar day. Awards `15...40 + min(streak, 7) * 5` coins plus a 25% roll for an unowned coin-shop wardrobe item (or +10 bonus coins).
- **Real Event Achievements**:
  - `first_comment`: Recorded only from `PostCommentsView` comment submission (`record(.comment)`).
  - `reactions_10`: Recorded only from non-removal post/comment reactions (`record(.reaction)`).
  - `stylist`: Recorded when saving an outfit preset (`MascotWardrobeStore.savePreset`).
  - `birthday`: Recorded when user-configured local birthday matches today's month/day.

## 3. Collectible Cards & Founding Collection (`MolibooCardStore`)
- **Separation of Identity**: Base character selection (`ModulaMascotSettings.kindKey`) is completely separate from Collectible Card editions (`founding.<id>` in `MolibooCardCatalogue`).
- **Founding Pack Rules**:
  - Free local packs (`openFoundingPack`), persisted under `moliboo.cards.owned.v1` and `moliboo.cards.packsOpened.v1`.
  - First pack (`packsOpened == 0`) is the deterministic 5-card welcome pack (`pip`, `moss`, `nimbus`, `ember`, and Legendary `pebble` revealed last).
  - Subsequent packs roll 5 cards using `MolibooSplitMix` RNG with slot 5 guaranteed `.rare` or higher, incrementing duplicate counts (`×2`, `×3`, etc.) in the binder.
