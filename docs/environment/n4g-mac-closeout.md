# N4G Mac closeout

Future home-machine mission. Remote source is **PARTIAL** until these gates pass.

After N4G source is on disk: **stop adding phases**. Do not start N4H while the giant dirty worktree remains unbuilt.

Next mission is:

**MODULA NATIVE — N4 INTEGRATION & CLOSEOUT**

recover Git, split N4B → N4C → N4D → N4E → N4F → N4G, push, verify Greenfield on `ssh modula-vps`, `xcodebuild`, simulator, iPhone, Instruments, Release without Metro.

## Recover / split (never reset)

1. Preserve the dirty worktree. Do not `git reset`, `git clean`, or checkout over files.
2. If Shell works, capture `git status`, `git diff --stat`.
3. Split commits in this order, recording shared hunks from each `docs/environment/n4*-remote-staging.md`:
   - N4B post-system
   - N4C communications
   - N4D command platform
   - N4E first-run / security / surfaces
   - N4F creation studio
   - N4G visual language / Edge Loop  
     Recommended branch: `cursor/phase-n4g-visual-language-fc45`

Recommended eventual N4G commits (when Git is recovered):

```text
feat(surface): add material, shape, depth, and trailing safe-area tokens
feat(edge-loop): add EdgeLoopEngine, cut-in shape, and ModulaEdgeLoop
feat(immersive): add FullBleedHero, avatar pocket, and onboarding scene
feat(home): migrate Home chrome to Edge Loop and compact Stories
feat(profile): apply carved cover/avatar pocket
feat(module-detail): cover-driven product hero without fake metrics
feat(onboarding): brand atmosphere scene
feat(posts): converge action rail materials and counts
feat(appearance): multi-sample font preview with contained loop
feat(shell): dock accessory into the tab surface
test(n4g): cover Edge Loop math, tokens, and chrome contracts
docs(n4g): document surface system and remote staging
```

## Native execution

- `xcodebuild` Debug PASS
- `xcodebuild` Release PASS
- Simulator: Edge Loop tap, drag, snap, VoiceOver increment; Home without duplicate tabs; Profile pocket; Module Detail; Onboarding; Typography preview
- Physical iPhone (required for PASS): Edge Loop drag/haptics, full-bleed covers, tab bar + accessory layering, progressive blur, media action rail vs Edge Loop collision
- Accessibility matrix: VoiceOver, Switch Control, large Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Colour
- Metro-free Release

## Product walkthrough

- Home Edge Loop: Following → For You → Modules loops; no horizontal mode strip
- Activity Edge Loop: All / Mentions / Requests
- Profile Edge Loop: Overview / Posts / Modules only
- Home Stories sit in a compact tray; feed is visible immediately
- Appearance → Typography: sample loop does not cover the preview
- Module Detail: no 4.8 / 10K downloads unless Greenfield supplies them
- Five tabs remain Home, Discover, Modules, Activity, Profile
