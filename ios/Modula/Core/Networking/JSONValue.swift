import Foundation

indirect enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(key: String) -> JSONValue? { if case .object(let value) = self { value[key] } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var number: Double? { if case .number(let v) = self { v } else { nil } }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var int: Int? { number.map { Int($0) } }
    var foundation: Any {
        switch self {
        case .object(let v): v.mapValues(\.foundation)
        case .array(let v): v.map(\.foundation)
        case .string(let v): v
        case .number(let v): v
        case .bool(let v): v
        case .null: NSNull()
        }
    }
}


/// Last first page of a feed/inbox on disk, per account, so a cold launch can paint
/// it immediately and revalidate (stale-while-revalidate). Caches directory; cleared
/// on sign-out. Reads and writes run off the main thread.
enum ModulaWarmCache {
    nonisolated static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("modula-warm", isDirectory: true)
    }

    nonisolated private static func file(_ name: String, account: String) -> URL {
        let safeAccount = String(account.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.prefix(80))
        return root.appendingPathComponent(safeAccount, isDirectory: true).appendingPathComponent(name + ".json")
    }

    nonisolated static func store(_ value: JSONValue, name: String, account: String?) {
        guard let account, !account.isEmpty else { return }
        let url = file(name, account: account)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    nonisolated static func load(name: String, account: String?) async -> JSONValue? {
        guard let account, !account.isEmpty else { return nil }
        let url = file(name, account: account)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: data)
        }.value
    }

    nonisolated static func clearAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
