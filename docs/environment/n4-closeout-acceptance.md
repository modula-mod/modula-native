# N4 Closeout Acceptance — In Progress

Updated: 2026-09-16 during Integration & Closeout.

## Gate status (live)

| Gate | Status | Evidence |
|---|---|---|
| Git recovery | **PASS** | `recovery/n4-source-stack-20260916-201638` @ `2402a20`; tag `native-n4-source-recovery-20260916-201638`; pushed |
| Dangerous automation disabled | **PASS** | `com.modula.n4b-caf1` unloaded; plist renamed; dispatcher no-op |
| Secrets excluded from recovery | **PASS** | No `.env` / credentials / provisioning in recovery commit |
| Closeout branch | **PASS** | `phase-n4-integration-closeout` @ tip includes recovery + closeout fixes |
| Debug build | **PASS** | Simulator iPhone 17 Pro (26.3.1) `BUILD SUCCEEDED` |
| Unit tests (ModulaTests) | **PASS** | 182 executed, 0 failures (N1 edge for bridge) |
| Greenfield For You | **PASS** | Was 500; now 200 `ranking-v1` after API `80c2c0d` |
| Greenfield media 500 | **PASS** | Sample JPG/PNG now 200 |
| Backend PR | **PASS** | [modula-latest#99](https://github.com/modula-mod/modula-latest/pull/99) merged `0c83b6f` |
| Metro :8081 | **PASS** | Absent during closeout Release attempt |
| Bundle credential scan | **PASS** | No fixture emails; `accessToken`/`refreshToken`/`Bearer` are Codable/header symbols only; no localhost/:8081 in Release app |
| Physical iPhone | **BLOCKED** | `modula.digital` offline in xctrace |
| Phase reconstruction N4B→N4G | **IN PROGRESS** | N4B [PR #3](https://github.com/modula-mod/modula-native/pull/3) `febdec6`; N4C [PR #4](https://github.com/modula-mod/modula-native/pull/4) `8715de4`; N4D [PR #5](https://github.com/modula-mod/modula-native/pull/5) `3085d64`; N4E [PR #6](https://github.com/modula-mod/modula-native/pull/6) `eb09214`; N4F [PR #7](https://github.com/modula-mod/modula-native/pull/7) `d19234d` build+tests PASS; N4G next |
| Release build | **PASS** | Simulator Release `BUILD SUCCEEDED`; `main.jsbundle` + hermes present; Metro :8081 absent |
| UITests | **PARTIAL** | Fail under App Gate signed-out (expected until fixture login harness) |
| App Lock / Face ID / visual / Instruments | **PENDING** | Needs online physical device |

## Recovery references

```text
RECOVERY STARTING BRANCH: recovery/n4-source-stack-20260916-201638 (created from dirty N4A+stack)
RECOVERY SNAPSHOT HEAD:   2402a200985f643f123a35a6c771caaecb4dcc2f
RECOVERY TAG:             native-n4-source-recovery-20260916-201638
CLOSEOUT BRANCH:          phase-n4-integration-closeout
BACKEND STARTING HEAD:    ff228cdcf9fc2d7efe3b951e8aa56e69eaf6ee65
BACKEND FINAL/DEPLOYED:   80c2c0d506da50df28f342ca43e9898391afe79d
```

## Capability-off (honest; not failures)

Messaging, In-Mail, Stories, Reels playback, Saved-list, photo publishing, multi-reactions.

## Next required actions

1. Reconstruct compiling N4B→N4G stacked branches + PRs
2. Bring physical iPhone online for App Lock / Face ID / Edge Loop / Release install
3. Finish Release-without-Metro + bundle credential scan
4. Complete acceptance matrix → final report + `native-n4` tag only on PASS
