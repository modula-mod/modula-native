import Foundation

/// Greenfield call ids are UUIDv7 strings, so they double as CallKit UUIDs.
typealias CallID = String

/// Server-owned call lifecycle (`services/greenfield-api/src/domains/calls/policy.ts`).
enum CallState: String, Sendable, Equatable, Hashable {
    case ringing, connecting, active, reconnecting
    case declined, cancelled, missed, ended, failed

    init?(parsing raw: String?) {
        guard let raw, let value = CallState(rawValue: raw) else { return nil }
        self = value
    }

    var isTerminal: Bool {
        switch self {
        case .declined, .cancelled, .missed, .ended, .failed: true
        case .ringing, .connecting, .active, .reconnecting: false
        }
    }
}

enum CallMediaKind: String, Sendable, Equatable, Hashable {
    case audio, video

    init(parsing raw: String?) { self = raw == "video" ? .video : .audio }
}

enum CallDirection: String, Sendable, Equatable, Hashable {
    case outgoing, incoming
}

struct CallParty: Sendable, Equatable, Hashable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: URL?

    var name: String {
        if !displayName.isEmpty { return displayName }
        if !handle.isEmpty { return "@\(handle)" }
        return "Modula user"
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.filter { $0 != "@" }.prefix(2)).uppercased()
    }
}

/// `CallDto` from the API. History rows and live calls share this shape.
struct CallRecord: Identifiable, Sendable, Equatable, Hashable {
    let id: CallID
    let conversationID: String
    let mediaKind: CallMediaKind
    var state: CallState
    var revision: Int
    let initiatorActorID: String
    let recipientActorID: String
    let direction: CallDirection
    let other: CallParty
    let ringDeadlineAt: Date?
    var stateDeadlineAt: Date?
    var acceptedAt: Date?
    var connectedAt: Date?
    var endedAt: Date?
    var terminalReason: String?
    var durationMs: Int?
    let createdAt: Date
    /// For the recipient: whether this session/device is the one that answered.
    var answeredHere: Bool?

    var uuid: UUID? { UUID(uuidString: id) }
}

struct CallHistoryPage: Sendable, Equatable {
    var items: [CallRecord]
    var nextCursor: String?
    var hasMore: Bool
}

/// `calls` block of `GET /v1/messaging/capabilities`. Everything defaults off: call buttons
/// only appear when the server says calls are enabled (no fake capability).
struct CallsCapabilities: Sendable, Equatable {
    var enabled = false
    var audio = false
    var video = false
    var voipPush = false
    var maxParticipants = 0
    var ringTimeoutMs = 30_000
    var negotiationTimeoutMs = 20_000
    var reconnectGraceMs = 30_000
    var signallingProtocolVersion = 0

    static let disabled = CallsCapabilities()
    static let supportedProtocolVersion = 1

    /// Calls are offered only for a protocol this build speaks and a 1:1 limit.
    var canCall: Bool {
        enabled && (audio || video) && signallingProtocolVersion == Self.supportedProtocolVersion && maxParticipants >= 2
    }

    func allows(_ kind: CallMediaKind) -> Bool {
        guard canCall else { return false }
        return kind == .video ? video : audio
    }
}

struct CallIceServer: Sendable, Equatable {
    let urls: [String]
    let username: String?
    let credential: String?
}

/// `POST /v1/calls/:id/media-credentials`. Short-lived TURN REST credentials; never persisted.
struct CallIceConfig: Sendable, Equatable {
    let servers: [CallIceServer]
    let relayOnly: Bool
    let expiresAt: Date?
}

struct CallSignallingTicket: Sendable, Equatable {
    let ticket: String
    let expiresAt: Date?
}

/// `call.updated` on the messaging socket (foreground ringing without PushKit).
struct CallRealtimeUpdate: Sendable, Equatable {
    let callID: CallID
    let conversationID: String
    let state: CallState
    let revision: Int
    let mediaKind: CallMediaKind
    let initiatorActorID: String
    let event: String
    let terminalReason: String?
}

