import Foundation

/// One call's signalling socket (protocol v1). SDP and ICE pass through in memory only; nothing
/// here is logged or stored. Losing the socket never ends the call by itself: the manager
/// reconnects with a fresh ticket while media keeps flowing.
@MainActor
final class CallSignallingClient {
    enum Event: Sendable {
        case ready(actorID: String, heartbeatMs: Int, call: CallRecord?)
        case snapshot(CallRecord)
        case accepted(CallRecord?)
        case terminal(CallState, CallRecord?)
        case offer(sdp: String, negotiationID: String)
        case answer(sdp: String, negotiationID: String)
        case candidate(CallIceCandidate, negotiationID: String)
        case reconnectRequired(ownerActorID: String?)
        /// `server.ack` for a relayed frame; `relayed == false` means the other phone's socket
        /// was not connected and the frame was dropped.
        case ack(messageID: String, relayed: Bool?)
        case error(code: String)
        case closed(code: Int)
    }

    let callID: CallID
    var onEvent: ((Event) -> Void)?
    private(set) var isOpen = false
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pump: Task<Void, Never>?
    private var heart: Task<Void, Never>?

    init(callID: CallID) {
        self.callID = callID
    }

    func connect(_ request: URLRequest) {
        close()
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 128 * 1024
        self.session = session
        task = socket
        socket.resume()
        pump = Task { [weak self] in await self?.listen(socket) }
    }

    func close() {
        pump?.cancel(); pump = nil
        heart?.cancel(); heart = nil
        task?.cancel(with: .normalClosure, reason: nil); task = nil
        session?.invalidateAndCancel(); session = nil
        isOpen = false
    }

    // MARK: Outgoing frames

    /// Returns the frame's message id so the caller can match its `server.ack`.
    @discardableResult
    func sendOffer(sdp: String, negotiationID: String) -> String? {
        send("signal.offer", negotiationID: negotiationID, payload: ["sdp": .string(sdp)])
    }

    @discardableResult
    func sendAnswer(sdp: String, negotiationID: String) -> String? {
        send("signal.answer", negotiationID: negotiationID, payload: ["sdp": .string(sdp)])
    }

    func sendCandidate(_ candidate: CallIceCandidate, negotiationID: String) {
        send("signal.ice_candidate", negotiationID: negotiationID, payload: CallSignalling.candidatePayload(candidate))
    }

    func sendMediaConnected(negotiationID: String, relay: Bool?, audio: Bool, video: Bool) {
        var payload: [String: JSONValue] = ["audio": .bool(audio), "video": .bool(video)]
        if let relay { payload["iceType"] = .string(relay ? "relay" : "host") }
        send("media.connected", negotiationID: negotiationID, payload: payload)
    }

    func sendMediaDisconnected(negotiationID: String, reason: String) {
        send("media.disconnected", negotiationID: negotiationID, payload: ["reason": .string(reason)])
    }

    func sendClientReady() {
        send("client.ready", negotiationID: nil, payload: [:])
    }

    @discardableResult
    private func send(_ type: String, negotiationID: String?, payload: [String: JSONValue]) -> String? {
        let messageID = CallSignalling.newMessageID()
        guard let task,
              let text = CallSignalling.frame(type: type, callID: callID, negotiationID: negotiationID, payload: payload, messageID: messageID)
        else { return nil }
        task.send(.string(text)) { @Sendable _ in }
        return messageID
    }

    // MARK: Incoming frames

    private func listen(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled, task === socket {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let value): data = value
                @unknown default: continue
                }
                handle(data)
            } catch {
                break
            }
        }
        guard task === socket else { return }
        let code = socket.closeCode.rawValue
        isOpen = false
        heart?.cancel(); heart = nil
        task = nil
        onEvent?(.closed(code: code))
    }

    private func handle(_ data: Data) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              value["callId"]?.string?.lowercased() == callID.lowercased() else { return }
        let payload = value["payload"]
        let negotiation = value["negotiationId"]?.string ?? ""
        switch value["type"]?.string ?? "" {
        case "server.ready":
            isOpen = true
            let heartbeat = max(5_000, payload?["heartbeatMs"]?.int ?? 15_000)
            startHeartbeat(every: heartbeat)
            onEvent?(.ready(actorID: payload?["actorId"]?.string ?? "", heartbeatMs: heartbeat, call: CallPayloadDecoder.record(payload?["call"])))
        case "call.snapshot":
            if let call = CallPayloadDecoder.record(payload?["call"]) { onEvent?(.snapshot(call)) }
        case "call.accepted":
            onEvent?(.accepted(CallPayloadDecoder.record(payload?["call"])))
        case "call.declined", "call.cancelled", "call.missed", "call.ended", "call.failed":
            let raw = String((value["type"]?.string ?? "call.ended").dropFirst("call.".count))
            onEvent?(.terminal(CallState(rawValue: raw) ?? .ended, CallPayloadDecoder.record(payload?["call"])))
        case "signal.offer":
            if let sdp = payload?["sdp"]?.string, !negotiation.isEmpty { onEvent?(.offer(sdp: sdp, negotiationID: negotiation)) }
        case "signal.answer":
            if let sdp = payload?["sdp"]?.string, !negotiation.isEmpty { onEvent?(.answer(sdp: sdp, negotiationID: negotiation)) }
        case "signal.ice_candidate":
            if let candidate = CallSignalling.candidate(from: payload), !negotiation.isEmpty {
                onEvent?(.candidate(candidate, negotiationID: negotiation))
            }
        case "server.ack":
            if let messageID = payload?["messageId"]?.string {
                onEvent?(.ack(messageID: messageID, relayed: payload?["relayed"]?.bool))
            }
        case "media.reconnect_required":
            onEvent?(.reconnectRequired(ownerActorID: payload?["ownerActorId"]?.string))
        case "error":
            onEvent?(.error(code: payload?["code"]?.string ?? "UNKNOWN"))
        default:
            break
        }
    }

    private func startHeartbeat(every ms: Int) {
        heart?.cancel()
        heart = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled else { return }
                self?.send("ping", negotiationID: nil, payload: [:])
            }
        }
    }
}
