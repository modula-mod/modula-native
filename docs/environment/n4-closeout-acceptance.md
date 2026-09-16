# N4 Closeout Acceptance — In Progress

Updated: 2026-09-16 during Integration & Closeout (N4G tip replay).

## Tip identity

```text
CLOSEOUT BRANCH:          phase-n4-integration-closeout
N4G BASE TIP:             ccda4f0fabb0d3d949a2a62e306b8b4e12aefc8f
REPLAYED PRODUCT FIX:     7ae8a0a0b911fad875d636fbb02ac238b785591d → 77e378b66c451b27215610a1552f06897749960a
CLOSEOUT TIP:             branch HEAD = product replay + this acceptance doc (verify: git rev-parse phase-n4-integration-closeout)
PRE-REPLAY BACKUP:        backup/phase-n4-integration-closeout-pre-n4g-replay @ 3bed336
RECOVERY (immutable):     2402a200985f643f123a35a6c771caaecb4dcc2f
```

Closeout is **N4G reconstructed tip + replayed closeout product/docs fixes**. Phase PRs #3–#8 history is unchanged.

## Gate status (live)

| Gate | Status | Evidence |
|---|---|---|
| Git recovery | **PASS** | `recovery/n4-source-stack-20260916-201638` @ `2402a20`; tag `native-n4-source-recovery-20260916-201638`; pushed |
| Dangerous automation disabled | **PASS** | `com.modula.n4b-caf1` unloaded; plist renamed; dispatcher no-op |
| Secrets excluded from recovery | **PASS** | No `.env` / credentials / provisioning in recovery commit |
| Phase reconstruction N4B→N4G | **PASS** | N4B [PR #3](https://github.com/modula-mod/modula-native/pull/3) `febdec6`; N4C [PR #4](https://github.com/modula-mod/modula-native/pull/4) `8715de4`; N4D [PR #5](https://github.com/modula-mod/modula-native/pull/5) `3085d64`; N4E [PR #6](https://github.com/modula-mod/modula-native/pull/6) `eb09214`; N4F [PR #7](https://github.com/modula-mod/modula-native/pull/7) `d19234d`; N4G [PR #8](https://github.com/modula-mod/modula-native/pull/8) `ccda4f0` |
| Closeout retarget onto N4G | **PASS** | Soft history rewrite of closeout only: reset to N4G `ccda4f0`, cherry-pick product fix `7ae8a0a` → `77e378b` (Saved/PostStateStore, auth copy, bridge skip, greenfield truth rewrite); CommandRegistry / FirstRun / PostComponents `@MainActor` already present on N4G |
| Greenfield For You | **PASS** | Was 500; now 200 `ranking-v1` after API `80c2c0d` |
| Greenfield media 500 | **PASS** | Sample JPG/PNG now 200 |
| Backend PR | **PASS** | [modula-latest#99](https://github.com/modula-mod/modula-latest/pull/99) merged `0c83b6f` |
| Metro :8081 | **PASS** | Absent during prior closeout Release attempt |
| Bundle credential scan | **PASS** | No fixture emails; `accessToken`/`refreshToken`/`Bearer` are Codable/header symbols only; no localhost/:8081 in Release app |
| Release build | **PASS** | Prior closeout Simulator Release `BUILD SUCCEEDED`; `main.jsbundle` + hermes present; Metro :8081 absent (re-verify optional after tip retarget) |
| Debug build (this tip) | **PASS** | Workspace Debug on sim `1F8BD84E-2432-45A0-B93A-36D7D745860D`; derivedData `/tmp/n4-closeout-on-n4g-derived`; `BUILD SUCCEEDED` |
| Unit tests (this tip) | **PASS** | ModulaTests 182 executed, 0 failures (incl. NativeFoundation / auth / N4C–N4F); bridge integration passed via N1 edge preference |
| Physical iPhone | **BLOCKED** | `modula.digital` offline in xctrace |
| UITests | **PARTIAL** | Fail under App Gate signed-out (expected until fixture login harness) |
| App Lock / Face ID / visual / Instruments | **PENDING** | Needs online physical device |

## Recovery / backend references

```text
RECOVERY STARTING BRANCH: recovery/n4-source-stack-20260916-201638
RECOVERY SNAPSHOT HEAD:   2402a200985f643f123a35a6c771caaecb4dcc2f
RECOVERY TAG:             native-n4-source-recovery-20260916-201638
BACKEND STARTING HEAD:    ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65
BACKEND FINAL/DEPLOYED:   80c2c0d506da50df28f342ca43e9898391afe79d
```

## Capability-off (honest; not failures)

Messaging, In-Mail, Stories, Reels playback, Saved-list, photo publishing, multi-reactions.

## Next required actions

1. Bring physical iPhone online for App Lock / Face ID / Edge Loop / Release install
2. UITests fixture harness (App Gate signed-out failures expected until then)
3. Complete acceptance matrix → final report + `native-n4` tag **only on PASS**