/// `modula` block of a PushKit VoIP payload (worker `buildVoipPayload`). No credentials, no SDP.
struct IncomingCallPush: Sendable, Equatable {
    let callID: CallID
    let conversationID: String
    let mediaKind: CallMediaKind
    let ringDeadlineAt: Date?
    let caller: CallParty
}

struct CallIceCandidate: Sendable, Equatable {
    let sdp: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

enum CallCommand: String, Sendable {
    case accept, decline, cancel, end
}

// MARK: - Decoding

enum CallPayloadDecoder {
    static func capabilities(_ value: JSONValue?) -> CallsCapabilities {
        guard let value, value["enabled"]?.bool == true else { return .disabled }
        var caps = CallsCapabilities()
        caps.enabled = true
        caps.audio = value["audio"]?.bool ?? false
        caps.video = value["video"]?.bool ?? false
        caps.voipPush = value["voipPush"]?.bool ?? false
        caps.maxParticipants = value["maxParticipants"]?.int ?? 0
        caps.ringTimeoutMs = value["ringTimeoutMs"]?.int ?? 30_000
        caps.negotiationTimeoutMs = value["negotiationTimeoutMs"]?.int ?? 20_000
        caps.reconnectGraceMs = value["reconnectGraceMs"]?.int ?? 30_000
        caps.signallingProtocolVersion = value["signallingProtocolVersion"]?.int ?? 0
        return caps
    }

    static func record(_ value: JSONValue?) -> CallRecord? {
        guard let value,
              let id = value["id"]?.string, UUID(uuidString: id) != nil,
              let conversation = value["conversationId"]?.string,
              let state = CallState(parsing: value["state"]?.string),
              let initiator = value["initiatorActorId"]?.string,
              let recipient = value["recipientActorId"]?.string,
              let direction = value["direction"]?.string.flatMap(CallDirection.init(rawValue:))
        else { return nil }
        let other = value["other"]
        return CallRecord(
            id: id.lowercased(),
            conversationID: conversation,
            mediaKind: CallMediaKind(parsing: value["mediaKind"]?.string),
            state: state,
            revision: value["revision"]?.int ?? 0,
            initiatorActorID: initiator,
            recipientActorID: recipient,
            direction: direction,
            other: CallParty(
                id: other?["id"]?.string ?? (direction == .outgoing ? recipient : initiator),
                handle: other?["handle"]?.string ?? "",
                displayName: other?["displayName"]?.string ?? "",
                avatarURL: other?["avatarUrl"]?.string.flatMap(URL.init(string:))
            ),
            ringDeadlineAt: date(value["ringDeadlineAt"]),
            stateDeadlineAt: date(value["stateDeadlineAt"]),
            acceptedAt: date(value["acceptedAt"]),
            connectedAt: date(value["connectedAt"]),
            endedAt: date(value["endedAt"]),
            terminalReason: value["terminalReason"]?.string,
            durationMs: value["durationMs"]?.int,
            createdAt: date(value["createdAt"]) ?? Date(),
            answeredHere: value["answeredHere"]?.bool
        )
    }

    static func history(_ value: JSONValue) -> CallHistoryPage {
        CallHistoryPage(
            items: (value["items"]?.array ?? []).compactMap { record($0) },
            nextCursor: value["nextCursor"]?.string,
            hasMore: value["hasMore"]?.bool ?? false
        )
    }

    static func iceConfig(_ value: JSONValue) -> CallIceConfig? {
        let servers: [CallIceServer] = (value["iceServers"]?.array ?? []).compactMap { item in
            let urls = (item["urls"]?.array ?? []).compactMap(\.string)
                .filter { $0.hasPrefix("stun:") || $0.hasPrefix("turn:") || $0.hasPrefix("turns:") }
            guard !urls.isEmpty else { return nil }
            return CallIceServer(urls: urls, username: item["username"]?.string, credential: item["credential"]?.string)
        }
        guard !servers.isEmpty else { return nil }
        return CallIceConfig(
            servers: servers,
            relayOnly: value["iceTransportPolicy"]?.string == "relay",
            expiresAt: date(value["expiresAt"])
        )
    }

