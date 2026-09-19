import Foundation

/// Result of router selection. The router owns selection, not inference.
enum RoutingDecision: Sendable, Equatable {
    case selected(providerID: String)
    case failed(IntelligenceError)
}

/// Selects an eligible provider using deterministic privacy and capability rules.
///
/// Ordering: among eligible candidates, the first provider in **registry registration order** wins.
/// Tests must not depend on dictionary iteration order.
struct IntelligenceRouter: Sendable {
    /// Selects a provider ID for `request` without executing it.
    func select(
        request: IntelligenceRequest,
        providers: [any IntelligenceProvider],
        availabilities: [String: IntelligenceAvailability],
        remoteIntelligencePermitted: Bool
    ) -> RoutingDecision {
        let supporting = providers.filter { $0.capabilities.contains(request.capability) }
        guard !supporting.isEmpty else {
            return .failed(.capabilityUnsupported)
        }

        let localSupporting = supporting.filter { $0.executionKind == .local }
        let remoteSupporting = supporting.filter { $0.executionKind == .remote }

        let availableLocal = localSupporting.filter {
            availabilities[$0.id]?.isEligibleForRouting == true
        }
        let availableRemote = remoteSupporting.filter {
            availabilities[$0.id]?.isEligibleForRouting == true
        }

        switch request.privacy {
        case .localOnly:
            if let provider = availableLocal.first {
                return .selected(providerID: provider.id)
            }
            if !localSupporting.isEmpty {
                return .failed(.localProviderUnavailable)
            }
            return .failed(.noEligibleProvider)

        case .preferLocal:
            if let provider = availableLocal.first {
                return .selected(providerID: provider.id)
            }
            if remoteIntelligencePermitted, let provider = availableRemote.first {
                return .selected(providerID: provider.id)
            }
            if !remoteSupporting.isEmpty, !remoteIntelligencePermitted {
                return .failed(.remoteExecutionForbidden)
            }
            return .failed(.noEligibleProvider)

        case .allowRemote:
            // Still prefer local when available (stable, predictable Mission 02 policy).
            if let provider = availableLocal.first {
                return .selected(providerID: provider.id)
            }
            if let provider = availableRemote.first {
                return .selected(providerID: provider.id)
            }
            return .failed(.noEligibleProvider)
        }
    }
}
