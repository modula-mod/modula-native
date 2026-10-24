# Native main consolidation inventory (MOLIBOO-2D-01 / NATIVE-CONSOLIDATION-01, Phase A)

Status: **DRAFT, remote-only.** Built from GitHub (read-only API) on 2026-10-24 at about 21:30 BST while the Mac was offline.
Nothing was modified: no pushes, merges, PR edits or deploys.
The local half of Phase A is listed in §7 and must be done on the Mac before this is committed as `docs/consolidation/native-main-inventory.md`.

Times are BST (UTC+1) unless they carry a Z.

---

## 1. Repository heads (origin)

| Repo | Default | origin/main SHA | Main commit time | Open PRs | Remote branches | CI on main |
|---|---|---|---|---|---|---|
| modula-native | main | `f73da4cf` (#167 squash) | 2026-10-23 09:18 | #168 (draft), #113, #99 (draft), #77 (draft) | 72 | "Native boundaries" (GitHub Actions, npm boundary/design/typecheck/test). **No Xcode build CI.** Last main run: success |
| modula-latest (GreenField) | main | `17aa21c3` (#136) | 2026-10-23 09:48 | #137 (draft), #133 (draft) | 47 | "API Atlas contract drift": main success; **#137 head `ef859f31` FAILING** |
| modula-product-standard | main | `ba5ae815` (#8) | 2026-10-23 02:00 | #9 (draft), #7 (draft) | 4 | verify: success (main, #9, #7) |
| modula-module-generator | main | `e922bcd0` (#4) | 2026-10-23 02:02 | #5 (draft) | 7 | ci: success (main, #5) |
| modula-game-lab | main | `2527ea3a` (#1) | 2026-10-23 09:25 | #2 (draft) | 3 (+ QA tags) | Web game source checks: success |
| modula-vault-notes | main | `56eaf9e3` (#18, 2.0.1) | 2026-10-17 21:35 | #19 (draft) | 8 | verify: #19 head success |

The previously reported Native main `f73da4cf` **is still the current origin/main**. The local main on the Mac is unverified.

Native tags: `native-n1`, `native-n2`, `nodus01-partial-recovery-20260921`, `native-design-recovery-20260921`, `native-settings-navigation-recovery-20260923` and `native-n4-source-recovery-20260916-201638`. These are recovery and history tags; none is a release tag. There are no GitHub releases.

---

## 2. Deliverable A table: Native workstreams

| Workstream | Branch / PR | Main contains it? | Tests | Merge decision |
|---|---|---|---|---|
| **Moliboo 2D** | #143–#166 (`ui/moliboos-*`, `moliboos/*-2d`, `moliboos/originals-redraw`, plus fixes #149–#153). All branch heads are in main history. | **YES.** Every one of the 24 PRs is merged; the last is #166 at `a8d0e913` (23 Oct 02:09). The roster is complete at 100 (#160). | Simulator and device builds were done per PR at the time (no CI). Re-verify on the canonical main build. | **Already merged.** Nothing is stranded on GitHub. |
| Moliboo 2D follow-ups requested on 23 Oct (Settings redo, art fidelity, modern Cards, theme logo plus the Appearance option) | Expected `ui/moliboos-settings-redo`, `ui/moliboos-art-fidelity`, `ui/moliboos-cards-modern`, logo | **Not on GitHub.** No such remote branches or PRs exist. | n/a | **Pending: check the Mac** for local-only branches or worktrees (§7). If absent, rebuild them in Phase G. |
| Moliboo 3D (legacy) | `phase/mol-0x-*`, #24–#54, #151 merged; `fix/mol-01-3d-crash` (#32, closed unmerged: +15 commits, 427/46 lines, RealityKit crash experiments + docs) | The 3D runtime **is in main**: `Features/Moliboo3D` plus `Resources/Moliboo3D` (877 files, ≈41 MB in git: 667 `.usdz` ≈35.8 MB, 205 png ≈5.2 MB). `native3D` is forced off by #154. | n/a | **Do not merge #32** (obsolete; 3D is dormant). Phase C/L: measure the Release footprint of `Resources/Moliboo3D` (ODR vs bundled) before removing anything. |
| **Nodus** | Core plus UI on main since Sep 19 – Oct 3 (`7b50b32c` … `9002c7cf` "ship Nodus Chat in Release behind a runtime flag with verified model download"). `nodus-release` (`8f5ab068`) is **ahead 0 / behind 396**, so it is fully contained. 02A1 physical-acceptance commits (`d7491f62`, `1be151e6`, `b782a2da`, Sep 27) are on main. #167 (Release excludes the experimental model) merged as `f73da4cf`. | **YES, for all code on GitHub.** `phase-nodus-02a1-physical-acceptance` **does not exist on origin**, and SHA `853b4c7` **is not on GitHub** (422 "No commit found"). Its content appears on main, rebased under different SHAs. | Unit: `Nodus01Tests`, `Nodus02ATests`, `NodusReleaseTests`, `LI02IntelligenceTests`. Python: `Tools/Nodus/tests`. `Tools/Nodus/evaluations/nodus-02a1/reviewed-interactions.jsonl` is **0 bytes**, so physical acceptance has not passed (README needs ≥75 reviewed interactions). | **Already merged** (remote). **Pending, Mac:** check for a local `phase-nodus-02a1-physical-acceptance` branch or worktree, or an unpushed `853b4c7`, and diff it against main. Then run the Phase B regression gates on canonical main. |
| Product UI (Vault renderer) | **#77** `phase/product-ui-polish-01` @ `95bfc6b7`, draft, **mergeable_state = dirty** | **NO.** Ahead 8 / behind 176, merge base Oct 17. The 17 files (+2411/−277: ProductUIRenderer, ProductUIRuntime, StructuredDocument, ModuleHost …) are not in main; spot-checks of the patch lines found no equivalent content. Not contained in `merge/all-20261020` either. | PR claims 33 focused tests plus 3 Basic Echo UI tests. 12 unit failures were unclassified. No CI run. | **Pending, needs rebase/conflict resolution plus a Mac build/test.** It is part of the Vault 2.1 stack (PS #7, latest #133, vault #19). **Do not merge** without the Vault compatibility gate, and do not release Vault 2.1 as a side effect. |
| GameHost | **#99** `feature/game-platform-02` @ `163fd7b6`, draft, mergeable **clean** | **NO.** Ahead 28 / behind 0 against `f73da4cf` (main already merged in). 58 files, +4974/−40: WebGameHost, WebGamePackage, ModuleArtifactStore +208, GreenfieldClient, ProductHubView, evidence and fixtures. | Boundary CI green on every push. The PR reports simulator QA (Phaser/PlayCanvas install, 0.1.0→0.1.1 update, offline, 10 cycles, a security matrix). Physical gameplay is **not** passed. | **Pending, needs a Mac build/test** (simulator acceptance on canonical main). Still draft; the remaining gates are listed in the PR. |
| PackageManager | **#168** `codex/on-demand-packages-02` @ `88163fec`, draft, base = `feature/game-platform-02` | **NO.** **Verified stacked on #99:** #168 vs #99 is ahead 11 / behind 0 (merge base = #99 head `163fd7b6`). #168 vs main is ahead 39 = #99's 28 plus its own 11. Own delta is 9 files, +558/−28: install plans, Storage & Downloads screen, ModuleVersions, Settings. | Boundary CI green. The PR reports 4/4 focused simulator tests. Generic PackageManager across all categories, Release size and physical acceptance are pending. | **Pending, needs a Mac build/test. Merge only after #99**, then retarget it to main. It merged a branch `codex/gamehost-02r-closeout` that is **not on origin**; check it on the Mac. |
| Nodus out of Release | #167 `codex/lean-core-size` | **YES** (squash `f73da4cf`). The branch shows ahead 2 / behind 1 only because of the squash; its patch (workflow, pbxproj −1, verify-boundaries) is identical. | Boundary CI green. | **Already merged.** The branch can be deleted later, but only with the user's OK. |
| Native shell fixes | **#113** `fix/shell-chrome-tests` @ `cae75783` (not draft) | **NO.** Ahead 1 / behind 113. Only tests (5 files, +16/−9): updates 4 stale shell-chrome tests and adds `@MainActor` on `SidebarSwipeFreezeUITests`. Main still has `testActivityKeepsTabRailAndAccessory`. The same one-line `SidebarSwipeFreezeUITests` fix is also in #99 (`abc06b43`), which will conflict trivially. | PR reports 582 tests, 0 failures, on 22 Oct. Needs a re-run on current main. | **Pending, needs a Mac test run.** Low risk and test-only. Merge early (before #99) or drop the duplicate line on rebase. |
| Shell fixes merged 22–23 Oct | #114–#153 (lock, profile, settings, search, polish audits, Metal backdrops) | **YES**, all merged. | Per-PR. | Already merged. |

### Other Native remote branches (all classified)

* **In main (merged PR heads or ancestors), 65 branches.** These include every `ui/moliboos-*`, `moliboos/*`, `fix/*`, `feat/*` and `ui/*` branch listed in §8. Also in this group:
  * `merge/all-20261020`: ahead 0 / behind 170.
  * `cursor/notes-account-records-ac33`: ahead 0 / behind 181.
  * `cursor/local-dev-lifecycle-662b` (#68).
  * `perf/feed-scroll` (#78).
  * `phase-post-05-…` (#14).
  * `nodus-release`.

  None of these 65 is stranded; all are safe to prune later, with approval.
* **Not in main:**
  * `feature/game-platform-02` (#99).
  * `codex/on-demand-packages-02` (#168).
  * `phase/product-ui-polish-01` (#77).
  * `fix/shell-chrome-tests` (#113).
  * `fix/mol-01-3d-crash` (#32 closed; obsolete 3D experiment).
  * `codex/lean-core-size`: squash-merged, so its content is in main.

Closed-unmerged Native PRs: #64 `phase/device-online-00` (consolidation handoff, Oct 17; branch deleted), #32, #19, and the stale Sep-28 N4 stack #1, #3–#8.

---

## 3. Nodus vs main (remote view)

* **On main:**
  * `Core/Intelligence/**`: contracts, router, provider registry, Apple System provider, deterministic provider, `NodusIntelligenceProvider`, `MLXNodusRuntime`, `NodusRuntime`, `NodusArtifactInstaller`, `NodusRelease`, Conversation, Knowledge, Memory, Search (Brave developer provider plus Keychain credential), Reasoning (Think: `NodusDeepReasoningCoordinator`, `NodusContextBudget`), Verification, Learning.
  * UI: `Features/Developer/Nodus*` (Chat, ComposerStudio, LibraryBrowser, Workspace, Knowledge, Memory, Search settings, `Nodus02A1PhysicalAcceptanceRunner`), `Features/Intelligence/IntelligenceChatView`, `Settings/IntelligenceSettingsViews`, `NodusModelSettingsCard`, `MascotAssistant`.
  * Tooling: `Tools/Nodus/**` (training/eval pipeline, R1–R7 configs, `manifests/nodus-r7-experimental.json`).
* **R7 model manifest:**
  * Qwen3-1.7B, MLX 4-bit, `providerID: modula.nodus`.
  * `stage: experimentalCandidate`, `shippingAllowed: false`.
  * 8 known failed promotion gates.
  * Per-file SHA-256 digests are present, which helps with the model-data package contract.
* **Release:** #167 removed `MODULA_INCLUDE_EXPERIMENTAL_NODUS = 1` from the Release config, and `verify-boundaries.py` now fails if it returns or if `model.safetensors` sits under `ios/Modula`. Debug still auto-bundles R7 (per the 02A inventory).
* **Missing / unproven:**
  * Physical 02A1 acceptance: 0 reviewed interactions.
  * The local-only 02A1 branch and `853b4c7` must be checked on the Mac.
  * There is no remote branch for any Nodus phase after 02A1.
  * The model-data package path (PS #9 `category: model-data`, `executionProvider`) is draft only.

**Conclusion:** there is no Nodus code stranded on GitHub. Gate B is about *testing* Nodus on canonical main, and possibly merging a local-only branch if the Mac has one.

---

## 4. Other repositories: open PR classification

| Repo / PR | Branch @ head | vs main | CI | What it is | Classification |
|---|---|---|---|---|---|
| product-standard **#9** (draft) | `codex/on-demand-packages-02` @ `b137df2a` | ahead 1 / behind 0 | verify ✅ | `ProductPackageDistribution` (`modula.package.1`, categories `module`, `web-runtime`, `game-content`, `model-data`, `asset-pack`), game runtime contract 1.1 with `runtimeDependency`, plus Nodus model-data and Moliboo asset-pack fixtures. The fixtures still say "synthetic **3D** asset". | **Foundation for Phases D and I.** Accept first, after a review that adds the 2D Moliboo descriptor needs. Pending QA-signed e2e. |
| product-standard **#7** (draft) | `phase/product-ui-text-transform-01` @ `582092b4` | ahead 2 / behind 1 | verify ✅ | Product UI document-workflow contract (Vault 2.1 stack). | Pending: Vault stack. Needs a rebase on #8; touches different files from #9. |
| modula-latest **#137** (draft) | `codex/on-demand-packages-02` @ `ef859f31` (pushed 17:01 today) | ahead 6 / behind 0 | **API Atlas drift ❌ on head** (also ❌ on `6d7d64d6`, `969a9380`, `c12244cd`; ✅ on `b123dfb0`) | Dependency solver, signed package descriptors, closure lock hash, package-plan endpoint, QA registry acceptance of optional game/runtime artifacts, reviewed lock for game updates. +1562/−540 over 32 files (much of it Atlas docs). | **Blocked: CI red.** Backend dependency of Native #168. QA-only, no production deploy. |
| modula-latest **#133** (draft) | `phase/vault-record-metadata-01` @ `e8e10094` | ahead 6 / behind 5 | (Oct 20) ✅ | Generic record metadata and legacy references (Vault 2.1 dependency). | Pending: Vault stack. Needs a rebase. |
| module-generator **#5** (draft) | `codex/on-demand-packages-02` @ `858a8d10` | ahead 1 / behind 0 | ci ✅ | Externalises Phaser/PlayCanvas runtimes in generated games. | Pending: depends on PS #9 (runtime contract 1.1). |
| game-lab **#2** (draft) | `codex/on-demand-packages-02` @ `a94b1415` (pushed 16:25 today) | ahead 9 / behind 0 | ✅ | Separate runtime and content archives, new Orbit Dash game, QA tags `qa-orbit-dash-v0.1.1`, `qa-orbit-arena-v0.2.0`, `qa-phaser-runtime-v4.2.1`, `qa-playcanvas-runtime-v2.23.3`. | Pending: depends on PS #9 and generator #5. |
| vault-notes **#19** (draft) | `phase/vault-product-experience-01` @ `86cd5652` | ahead 21 / behind 0 | verify ✅ | Vault 2.1.0-rc4 candidate. Includes the unmerged 2.0.2 branch commits. | **Do not merge in this mission** ("Do not release Vault 2.1 as a side effect"). Depends on PS #7, Native #77 and latest #133. |
| vault-notes branch `cursor/vault-notes-2.0.2-ac33` (no PR) | `bd544027` | ahead 4 / behind 2 | — | The Vault Notes **2.0.2** release commits are **not on main** (main = 2.0.1). They are only reachable via #19 / this branch. | **Surprise:** the mission regression-tests 2.0.2, but its source is unmerged. Decide on a 2.0.2-only PR (no 2.1). Needs the user's OK. |
| modula-latest unmerged-looking branches (`phase-gai-01…`, `feat/registry-trust-pipeline`, `fix/story-expiry-rail-auth`, `codex/konsta-web-presentation`, `feat/products-list-latest-presentation`, `phase-api-baseline-02-production-convergence`, `backup/main-before-merge-20261004`) | — | all ahead 0 | — | Contained in main. | Obsolete; can be pruned later with approval. |
| module-generator `phase/module-generator-01` | `5b2a0f79` | ahead 0 / behind 8 | — | Contained. | Obsolete. |

Merged reference PRs for context: PS #8 (game runtime 1.0), generator #4, game-lab #1, latest #135 (QA game artifact retention) and #136 (semver resolver). All merged 23 Oct.

---

## 5. Stacks and dependencies (from PR metadata and diffs)

```
Package / game stack ("codex/on-demand-packages-02" in 5 repos, actively pushed today):
  PS #9  ──►  generator #5  ──►  game-lab #2
     │
     └──►  latest #137 (CI red)  ──►  Native #168  ──(stacked on)──►  Native #99  ──►  main
Vault 2.1 stack (stale since 20 Oct):
  PS #7  ──►  latest #133  ──►  Native #77 (dirty)  ──►  vault-notes #19 (2.1-rc4, do not release)
Independent:
  Native #113 (tests only)
```

## 6. Proposed dependency-safe merge order (none executed)

1. **Native #113**: test-only. Re-run `ModulaTests` on the Mac against current main, then merge. In #99, keep the identical `@MainActor` line.
2. **Product Standard #9**: shared contracts. Review the asset-pack fixture for 2D Moliboo first (Phase C/D may add a `moliboo.character.1` descriptor schema here).
3. **Module Generator #5**, then **Game Lab #2**: dev tools that depend on #9. Neither changes Native.
4. **GreenField #137**: only once API Atlas CI is green, QA-deployed in isolation and DB-backed gates pass. No production deploy.
5. **Native #99** (GameHost): after a simulator build/test on the Mac against current main.
6. **Native #168** (PackageManager): retarget to main after #99 merges, then build, test and merge. It must not merge before #99.
7. **Native Moliboo 2D asset-pack work** (new, Phases C–F): built on #168's PackageManager plus PS #9 `asset-pack`.
8. **Nodus:** nothing to merge remotely. Merge a local-only 02A1 branch only if the Mac has one and it is accepted.
9. **Vault 2.1 stack (PS #7, latest #133, Native #77, vault #19):** keep as draft. Native #77 needs a rebase across 176 commits and must not ship Vault 2.1. Re-evaluate after the Vault compatibility gate.

## 7. Must be verified on the Mac (Phase A, local half)

1. Run `git -C ~/Developer/modula-native status --porcelain=v2 --branch` and record local `main` vs `origin/main` (`f73da4cf`). **Do not reset.**
2. Run `git worktree list --porcelain`. For each worktree, record branch, HEAD, dirty files and untracked files. Expected: `modula-native-nodus02a` and others. **Never touch `~/Developer/modula-native-merge`.**
3. Run `git branch -vv --no-merged origin/main` and `git log --branches --not --remotes --oneline` to find **local-only commits**. Specifically look for:
   * `phase-nodus-02a1-physical-acceptance` and commit `853b4c7` (`git cat-file -t 853b4c7`).
   * `codex/gamehost-02r-closeout`, which #168 merged but is not on origin.
   * `ui/moliboos-settings-redo`, `ui/moliboos-art-fidelity`, `ui/moliboos-cards-modern` and any logo branch (23 Oct dispatch).
   * Any later `phase-nodus-*`.
4. `git stash list` in every worktree.
5. Untracked files: `git status --ignored=no -uall`. Record them only; do not discard.
6. Current installed simulator build: `xcrun simctl listapps booted | grep digital.modula` and `xcrun simctl list devices booted`.
7. Physical devices: `xcrun devicectl list devices`. iPhone UDID `00008150-00043C2A11A3401C`; error 4016 means locked or unavailable.
8. Local tags: `git tag --no-merged origin/main`.
9. A Release build of `f73da4cf` for the size baseline (historical: 188,856 KiB, ZIP 62,818,198 B), with `Resources/Moliboo3D` bundled vs ODR.
10. `Tools/Nodus` model cache presence, for the R7 harness.
11. VPS (read-only): `/root/modula-latest` HEAD vs `17aa21c3`, and whether an isolated QA registry exists.

## 8. Recently merged Native PRs (last 40, newest first)

#167 Nodus out of Release · #166 Cards clean binder · #165 Studio Apple-simple + wardrobe fit · #164 World scroll perf · #163 clean space home · #162 Modula-feel home · #161 Originals redraw · #160 Dreamers 086–100 · #159 Stardust 071–085 · #158 Enchanted 056–070 · #157 Underground 041–055 · #156 Angels 026–040 + parts kit · #155 Originals 2D · #154 2D-only (native3D forced off) · #153 Wardrobe vector thumbs · #152 Studio ground shadow · #151 Signature Cap fit (3D) · #150 pack glow clip · #149 Studio env checkmark · #148 Cards/Welcome · #147 Studio 2 · #146 Studio · #145 Profile top blur · #144 Passcode Liquid Glass · #143 Moliboos core polish · #142 Polish audit 1022b · #141 Polish audit 1022 · #140 Perspective Grid · #139 Passcode keypad · #138 Spectral Drape · #137 Send to Island · #136 Lock polish · #135 Profile progressive blur · #134 Lock escape · #133 Lock lockout · #132 Profile tabs z-index · #131 Profile pin composer · #130 Profile header · #129 Slide to unlock · #128 Settings island drop.

(Earlier: #115–#127 on 22 Oct; #78–#112 on 20–22 Oct; Nodus, Moliboo 3D and ModuleHost history at #24–#76.)

---

## Mac inventory (local machine, collected 2026-10-24 ~22:10 BST)

origin/main at collection: `f73da4c`. Canonical checkout `~/Developer/modula-native` is on `nodus-release` (`8f5ab06`, identical to origin, fully contained in main).

### Nodus references
| Ref | Status |
|---|---|
| `853b4c7` "fix(nodus): preserve routed freshness through context" | Exists locally as an unreachable commit (no branch). Patch-id identical to `94aa260` on main → **already in main (rebased)**. Safe to drop. |
| `phase-nodus-02a1-physical-acceptance` | No local or remote branch remains; content in main. |
| `nodus-release` `8f5ab06` | Pushed, contained in main. |

### Local-only commits (not on any remote)
| Branch / worktree | Commits | Assessment |
|---|---|---|
| `phase-native-consolidation-00` (`~/Developer/modula-native-consolidation-00`, clean) | 4 merge/normalize commits from 2026-10-04 (`44ac02b`, `3266547`, `93af94b`, `a6ff81c`), 391 behind main | Superseded consolidation attempt; content landed via later PRs. Archive, don't merge. |
| `fix/shell-chrome-tests` (`~/Developer/modula-native-landing`, clean) | `9727e05` merge of origin/main only | No unique work. |
| `codex/on-demand-packages-02-full-backup` (Codex clone `~/Documents/Codex/2026-10-21/.../modula-native`) | `ce79cc4` "Verify shared web runtimes and expose measured download storage" | Backup of the on-demand-packages line (#168 lineage). Compare with #168 before deleting. |

### Uncommitted work that matters
| Worktree | Branch | State | Assessment |
|---|---|---|---|
| `~/Developer/worktrees/modula-native-slide` | `ui/moliboos-settings-redo` (= main @ #166, 1 behind) | 6 modified + 1 untracked, last edited 2026-10-23 02:15: `MolibooSettingsView.swift` (323 lines changed), `MolibooCards.swift`, `MolibooWorldView.swift`, `HomeView.swift`, `SettingsStore.swift`, `SettingsView.swift`, new `DesignSystem/MoliboosWordmark.swift` | **The un-shipped Moliboo Settings redo + Moliboos wordmark/logo work.** Must be committed + PR'd as part of Moliboo Phase work; not on GitHub anywhere. |
| `~/Developer/worktrees/modula-native-fits` | `fix/wardrobe-fits-all` (`6ad23ae`, 234 behind) | 4 modified + 2 untracked tests (MOL03 wardrobe fit validator) | 3D-era wardrobe fit work (MolibooSceneController / WardrobeRig). Obsolete for 2D; archive as patch. |
| `~/Developer/modula-native` | `nodus-release` | `project.pbxproj` + `Localizable.xcstrings` modified (Xcode churn vs. an old tree) | Stale, not product work. |
| `~/Developer/worktrees/merge-all` | `merge/all-20261020` | 2 modified | Old merge staging. |
| Other dirty worktrees (1–3 files each): `modula-native-art` (detached), `lock-v2`, `module-ecosystem-01`, `pdf`, `profile4`, `reaction-swipe`, `scroll`, `sidebar3`, Codex `native` (`phase/product-ui-polish-01`) | various | small diffs | Review individually before any cleanup; nothing deleted. |
| `~/Developer/modula-native-merge` | — | not inspected (never-touch) | — |

34 worktrees total. Stashes (4, untouched): `freeze-repro-debug (fake feed + test)` on fix/home-sidebar-hang; `pod-install pbxproj (main-install)`; `temp continual-learning hook state` on main; `Cursor: moved local changes to cloud agent` on phase-n2-ios-ui-polish. None contain Moliboo 2D or Nodus product work.

### Simulators / devices
- Booted sims (iOS 26.3): "Freeze Repro", "iPhone 17 Pro Landing", "iPhone 17 Pro Max".
- Physical: `modula.digital` iPhone 17 Pro Max, UDID `00008150-00043C2A11A3401C` — **unavailable** at collection time (Wi-Fi/locked).