    static func ticket(_ value: JSONValue) -> CallSignallingTicket? {
        guard let ticket = value["ticket"]?.string, ticket.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil
        else { return nil }
        return CallSignallingTicket(ticket: ticket, expiresAt: date(value["expiresAt"]))
    }

    static func realtimeUpdate(_ value: JSONValue) -> CallRealtimeUpdate? {
        guard value["type"]?.string == "call.updated",
              let id = value["callId"]?.string, UUID(uuidString: id) != nil,
              let conversation = value["conversationId"]?.string,
              let state = CallState(parsing: value["state"]?.string)
        else { return nil }
        return CallRealtimeUpdate(
            callID: id.lowercased(),
            conversationID: conversation,
            state: state,
            revision: value["revision"]?.int ?? 0,
            mediaKind: CallMediaKind(parsing: value["mediaKind"]?.string),
            initiatorActorID: value["initiatorActorId"]?.string ?? "",
            event: value["event"]?.string ?? "",
            terminalReason: value["terminalReason"]?.string
        )
    }

    /// Parses a PushKit dictionary. Anything unexpected returns nil; the caller still reports
    /// (and immediately ends) a CallKit call, because iOS requires every VoIP push to be reported.
    static func incomingPush(_ payload: [AnyHashable: Any]) -> IncomingCallPush? {
        guard let modula = payload["modula"] as? [String: Any],
              modula["type"] as? String == "call.incoming",
              let id = modula["callId"] as? String, UUID(uuidString: id) != nil,
              let conversation = modula["conversationId"] as? String
        else { return nil }
        let caller = modula["caller"] as? [String: Any]
        return IncomingCallPush(
            callID: id.lowercased(),
            conversationID: conversation,
            mediaKind: CallMediaKind(parsing: modula["mediaKind"] as? String),
            ringDeadlineAt: MessagingPayloadDecoder.decodeDate(modula["ringDeadlineAt"] as? String),
            caller: CallParty(
                id: caller?["actorId"] as? String ?? "",
                handle: caller?["handle"] as? String ?? "",
                displayName: caller?["displayName"] as? String ?? "",
                avatarURL: nil
            )
        )
    }

    private static func date(_ value: JSONValue?) -> Date? {
        MessagingPayloadDecoder.decodeDate(value?.string)
    }
}

// MARK: - Signalling protocol v1

enum CallSignalling {
    static let protocolVersion = 1

    static func path(callID: CallID) -> String { "/v1/calls/\(callID.lowercased())/signalling" }

    static func isSignallingPath(_ path: String) -> Bool {
        path.range(of: "^/v1/calls/[0-9a-f-]{36}/signalling$", options: .regularExpression) != nil
    }

    /// Message and negotiation ids must match `^[A-Za-z0-9._:-]{8,64}$` on the server.
    static func newMessageID() -> String { "m-" + UUID().uuidString.lowercased() }
    static func newNegotiationID() -> String { "n-" + UUID().uuidString.lowercased() }

    static func frame(type: String, callID: CallID, negotiationID: String?, payload: [String: JSONValue], messageID: String = newMessageID()) -> String? {
        var object: [String: JSONValue] = [
            "protocolVersion": .number(Double(protocolVersion)),
            "type": .string(type),
            "messageId": .string(messageID),
            "callId": .string(callID.lowercased()),
            "payload": .object(payload),
        ]
        if let negotiationID { object["negotiationId"] = .string(negotiationID) }
        guard let data = try? JSONEncoder().encode(JSONValue.object(object)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func candidatePayload(_ candidate: CallIceCandidate) -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "candidate": .string(candidate.sdp),
            "sdpMLineIndex": .number(Double(candidate.sdpMLineIndex)),
        ]
        if let mid = candidate.sdpMid { payload["sdpMid"] = .string(mid) }
        return payload
    }

