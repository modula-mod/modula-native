# GUBIC: platform specification (v1)

Status: draft for Andy's review. This is the same document in `modula-mod/modula-latest`
(`docs/gubic/GUBIC-PLATFORM-SPEC.md`) and `modula-mod/modula-native` (`docs/gubic/GUBIC-PLATFORM-SPEC.md`).

> GUBIC is Modula's integrated gaming platform. Inside Modula, people discover, play, create,
> publish and share games. Think Apple Arcade + Steam + a game creator marketplace. Players become
> creators, and games become part of their digital identity. (Andy's brief)

## 1. Scope and phases

| Phase | Scope | Status |
|---|---|---|
| G0 Catalogue foundation | Game catalogue policy on the immutable registry (`078_gubic_game_catalogue`): `/v1/gubic/games`, featured, new releases, categories, publisher, versions, eligibility, install-plan, My Games | Already on `main` |
| **G1 Play platform** (this change) | Library, play sessions, lobbies + WebSocket, achievements, developer submissions + review, Premium capabilities; native Product Hub entry, Discover, Library, Detail, Player (WKWebView runtime + JS bridge), Lobbies, Creator/Publish | `feature/gubic` (backend), `design/gubic` (native) |
| G2 Identity integration | Achievements on profiles, friends-only lobbies, community game pages, Moliboo-as-player (Bible §08), share cards | Later |
| G3 Creator economy | Paid games, in-game purchases, storefront, DIMON rewards. Needs payments authorisation (Premium P4) | Later |
| G4 More engines | PlayCanvas GA, MMORPG client runtime, **legally compatible retro emulation** (see §10) | Later; flagged |

Everything in G1 is behind flags: backend `MODULA_GUBIC_PLAY_ENABLED` (off by default), native
`GubicFeature.enabled` (on in Debug, off in Release unless switched on in Developer settings).

## 2. Architecture

```
iOS (SwiftUI)                                      Greenfield API (Fastify + PostgreSQL)
───────────────                                    ───────────────────────────────────
Product Hub ─▶ GUBIC hub (Discover │ Library │ Create)
   │                                               /v1/gubic/games, featured, categories, …   (G0, registry projection)
   ├─ GubicStore (@Observable) ──── HTTPS ───────▶ /v1/gubic/library, sessions, achievements  (G1, gubic/play-service.ts)
   │                                               /v1/gubic/games/:id/lobbies, /lobbies/*
   ├─ GubicLobbySocket ─────────── WSS ──────────▶ /v1/gubic/lobbies/:id/socket                (GubicLobbyHub)
   │                                               /v1/developer/gubic/submissions              (publisher-scoped)
   │                                               /v1/admin/gubic/submissions/:id/decision     (operator review)
   └─ GubicPlayerView
        └─ WKWebView (sandboxed, gubic:// scheme)
             └─ game JS ── window.gubic (bridge v1) ──▶ GubicBridge (native validation) ──▶ API
```

* **The registry stays the source of truth** for releases, signatures, artifacts, compatibility and
  installs. GUBIC tables only add game policy (catalogue entry), player state and review evidence.
* **Postgres is authoritative** for lobbies; the WebSocket only pushes change notifications and
  relays opaque game messages. In v1 the hub is in-process (one API node). Multi-node needs
  Postgres `LISTEN/NOTIFY` or Redis behind the same `GubicLobbyHub` interface.
* **Games never get account credentials, wallet writes or inventory writes.** They talk only to the
  host bridge, which validates and calls Greenfield with the user's session.

### 2.1 Data model (`080_gubic_play_platform`)

| Table | Purpose | Notes |
|---|---|---|
| `greenfield_gubic_library_items` | Per-account library: added, favourite, hidden, last played, play count, total play time | Remove keeps achievements |
| `greenfield_gubic_play_sessions` | One row per play; one active session per account and game | Abandoned sessions count only up to the last heartbeat; capped at 24 h |
| `greenfield_gubic_lobbies` | Lobby: game, host, title, `public`/`invite`, 6-char join code, 2 to 16 players, `open`/`in-game`/`closed`, revision, 2 h TTL | Join code only shown to members |
| `greenfield_gubic_lobby_members` | Members with role, ready, joined/left | Host leaving closes the lobby |
| `greenfield_gubic_achievements` | Definitions declared in the manifest; written on approval | Removed ones retire; unlocks are never deleted |
| `greenfield_gubic_achievement_unlocks` | Append-only (trigger) unlock history | Identity history: survives uninstall and downgrade |
| `greenfield_gubic_submissions` | Developer submissions with normalised manifest + SHA-256, monetisation, status, reviewer, reason | One open submission per game; unique (game, version) |
| `greenfield_premium_capabilities` rows | `gubic_*` capabilities in the Premium catalogue | See §8 |

### 2.2 HTTP API (G1)

All routes use the standard envelope `{ok, data | error, requestId}` and Greenfield bearer sessions.

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/gubic/capabilities` | Server-evaluated `gubic_*` Premium capabilities for the caller |
| GET | `/v1/gubic/library` | Library items with stats, achievements unlocked, published game projection |
| PUT/DELETE | `/v1/gubic/library/:gameId` | Add/favourite/hide; remove (refused while a session is active) |
| POST | `/v1/gubic/games/:gameId/sessions` | Start a session `{clientPlatform, releaseVersion?, lobbyId?}` |
| POST | `/v1/gubic/sessions/:id/heartbeat`, `/end` | Heartbeat every 60 s; end records duration |
| POST | `/v1/gubic/sessions/:id/achievements/:key` | Unlock; idempotent; must be an active session for a declared, non-retired achievement; max 50 per session |
| GET | `/v1/gubic/games/:gameId/achievements` | Definitions (hidden ones concealed until earned) + caller's unlocks |
| GET | `/v1/gubic/me/achievements` | Caller's unlock history and points |
| GET/POST | `/v1/gubic/games/:gameId/lobbies` | List open public lobbies; create (size capped by plan) |
| POST | `/v1/gubic/lobbies/join` | Join by `joinCode` (works for invite lobbies) |
| GET | `/v1/gubic/lobbies/:id` | Members only for invite lobbies |
| POST | `/v1/gubic/lobbies/:id/join`, `/leave`, `/ready`, `/start` | Start: host only, at least 2 players, all ready |
| WS | `/v1/gubic/lobbies/:id/socket` | Bearer header; member only. Server → `hello`, `lobby.updated`, `lobby.started`, `lobby.closed`, `relay`, `pong`, `error`. Client → `ping`, `relay {payload}` (max 4 KB, 30/s; never interpreted by the server) |
| POST/GET | `/v1/developer/gubic/submissions` | Submit manifest for a publisher you can act for; list by `publisherId` |
| POST | `/v1/developer/gubic/submissions/:id/withdraw` | Pending only |
| GET | `/v1/admin/gubic/submissions` | Operator review queue |
| POST | `/v1/admin/gubic/submissions/:id/decision` | `{decision: approve|reject, reason}`; rejection requires a reason |

## 3. Game package and manifest

A game ships as the existing content-addressed web archive (`application/vnd.modula.game-web+tgz`,
verified by `WebGamePackage`: ustar only, no links, no native payloads, inventory digests,
mandatory restrictive CSP, 50 MB compressed / 64 MB expanded) plus `gubic.game.json`:

```json
{
  "schema": "modula.gubic.game.v1",
  "gameId": "digital.modula.games.orbit-tap",
  "version": "1.0.0",
  "title": "Orbit Tap",
  "summary": "Tap to swap orbits and collect stars.",
  "genre": "Arcade",
  "categories": ["arcade", "casual"],
  "runtime": {"engine": "html5", "engineVersion": null, "entry": "index.html", "orientation": "portrait"},
  "bridge": {"version": 1, "capabilities": ["lifecycle", "score", "achievements"]},
  "network": "none",
  "multiplayer": null,
  "achievements": [
    {"key": "first-star", "title": "First star", "description": "Collect a star", "points": 10},
    {"key": "orbit-master", "title": "Orbit master", "description": "Score 50", "points": 40, "hidden": true}
  ],
  "ageRating": "4+",
  "monetisation": "free",
  "userGeneratedContent": false,
  "packageSizeBytes": 120000
}
```

Rules (enforced by `validateGubicManifest`, unit-tested):

* `engine` ∈ `html5 | phaser | playcanvas`. `mmorpg-client` and `retro-emulation` are recognised but refused as "later phase".
* `network` ∈ `none | lobby-relay`. **Games never get open internet access**; CSP has `connect-src 'none'`.
* Multiplayer needs `network: lobby-relay`, the `lobby` capability, and 2 ≤ min ≤ max ≤ 16.
* Bridge capabilities: `lifecycle` (required), `score`, `achievements`, `lobby`, `player.profile`, `moliboo.avatar`, `storage.namespaced`. Unknown ones are rejected.
* Up to 100 achievements, keys `^[a-z0-9][a-z0-9_.-]{0,63}$`, 0 to 100 points each, ≤ 1000 total.
* `ageRating` ∈ `4+ | 9+ | 12+ | 17+`; `monetisation` ∈ `free | paid | in-game-purchases`.
* The normalised manifest is stored with a canonical SHA-256 digest.

## 4. HTML5/Phaser runtime (native)

`GubicPlayerView` hosts one `WKWebView` per play:

* **Origin isolation**: content is served only from a custom `gubic://<random-session-origin>/` scheme
  handler from an in-memory file map (bundled sample or a verified package). Unlisted paths, queries
  and fragments fail. Responses carry `Content-Security-Policy: default-src 'none'; script-src 'self';
  style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'none';
  object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`, `nosniff`,
  `no-referrer`, `no-store` and a Permissions-Policy denying camera, mic, location and motion.
* **Data**: `WKWebsiteDataStore.nonPersistent()`, so no cookies, storage or cache survive the session.
  (Namespaced saves come later through `storage.namespaced`.)
* **Navigation**: only the session origin; everything else is cancelled. No new windows; `alert/confirm/prompt` are suppressed; media/device permission requests are denied, and the device-API shim from `WebGameHost` is reused.
* **Lifecycle**: scene phase changes pause the game (`gubic:pause`/`gubic:resume` events); the web process crashing shows a recoverable state; closing the player ends the session and clears the web view.
* **Reduce Motion**: the host passes `reduceMotion` in the `hello` payload; games must honour it (the sample does: no screen shake or particle bursts).
* **Phaser**: Phaser builds are ordinary HTML5 packages. Phaser is bundled *inside the package* (or later as a verified shared runtime via `SharedWebRuntimeStore`), never loaded from a CDN.

### 4.1 JS bridge v1

Injected at document start in the main frame only, as a frozen `window.gubic`:

```js
gubic.ready()                       // game finished loading
gubic.reportScore(n)                // integer 0…1e9, max 4/s; shown by the host (no leaderboards in v1)
gubic.unlockAchievement(key)        // host validates key format + manifest + rate, then calls the API
gubic.gameOver({score})             // ends the round; the host offers Play again
gubic.lobby.send(payload)           // only when the manifest declares lobby; relayed over the lobby WebSocket
addEventListener('gubic:hello', e)  // {bridgeVersion:1, reduceMotion, locale, player:{handle}|null, lobby|null}
addEventListener('gubic:pause' | 'gubic:resume' | 'gubic:lobby', …)
```

Native side (`GubicBridge`, a `WKScriptMessageHandler` named `gubic`):

* Accepts messages only from the session origin's main frame; every message is a small JSON object with a `type` from an allow-list, otherwise it is dropped.
* Capabilities not declared in the manifest are refused even if the page calls them.
* Rate limits per message type; payload cap of 4 KB.
* The page never receives tokens, account IDs or wallet data, only the public handle (if `player.profile` is declared).
* Achievement unlocks go to `POST /v1/gubic/sessions/:id/achievements/:key`; the server is authoritative. For the bundled sample (not in the catalogue) unlocks are shown as **local preview, not recorded** — nothing is faked.

## 5. Publishing and review flow

1. **Create** (Developer Studio, existing): publisher, namespace, agreement, product, source, build.
2. **Release**: a signed registry release with `registry_kind = game` (existing MPS/registry flow).
3. **Catalogue entry**: `PUT /v1/developer/gubic/games/:gameId` (G0) with genre, categories, runtime, age.
4. **Submit**: `POST /v1/developer/gubic/submissions {publisherId, manifest}`. Validates the manifest, checks publisher access, checks `gubic_publish_free` and (for paid/IAP) `gubic_creator_monetisation`, one open submission per game, moves the catalogue entry to `in-review`, and appends a `submitted` event.
5. **Review** (operator): automated checks (manifest, CSP, package verification, size), then a human pass for content, age rating, IP and safety.
6. **Decision**: `approve` publishes via the existing catalogue review, which **re-checks registry trust and publisher ownership** (fails closed), writes achievement definitions, and retires removed ones. `reject` needs a reason shown to the developer; they can resubmit.
7. **Withdraw**: the developer can withdraw a pending submission.

The native Creator tab shows your submissions and their status, the manifest checklist and the
monetisation gate. Uploading builds stays in Developer Studio and the web studio.

## 6. Multiplayer lobbies

* Create (public or invite) → share the 6-character code (no 0/O/1/I) → join → ready → host starts → each player starts a session with `lobbyId`.
* Live updates over the WebSocket; the client refetches `GET /v1/gubic/lobbies/:id` on `lobby.updated` (revision-ordered) and falls back to polling if the socket drops.
* The relay is for small turn or state messages only (≤ 4 KB, ≤ 30/s per socket). Real-time action games need a dedicated authoritative game server later (G4).
* Safety: members see handles only; the code is visible to members only; the host leaving closes the lobby; one hosted lobby per account; 2 h TTL. Friends-only lobbies, invites by DM and blocking-aware matchmaking come in G2.

## 7. Achievements

* Declared in the manifest, written on approval, unlocked only via an active session, idempotent, append-only.
* Hidden achievements stay concealed until earned. Points are 0 to 100 each, ≤ 1000 per game.
* Achievements are identity: they survive uninstall, removal from the library and a Premium downgrade ("owned things stay owned").
* G2 shows them on profiles. **Achievements never mint DIMON or cosmetics directly**; any reward claim goes through server-validated reward services with fraud and idempotency controls (Bible §8.4.5).

## 8. Premium gating (per "Modula Premium: Concept & Build Plan")

Principles applied: *Premium makes your platform bigger; it never makes the free platform worse.
Everything free today stays free. Owned things stay owned. Never sell or imply verification. No fake
scarcity, no pay-to-win.* Limits come from the server; the client renders a contextual glass prompt
and never decides entitlements itself.

| Capability (`/v1/gubic/capabilities`) | Core (free) | Plus | Horizon | Horizon Plus | Studio | Mode |
|---|---|---|---|---|---|---|
| `gubic_play`: discover, library, play, lobbies, achievements | ✓ | ✓ | ✓ | ✓ | ✓ | existing_free |
| `gubic_publish_free`: publish free games | ✓ | ✓ | ✓ | ✓ | ✓ | existing_free |
| `gubic_lobby_size` (max players per hosted lobby) | 8 | 12 | 16 | 16 | 16 | existing_free with tier values |
| `gubic_creator_analytics` | | | ✓ | ✓ | ✓ | qa_only |
| `gubic_creator_monetisation`: paid games, IAP, storefront | | | | ✓ | ✓ | qa_only (payments not authorised) |
| `gubic_studio_team_publishing`: seats, shared release roles | | | | | ✓ | qa_only |

* Paid tiers map to the doc: Horizon Plus = "Everything, for creators: creator subscriptions, storefront"; Studio = teams and seats.
* `qa_only` capabilities are only evaluated for QA fixture memberships outside production until payments (Premium P4) are authorised. The purchase flag stays `false`.
* Gameplay stats never depend on tier (no pay-to-win). Cosmetic Moliboo editions cannot change hitboxes or speed (Bible §8.6).
* Native: `GubicPremiumGate` shows a small glass prompt naming the plan ("Paid games need Modula Horizon Plus. Free games can be published on every plan.") with one quiet link to the Premium hub; no interstitials or countdowns. If capabilities can't be loaded, paid actions fail closed.

## 9. Native UI (design/gubic)

* **Product Hub entry**: one GUBIC card at the top of Product Hub (flag-gated) using the provided GUBIC app icon. No Modula M ribbon logo on GUBIC surfaces.
* **GUBIC hub**: a segmented control for Discover · Library · Create, with search.
  * *Discover*: featured, new releases and category chips from `/v1/gubic/featured`, `/new-releases` and `/categories`, plus the bundled **Sample game** card (clearly labelled "Bundled sample, not in the catalogue").
  * *Library*: `/v1/gubic/library` plus `/v1/gubic/my-games` (installs and updates).
  * *Create*: manifest checklist, your submissions (`/v1/developer/gubic/submissions`), and the Premium gate for paid games.
* **Game detail**: hero, publisher, age, size, runtime, achievements, lobbies, and Play / Add to Library.
* **Player**: full-screen `GubicPlayerView` with a glass top bar (Exit, Pause, score, achievement toast).
* **Lobbies**: list, create (public/invite, size capped by plan), join by code, ready, start, live via WebSocket.
* Tokens: `ModulaColor`, `ModulaSpacing`, `ModulaLayout`, `modulaGlass`. Every button uses the user's live accent (`app.appearance.liveAccent`). Fonts unchanged. Reduce Motion removes springs and pulses. Empty states, not fake data, when routes return 404 (backend not deployed) or nothing is published.

## 10. Emulation and other engines (later, flagged)

* **Retro emulation is out of G1 and refused by the manifest validator.** When it lands, it accepts
  only legally compatible content: homebrew and public-domain ROMs with a licence declaration, or
  content the user can prove they own and that is licensed for that use. No BIOS or ROM distribution
  without rights, no scraping, and emulator cores must be compatibly licensed (e.g. GPL obligations
  respected) and pass App Store Guideline 4.7 (mini apps and game emulators). It will go through the
  same review with extra rights evidence.
* **MMORPG**: needs authoritative game servers, anti-cheat, moderation, voice/chat safety and a cost model. Out of scope until G4.
* **PlayCanvas**: package format already supported by `WebGameHost`. GUBIC accepts `playcanvas` manifests; GA after device performance QA.

## 11. Security, privacy and policy notes

* `modula-latest/AGENTS.md` forbids generic WebView *product UIs*. GUBIC games are sandboxed **game content** in a native host with no access to product data. This is the same exception `WebGameHost` already uses, and it should be confirmed by Andy (ADR).
* App Store: HTML5 games inside the app are allowed as mini-games (Guideline 4.7) when content is reviewed and the app offers an index. Paid games and IAP must use StoreKit (Premium P4).
* Privacy: sessions store platform and durations only. Lobbies expose handles to members only. No location, contacts, camera or mic. Account deletion must cascade GUBIC rows (follow-up: add to the account-data export/delete inventory).
* Abuse: lobby relay limits, operator review, takedown via `retired` status (existing catalogue event log).

## 12. Open questions for Andy

1. Is GUBIC a top-level Product Hub entry for launch, or behind a "Games" category?
2. Lobby sizes 8/12/16 by tier: OK, or keep everyone at 16 and gate only creator features?
3. Revenue share for paid games (G3), and should Horizon Plus include a reduced platform fee?
4. Which first-party games launch first? Bible §8.3 suggests Moliboo Hop and Moliboo Dash.
5. Retro emulation: proceed with a homebrew-only pilot, or drop it?
