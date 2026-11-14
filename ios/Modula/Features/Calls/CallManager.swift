@preconcurrency import AVFoundation
@preconcurrency import CallKit
import Foundation
import Observation
@preconcurrency import PushKit
import UIKit

/// Owns the one live 1:1 call: CallKit, PushKit, the signalling socket and the WebRTC engine.
/// The server is the source of truth for call state; local state only mirrors it and never
/// invents a capability (no call UI unless `/v1/messaging/capabilities` reports calls on).
@MainActor @Observable
final class CallManager {
    static let shared = CallManager()

    enum Phase: Equatable {
        case outgoingRinging, incomingRinging, connecting, active, reconnecting
        case ended(String)
    }

    struct Session: Equatable {
        var record: CallRecord
        var phase: Phase
        var connectedAt: Date?
    }

    private(set) var session: Session?
    private(set) var media: CallMediaEngine?
    private(set) var capabilities: CallsCapabilities = .disabled
    private(set) var historyByConversation: [String: [CallRecord]] = [:]
    private(set) var lastError: String?
    var isMinimized = false

    @ObservationIgnored private var repository: CallRepository?
    @ObservationIgnored private var signalling: CallSignallingClient?
    @ObservationIgnored private var callKit: CallKitBridge?
    @ObservationIgnored private var pushKit: VoipPushBridge?
    @ObservationIgnored private var signedIn = false
    @ObservationIgnored private var myActorID: String?
    @ObservationIgnored private var negotiationID: String?
    @ObservationIgnored private var offerSent = false
    @ObservationIgnored private var reportedConnectedNegotiation: String?
    @ObservationIgnored private var outgoingConnectedReported = false
    @ObservationIgnored private var holdLocalCandidates = false
    @ObservationIgnored private var pendingLocalCandidates: [(CallIceCandidate, String)] = []
    @ObservationIgnored private var earlyRemoteCandidates: [String: [CallIceCandidate]] = [:]
    @ObservationIgnored private var lastOffer: (messageID: String, negotiation: String)?
    @ObservationIgnored private var offerResends = 0
    @ObservationIgnored private var answered: (negotiation: String, sdp: String)?
    @ObservationIgnored private var appliedAnswerNegotiation: String?
    @ObservationIgnored private var signallingAttempts = 0
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var endedLocally: Set<CallID> = []
    @ObservationIgnored private var pendingAnswer: CXAnswerCallAction?
    @ObservationIgnored private var callKitMuted = false
    @ObservationIgnored private var voipToken: String?
    @ObservationIgnored private var lastVoipRegistration: String?
    @ObservationIgnored private var historyLoadedAt: [String: Date] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard

    enum Keys {
        static let voipEnabled = "calls.voip.lastEnabled.v1"
        static let registration = "calls.voip.registrationId.v1"
        static let pushDevice = "push.registeredDeviceID"
    }

    private init() {}

    // MARK: Launch, account and capabilities

    /// From `application(_:didFinishLaunchingWithOptions:)`. PushKit must be registered at launch
    /// so a VoIP push that cold-launches the app is delivered; only done once the server has
    /// reported VoIP calls on (remembered from the last capability probe).
    func bootstrapAtLaunch() {
        if defaults.bool(forKey: Keys.voipEnabled) { startPushKit() }
    }

    func attach(client: GreenfieldClient, signedIn: Bool) {
        if repository == nil { repository = CallRepository(client: client) }
        self.signedIn = signedIn
        if signedIn { Task { await registerVoipIfPossible() } }
    }

    func accountChanged(signedIn: Bool) {
        self.signedIn = signedIn
        if signedIn {
            Task { await registerVoipIfPossible() }
        } else {
            historyByConversation = [:]
            historyLoadedAt = [:]
            lastVoipRegistration = nil
        }
    }

    /// Called before sign-out while the session can still authenticate.
    func signOut() async {
        if session != nil { hangUp() }
        if let id = defaults.string(forKey: Keys.registration), let repository {
            try? await repository.deleteVoip(registrationID: id)
        }
        defaults.removeObject(forKey: Keys.registration)
        lastVoipRegistration = nil
        historyByConversation = [:]
        historyLoadedAt = [:]
        signedIn = false
    }