    static func candidate(from payload: JSONValue?) -> CallIceCandidate? {
        guard let payload, let sdp = payload["candidate"]?.string, !sdp.isEmpty else { return nil }
        return CallIceCandidate(sdp: sdp, sdpMid: payload["sdpMid"]?.string, sdpMLineIndex: Int32(payload["sdpMLineIndex"]?.int ?? 0))
    }
}

enum CallIdempotency {
    /// 41 characters from `[a-z0-9-]`: valid for the native client check and the API (16–128 printable).
    static func key() -> String { "call-" + UUID().uuidString.lowercased() }
}

// MARK: - Presentation helpers

enum CallCopy {
    static func errorMessage(_ error: Error) -> String {
        switch error {
        case APIError.rejected(_, "FORBIDDEN"): "You can’t call this person right now."
        case APIError.rejected(_, "CONFLICT"): "They’re on another call, or this call already ended."
        case APIError.rejected(_, "REVISION_CONFLICT"): "This call changed. Try again."
        case APIError.rejected(_, "CAPABILITY_UNAVAILABLE"): "Calls aren’t available right now."
        case APIError.rejected(_, "RATE_LIMITED"): "Too many calls. Try again in a few minutes."
        case APIError.rejected(_, "NOT_FOUND"): "This call is no longer available."
        case APIError.unauthenticated: "Sign in to Modula to call."
        default: "Couldn’t connect the call."
        }
    }

    static func duration(ms: Int) -> String {
        let total = max(0, ms / 1000)
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// One line for a call row in the chat ("Video call · 4:12", "Missed voice call").
    static func historyTitle(_ record: CallRecord) -> String {
        let kind = record.mediaKind == .video ? "video call" : "voice call"
        switch record.state {
        case .missed:
            return record.direction == .incoming ? "Missed \(kind)" : "No answer"
        case .declined:
            return record.direction == .incoming ? "Declined \(kind)" : "Call declined"
        case .cancelled:
            return record.direction == .incoming ? "Missed \(kind)" : "Cancelled \(kind)"
        case .failed:
            return "Call failed"
        case .ended:
            let base = record.mediaKind == .video ? "Video call" : "Voice call"
            if let ms = record.durationMs, ms > 0 { return "\(base) · \(duration(ms: ms))" }
            return base
        case .ringing, .connecting, .active, .reconnecting:
            return record.mediaKind == .video ? "Video call in progress" : "Voice call in progress"
        }
    }

    static func isMissed(_ record: CallRecord) -> Bool {
        record.direction == .incoming && (record.state == .missed || record.state == .cancelled)
    }
}

/// Places call rows between messages by time. Calls older than the oldest loaded message are
/// held back while older history can still load, so a row never jumps when scrolling up.
enum CallHistoryPlacement {
    struct Slots: Equatable {
        var before: [String: [CallRecord]] = [:]
        var trailing: [CallRecord] = []
    }

    static func place(calls: [CallRecord], messages: [(id: String, sentAt: Date)], hasOlder: Bool) -> Slots {
        var slots = Slots()
        guard !calls.isEmpty else { return slots }
        let ordered = calls.sorted { $0.createdAt < $1.createdAt }
        guard let first = messages.first else {
            slots.trailing = hasOlder ? [] : ordered
            return slots
        }
        var index = 0
        for call in ordered {
            if call.createdAt < first.sentAt && hasOlder { continue }
            while index < messages.count && messages[index].sentAt <= call.createdAt { index += 1 }
            if index < messages.count {
                slots.before[messages[index].id, default: []].append(call)
            } else {
                slots.trailing.append(call)
            }
        }
        return slots
    }
}
