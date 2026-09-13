# Host bridge 0.1.0

Modules submit versioned requests with a native-issued surface/session identifier. Swift validates session validity, module manifest grants, action name, typed parameters and permitted destination before dispatch. A module never supplies a URL, authorization header, account selector or arbitrary native method name. Responses are JSON values or structured safe error codes. A disposed session cannot continue issuing actions; asynchronous responses must be discarded after revocation.

Contract families: navigation, presentation, appearance, lifecycle, permissions, haptics, sharing, clipboard, files, module settings, authentication context, backend access and diagnostics. N1 implements only the operations needed for diagnostic proof and real records. Unsupported families return an explicit unsupported/denied result; a contract declaration does not imply a native implementation.

Semantic appearance snapshot: colorScheme, oled, accent, surfacePreference, reduceMotion, textScale. Lifecycle includes mounted, active, inactive, backgrounded, foregrounded, unmounted, memoryPressure and appearanceChanged. Events include a surface/session identity to prevent cross-surface delivery.

Host navigation resolves profile/post/product/module/settings/home through one coordinator. Presentation requests are governed by native UI. Record requests are limited to the current module's declared collection, operation and session account. The backend still performs its own installation/permission/revision checks. No false assertion of third-party isolation: bundled modules share JS memory.

N1 Vault implements a closed record vocabulary: `backend.records.list`, `get`, `create`, `update`, and `delete`. JavaScript supplies the declared `note` collection and operation-specific values only. Swift constructs the fixed Greenfield path, HTTP method, revision body, and authenticated request. Exact-key validation rejects URL/header injection, foreign collections, Boolean/fractional/out-of-range revisions, unknown operations, malformed payloads, expired sessions, unmounted sessions, and module-identity mismatches.

The custom Vault surface owns only `/`, `/new`, and note/editor state within its React tree. Product Hub enters `AppRoute.module("digital.modula.vault-notes")`; profile requests cross the bridge and become a native `AppRoute.profile`. Native Back, Close, Retry, failure presentation, and global navigation remain outside the React surface.
