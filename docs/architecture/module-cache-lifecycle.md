# Module cache lifecycle

Slots: `ACTIVE`, `PREVIOUS_GOOD`, `STAGED`.

Layout: `Application Support/Modula/ModuleCache/{accountId}/{moduleId}/{SLOT}/`.

No bearer token is stored with artifacts. Cache directories are per-account.

## Update

`ACTIVE 1.0` → download 1.1 → `STAGED 1.1` → verify → permission/compatibility gates → atomic activation → `ACTIVE 1.1` + `PREVIOUS_GOOD 1.0`.

A digest mismatch never writes `STAGED`. An activation-health failure restores `PREVIOUS_GOOD` without changing permission grants.

## Offline

An installed `ACTIVE` frontend opens without GreenField. Record reads use the last local cache; allowed edits queue with stable mutation IDs. Revocation discovery is delayed while offline; sensitive operations fail closed when current authorization is required.

Last-known-trust policy: a previously verified `ACTIVE` release may render its UI offline. New capability use and remote functions do not.
