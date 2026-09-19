# N3A acceptance notes

Branch: `cursor/phase-n3a-ios-activity-auth-54cd`
Baseline: `main` @ `af1956f` (N2 `75e4b3a` tagged `native-n2`)
Final HEAD: `97f04af`

## Implemented in-repo

- Auth error mapping (`INVALID_CREDENTIALS` → friendly copy)
- Sign-in / Forgot Password / Create Account surfaces; signed-in Account settings
- Auth return-route via `NavigationCoordinator`
- `ShellChromePolicy` hides tab/rail/accessory on `/auth/*` and `/settings/account/*`
- `ShellAccessoryHost` with Activity Summary / Filter / Mark All Read
- Native Activity timeline, modes, repository over Greenfield notifications/connections
- Docs: `docs/migration/activity-backend.md`
- Unit tests: `ActivityAuthTests.swift`; UI test scaffold `N3AActivityAuthUITests`
- Fixture probe: `scripts/n1/activity-fixture.mjs`
- Design/boundary/typecheck green on Node 22

## OPEN (Mac + VPS required)

- `ssh modula-vps` Greenfield source confirmation of notification/request JSON + accept/decline
- N1 fixture activity seeding with real social flows
- `xcodebuild` unit/UI/Release acceptance, Simulator demo, physical device
- Live Keychain login lifecycle against N1 fixture

## Verdict

PARTIAL until Mac/VPS gates close.
