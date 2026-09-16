# N4E Mac closeout

Future home-machine mission. Remote source is PARTIAL until these gates pass.

## Recover / split phases (never reset)

1. Preserve the dirty worktree. Do not `git reset`, `git clean`, or checkout over files.
2. If Shell works, capture `git status`, `git diff --stat`, and stash only if needed for a throwaway experiment — never drop N4B/N4C/N4D/N4E.
3. Split commits in this order:
   - N4B post-system
   - N4C communications
   - N4D command platform
   - N4E first-run / security / surfaces  
     Recommended branch: `cursor/phase-n4e-ios-first-run-security-surfaces`
4. Record exact shared hunks from `docs/environment/n4e-remote-staging.md`.

## Backend

- `ssh modula-vps`
- Verify auth: `/v1/sessions`, `/v1/accounts/register`, verify-email, forgot/reset, `/v1/accounts/me/sessions`
- Verify notification preferences
- Verify reaction types / breakdown / list
- Verify profile media (cover, focal point, headline)
- Verify module metadata (coverImage, screenshots, release notes, install)

## Native execution

- `xcodebuild` Debug PASS
- `xcodebuild` Release PASS
- Simulator: onboarding, login, register, first-run, settings walkthrough, profile, module detail
- Physical iPhone: Face ID, App Passcode, background lock, deep-link lock
- Instruments
- Metro-free Release
- Full N1→N4 regression

## Product walkthrough

- Open Modula → no Home flash while signed out
- Onboarding Skip → authentication, never Home
- First-run then `/home/following`
- App Lock cold launch and app-switcher cover
- Settings every route: FUNCTIONAL or CAPABILITY-UNAVAILABLE
- Profile full-bleed cover / avatar pocket / compact header
- Module Detail full-bleed hero / Install-Open truth / publisher
- Reaction picker: Like tap; long-press vocabulary gated until HTTP exists
