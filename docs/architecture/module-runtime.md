# Module runtime

One lazily initialized `RCTReactNativeFactory` belongs to ModuleRuntimeController. Its root-view factory creates disposable module surfaces. SwiftUI ModuleHost → UIViewControllerRepresentable → ReactNativeViewController → factory UIView → ModulaModuleRoot → ModuleRegistry. No other feature imports React. Native app launch and navigation require no JavaScript. The initial native-only Xcode build is preserved in Git before RN integration.

State vocabulary: idle, preparing, startingRuntime, loadingModule, ready, suspended, failed, unavailable. Mount identity is unique per surface; remount invalidates the old session. Closing releases the surface and its host capability, not the shared runtime. A runtime may be reset only by explicit recovery policy, not for every module.

Diagnostic module must precede Vault Notes. Initial props and subsequent semantic environment/lifecycle updates are scoped to a surface. Ready is acknowledged by JS after rendering; native surface creation alone is not readiness. Module exceptions are caught by a React error boundary; native close/retry/navigation controls remain outside RN. A fatal native bug/OOM in any in-process framework cannot be sandboxed by a JS error boundary. This is a practical containment boundary for bundled trusted code, not process isolation.

Release bundles JS and assets at build time. The N1 Debug control build is also deterministic and bundled; Metro is optional development tooling and is not required by the current delegate. Missing bundle reports unavailable without preventing native launch. No remote executable code distribution exists. Codegen TurboModule is the versioned native request/event transport; old RCTBridge application bootstrap is not used. Any inherited sourceURL method signature required by RN factory protocol does not establish legacy bridge ownership.

Module registry accepts manifests with exact bundled module version, runtime, entry, permissions and minimum host/bridge versions. Backend installation/release/permission truth remains separate. Module-local navigation may be custom RN; application routes require host validation. @modula/product-ui remains an optional future adapter, not a universal UI restriction.

N1 freezes one runtime factory for the application lifecycle and disposable surfaces for each open. Ten consecutive real Vault opens retained initialization count one. The measured second surface mount was 58.2 ms; closing invalidates its ModuleSession and listener delivery while retaining the runtime. Native diagnostics records factory setup, first ready/data times, surface durations, memory warnings, session state, last rejected action, and semantic environment without displaying credentials.
# N2 design environment

The N1 runtime lifecycle and security boundary remain unchanged. N2 extends the environment additively with `designContractVersion: 1`, semantic theme/dark style, accent, font family, text scale, density, motion, haptics, contrast/transparency, icon style, interface shape, and module branding. Old modules may ignore every new optional field.

`initialPath` is optional module-local state. The host validates the global module route and passes the remaining relative path to the module; Vault interprets its own `/new` and `/note/:noteId[/edit]` paths. No environment field contains credentials, authentication headers, or account preferences unrelated to module presentation. Modules cannot mutate the shell's Appearance settings.
