# N4 Final Acceptance — Start Truth

Recorded: 2026-09-18 during Final Acceptance & Merge (no N5).

## Tip identity

```text
CLOSEOUT BRANCH:   phase-n4-integration-closeout
CLOSEOUT TIP:      df2b96627d0965af0b3f2de1f1f1c01672502763
N4G BASE TIP:      ccda4f0fabb0d3d949a2a62e306b8b4e12aefc8f
RECOVERY:          2402a200985f643f123a35a6c771caaecb4dcc2f
origin/main:       af1956f69cf29889559b82c43f7116e57ac686a4 (N2 polish; N3/N4A not yet on main)
```

## Device install (in progress)

| Step | Status | Evidence |
|---|---|---|
| Device online | PASS | `modula.digital` UDID `00008150-00043C2A11A3401C`, iOS 27.0, Developer Mode enabled, wired |
| Debug build @ `df2b966` | PASS | `/tmp/n4-final-acceptance/DerivedDataDevice` — `BUILD SUCCEEDED` |
| `devicectl` install | PASS | `digital.modula.app.native` installed |
| Cold launch | **BLOCKED** | Device system lock screen (Enter Passcode / Face ID). Launch denied: `Locked` |
| Screenshot | captured | `artifacts/n4-final-acceptance/screenshots/00-pre-unlock.png` |

## PR stack (read-only check)

| PR | State | Base → Head | Tip |
|---|---|---|---|
| #3 N4B | OPEN / MERGEABLE | N4A → N4B | `febdec6` |
| #4 N4C | OPEN | N4B → N4C | `8715de4` |
| #5 N4D | OPEN | N4C → N4D | `3085d64` |
| #6 N4E | OPEN | N4D → N4E | `eb09214` |
| #7 N4F | OPEN | N4E → N4F | `d19234d` |
| #8 N4G | OPEN | N4F → N4G | `ccda4f0` |
| Closeout | not created | N4G → closeout | `df2b966` |

Note: N4A (`1ef3fc4`) and N3 lineage are **not** on `origin/main`. Merge plan must account for bringing N3/N4A (or the cumulative tip) onto main before/with the N4B→Closeout stack. Do not merge blindly.

## Next human action required

Unlock `modula.digital` (Face ID or device passcode) and leave it unlocked for the baseline walk.
