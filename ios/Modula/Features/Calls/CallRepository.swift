import Foundation

/// REST side of 1:1 calls. Every lifecycle command carries a fresh `Idempotency-Key`, so a retry
/// after a dropped response replays instead of acting twice.
actor CallRepository {
    private let client: GreenfieldClient

    init(client: GreenfieldClient) {
        self.client = client
    }

    enum Paths {
        static func start(conversationID: String) -> String { "/v1/conversations/\(escape(conversationID))/calls" }
        static func call(_ id: CallID) -> String { "/v1/calls/\(id.lowercased())" }
        static func command(_ command: CallCommand, id: CallID) -> String { "/v1/calls/\(id.lowercased())/\(command.rawValue)" }
        static func ticket(_ id: CallID) -> String { "/v1/calls/\(id.lowercased())/signalling-ticket" }
        static func mediaCredentials(_ id: CallID) -> String { "/v1/calls/\(id.lowercased())/media-credentials" }
        static let voipDevices = "/v1/push/voip-devices"
        static func voipDevice(_ registrationID: String) -> String { "/v1/push/voip-devices/\(escape(registrationID))" }
        static let capabilities = "/v1/messaging/capabilities"

        static func history(conversationID: String?, cursor: String?, limit: Int = 30) -> String {
            var items = [URLQueryItem(name: "limit", value: String(limit))]
            if let conversationID { items.append(URLQueryItem(name: "conversationId", value: conversationID)) }
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            var components = URLComponents()
            components.path = "/v1/me/calls"
            components.queryItems = items
            return components.string ?? "/v1/me/calls"
        }

        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
        }
    }

    func capabilities() async throws -> CallsCapabilities {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: Paths.capabilities)
        return CallPayloadDecoder.capabilities(value["calls"])
    }

    /// Returns the call and whether the server matched it to the other person's ringing call (glare).
    func start(conversationID: String, mediaKind: CallMediaKind, deviceID: String?) async throws -> (call: CallRecord, glare: Bool) {
        var body: [String: JSONValue] = ["mediaKind": .string(mediaKind.rawValue)]
        if let deviceID { body["deviceId"] = .string(deviceID) }
        let value: JSONValue = try await client.authenticatedJSON(
            "POST", path: Paths.start(conversationID: conversationID), body: .object(body), idempotencyKey: CallIdempotency.key()
        )
        guard let call = CallPayloadDecoder.record(value["call"]) else { throw APIError.invalidResponse }
        return (call, value["glare"]?.bool ?? false)
    }

    func command(_ command: CallCommand, callID: CallID, deviceID: String? = nil, reason: String? = nil) async throws -> CallRecord {
        var body: [String: JSONValue] = [:]
        if let deviceID { body["deviceId"] = .string(deviceID) }
        if let reason { body["reason"] = .string(reason) }
        let value: JSONValue = try await client.authenticatedJSON(
            "POST", path: Paths.command(command, id: callID), body: .object(body), idempotencyKey: CallIdempotency.key()
        )
        guard let call = CallPayloadDecoder.record(value["call"]) else { throw APIError.invalidResponse }
        return call
    }

    func call(_ id: CallID) async throws -> CallRecord {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: Paths.call(id))
        guard let call = CallPayloadDecoder.record(value["call"]) else { throw APIError.invalidResponse }
        return call
    }

    func history(conversationID: String?, cursor: String? = nil) async throws -> CallHistoryPage {
        let value: JSONValue = try await client.authenticatedJSON("GET", path: Paths.history(conversationID: conversationID, cursor: cursor))
        return CallPayloadDecoder.history(value)
    }

    func ticket(callID: CallID) async throws -> CallSignallingTicket {
        let value: JSONValue = try await client.authenticatedJSON("POST", path: Paths.ticket(callID), body: .object([:]))
        guard let ticket = CallPayloadDecoder.ticket(value) else { throw APIError.invalidResponse }
        return ticket
    }

    func iceConfig(callID: CallID) async throws -> CallIceConfig {
        let value: JSONValue = try await client.authenticatedJSON("POST", path: Paths.mediaCredentials(callID), body: .object([:]))
        guard let config = CallPayloadDecoder.iceConfig(value) else { throw APIError.invalidResponse }
        return config
    }

    /// Ticket-authenticated socket request. The ticket is single use and expires in 60 s.
    func signallingRequest(callID: CallID, ticket: CallSignallingTicket) async throws -> URLRequest {
        try await client.callSignallingRequest(path: CallSignalling.path(callID: callID), ticket: ticket.ticket)
    }

    /// Registers this device's PushKit token. `deviceID` is the ordinary APNs registration id
    /// (`POST /v1/push/devices`), which the server uses to prove the device belongs to this account.
    func registerVoip(deviceID: String, token: String, environment: String) async throws -> String {
        let body: JSONValue = .object([
            "deviceId": .string(deviceID),
            "token": .string(token),
            "environment": .string(environment),
            "appVersion": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"),
        ])
        let value: JSONValue = try await client.authenticatedJSON("POST", path: Paths.voipDevices, body: body)
        guard let id = value["registration"]?["registrationId"]?.string else { throw APIError.invalidResponse }
        return id
    }

    func deleteVoip(registrationID: String) async throws {
        let _: JSONValue = try await client.authenticatedJSON("DELETE", path: Paths.voipDevice(registrationID))
    }
}
