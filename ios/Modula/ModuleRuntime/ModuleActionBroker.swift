import Foundation

/// Generic inter-module action broker. Source modules never write another module's records.
enum ModuleActionBroker {
    struct Request: Equatable, Sendable {
        var requestId: String
        var idempotencyKey: String
        var sourceModuleId: String
        var sourceReleaseId: String
        var targetModuleId: String
        var targetActionId: String
        var payload: [String: String]
    }

    struct Result: Equatable, Sendable {
        var requestId: String
        var status: String
        var targetRecordId: String?
        var mutationId: String?
        var error: String?
    }

    enum BrokerError: Error, Equatable, LocalizedError {
        case sourceNotInstalled
        case targetNotInstalled
        case permissionDenied
        case unknownTargetAction
        case invalidPayload
        case targetOwnedMutationRequired

        var errorDescription: String? {
            switch self {
            case .sourceNotInstalled: "The source module is not installed for this account."
            case .targetNotInstalled: "The target module is not installed for this account."
            case .permissionDenied: "This inter-module action is not granted for the current releases."
            case .unknownTargetAction: "The target module does not declare that action."
            case .invalidPayload: "The action payload does not match the target input schema."
            case .targetOwnedMutationRequired: "Cross-module writes must be applied by the target module."
            }
        }
    }

    /// In-memory idempotency. A retry with the same key returns the first result.
    @MainActor
    final class Session {
        private var results: [String: Result] = [:]

        func invoke(
            _ request: Request,
            sourceInstalled: Bool,
            targetInstalled: Bool,
            granted: [String],
            targetActions: [JSONValue],
            apply: (Request) throws -> Result
        ) throws -> Result {
            if let prior = results[request.idempotencyKey] { return prior }
            guard sourceInstalled else { throw BrokerError.sourceNotInstalled }
            guard targetInstalled else { throw BrokerError.targetNotInstalled }
            let required = "actions:invoke:\(request.targetModuleId):\(request.targetActionId)"
            guard granted.contains(required) || granted.contains("actions:invoke") else {
                throw BrokerError.permissionDenied
            }
            guard targetActions.contains(where: { $0["id"]?.string == request.targetActionId }) else {
                throw BrokerError.unknownTargetAction
            }
            if request.payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                throw BrokerError.invalidPayload
            }
            let result = try apply(request)
            results[request.idempotencyKey] = result
            return result
        }
    }
}
