import Foundation

/// App-facing façade for native intelligence.
///
/// Hides provider registry internals, Apple APIs, model paths, and prompt engines.
protocol ModulaIntelligenceService: Sendable {
    func execute(_ request: IntelligenceRequest) async throws -> IntelligenceResponse
}

/// Default Modula intelligence coordinator.
///
/// AI proposes. Modula validates. Modula authorizes. Modula executes.
/// The intelligence subsystem never directly executes arbitrary Swift, shell, JS, SQL,
/// filesystem, HTTP, deep links, selectors, or URLs because a model emitted them.
actor ModulaIntelligence: ModulaIntelligenceService {
    let providers: IntelligenceProviderRegistry
    let tools: IntelligenceToolRegistry
    let diagnostics: IntelligenceDiagnostics
    private let router = IntelligenceRouter()
    private var remoteIntelligencePermitted: Bool

    init(
        providers: IntelligenceProviderRegistry? = nil,
        tools: IntelligenceToolRegistry = IntelligenceToolRegistry(),
        diagnostics: IntelligenceDiagnostics = IntelligenceDiagnostics(),
        remoteIntelligencePermitted: Bool = false,
        registerDeterministicLocalProvider: Bool = true
    ) {
        if let providers {
            self.providers = providers
        } else if registerDeterministicLocalProvider {
            // Registry actor init populates isolation synchronously — safe for AppEnvironment.
            self.providers = try! IntelligenceProviderRegistry(providers: [DeterministicLocalProvider()])
        } else {
            self.providers = try! IntelligenceProviderRegistry(providers: [])
        }
        self.tools = tools
        self.diagnostics = diagnostics
        self.remoteIntelligencePermitted = remoteIntelligencePermitted
    }

    func setRemoteIntelligencePermitted(_ permitted: Bool) {
        remoteIntelligencePermitted = permitted
    }

    func isRemoteIntelligencePermitted() -> Bool {
        remoteIntelligencePermitted
    }

    func execute(_ request: IntelligenceRequest) async throws -> IntelligenceResponse {
        try Task.checkCancellation()

        let allProviders = await providers.allProviders()
        var availabilities: [String: IntelligenceAvailability] = [:]
        for provider in allProviders where provider.capabilities.contains(request.capability) {
            availabilities[provider.id] = await provider.availability()
        }

        let decision = router.select(
            request: request,
            providers: allProviders,
            availabilities: availabilities,
            remoteIntelligencePermitted: remoteIntelligencePermitted
        )

        switch decision {
        case .failed(let error):
            diagnostics.record(
                IntelligenceDiagnosticEvent(
                    requestID: request.id,
                    capability: request.capability,
                    providerID: nil,
                    executionKind: nil,
                    duration: nil,
                    status: error == .requestCancelled ? .cancelled : .failure,
                    errorCode: error.code
                )
            )
            throw error

        case .selected(let providerID):
            guard let provider = await providers.provider(id: providerID) else {
                let error = IntelligenceError.providerNotFound(providerID: providerID)
                diagnostics.record(
                    IntelligenceDiagnosticEvent(
                        requestID: request.id,
                        capability: request.capability,
                        providerID: providerID,
                        executionKind: nil,
                        duration: nil,
                        status: .failure,
                        errorCode: error.code
                    )
                )
                throw error
            }

            // Defense in depth (P1): never execute a remote provider for localOnly.
            if request.privacy == .localOnly, provider.executionKind == .remote {
                let error = IntelligenceError.remoteExecutionForbidden
                diagnostics.record(
                    IntelligenceDiagnosticEvent(
                        requestID: request.id,
                        capability: request.capability,
                        providerID: provider.id,
                        executionKind: provider.executionKind,
                        duration: nil,
                        status: .failure,
                        errorCode: error.code
                    )
                )
                throw error
            }

            diagnostics.record(
                IntelligenceDiagnosticEvent(
                    requestID: request.id,
                    capability: request.capability,
                    providerID: provider.id,
                    executionKind: provider.executionKind,
                    duration: nil,
                    status: .routed,
                    errorCode: nil
                )
            )

            let context = IntelligenceExecutionContext(
                source: request.source,
                authorizedToolIDs: request.allowedToolIDs,
                grantedPermissions: [],
                remoteIntelligencePermitted: remoteIntelligencePermitted,
                diagnostics: IntelligenceDiagnosticsBox(diagnostics: diagnostics)
            )

            do {
                try Task.checkCancellation()
                let response = try await provider.execute(request, context: context)
                diagnostics.record(
                    IntelligenceDiagnosticEvent(
                        requestID: request.id,
                        capability: request.capability,
                        providerID: response.providerID,
                        executionKind: response.executionKind,
                        duration: response.duration,
                        status: .success,
                        errorCode: nil
                    )
                )
                return response
            } catch is CancellationError {
                diagnostics.record(
                    IntelligenceDiagnosticEvent(
                        requestID: request.id,
                        capability: request.capability,
                        providerID: provider.id,
                        executionKind: provider.executionKind,
                        duration: nil,
                        status: .cancelled,
                        errorCode: IntelligenceError.requestCancelled.code
                    )
                )
                throw IntelligenceError.requestCancelled
            } catch let error as IntelligenceError {
                diagnostics.record(
                    IntelligenceDiagnosticEvent(
                        requestID: request.id,
                        capability: request.capability,
                        providerID: provider.id,
                        executionKind: provider.executionKind,
                        duration: nil,
                        status: error == .requestCancelled ? .cancelled : .failure,
                        errorCode: error.code
                    )
                )
                throw error
            } catch {
                let wrapped = IntelligenceError.providerFailure(
                    providerID: provider.id,
                    detail: String(describing: type(of: error))
                )
                diagnostics.record(
                    IntelligenceDiagnosticEvent(
                        requestID: request.id,
                        capability: request.capability,
                        providerID: provider.id,
                        executionKind: provider.executionKind,
                        duration: nil,
                        status: .failure,
                        errorCode: wrapped.code
                    )
                )
                throw wrapped
            }
        }
    }

    func privacyProbe() async -> (pass: Bool, detail: String) {
        let locals = await providers.providers(executionKind: .local)
        for provider in locals {
            if await provider.availability().isEligibleForRouting {
                return (true, "Available local provider: \(provider.id)")
            }
        }
        return (false, "No available local provider")
    }

    func diagnosticsSnapshot() async -> IntelligenceServiceSnapshot {
        let all = await providers.allProviders()
        var localCount = 0
        var remoteCount = 0
        for provider in all {
            switch provider.executionKind {
            case .local: localCount += 1
            case .remote: remoteCount += 1
            }
        }
        let probe = await privacyProbe()
        return IntelligenceServiceSnapshot(
            coreReady: true,
            providerCount: all.count,
            localProviderCount: localCount,
            remoteProviderCount: remoteCount,
            realModelConnected: false,
            privacyEnforcementPass: probe.pass,
            networkRequired: false,
            lastEvent: await diagnostics.snapshot()
        )
    }
}

struct IntelligenceServiceSnapshot: Sendable, Equatable {
    let coreReady: Bool
    let providerCount: Int
    let localProviderCount: Int
    let remoteProviderCount: Int
    let realModelConnected: Bool
    let privacyEnforcementPass: Bool
    let networkRequired: Bool
    let lastEvent: IntelligenceDiagnosticEvent?
}
