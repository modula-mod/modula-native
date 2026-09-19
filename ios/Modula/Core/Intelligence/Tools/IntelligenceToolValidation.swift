import Foundation

enum IntelligenceToolValidation {
    static func validate(
        arguments: IntelligenceValue,
        against schema: IntelligenceToolSchema,
        path: String = "$"
    ) -> String? {
        switch schema {
        case .any:
            return nil
        case .optional(let inner):
            if arguments.isNull { return nil }
            return validate(arguments: arguments, against: inner, path: path)
        case .null:
            return arguments.isNull ? nil : "\(path): expected null"
        case .boolean:
            return arguments.boolValue != nil ? nil : "\(path): expected boolean"
        case .integer:
            return arguments.integerValue != nil ? nil : "\(path): expected integer"
        case .double:
            if arguments.doubleValue != nil || arguments.integerValue != nil { return nil }
            return "\(path): expected number"
        case .string:
            return arguments.stringValue != nil ? nil : "\(path): expected string"
        case .array(let element):
            guard let items = arguments.arrayValue else {
                return "\(path): expected array"
            }
            for (index, item) in items.enumerated() {
                if let error = validate(arguments: item, against: element, path: "\(path)[\(index)]") {
                    return error
                }
            }
            return nil
        case .object(let properties, let required, let additionalProperties):
            guard let object = arguments.objectValue else {
                return "\(path): expected object"
            }
            for key in required where object[key] == nil || object[key]?.isNull == true {
                return "\(path): missing required property '\(key)'"
            }
            if !additionalProperties {
                for key in object.keys where properties[key] == nil {
                    return "\(path): unexpected property '\(key)'"
                }
            }
            for (key, propertySchema) in properties {
                guard let value = object[key] else { continue }
                if let error = validate(arguments: value, against: propertySchema, path: "\(path).\(key)") {
                    return error
                }
            }
            return nil
        }
    }
}
