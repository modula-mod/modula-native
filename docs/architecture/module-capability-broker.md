# Module capability broker

Native owns device capabilities. Modules request; the user reviews; the host grants per exact release.

Supported (subject to OS permission and review): `mediaPicker`, `share`, `biometrics`, `secureStorage`, `localIntelligence`, `backgroundTask`, plus Product UI `ui.*@1` renderers.

Every request checks installation, release trust, enabled state, exact-release permission review, grant, host capability version, and OS permission.

`localOnly` intelligence never leaves the device. If no local provider can run, the broker returns `CAPABILITY_UNAVAILABLE` and does not invent output.

`settings:register` does not imply `settings:read` or `settings:write`. Vault 2 permissions are not auto-granted because Vault 1.8 previously worked.

## App Store

A host broker is not automatic Guideline 4.7.2 compliance. Downloaded software must not expose new native APIs without Apple permission. This implementation keeps native ownership inside the signed app and treats public distribution approval as a separate gate from internal technical acceptance.