    func updateCapabilities(_ caps: CallsCapabilities) {
        capabilities = caps
        let voip = caps.canCall && caps.voipPush
        defaults.set(voip, forKey: Keys.voipEnabled)
        if voip {
            startPushKit()
            Task { await registerVoipIfPossible() }
        } else {
            pushKit?.stop()
            pushKit = nil
        }
    }

    func canStartCall(_ kind: CallMediaKind) -> Bool { capabilities.allows(kind) && session == nil }

    // MARK: PushKit

    private func startPushKit() {
        guard pushKit == nil else { return }
        pushKit = VoipPushBridge()
    }

    func voipTokenUpdated(_ token: String?) {
        voipToken = token
        lastVoipRegistration = nil
        Task { await registerVoipIfPossible() }
    }

    /// The ordinary APNs device registration id, which proves the device to the VoIP route.
    func pushDeviceRegistered(_ deviceID: String) {
        defaults.set(deviceID, forKey: Keys.pushDevice)
        Task { await registerVoipIfPossible() }
    }

    private func registerVoipIfPossible() async {
        guard signedIn, capabilities.canCall, capabilities.voipPush, let repository, let token = voipToken,
              let device = defaults.string(forKey: Keys.pushDevice) else { return }
        let marker = "\(device)|\(token)"
        guard lastVoipRegistration != marker else { return }
        lastVoipRegistration = marker
        do {
            let id = try await repository.registerVoip(deviceID: device, token: token, environment: PushAPI.environment)
            defaults.set(id, forKey: Keys.registration)
        } catch {
            lastVoipRegistration = nil
        }
    }

    /// Every VoIP push must reach CallKit before this returns, or iOS ends the app and stops
    /// delivering VoIP pushes. Unknown or stale pushes are reported and ended at once.
    func handleVoipPush(_ payload: [AnyHashable: Any]) {
        let push = CallPayloadDecoder.incomingPush(payload)
        let bridge = callKitBridge()
        CallMediaEngine.prepareAudioSessionForCallKit()
        guard let push, let uuid = UUID(uuidString: push.callID) else {
            let throwaway = UUID()
            bridge.reportIncoming(uuid: throwaway, name: "Modula", handle: "modula", video: false)
            bridge.reportEnded(uuid: throwaway, reason: .failed)
            return
        }
        if let current = session {
            // Already ringing from the messaging socket: re-reporting satisfies PushKit.
            bridge.reportIncoming(uuid: uuid, name: push.caller.name, handle: push.caller.handle, video: push.mediaKind == .video)
            if current.record.id != push.callID { bridge.reportEnded(uuid: uuid, reason: .failed) }
            return
        }
        let placeholder = CallRecord(
            id: push.callID, conversationID: push.conversationID, mediaKind: push.mediaKind, state: .ringing, revision: 0,
            initiatorActorID: push.caller.id, recipientActorID: "", direction: .incoming, other: push.caller,
            ringDeadlineAt: push.ringDeadlineAt, stateDeadlineAt: push.ringDeadlineAt, acceptedAt: nil, connectedAt: nil,
            endedAt: nil, terminalReason: nil, durationMs: nil, createdAt: Date(), answeredHere: nil
        )
        session = Session(record: placeholder, phase: .incomingRinging)
        isMinimized = false
        bridge.reportIncoming(uuid: uuid, name: push.caller.name, handle: push.caller.handle, video: push.mediaKind == .video)
        startWatchdog()
        let id = push.callID
        Task { await reconcile(callID: id, waitForRepository: true) }
    }

    // MARK: Realtime (foreground ringing without PushKit)

    func handleRealtime(_ update: CallRealtimeUpdate) {
        if let current = session, current.record.id == update.callID {
            if update.state.isTerminal || update.revision > current.record.revision {
                Task { await reconcile(callID: update.callID) }
            }
        } else if session == nil, update.state == .ringing, update.event == "started", capabilities.canCall {
            Task { await presentIncoming(callID: update.callID) }
        }
        if update.state.isTerminal {
            Task { await loadHistory(update.conversationID, force: true) }
        }
    }

