import AVFoundation
import Foundation
import Observation
@preconcurrency import WebRTC

enum CallMediaConnection: Sendable, Equatable {
    case new, checking, connected, disconnected, failed, closed
}

/// WebRTC peer connection for one 1:1 call: Opus audio, optional camera video, trickle ICE,
/// ICE restart for network changes. Media is DTLS-SRTP between the two phones (or via TURN,
/// which relays encrypted packets it cannot read). This is transport encryption, not a
/// verified end-to-end identity, and the UI never claims otherwise.
@MainActor @Observable
final class CallMediaEngine {
    private(set) var connection: CallMediaConnection = .new
    private(set) var localVideoTrack: RTCVideoTrack?
    private(set) var remoteVideoTrack: RTCVideoTrack?
    private(set) var isMuted = false
    private(set) var isCameraOn = false
    private(set) var isFrontCamera = true
    private(set) var isSpeakerOn = false

    /// Local ICE candidates to send over signalling.
    @ObservationIgnored var onLocalCandidate: ((CallIceCandidate) -> Void)?
    @ObservationIgnored var onConnectionChange: ((CallMediaConnection) -> Void)?

    @ObservationIgnored private var peer: RTCPeerConnection?
    @ObservationIgnored private var observer: PeerObserver?
    @ObservationIgnored private var audioTrack: RTCAudioTrack?
    @ObservationIgnored private var videoSource: RTCVideoSource?
    @ObservationIgnored private var capturer: RTCCameraVideoCapturer?
    @ObservationIgnored private var pendingRemoteCandidates: [CallIceCandidate] = []
    @ObservationIgnored private var hasRemoteDescription = false
    @ObservationIgnored let mediaKind: CallMediaKind

