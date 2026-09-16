# N4D Mac closeout checklist

Preserve the dirty worktree. Never `git reset` / `git clean` / discard N4B/N4C.

## Git

- [ ] Confirm branch + HEAD
- [ ] Split and push N4B
- [ ] Split and push N4C
- [ ] Create `cursor/phase-n4d-ios-command-platform`
- [ ] Commit N4D series (docs → registry → UI → create → saved → collections → drafts → share → system → a11y → tests → architecture)
- [ ] Open PRs against the intended base

## Backend

- [ ] `ssh modula-vps`
- [ ] Verify saved-post list contract (or confirm MISSING)
- [ ] Verify collections contract (or keep local-only)
- [ ] Verify share-card messaging contract
- [ ] Replace provisional paths if different
- [ ] Flip `SavedBackendCapabilities.listSavedPosts` only when verified

## Xcode / device

- [ ] Xcode Debug build
- [ ] Release build without Metro
- [ ] Simulator: Command Center sheet, ⌘K if hardware keyboard
- [ ] Device: Command Center, Saved, Collections, Drafts, Share sheet
- [ ] Home Screen Quick Actions
- [ ] App Shortcuts / Intents
- [ ] Spotlight installed-module / settings hits
- [ ] Instruments (launch + Command Center typing)
- [ ] N1→N4 regression (ModuleHost still Hermes-gated correctly)

## Product checks

- [ ] No sixth root tab
- [ ] Search ≠ Command Center
- [ ] Create Story / Message / In-Mail capability-honest
- [ ] Local collections say “Stored on this iPhone”
- [ ] Draft bodies never logged
- [ ] Open Vault Notes only when installed → ModuleHost