    private func presentIncoming(callID: CallID) async {
        guard let repository, let record = try? await repository.call(callID),
              record.direction == .incoming, record.state == .ringing, session == nil, let uuid = record.uuid else { return }
        CallMediaEngine.prepareAudioSessionForCallKit()
        session = Session(record: record, phase: .incomingRinging)
        isMinimized = false
        callKitBridge().reportIncoming(uuid: uuid, name: record.other.name, handle: record.other.handle, video: record.mediaKind == .video)
        startWatchdog()
    }

    // MARK: User actions

    func startCall(conversationID: String, mediaKind: CallMediaKind) async {
        lastError = nil
        guard session == nil else { lastError = "You’re already on a call."; return }
        guard capabilities.allows(mediaKind), let repository else { return }
        guard await Self.requestPermissions(for: mediaKind) else {
            lastError = mediaKind == .video
                ? "Allow camera and microphone access for Modula in Settings to video call."
                : "Allow microphone access for Modula in Settings to call."
            HapticEngine.shared.play(.failure)
            return
        }
        do {
            let result = try await repository.start(conversationID: conversationID, mediaKind: mediaKind, deviceID: nil)
            guard session == nil, let uuid = result.call.uuid else { return }
            CallMediaEngine.prepareAudioSessionForCallKit()
            if result.glare || result.call.direction == .incoming {
                // They called at the same moment: answer their call instead of ringing back.
                session = Session(record: result.call, phase: .incomingRinging)
                callKitBridge().reportIncoming(uuid: uuid, name: result.call.other.name, handle: result.call.other.handle, video: result.call.mediaKind == .video)
                startWatchdog()
                answer()
                return
            }
            session = Session(record: result.call, phase: .outgoingRinging)
            isMinimized = false
            HapticEngine.shared.play(.confirmation)
            callKitBridge().requestStart(uuid: uuid, name: result.call.other.name, handle: result.call.other.handle, video: mediaKind == .video)
            startWatchdog()
            await prepareMedia(for: result.call)
        } catch {
            lastError = CallCopy.errorMessage(error)
            HapticEngine.shared.play(.failure)
        }
    }

    func answer() {
        guard let current = session, current.phase == .incomingRinging, let uuid = current.record.uuid else { return }
        callKitBridge().requestAnswer(uuid: uuid)
    }

    func hangUp() {
        guard let current = session, let uuid = current.record.uuid else { return }
        if case .ended = current.phase { return }
        callKitBridge().requestEnd(uuid: uuid)
    }

    func toggleMute() {
        guard let current = session, let uuid = current.record.uuid else { return }
        callKitBridge().requestMute(uuid: uuid, muted: !(media?.isMuted ?? callKitMuted))
    }

    func toggleSpeaker() {
        guard let media else { return }
        media.setSpeaker(!media.isSpeakerOn)
    }

    func toggleCamera() {
        guard let media else { return }
        media.setCamera(on: !media.isCameraOn)
    }

    func flipCamera() { media?.flipCamera() }

    func dismissError() { lastError = nil }

