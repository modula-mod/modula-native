# Host bridge 0.1.0

Modules submit versioned requests with a native-issued surface/session identifier. Swift validates session validity, module manifest grants, action name, typed parameters and permitted destination before dispatch. A module never supplies a URL, authorization header, account selector or arbitrary native method name. Responses are JSON values or structured safe error codes. A disposed session cannot continue issuing actions; asynchronous responses must be discarded after revocation.

Contract families: navigation, presentation, appearance, lifecycle, permissions, haptics, sharing, clipboard, files, module settings, authentication context, backend access and diagnostics. N1 implements only the operations needed for diagnostic proof and real records. Unsupported families return an explicit unsupported/denied result; a contract declaration does not imply a native implementation.

Semantic appearance snapshot: colorScheme, oled, accent, surfacePreference, reduceMotion, textScale. Lifecycle includes mounted, active, inactive, backgrounded, foregrounded, unmounted, memoryPressure and appearanceChanged. Events include a surface/session identity to prevent cross-surface delivery.

Host navigation resolves profile/post/product/module/settings/home through one coordinator. Presentation requests are governed by native UI. Record requests are limited to the current module's declared collection, operation and session account. The backend still performs its own installation/permission/revision checks. No false assertion of third-party isolation: bundled modules share JS memory.