    private static let factory: RTCPeerConnectionFactory = {
        _ = RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    init(mediaKind: CallMediaKind) {
        self.mediaKind = mediaKind
        isSpeakerOn = mediaKind == .video
    }

    /// CallKit owns audio-session activation; WebRTC must wait for `didActivate`.
    static func prepareAudioSessionForCallKit() {
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = true
        session.isAudioEnabled = false
    }

    static func configureAudioSession(for kind: CallMediaKind) {
        let session = RTCAudioSession.sharedInstance()
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = kind == .video ? AVAudioSession.Mode.videoChat.rawValue : AVAudioSession.Mode.voiceChat.rawValue
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.setConfiguration(configuration)
    }

    static func audioSessionActivated(_ audioSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.audioSessionDidActivate(audioSession)
        session.isAudioEnabled = true
    }

    static func audioSessionDeactivated(_ audioSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.audioSessionDidDeactivate(audioSession)
        session.isAudioEnabled = false
    }

    // MARK: Lifecycle

    func start(ice: CallIceConfig) -> Bool {
        guard peer == nil else { return true }
        let configuration = RTCConfiguration()
        configuration.iceServers = ice.servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.iceTransportPolicy = ice.relayOnly ? .relay : .all
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        let observer = PeerObserver { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let made: RTCPeerConnection? = Self.factory.peerConnection(with: configuration, constraints: constraints, delegate: observer)
        guard let peer = made else { return false }
        self.observer = observer
        self.peer = peer

        let audioSource = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audio = Self.factory.audioTrack(with: audioSource, trackId: "modula-audio")
        audio.isEnabled = !isMuted
        _ = peer.add(audio, streamIds: ["modula"])
        audioTrack = audio

        if mediaKind == .video {
            let source = Self.factory.videoSource()
            let track = Self.factory.videoTrack(with: source, trackId: "modula-video")
            _ = peer.add(track, streamIds: ["modula"])
            videoSource = source
            capturer = RTCCameraVideoCapturer(delegate: source)
            localVideoTrack = track
            setCamera(on: true)
        }
        applySpeaker()
        return true
    }

    func close() {
        capturer?.stopCapture()
        capturer = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        videoSource = nil
        audioTrack = nil
        peer?.close()
        peer = nil
        observer = nil
        pendingRemoteCandidates = []
        hasRemoteDescription = false
        connection = .closed
    }

    // MARK: Negotiation

    func makeOffer(iceRestart: Bool = false) async throws -> String {
        guard let peer else { throw APIError.invalidResponse }
        if iceRestart { peer.restartIce() }
        let constraints = offerConstraints
        // Completions run on WebRTC's signalling thread. They are @Sendable so they never
        // inherit (and dynamically assert) main-actor isolation; only the SDP string crosses.
        let sdp: String = try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: constraints, completionHandler: { @Sendable description, error in
                if let sdp = description?.sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: error ?? APIError.invalidResponse) }
            })
        }
        try await setLocal(RTCSessionDescription(type: .offer, sdp: sdp))
        return sdp
    }

    func acceptOffer(_ sdp: String) async throws -> String {
        guard let peer else { throw APIError.invalidResponse }
        try await setRemote(RTCSessionDescription(type: .offer, sdp: sdp))
        let constraints = offerConstraints
        let answer: String = try await withCheckedThrowingContinuation { continuation in
            peer.answer(for: constraints, completionHandler: { @Sendable description, error in
                if let sdp = description?.sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: error ?? APIError.invalidResponse) }
            })
        }
        try await setLocal(RTCSessionDescription(type: .answer, sdp: answer))
        return answer
    }

    func acceptAnswer(_ sdp: String) async throws {
        try await setRemote(RTCSessionDescription(type: .answer, sdp: sdp))
    }

    func addRemoteCandidate(_ candidate: CallIceCandidate) {
        guard hasRemoteDescription, let peer else {
            if pendingRemoteCandidates.count < 256 { pendingRemoteCandidates.append(candidate) }
            return
        }
        let ice = RTCIceCandidate(sdp: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
        peer.add(ice, completionHandler: { @Sendable _ in })
    }

    /// Current local description, including every candidate gathered so far. Re-sent when the
    /// first offer reached the server before the other phone's socket was connected.
    var localSDP: String? { peer?.localDescription?.sdp }

    /// A new negotiation (ICE restart) starts with a fresh candidate queue.
    func beginRenegotiation() {
        hasRemoteDescription = false
        pendingRemoteCandidates = []
    }

    private var offerConstraints: RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: [
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveVideo: mediaKind == .video ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse,
        ], optionalConstraints: nil)
    }

    private func setLocal(_ description: RTCSessionDescription) async throws {
        guard let peer else { throw APIError.invalidResponse }
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            peer.setLocalDescription(description, completionHandler: { @Sendable error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func setRemote(_ description: RTCSessionDescription) async throws {
        guard let peer else { throw APIError.invalidResponse }
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            peer.setRemoteDescription(description, completionHandler: { @Sendable error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        hasRemoteDescription = true
        let queued = pendingRemoteCandidates
        pendingRemoteCandidates = []
        for candidate in queued { addRemoteCandidate(candidate) }
    }

    // MARK: Controls

    func setMuted(_ muted: Bool) {
        isMuted = muted
        audioTrack?.isEnabled = !muted
    }

    func setCamera(on: Bool) {
        guard mediaKind == .video, let capturer else { return }
        isCameraOn = on
        localVideoTrack?.isEnabled = on
        if on { startCapture(capturer) } else { capturer.stopCapture() }
    }

    func flipCamera() {
        guard mediaKind == .video, let capturer, isCameraOn else { return }
        isFrontCamera.toggle()
        startCapture(capturer)
    }

    func setSpeaker(_ on: Bool) {
        isSpeakerOn = on
        applySpeaker()
    }

    private func applySpeaker() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
    }

    private func startCapture(_ capturer: RTCCameraVideoCapturer) {
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == position })
                ?? RTCCameraVideoCapturer.captureDevices().first else { return }
        // ~720p keeps a 1:1 call sharp without burning battery or uplink.
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let format = formats.min { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return abs(Int(l.width) * Int(l.height) - 1280 * 720) < abs(Int(r.width) * Int(r.height) - 1280 * 720)
        }
        guard let format else { return }
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        capturer.startCapture(with: device, format: format, fps: Int(min(30, maxRate)))
    }

    // MARK: Peer events

    private func handle(_ event: PeerObserver.Event) {
        switch event {
        case .candidate(let candidate):
            onLocalCandidate?(candidate)
        case .connection(let state):
            guard state != connection else { return }
            connection = state
            onConnectionChange?(state)
        case .tracksChanged:
            refreshRemoteVideo()
        }
    }

    private func refreshRemoteVideo() {
        guard let peer else { remoteVideoTrack = nil; return }
        let track = peer.transceivers
            .first { $0.mediaType == .video }
            .flatMap { $0.receiver.track as? RTCVideoTrack }
        if track !== remoteVideoTrack { remoteVideoTrack = track }
    }
}

/// WebRTC calls its delegate on the signalling thread. Only Sendable values leave this object;
/// the engine hops to the main actor before touching state.
private final class PeerObserver: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case candidate(CallIceCandidate)
        case connection(CallMediaConnection)
        case tracksChanged
    }

    private let emit: @Sendable (Event) -> Void

    init(emit: @escaping @Sendable (Event) -> Void) {
        self.emit = emit
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) { emit(.tracksChanged) }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) { emit(.tracksChanged) }
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        emit(.candidate(CallIceCandidate(sdp: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let mapped: CallMediaConnection
        switch newState {
        case .new: mapped = .new
        case .checking: mapped = .checking
        case .connected, .completed: mapped = .connected
        case .disconnected: mapped = .disconnected
        case .failed: mapped = .failed
        case .closed: mapped = .closed
        default: return
        }
        emit(.connection(mapped))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        emit(.tracksChanged)
    }
}