    static func requestPermissions(for kind: CallMediaKind) async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        if kind == .video { return await AVCaptureDevice.requestAccess(for: .video) }
        return true
    }

    // MARK: History

    func history(for conversationID: String) -> [CallRecord] { historyByConversation[conversationID] ?? [] }

    func loadHistory(_ conversationID: String, force: Bool = false) async {
        guard capabilities.enabled, let repository else { return }
        if !force, let loaded = historyLoadedAt[conversationID], Date().timeIntervalSince(loaded) < 30 { return }
        historyLoadedAt[conversationID] = Date()
        guard let page = try? await repository.history(conversationID: conversationID) else { return }
        historyByConversation[conversationID] = page.items
    }

    private func remember(_ record: CallRecord) {
        var items = historyByConversation[record.conversationID] ?? []
        items.removeAll { $0.id == record.id }
        items.insert(record, at: 0)
        historyByConversation[record.conversationID] = items
    }

    // MARK: CallKit actions (main queue)

    fileprivate func perform(start action: CXStartCallAction) {
        guard let current = session, current.record.uuid == action.callUUID else { action.fail(); return }
        CallMediaEngine.configureAudioSession(for: current.record.mediaKind)
        callKitBridge().provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        action.fulfill()
    }

    fileprivate func perform(answer action: CXAnswerCallAction) {
        guard let current = session, current.record.uuid == action.callUUID, current.phase == .incomingRinging, let repository else {
            action.fail(); return
        }
        CallMediaEngine.configureAudioSession(for: current.record.mediaKind)
        pendingAnswer = action
        session?.phase = .connecting
        isMinimized = false
        let id = current.record.id
        let kind = current.record.mediaKind
        Task {
            guard await Self.requestPermissions(for: kind) else {
                self.failAnswer(id, message: "Allow microphone access for Modula in Settings to answer calls.")
                return
            }
            do {
                let record = try await repository.command(.accept, callID: id)
                guard self.session?.record.id == id else { return }
                self.pendingAnswer?.fulfill()
                self.pendingAnswer = nil
                self.apply(record)
                await self.prepareMedia(for: record)
            } catch {
                self.failAnswer(id, message: CallCopy.errorMessage(error))
            }
        }
    }

    private func failAnswer(_ id: CallID, message: String) {
        pendingAnswer?.fail()
        pendingAnswer = nil
        guard session?.record.id == id else { return }
        endedLocally.insert(id)
        lastError = message
        finish(record: nil, state: .failed, label: message)
        Task { await reconcileHistory(id) }
    }

    fileprivate func perform(end action: CXEndCallAction) {
        action.fulfill()
        endCurrentCall(uuid: action.callUUID)
    }

    /// Ends the current call locally and tells the server (decline, cancel or end).
    fileprivate func endCurrentCall(uuid: UUID) {
        guard let current = session, current.record.uuid == uuid else { return }
        if case .ended = current.phase { return }
        let id = current.record.id
        endedLocally.insert(id)
        let command: CallCommand
        let state: CallState
        if current.record.state == .ringing && current.phase != .connecting {
            command = current.record.direction == .incoming ? .decline : .cancel
            state = current.record.direction == .incoming ? .declined : .cancelled
        } else {
            command = .end
            state = .ended
        }
        if let pendingAnswer { pendingAnswer.fail(); self.pendingAnswer = nil }
        finish(record: nil, state: state, label: nil)
        guard let repository else { return }
        Task {
            if let record = try? await repository.command(command, callID: id) { self.remember(record) }
            else { await self.reconcileHistory(id) }
        }
    }

    fileprivate func perform(mute action: CXSetMutedCallAction) {
        callKitMuted = action.isMuted
        media?.setMuted(action.isMuted)
        action.fulfill()
    }

    fileprivate func providerDidReset() {
        teardownMedia()
        session = nil
        pendingAnswer = nil
    }

    fileprivate func audioActivated(_ audioSession: AVAudioSession) { CallMediaEngine.audioSessionActivated(audioSession) }
    fileprivate func audioDeactivated(_ audioSession: AVAudioSession) { CallMediaEngine.audioSessionDeactivated(audioSession) }

    fileprivate func incomingReportFailed(_ callID: CallID) {
        // CallKit refused the call (Do Not Disturb, blocked, or already reported elsewhere).
        guard let current = session, current.record.id == callID, current.phase == .incomingRinging else { return }
        teardownMedia()
        session = nil
    }

    fileprivate func startRequestFailed(_ callID: CallID) {
        guard session?.record.id == callID else { return }
        endedLocally.insert(callID)
        finish(record: nil, state: .failed, label: "Couldn’t start the call.")
        if let repository { Task { _ = try? await repository.command(.cancel, callID: callID) } }
    }

    private func callKitBridge() -> CallKitBridge {
        if let callKit { return callKit }
        let bridge = CallKitBridge()
        callKit = bridge
        return bridge
    }

    // MARK: Media and signalling

    private func prepareMedia(for record: CallRecord) async {
        guard let repository, media == nil else { return }
        do {
            let ice = try await repository.iceConfig(callID: record.id)
            guard session?.record.id == record.id, media == nil else { return }
            let engine = CallMediaEngine(mediaKind: record.mediaKind)
            engine.onLocalCandidate = { [weak self] candidate in self?.sendLocalCandidate(candidate) }
            engine.onConnectionChange = { [weak self] state in self?.mediaChanged(state) }
            guard engine.start(ice: ice) else { throw APIError.invalidResponse }
            if callKitMuted { engine.setMuted(true) }
            media = engine
            await connectSignalling(callID: record.id)
        } catch {
            await failCall(record.id, message: CallCopy.errorMessage(error))
        }
    }

    private func connectSignalling(callID: CallID) async {
        guard let repository, session?.record.id == callID else { return }
        do {
            let ticket = try await repository.ticket(callID: callID)
            let request = try await repository.signallingRequest(callID: callID, ticket: ticket)
            guard session?.record.id == callID else { return }
            let client = signalling ?? CallSignallingClient(callID: callID)
            client.onEvent = { [weak self] event in self?.handleSignal(event, callID: callID) }
            signalling = client
            client.connect(request)
        } catch {
            scheduleSignallingRetry(callID)
        }
    }

    private func scheduleSignallingRetry(_ callID: CallID) {
        guard let current = session, current.record.id == callID, !current.record.state.isTerminal else { return }
        if case .ended = current.phase { return }
        signallingAttempts += 1
        guard signallingAttempts <= 6 else {
            Task { await reconcile(callID: callID) }
            return
        }
        let delay = min(8.0, pow(2.0, Double(signallingAttempts - 1)))
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard self.session?.record.id == callID, self.signalling?.isOpen != true else { return }
            await self.connectSignalling(callID: callID)
        }
    }

    private func handleSignal(_ event: CallSignallingClient.Event, callID: CallID) {
        guard session?.record.id == callID else { return }
        switch event {
        case .ready(let actorID, _, let call):
            myActorID = actorID
            signallingAttempts = 0
            if let call { apply(call) }
            flushLocalCandidates()
            maybeSendOffer()
        case .snapshot(let call):
            apply(call)
        case .accepted(let call):
            if let call { apply(call) }
            maybeSendOffer()
        case .terminal(let state, let call):
            finish(record: call, state: state, label: nil)
        case .offer(let sdp, let negotiation):
            answerOffer(sdp, negotiation: negotiation)
        case .answer(let sdp, let negotiation):
            guard negotiation == negotiationID, appliedAnswerNegotiation != negotiation, let media else { return }
            appliedAnswerNegotiation = negotiation
            lastOffer = nil
            Task { try? await media.acceptAnswer(sdp) }
        case .ack(let messageID, let relayed):
            if relayed == false, let offer = lastOffer, offer.messageID == messageID { resendOffer(offer.negotiation) }
        case .candidate(let candidate, let negotiation):
            if negotiation == negotiationID {
                media?.addRemoteCandidate(candidate)
            } else if earlyRemoteCandidates.count < 4, (earlyRemoteCandidates[negotiation]?.count ?? 0) < 256 {
                earlyRemoteCandidates[negotiation, default: []].append(candidate)
            }
        case .reconnectRequired(let owner):
            session?.phase = .reconnecting
            if let owner, owner == myActorID { restartIce() }
        case .error(let code):
            if code == "CALL_ALREADY_TERMINAL" || code == "CALL_ALREADY_ANSWERED" {
                Task { await reconcile(callID: callID) }
            }
        case .closed(let code):
            signalling = nil
            if code == 4403 { Task { await reconcile(callID: callID) } }
            else { scheduleSignallingRetry(callID) }
        }
    }

    private func maybeSendOffer() {
        guard let current = session, current.record.direction == .outgoing, current.record.state == .connecting,
              !offerSent, let media, let signalling, signalling.isOpen else { return }
        offerSent = true
        let negotiation = CallSignalling.newNegotiationID()
        negotiationID = negotiation
        reportedConnectedNegotiation = nil
        holdLocalCandidates = true
        Task {
            do {
                let sdp = try await media.makeOffer()
                if let messageID = self.signalling?.sendOffer(sdp: sdp, negotiationID: negotiation) {
                    self.lastOffer = (messageID, negotiation)
                    self.offerResends = 0
                }
            } catch {
                self.offerSent = false
            }
            self.holdLocalCandidates = false
            self.flushLocalCandidates()
        }
    }

    private func answerOffer(_ sdp: String, negotiation: String) {
        guard let media else { return }
        if let answered, answered.negotiation == negotiation {
            // The caller re-sent its offer (our socket joined late); repeat the same answer.
            signalling?.sendAnswer(sdp: answered.sdp, negotiationID: negotiation)
            return
        }
        if negotiation != negotiationID {
            negotiationID = negotiation
            reportedConnectedNegotiation = nil
            media.beginRenegotiation()
        }
        holdLocalCandidates = true
        let early = earlyRemoteCandidates.removeValue(forKey: negotiation) ?? []
        earlyRemoteCandidates = [:]
        Task {
            do {
                let answer = try await media.acceptOffer(sdp)
                self.answered = (negotiation, answer)
                self.signalling?.sendAnswer(sdp: answer, negotiationID: negotiation)
                for candidate in early { media.addRemoteCandidate(candidate) }
            } catch {
                await self.failCall(self.session?.record.id ?? "", message: "Couldn’t connect the call.")
            }
            self.holdLocalCandidates = false
            self.flushLocalCandidates()
        }
    }

    /// The lexically lower actor owns the ICE-restart offer while reconnecting (server rule).
    private func restartIce() {
        guard let media, let signalling, signalling.isOpen else { return }
        let negotiation = CallSignalling.newNegotiationID()
        negotiationID = negotiation
        reportedConnectedNegotiation = nil
        media.beginRenegotiation()
        holdLocalCandidates = true
        Task {
            if let sdp = try? await media.makeOffer(iceRestart: true),
               let messageID = self.signalling?.sendOffer(sdp: sdp, negotiationID: negotiation) {
                self.lastOffer = (messageID, negotiation)
                self.offerResends = 0
            }
            self.holdLocalCandidates = false
            self.flushLocalCandidates()
        }
    }

    /// The offer reached the server while the other phone's socket was not connected yet.
    /// Re-send the current local description (which now carries gathered candidates).
    private func resendOffer(_ negotiation: String) {
        guard offerResends < 30 else { return }
        offerResends += 1
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard self.negotiationID == negotiation, self.appliedAnswerNegotiation != negotiation,
                  let sdp = self.media?.localSDP,
                  let messageID = self.signalling?.sendOffer(sdp: sdp, negotiationID: negotiation) else { return }
            self.lastOffer = (messageID, negotiation)
        }
    }

    private func sendLocalCandidate(_ candidate: CallIceCandidate) {
        guard let negotiation = negotiationID else { return }
        if holdLocalCandidates || signalling?.isOpen != true {
            if pendingLocalCandidates.count < 128 { pendingLocalCandidates.append((candidate, negotiation)) }
            return
        }
        signalling?.sendCandidate(candidate, negotiationID: negotiation)
    }

    private func flushLocalCandidates() {
        guard !holdLocalCandidates, let signalling, signalling.isOpen else { return }
        let queued = pendingLocalCandidates
        pendingLocalCandidates = []
        for (candidate, negotiation) in queued where negotiation == negotiationID {
            signalling.sendCandidate(candidate, negotiationID: negotiation)
        }
    }

    private func mediaChanged(_ state: CallMediaConnection) {
        guard let current = session else { return }
        switch state {
        case .connected:
            guard let negotiation = negotiationID, reportedConnectedNegotiation != negotiation else { return }
            reportedConnectedNegotiation = negotiation
            signalling?.sendMediaConnected(negotiationID: negotiation, relay: nil, audio: !(media?.isMuted ?? false), video: media?.isCameraOn ?? false)
            if session?.connectedAt == nil { session?.connectedAt = Date() }
            session?.phase = .active
            if current.record.direction == .outgoing, !outgoingConnectedReported, let uuid = current.record.uuid {
                outgoingConnectedReported = true
                callKitBridge().provider.reportOutgoingCall(with: uuid, connectedAt: Date())
            }
        case .disconnected, .failed:
            guard let negotiation = negotiationID, current.phase == .active || current.phase == .reconnecting else { return }
            reportedConnectedNegotiation = nil
            session?.phase = .reconnecting
            signalling?.sendMediaDisconnected(negotiationID: negotiation, reason: state == .failed ? "ice_failed" : "ice_disconnected")
        case .new, .checking, .closed:
            break
        }
    }

    // MARK: State

    private func apply(_ record: CallRecord) {
        guard var current = session, current.record.id == record.id else { return }
        if record.state.isTerminal {
            finish(record: record, state: record.state, label: nil)
            return
        }
        if record.direction == .incoming, record.state != .ringing, record.answeredHere == false {
            // Answered on another device signed in to this account.
            finish(record: record, state: record.state, label: "Answered on another device", reason: .answeredElsewhere)
            return
        }
        guard record.revision >= current.record.revision else { return }
        let wasRinging = current.phase == .outgoingRinging
        current.record = record
        switch record.state {
        case .ringing:
            current.phase = record.direction == .outgoing ? .outgoingRinging : (current.phase == .connecting ? .connecting : .incomingRinging)
        case .connecting:
            if current.phase != .active { current.phase = .connecting }
        case .active:
            current.phase = .active
            current.connectedAt = current.connectedAt ?? record.connectedAt ?? Date()
        case .reconnecting:
            current.phase = .reconnecting
        default:
            break
        }
        session = current
        if wasRinging, record.state == .connecting, let uuid = record.uuid {
            callKitBridge().provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
        }
        maybeSendOffer()
    }

    private func reconcile(callID: CallID, waitForRepository: Bool = false) async {
        var attempts = 0
        while repository == nil, waitForRepository, attempts < 50 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let repository else {
            await failCall(callID, message: "Sign in to Modula to answer calls.")
            return
        }
        do {
            let record = try await repository.call(callID)
            apply(record)
        } catch APIError.rejected(404, _) {
            await failCall(callID, message: "This call is no longer available.")
        } catch APIError.unauthenticated {
            await failCall(callID, message: "Sign in to Modula to answer calls.")
        } catch {
            // Network blip: the watchdog tries again.
        }
    }

    private func reconcileHistory(_ callID: CallID) async {
        guard let repository, let record = try? await repository.call(callID) else { return }
        remember(record)
    }

    private func failCall(_ callID: CallID, message: String) async {
        guard let current = session, current.record.id == callID else { return }
        if case .ended = current.phase { return }
        let wasLive = !current.record.state.isTerminal
        lastError = message
        finish(record: nil, state: .failed, label: message)
        if wasLive, let repository, current.record.revision > 0 {
            let command: CallCommand = current.record.state == .ringing
                ? (current.record.direction == .incoming ? .decline : .cancel) : .end
            _ = try? await repository.command(command, callID: callID, reason: command == .end ? "media_failed" : nil)
        }
    }

    private func finish(record: CallRecord?, state: CallState, label: String?, reason: CXCallEndedReason? = nil) {
        guard var current = session else { return }
        if let record, record.id != current.record.id { return }
        if case .ended = current.phase { return }
        var final = record ?? current.record
        if record == nil {
            final.state = state
            final.endedAt = Date()
            if let connected = current.connectedAt { final.durationMs = Int(Date().timeIntervalSince(connected) * 1000) }
        }
        let local = endedLocally.contains(final.id)
        teardownMedia()
        if let uuid = final.uuid, !local {
            callKitBridge().reportEnded(uuid: uuid, reason: reason ?? Self.endedReason(for: final))
        }
        current.record = final
        current.phase = .ended(label ?? Self.endedLabel(for: final))
        session = current
        if final.revision > 0 { remember(final) }
        HapticEngine.shared.play(final.state == .failed ? .failure : .confirmation)
        let id = final.id
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard self.session?.record.id == id else { return }
            self.session = nil
            self.isMinimized = false
            self.endedLocally.remove(id)
        }
    }

    private func teardownMedia() {
        watchdog?.cancel(); watchdog = nil
        media?.close(); media = nil
        signalling?.onEvent = nil
        signalling?.close(); signalling = nil
        negotiationID = nil
        lastOffer = nil
        offerResends = 0
        answered = nil
        appliedAnswerNegotiation = nil
        offerSent = false
        reportedConnectedNegotiation = nil
        outgoingConnectedReported = false
        holdLocalCandidates = false
        pendingLocalCandidates = []
        earlyRemoteCandidates = [:]
        signallingAttempts = 0
        callKitMuted = false
    }

    /// Reconciles with the server while the socket is down or a deadline has passed, so a lost
    /// event never leaves a phantom call on screen. Timeouts themselves are server-owned.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled, let current = self.session else { return }
                if case .ended = current.phase { return }
                let overdue = current.record.stateDeadlineAt.map { Date() > $0.addingTimeInterval(2) } ?? false
                if self.signalling?.isOpen != true || overdue {
                    await self.reconcile(callID: current.record.id)
                }
            }
        }
    }

    static func endedReason(for record: CallRecord) -> CXCallEndedReason {
        switch record.state {
        case .missed: .unanswered
        case .failed: .failed
        case .declined: record.direction == .incoming ? .declinedElsewhere : .remoteEnded
        default: .remoteEnded
        }
    }

    static func endedLabel(for record: CallRecord) -> String {
        switch record.state {
        case .declined: return record.direction == .incoming ? "Declined" : "Call declined"
        case .cancelled: return record.direction == .incoming ? "Missed call" : "Cancelled"
        case .missed: return record.direction == .incoming ? "Missed call" : "No answer"
        case .failed: return "Call failed"
        default:
            if let ms = record.durationMs, ms > 0 { return "Call ended · \(CallCopy.duration(ms: ms))" }
            return "Call ended"
        }
    }
}

