# iOS module distribution

N1 ships executable module code inside the signed application. No arbitrary npm packages, native libraries, executable frameworks or remote JS bundles are installed at runtime.

Future Marketplace distribution requires a separate design/review gate covering software index and metadata, universal links, privacy consent, age controls, purchases, native API exposure and App Review strategy. Technical runtime capability is not evidence that every distribution model is permitted. Recheck current Apple rules at that future decision; this document is not approval for remote execution.

Backend catalogue/install state can be remote while executable module code remains bundled. Their versions and compatibility must be reconciled explicitly. An enabled server product does not imply compatible code is available in the native binary. Unknown or unavailable modules get a native unavailable state.
