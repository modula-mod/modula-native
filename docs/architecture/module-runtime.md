# Module runtime

One lazily initialized `RCTReactNativeFactory` belongs to ModuleRuntimeController. Its root-view factory creates disposable module surfaces. SwiftUI ModuleHost → UIViewControllerRepresentable → ReactNativeViewController → factory UIView → ModulaModuleRoot → ModuleRegistry. No other feature imports React. Native app launch and navigation require no JavaScript. The initial native-only Xcode build is preserved in Git before RN integration.

State vocabulary: idle, preparing, startingRuntime, loadingModule, ready, suspended, failed, unavailable. Mount identity is unique per surface; remount invalidates the old session. Closing releases the surface and its host capability, not the shared runtime. A runtime may be reset only by explicit recovery policy, not for every module.

Diagnostic module must precede Vault Notes. Initial props and subsequent semantic environment/lifecycle updates are scoped to a surface. Ready is acknowledged by JS after rendering; native surface creation alone is not readiness. Module exceptions are caught by a React error boundary; native close/retry/navigation controls remain outside RN. A fatal native bug/OOM in any in-process framework cannot be sandboxed by a JS error boundary. This is a practical containment boundary for bundled trusted code, not process isolation.

Release bundles JS and assets at build time. Missing bundle reports unavailable without preventing native launch. Debug may connect to Metro. No remote executable code distribution exists. Codegen TurboModule is the versioned native request/event transport; old RCTBridge application bootstrap is not used. Any inherited sourceURL method signature required by RN factory protocol does not establish legacy bridge ownership.

Module registry accepts manifests with exact bundled module version, runtime, entry, permissions and minimum host/bridge versions. Backend installation/release/permission truth remains separate. Module-local navigation may be custom RN; application routes require host validation. @modula/product-ui remains an optional future adapter, not a universal UI restriction.