// MARK: - CallKit

/// CallKit delivers on the main queue (`queue: nil`), so the conformance is main-actor isolated;
/// `@preconcurrency` adds a runtime check instead of hopping.
@MainActor
final class CallKitBridge: NSObject, @preconcurrency CXProviderDelegate {
    let provider: CXProvider
    private let controller = CXCallController()

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        // Keep Modula calls out of the Phone app's Recents (and iCloud call history).
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    private static func update(name: String, handle: String, video: Bool) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle.isEmpty ? name : "@\(handle)")
        update.localizedCallerName = name
        update.hasVideo = video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    func reportIncoming(uuid: UUID, name: String, handle: String, video: Bool) {
        let id = uuid.uuidString.lowercased()
        provider.reportNewIncomingCall(with: uuid, update: Self.update(name: name, handle: handle, video: video)) { @Sendable error in
            guard let error else { return }
            if let callError = error as? CXErrorCodeIncomingCallError, callError.code == .callUUIDAlreadyExists { return }
            Task { @MainActor in CallManager.shared.incomingReportFailed(id) }
        }
    }

    func reportEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    func requestStart(uuid: UUID, name: String, handle: String, video: Bool) {
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: handle.isEmpty ? name : "@\(handle)"))
        action.isVideo = video
        let id = uuid.uuidString.lowercased()
        controller.request(CXTransaction(action: action)) { @Sendable error in
            guard error != nil else { return }
            Task { @MainActor in CallManager.shared.startRequestFailed(id) }
        }
        provider.reportCall(with: uuid, updated: Self.update(name: name, handle: handle, video: video))
    }

    func requestAnswer(uuid: UUID) {
        controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { @Sendable _ in }
    }

    func requestEnd(uuid: UUID) {
        let id = uuid
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { @Sendable error in
            guard error != nil else { return }
            // CallKit no longer knows the call (already ended there): end it here directly.
            Task { @MainActor in CallManager.shared.endWithoutCallKit(id) }
        }
    }

    func requestMute(uuid: UUID, muted: Bool) {
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))) { @Sendable _ in }
    }

    func providerDidReset(_ provider: CXProvider) { CallManager.shared.providerDidReset() }
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) { CallManager.shared.perform(start: action) }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) { CallManager.shared.perform(answer: action) }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) { CallManager.shared.perform(end: action) }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) { CallManager.shared.perform(mute: action) }
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) { action.fail() }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) { CallManager.shared.audioActivated(audioSession) }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) { CallManager.shared.audioDeactivated(audioSession) }
}

extension CallManager {
    fileprivate func endWithoutCallKit(_ uuid: UUID) {
        // CallKit has no record of the call, so there is no action to fulfil.
        endCurrentCall(uuid: uuid)
    }
}

// MARK: - PushKit

/// PushKit delivers on the main queue. Registered only while the server reports VoIP calls on.
@MainActor
final class VoipPushBridge: NSObject, @preconcurrency PKPushRegistryDelegate {
    private let registry: PKPushRegistry

    override init() {
        registry = PKPushRegistry(queue: .main)
        super.init()
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    func stop() {
        registry.desiredPushTypes = []
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        CallManager.shared.voipTokenUpdated(pushCredentials.token.map { String(format: "%02x", $0) }.joined())
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        CallManager.shared.voipTokenUpdated(nil)
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        defer { completion() }
        guard type == .voIP else { return }
        CallManager.shared.handleVoipPush(payload.dictionaryPayload)
    }
}
