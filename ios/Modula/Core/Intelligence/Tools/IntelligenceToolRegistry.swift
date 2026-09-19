import Foundation

/// Registry for tool descriptors. Validation only — no tool execution in Mission 02.
actor IntelligenceToolRegistry {
    private var toolsByID: [String: IntelligenceTool] = [:]
    private var registrationOrder: [String] = []

    func register(_ tool: IntelligenceTool) throws {
        guard Self.isValidToolID(tool.id) else {
            throw IntelligenceError.invalidRequest(detail: "Invalid tool id")
        }
        guard toolsByID[tool.id] == nil else {
            throw IntelligenceError.duplicateTool(toolID: tool.id)
        }
        toolsByID[tool.id] = tool
        registrationOrder.append(tool.id)
    }

    @discardableResult
    func unregister(id: String) -> Bool {
        guard toolsByID.removeValue(forKey: id) != nil else { return false }
        registrationOrder.removeAll { $0 == id }
        return true
    }

    func lookup(id: String) -> IntelligenceTool? {
        toolsByID[id]
    }

    func allTools() -> [IntelligenceTool] {
        registrationOrder.compactMap { toolsByID[$0] }
    }

    func allowedTools(ids: Set<String>) -> [IntelligenceTool] {
        allTools().filter { ids.contains($0.id) }
    }

    /// Validate a proposed tool call without executing it.
    func validateCall(
        _ call: IntelligenceToolCall,
        authorizedToolIDs: Set<String>,
        grantedPermissions: Set<String>
    ) throws -> IntelligenceValidatedToolCall {
        guard let tool = toolsByID[call.toolID] else {
            throw IntelligenceError.toolNotFound(toolID: call.toolID)
        }
        guard authorizedToolIDs.contains(call.toolID) else {
            throw IntelligenceError.toolNotAuthorizedForRequest(toolID: call.toolID)
        }
        if let permission = tool.requiredPermission, !grantedPermissions.contains(permission) {
            throw IntelligenceError.toolPermissionDenied(toolID: call.toolID, permission: permission)
        }
        if let detail = IntelligenceToolValidation.validate(arguments: call.arguments, against: tool.inputSchema) {
            throw IntelligenceError.toolArgumentsInvalid(toolID: call.toolID, detail: detail)
        }
        return IntelligenceValidatedToolCall(toolID: call.toolID, arguments: call.arguments)
    }

    private static func isValidToolID(_ id: String) -> Bool {
        let pattern = #"^[a-z][a-z0-9]*(?:[.\-][a-z0-9]+)*$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }
}
