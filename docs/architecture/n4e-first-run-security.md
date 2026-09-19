# N4E — First run, security, and product surfaces

## Boot

`AppGateHost` sits above `NavigationCoordinator`, Root Shell, and `ModuleHost`.

```text
APP LAUNCH → BOOT
  no session + onboarding unseen → /auth/welcome
  no session + onboarding seen → /auth/login
  session + first-run incomplete → FirstRunSetup
  session + App Lock required → Unlock Modula
  otherwise → /home/following
```

The shell is not mounted until `AppLaunchState.ready`. Deep links are held on `AppGate` and resume after auth, first-run, and unlock.

## Distinctions

- Onboarding explains Modula (device-local seen flag).
- Auth establishes a Greenfield session (Keychain).
- First-run configures the newly authenticated identity (device-local completion keyed by account ID until a Greenfield contract exists).
- App Lock protects the already authenticated local app. It never replaces account login.

## Sign-out retention

| State | On sign-out |
|---|---|
| Appearance | Retained |
| Onboarding-seen | Retained |
| Local drafts | Retained (warn; user can discard) |
| Local collections | Retained |
| App Lock PIN / settings | Reset |
| Auth tokens / authenticated caches | Cleared |

## Security

- Passcode: 6 digits, PBKDF2-HMAC-SHA256 verifier, Keychain `WhenUnlockedThisDeviceOnly`
- Attempts: escalating delay, never wipe
- Biometrics: `LocalAuthentication` abstraction; failure falls back to passcode
- Privacy cover on inactive/background when App Lock is enabled or locked
- Logging never includes passcode, verifier, tokens, biometric templates, message/draft bodies
