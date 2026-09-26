# NODUS-02A Repository Inventory

Date: 2026-09-24

## Repository gate

- Canonical repository: `/Users/msjoy/Developer/modula-native`
- Canonical branch: `main`
- Canonical HEAD: `ff29669b06ad76f570c5da396d045112478e0f58`
- `origin/main`: `ff29669b06ad76f570c5da396d045112478e0f58`
- Feature worktree: `/Users/msjoy/Developer/modula-native-nodus02a`
- Feature branch: `phase-nodus-02a-personal-intelligence`
- The canonical checkout had one pre-existing protected change at
  `.cursor/hooks/state/continual-learning.json`. It was not modified, discarded, or copied into
  the feature worktree.

## Accepted architecture to reuse

### Persistence and data protection

- `Core/Persistence/PrivateFileStore.swift` is the accepted private Application Support
  abstraction. It writes atomically with
  `completeFileProtectionUntilFirstUserAuthentication`, excludes its directory from backup, and
  currently serves drafts, collections, command history, share state, and Spotlight state.
- `Core/Intelligence/Nodus/NodusVerificationStore.swift` persists verification and governed
  learning state as protected JSON under `Application Support/Modula/Nodus`.
- No Core Data, SwiftData, SQLite, or accepted full-text index exists in the application today.
  NODUS-02A will therefore use bounded native protected JSON stores plus an in-memory lexical
  index. This avoids a new dependency and keeps migration explicit. The contracts do not prevent a
  later SQLite/FTS implementation.
- Nodus chat, knowledge, memory, and learning content must not use `UserDefaults`.

### Secure storage

- `Core/Persistence/KeychainStore.swift` is the accepted Keychain wrapper. It uses a service-scoped
  generic-password item and `AfterFirstUnlockThisDeviceOnly` accessibility.
- The developer search credential will use a dedicated Keychain namespace. It will not be stored in
  source, plist, xcconfig, prompts, chat state, exports, diagnostics, or logs.

### Routing and Developer navigation

- `Navigation/AppRoute.swift` owns typed routes. The current Developer Local Intelligence route is
  `Settings -> Developer -> Local Intelligence`; `nodus-chat` is a separate child route.
- `Features/Settings/SettingsCategoryViews.swift` contains the DEBUG-only Developer host.
- NODUS-02A should evolve that existing area into a Nodus workspace and Search settings. It must not
  create a new consumer destination or competing application shell.

### Nodus runtime and chat

- The accepted execution path is
  `NodusChatView -> NodusChatViewModel -> ModulaIntelligence -> IntelligenceRouter -> modula.nodus -> NodusIntelligenceProvider -> MLXNodusRuntime`.
- `NodusIntelligenceProvider` is local and fail-closed. It exposes provider ID `modula.nodus` and
  cannot fall through to a remote model for a `localOnly` request.
- `NodusPromptContract.normalize` already strips `<think>...</think>` output. Hidden reasoning is
  neither displayed nor persisted.
- The existing chat is a single ephemeral array. It forwards the last eight messages, has no
  persistent conversation identity, and supports clear/cancel, confidence/freshness details,
  verification queueing, and developer ratings.
- `Nodus R7 Experimental` remains `experimentalCandidate`, with `shippingAllowed == false`.

### Confidence, freshness, verification, and learning

- `NodusFreshnessClassifier` detects current-data prompts such as weather, news, and latest-version
  questions.
- `NodusConfidenceEngine` computes confidence outside generation.
- `NodusVerificationStore`, `NodusVerificationTrustStore`, and `NodusLearningPipeline` already
  implement signed verification ingestion, privacy/consent gates, human review, and dataset revision
  provenance.
- NODUS-02A should extend those contracts for direct developer corrections rather than create an
  automatic training path. No model weights, adapters, or training scripts are invoked by chat.

### Share/export

- Native sharing uses `ShareLink` and the typed `SharePayload` architecture.
- Developer Nodus evaluations already maintain a local JSONL export URL. Approved learning
  candidates should follow the same local-file/`ShareLink` pattern and must omit credentials and
  unrelated user Memory.

### Document import and PDF support

- `IntelligenceDiagnosticsView` already uses SwiftUI `fileImporter` with security-scoped resource
  access for artifact installation.
- No current user-document ingestion flow exists.
- PDFKit is an Apple system framework and can be imported directly for text extraction without a
  package. Scanned PDFs with no extractable page text will return a typed no-text result; OCR is out
  of scope.
- `UniformTypeIdentifiers` is already used elsewhere in the native target.

### Networking

- `GreenfieldClient` is the accepted authenticated Greenfield transport but is not appropriate for a
  developer-configured third-party Search provider.
- There is no accepted generic public-search abstraction. NODUS-02A will introduce
  `NodusSearchProvider`, normalized source/result contracts, and a narrowly scoped Brave developer
  provider using `URLSession`.
- Current official Brave documentation specifies
  `https://api.search.brave.com/res/v1/web/search`, query parameter `q`, and the
  `X-Subscription-Token` header. Provider-specific response types stay behind the abstraction.
- Search content is untrusted evidence and will be delimited from system instructions. Search never
  grants tools, file, Settings, or model authority.

## Implementation constraints derived from inventory

1. Reuse `PrivateFileStore`, `KeychainStore`, typed Settings routes, `ModulaIntelligence`, the Nodus
   provider, freshness/confidence engines, verification state, file import, and native sharing.
2. Keep conversation, Knowledge, Memory, and Learning as distinct protected stores/contracts.
3. Use bounded lexical retrieval initially; do not add an embedding model or persistence package.
4. Introduce a conversation engine that owns context budgeting and coordinates retrieval, optional
   Search, local generation, citations, diagnostics, and cancellation.
5. Block local generation for `current_data_required` when Search is off, returning the explicit
   product response instead of letting R7 fabricate live facts.
6. Preserve Debug automatic R7 bundling and Release exclusion behavior.
7. Preserve old developer evaluations and verification state. New decoders must tolerate existing
   records.
8. Simulator acceptance covers UI, persistence, retrieval, fixtures, and typed unsupported-device
   handling. Physical iPhone remains authoritative for MLX generation and performance.

