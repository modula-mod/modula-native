import XCTest
@testable import Modula

/// Pure call logic: capability gating, DTO decoding, signalling frames, history placement.
/// Media, CallKit and PushKit need a physical device and are not covered here.
final class CallTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private let callID = "0192f3a4-5b6c-7d8e-9f01-23456789abcd"

    private func record(id: String, createdAt: String, state: String = "ended", direction: String = "outgoing", durationMs: Int? = nil) throws -> CallRecord {
        let duration = durationMs.map { ", \"durationMs\": \($0)" } ?? ""
        let value = try json("""
        {"id": "\(id)", "conversationId": "c1", "mediaKind": "video", "state": "\(state)", "revision": 3,
         "initiatorActorId": "a1", "recipientActorId": "a2", "direction": "\(direction)",
         "other": {"id": "a2", "handle": "sam", "displayName": "Sam Lee"},
         "createdAt": "\(createdAt)"\(duration)}
        """)
        return try XCTUnwrap(CallPayloadDecoder.record(value))
    }

    // MARK: Capabilities

    func testCapabilitiesDefaultOff() throws {
        XCTAssertFalse(CallsCapabilities.disabled.canCall)
        XCTAssertFalse(CallPayloadDecoder.capabilities(nil).canCall)
        let off = try json(#"{"enabled": false, "audio": false, "video": false, "voipPush": false}"#)
        XCTAssertEqual(CallPayloadDecoder.capabilities(off), .disabled)
        XCTAssertFalse(MessagingBackendCapabilities.production.calls.canCall)
    }

    func testCapabilitiesEnabled() throws {
        let on = try json("""
        {"enabled": true, "audio": true, "video": true, "voipPush": true, "maxParticipants": 2,
         "ringTimeoutMs": 30000, "negotiationTimeoutMs": 20000, "reconnectGraceMs": 30000, "signallingProtocolVersion": 1}
        """)
        let caps = CallPayloadDecoder.capabilities(on)
        XCTAssertTrue(caps.canCall)
        XCTAssertTrue(caps.allows(.audio))
        XCTAssertTrue(caps.allows(.video))
        XCTAssertTrue(caps.voipPush)
    }

    func testCapabilitiesRejectUnknownProtocolOrVideoOff() throws {
        let future = try json(#"{"enabled": true, "audio": true, "video": true, "maxParticipants": 2, "signallingProtocolVersion": 2}"#)
        XCTAssertFalse(CallPayloadDecoder.capabilities(future).canCall)
        let audioOnly = try json(#"{"enabled": true, "audio": true, "video": false, "maxParticipants": 2, "signallingProtocolVersion": 1}"#)
        let caps = CallPayloadDecoder.capabilities(audioOnly)
        XCTAssertTrue(caps.allows(.audio))
        XCTAssertFalse(caps.allows(.video))
    }

    func testCapabilitiesEmbeddedInMessagingV3() throws {
        let value = try json("""
        {"version": 3, "calls": {"enabled": true, "audio": true, "video": true, "maxParticipants": 2, "signallingProtocolVersion": 1}}
        """)
        let caps = try XCTUnwrap(MessagingPayloadDecoder.capabilitiesV3(from: value))
        XCTAssertTrue(caps.calls.canCall)
        let without = try XCTUnwrap(MessagingPayloadDecoder.capabilitiesV3(from: try json(#"{"version": 3}"#)))
        XCTAssertFalse(without.calls.canCall)
    }

    // MARK: Decoding

    func testRecordDecoding() throws {
        let call = try record(id: callID.uppercased(), createdAt: "2026-11-10T12:00:00.000Z", durationMs: 252_000)
        XCTAssertEqual(call.id, callID)
        XCTAssertEqual(call.mediaKind, .video)
        XCTAssertEqual(call.state, .ended)
        XCTAssertTrue(call.state.isTerminal)
        XCTAssertEqual(call.other.name, "Sam Lee")
        XCTAssertEqual(call.other.initials, "SL")
        XCTAssertNotNil(call.uuid)
        XCTAssertEqual(CallCopy.historyTitle(call), "Video call · 4:12")
    }

    func testRecordRejectsBadIDs() throws {
        let value = try json(#"{"id": "nope", "conversationId": "c1", "state": "ended", "initiatorActorId": "a", "recipientActorId": "b", "direction": "outgoing"}"#)
        XCTAssertNil(CallPayloadDecoder.record(value))
    }

    func testHistoryTitles() throws {
        XCTAssertEqual(CallCopy.historyTitle(try record(id: callID, createdAt: "2026-11-10T12:00:00Z", state: "missed", direction: "incoming")), "Missed video call")
        XCTAssertEqual(CallCopy.historyTitle(try record(id: callID, createdAt: "2026-11-10T12:00:00Z", state: "missed")), "No answer")
        XCTAssertTrue(CallCopy.isMissed(try record(id: callID, createdAt: "2026-11-10T12:00:00Z", state: "cancelled", direction: "incoming")))
        XCTAssertEqual(CallCopy.duration(ms: 3_725_000), "1:02:05")
    }

    func testIceConfigFiltersSchemes() throws {
        let value = try json("""
        {"iceServers": [{"urls": ["turn:turn.modula.digital:3478?transport=udp", "http://evil"], "username": "1:a", "credential": "x"},
                        {"urls": ["javascript:alert(1)"]}],
         "iceTransportPolicy": "relay", "expiresAt": "2026-11-10T12:10:00Z"}
        """)
        let config = try XCTUnwrap(CallPayloadDecoder.iceConfig(value))
        XCTAssertEqual(config.servers.count, 1)
        XCTAssertEqual(config.servers[0].urls, ["turn:turn.modula.digital:3478?transport=udp"])
        XCTAssertTrue(config.relayOnly)
        XCTAssertNil(CallPayloadDecoder.iceConfig(try json(#"{"iceServers": []}"#)))
    }

    func testTicketValidation() throws {
        XCTAssertNotNil(CallPayloadDecoder.ticket(try json(#"{"ticket": "abcdefghijklmnopqrstuvwxyz0123456789_-AB"}"#)))
        XCTAssertNil(CallPayloadDecoder.ticket(try json(#"{"ticket": "short"}"#)))
        XCTAssertNil(CallPayloadDecoder.ticket(try json(#"{"ticket": "abcdefghijklmnopqrstuvwxyz0123456789\r\nX-Evil: 1"}"#)))
    }

    func testRealtimeUpdate() throws {
        let value = try json("""
        {"type": "call.updated", "callId": "\(callID)", "conversationId": "c1", "state": "ringing", "revision": 1,
         "mediaKind": "audio", "initiatorActorId": "a1", "event": "call.started", "terminalReason": null}
        """)
        let update = try XCTUnwrap(CallPayloadDecoder.realtimeUpdate(value))
        XCTAssertEqual(update.state, .ringing)
        XCTAssertEqual(update.mediaKind, .audio)
        XCTAssertNil(CallPayloadDecoder.realtimeUpdate(try json(#"{"type": "message.created"}"#)))
    }

    func testIncomingPushParsing() {
        let payload: [AnyHashable: Any] = [
            "aps": [String: Any](),
            "modula": [
                "type": "call.incoming", "callId": callID.uppercased(), "conversationId": "c1", "mediaKind": "video",
                "ringDeadlineAt": "2026-11-10T12:00:30.000Z",
                "caller": ["actorId": "a1", "handle": "sam", "displayName": ""],
            ] as [String: Any],
        ]
        let push = CallPayloadDecoder.incomingPush(payload)
        XCTAssertEqual(push?.callID, callID)
        XCTAssertEqual(push?.mediaKind, .video)
        XCTAssertEqual(push?.caller.name, "@sam")
        XCTAssertNotNil(push?.ringDeadlineAt)
        XCTAssertNil(CallPayloadDecoder.incomingPush(["modula": ["type": "message.created"]]))
        XCTAssertNil(CallPayloadDecoder.incomingPush([:]))
    }

    // MARK: Signalling

    func testFrameEncoding() throws {
        let messageID = CallSignalling.newMessageID()
        let negotiationID = CallSignalling.newNegotiationID()
        for id in [messageID, negotiationID] {
            XCTAssertNotNil(id.range(of: "^[A-Za-z0-9._:-]{8,64}$", options: .regularExpression))
        }
        let candidate = CallIceCandidate(sdp: "candidate:1 1 udp 1 1.2.3.4 5 typ relay", sdpMid: "0", sdpMLineIndex: 0)
        let text = try XCTUnwrap(CallSignalling.frame(type: "webrtc.candidate", callID: callID.uppercased(), negotiationID: negotiationID,
                                                     payload: CallSignalling.candidatePayload(candidate), messageID: messageID))
        let decoded = try json(text)
        XCTAssertEqual(decoded["protocolVersion"]?.int, 1)
        XCTAssertEqual(decoded["type"]?.string, "webrtc.candidate")
        XCTAssertEqual(decoded["callId"]?.string, callID)
        XCTAssertEqual(decoded["messageId"]?.string, messageID)
        XCTAssertEqual(decoded["negotiationId"]?.string, negotiationID)
        XCTAssertEqual(CallSignalling.candidate(from: decoded["payload"]), candidate)
    }

    func testSignallingPathValidation() {
        XCTAssertTrue(CallSignalling.isSignallingPath(CallSignalling.path(callID: callID.uppercased())))
        XCTAssertFalse(CallSignalling.isSignallingPath("/v1/calls/../admin/signalling"))
        XCTAssertFalse(CallSignalling.isSignallingPath("https://evil.example/v1/calls/\(callID)/signalling"))
    }

    func testIdempotencyKeyIsAccepted() {
        let key = CallIdempotency.key()
        XCTAssertTrue(GreenfieldClient.isSafeIdempotencyKey(key))
        XCTAssertGreaterThanOrEqual(key.count, 16)
        XCTAssertNotEqual(key, CallIdempotency.key())
    }

    func testErrorCopy() {
        XCTAssertEqual(CallCopy.errorMessage(APIError.rejected(409, "CONFLICT")), "They’re on another call, or this call already ended.")
        XCTAssertEqual(CallCopy.errorMessage(APIError.rejected(503, "CAPABILITY_UNAVAILABLE")), "Calls aren’t available right now.")
        XCTAssertEqual(CallCopy.errorMessage(URLError(.timedOut)), "Couldn’t connect the call.")
    }

    // MARK: History placement

    func testPlacementBetweenMessages() throws {
        let formatter = ISO8601DateFormatter()
        let messages: [(id: String, sentAt: Date)] = [
            (id: "m1", sentAt: formatter.date(from: "2026-11-10T10:00:00Z")!),
            (id: "m2", sentAt: formatter.date(from: "2026-11-10T12:00:00Z")!),
        ]
        let early = try record(id: "0192f3a4-5b6c-7d8e-9f01-000000000001", createdAt: "2026-11-10T09:00:00Z")
        let middle = try record(id: "0192f3a4-5b6c-7d8e-9f01-000000000002", createdAt: "2026-11-10T11:00:00Z")
        let late = try record(id: "0192f3a4-5b6c-7d8e-9f01-000000000003", createdAt: "2026-11-10T13:00:00Z")

        let complete = CallHistoryPlacement.place(calls: [late, early, middle], messages: messages, hasOlder: false)
        XCTAssertEqual(complete.before["m1"], [early])
        XCTAssertEqual(complete.before["m2"], [middle])
        XCTAssertEqual(complete.trailing, [late])

        let paged = CallHistoryPlacement.place(calls: [late, early, middle], messages: messages, hasOlder: true)
        XCTAssertNil(paged.before["m1"])
        XCTAssertEqual(paged.before["m2"], [middle])
        XCTAssertEqual(paged.trailing, [late])

        XCTAssertEqual(CallHistoryPlacement.place(calls: [early], messages: [], hasOlder: false).trailing, [early])
        XCTAssertTrue(CallHistoryPlacement.place(calls: [early], messages: [], hasOlder: true).trailing.isEmpty)
    }
}
