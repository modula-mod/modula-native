import Foundation

/// Concurrency-safe provider registry. Does not instantiate models.
actor IntelligenceProviderRegistry {
    private var providersByID: [String: any IntelligenceProvider] = [:]
    private var registrationOrder: [String] = []

    init(providers: [any IntelligenceProvider] = []) throws {
        for provider in providers {
            let id = provider.id
            guard Self.isValidProviderID(id) else {
                throw IntelligenceError.invalidRequest(detail: "Invalid provider id")
            }
            guard providersByID[id] == nil else {
                throw IntelligenceError.duplicateProvider(providerID: id)
            }
            providersByID[id] = provider
            registrationOrder.append(id)
        }
    }

    func register(_ provider: any IntelligenceProvider) throws {
        let id = provider.id
        guard Self.isValidProviderID(id) else {
            throw IntelligenceError.invalidRequest(detail: "Invalid provider id")
        }
        guard providersByID[id] == nil else {
            throw IntelligenceError.duplicateProvider(providerID: id)
        }
        providersByID[id] = provider
        registrationOrder.append(id)
    }

    @discardableResult
    func unregister(id: String) -> Bool {
        guard providersByID.removeValue(forKey: id) != nil else { return false }
        registrationOrder.removeAll { $0 == id }
        return true
    }

    func provider(id: String) -> (any IntelligenceProvider)? {
        providersByID[id]
    }

    /// Providers in stable registration order.
    func allProviders() -> [any IntelligenceProvider] {
        registrationOrder.compactMap { providersByID[$0] }
    }

    func providers(capableOf capability: IntelligenceCapability) -> [any IntelligenceProvider] {
        allProviders().filter { $0.capabilities.contains(capability) }
    }

    func providers(executionKind: IntelligenceExecutionKind) -> [any IntelligenceProvider] {
        allProviders().filter { $0.executionKind == executionKind }
    }

    private static func isValidProviderID(_ id: String) -> Bool {
        let pattern = #"^[a-z][a-z0-9]*(?:[.\-][a-z0-9]+)*$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }
}
