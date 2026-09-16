# N4 Integration & Closeout — Start Truth

Recorded: 2026-09-16 (local Mac inspection, mutation deferred until after this document).

## Repository identity

| Field | Value |
| --- | --- |
| Working directory | `/Users/msjoy/Developer/modula-native` |
| Current branch | `recovery/n4-source-stack-20260916-201638` |
| Current HEAD | `2402a200985f643f123a35a6c771caaecb4dcc2f` |
| Local `main` | `22f34ddf247ae25656ae6c8dbe3d68082e83d18d` |
| `origin/main` | `af1956f69cf29889559b82c43f7116e57ac686a4` |
| N4A baseline (expected) | `1ef3fc42d60849a565a5655943861c16ca502431` |
| N4A baseline (verified) | `1ef3fc42d60849a565a5655943861c16ca502431` (matches) |

Notes:

- Local `main` remains at N1 freeze (`native-n1`) and is **behind** `origin/main` by the N2 polish merge lineage.
- `origin/main` matches the previously reported SHA `af1956f…`.
- Local `main` matches the previously reported SHA `22f34dd…`.

## Recovery snapshot (already present before this closeout session)

The dirty N4B–N4G source stack was already checkpointed in a prior recovery step:

| Field | Value |
| --- | --- |
| Recovery branch | `recovery/n4-source-stack-20260916-201638` |
| Recovery snapshot alias | `recovery/n4-stack-snapshot` |
| Recovery HEAD | `2402a200985f643f123a35a6c771caaecb4dcc2f` |
| Commit subject | `chore(recovery): checkpoint N4B-N4G source stack` |
| Parent | `1ef3fc4` (N4A) |
| Delta vs N4A | 160 files, +22303 / −802 |
| Remote branch | pushed (`origin/recovery/n4-source-stack-20260916-201638`) |
| Remote snapshot | pushed (`origin/recovery/n4-stack-snapshot`) |
| Recovery tag at inspection | **missing** (to be created as `native-n4-source-recovery-20260916-201638`) |

## Working tree at inspection

Almost clean relative to the recovery commit. Remaining local-only noise:

| Path | Status | Action |
| --- | --- | --- |
| `.cursor/hooks/state/continual-learning.json` | modified | leave uncommitted (Cursor runtime state) |
| `.cursor/hooks/state/n4b-caf1-trigger.txt` | untracked | leave uncommitted (hook trigger noise) |

No `.env`, credentials, `.p12`, `.mobileprovision`, Keychain exports, DerivedData, or fixture secret files appear in `git status`.

## Dirty / untracked product source

None remaining. The N4B–N4G product source is already inside the recovery commit.

## N4 staging documents present

| Document | Present |
| --- | --- |
| `docs/environment/n4-greenfield-truth.md` | yes |
| `docs/environment/n4c-remote-staging.md` | yes |
| `docs/environment/n4c-mac-closeout.md` | yes |
| `docs/environment/n4d-remote-staging.md` | yes |
| `docs/environment/n4d-mac-closeout.md` | yes |
| `docs/environment/n4e-remote-staging.md` | yes |
| `docs/environment/n4e-mac-closeout.md` | yes |
| `docs/environment/n4f-remote-staging.md` | yes |
| `docs/environment/n4f-mac-closeout.md` | yes |
| `docs/environment/n4g-remote-staging.md` | yes |
| `docs/environment/n4g-mac-closeout.md` | yes |
| `docs/environment/settings-route-audit.md` | yes |
| `docs/environment/n4-closeout-start.md` | this file |
| `docs/environment/n4-closeout-acceptance.md` | not yet |

Architecture / migration companions also present under `docs/architecture/n4*.md` and `docs/migration/*-backend.md`.

## Graph context (abbreviated)

```text
* 2402a20 (HEAD -> recovery/n4-source-stack-…) chore(recovery): checkpoint N4B-N4G source stack
* 1ef3fc4 (N4A / phase-n4a-ios-profile-polish) test(profile): expand N4A interaction coverage…
…
* af1956f (origin/main) Merge phase-n2-ios-ui-polish…
* 22f34dd (main, tag: native-n1) docs(n1): freeze acceptance evidence
```

Historic phase branch names such as `cursor/phase-n4g-visual-language-fc45` still point at N4A (`1ef3fc4`) and do **not** contain the recovered N4B–N4G source. Reconstruction branches will be created later from truth, not assumed from those names.

## Dangerous automation inspection

| Item | Finding |
| --- | --- |
| `/tmp/n4b-caf1-run.sh` | present (was a closeout job dispatcher) |
| `~/Library/LaunchAgents/com.modula.n4b-caf1.plist` | present on disk |
| `launchctl` `com.modula.n4b-caf1` | **not loaded** at inspection |
| `launchctl` `com.modula.n3b-ssh-audit` | loaded, state not running (SSH audit only; left alone) |

### Disablement performed after inspection

1. Bootout/unload attempted for `com.modula.n4b-caf1` (already absent from launchd).
2. Dispatcher rewritten to an immediate no-op that only appends `/tmp/n4b-caf1-disabled.log`.
3. Plist renamed to `com.modula.n4b-caf1.plist.disabled-<stamp>` so it cannot reload.
4. Pending `/tmp/n4-closeout-job.sh` / kick / lock cleared if present.

Unrelated LaunchAgents were not removed.

## Immediate next gates

1. Create/push recovery tag `native-n4-source-recovery-20260916-201638`.
2. Branch `phase-n4-integration-closeout` from the recovery HEAD (leave recovery refs untouched).
3. Verify toolchain and attempt cumulative Debug build **before** phase history reconstruction.
4. Establish live Greenfield truth via `ssh modula-vps` and repair For You / media 500.
