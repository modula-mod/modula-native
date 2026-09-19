import Foundation

/// Provider-neutral structured payload. Public intelligence contracts must not use `Any`.
enum IntelligenceValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case array([IntelligenceValue])
    case object([String: IntelligenceValue])

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var objectValue: [String: IntelligenceValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    var arrayValue: [IntelligenceValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var integerValue: Int? {
        if case let .integer(value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case let .double(value) = self { return value }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum ValueType: String, Codable {
        case null, bool, integer, double, string, array, object
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let type = try? container.decode(ValueType.self, forKey: .type) {
            switch type {
            case .null:
                self = .null
            case .bool:
                self = .bool(try container.decode(Bool.self, forKey: .value))
            case .integer:
                self = .integer(try container.decode(Int.self, forKey: .value))
            case .double:
                self = .double(try container.decode(Double.self, forKey: .value))
            case .string:
                self = .string(try container.decode(String.self, forKey: .value))
            case .array:
                self = .array(try container.decode([IntelligenceValue].self, forKey: .value))
            case .object:
                self = .object(try container.decode([String: IntelligenceValue].self, forKey: .value))
            }
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([IntelligenceValue].self) {
            self = .array(value)
        } else if let value = try? single.decode([String: IntelligenceValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unsupported IntelligenceValue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(ValueType.null, forKey: .type)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .array(let value):
            try container.encode(ValueType.array, forKey: .type)
            try container.encode(value, forKey: .value)
        case .object(let value):
            try container.encode(ValueType.object, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
