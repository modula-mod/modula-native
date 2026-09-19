import Foundation

enum IntelligenceToolAccess: String, Sendable, Equatable, Hashable, Codable {
    case read
    case write
}

/// Minimal schema representation for validating structured tool arguments.
/// No third-party JSON Schema dependency.
indirect enum IntelligenceToolSchema: Sendable, Equatable {
    case any
    case null
    case boolean
    case integer
    case double
    case string
    case array(of: IntelligenceToolSchema)
    case object(properties: [String: IntelligenceToolSchema], required: Set<String>, additionalProperties: Bool)
    case optional(IntelligenceToolSchema)
}

/// Tool descriptor. Models propose; Modula owns execution later.
///
/// Security invariant: AI proposes. Modula validates. Modula authorizes. Modula executes.
/// Tools never carry executable Swift closures from model output.
struct IntelligenceTool: Sendable, Equatable, Identifiable {
    let id: String
    let description: String
    let access: IntelligenceToolAccess
    let requiredPermission: String?
    let inputSchema: IntelligenceToolSchema

    init(
        id: String,
        description: String,
        access: IntelligenceToolAccess,
        requiredPermission: String? = nil,
        inputSchema: IntelligenceToolSchema
    ) {
        self.id = id
        self.description = description
        self.access = access
        self.requiredPermission = requiredPermission
        self.inputSchema = inputSchema
    }
}

struct IntelligenceToolCall: Sendable, Equatable, Identifiable {
    let id: String
    let toolID: String
    let arguments: IntelligenceValue

    init(id: String = UUID().uuidString, toolID: String, arguments: IntelligenceValue) {
        self.id = id
        self.toolID = toolID
        self.arguments = arguments
    }
}

struct IntelligenceValidatedToolCall: Sendable, Equatable {
    let toolID: String
    let arguments: IntelligenceValue
}
