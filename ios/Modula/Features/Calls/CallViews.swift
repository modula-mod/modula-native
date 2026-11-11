import SwiftUI
import UIKit
@preconcurrency import WebRTC

// MARK: - Host

/// App-wide call surface. Generic: it only reads `CallManager` and knows nothing about the
/// screen underneath. Crisp, no-bounce transitions; plain fades under Reduce Motion.
struct CallOverlayHost: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var calls: CallManager { CallManager.shared }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let session = calls.session, !calls.isMinimized {
                    CallScreen(session: session)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(10)
                }
            }
            .overlay(alignment: .top) {
                if let session = calls.session, calls.isMinimized {
                    CallReturnPill(session: session)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(11)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28), value: calls.session?.record.id)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.24), value: calls.isMinimized)
            .alert(
                "Call",
                isPresented: Binding(get: { calls.lastError != nil && calls.session == nil }, set: { if !$0 { calls.dismissError() } }),
                actions: { Button("OK", role: .cancel) { calls.dismissError() } },
                message: { Text(calls.lastError ?? "") }
            )
    }
}

// MARK: - Full-screen call

struct CallScreen: View {
    let session: CallManager.Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var calls: CallManager { CallManager.shared }
    private var media: CallMediaEngine? { calls.media }
    private var record: CallRecord { session.record }
    private var showsRemoteVideo: Bool {
        record.mediaKind == .video && media?.remoteVideoTrack != nil && (session.phase == .active || session.phase == .reconnecting)
    }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if !showsRemoteVideo { identity.padding(.top, 48) }
                Spacer(minLength: 24)
                controls.padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
            if record.mediaKind == .video, let local = media?.localVideoTrack, media?.isCameraOn == true {
                CallVideoView(track: local, mirrored: media?.isFrontCamera ?? true)
                    .frame(width: 104, height: 152)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 64)
                    .padding(.trailing, 16)
                    .transition(.opacity)
                    .accessibilityLabel("Your camera")
            }
        }
        // Dark for this subtree only; `preferredColorScheme` would flip the whole window.
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("calls.screen")
    }

    @ViewBuilder
    private var backdrop: some View {
        if showsRemoteVideo, let remote = media?.remoteVideoTrack {
            CallVideoView(track: remote, mirrored: false)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).frame(height: 180)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).frame(height: 260)
                }
        } else {
            ZStack {
                Color.black
                if let url = record.other.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { Color.clear }
                    .blur(radius: 60)
                    .opacity(0.55)
                }
                LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var topBar: some View {
        HStack {
            if session.phase != .incomingRinging, !isEnded {
                Button {
                    calls.isMinimized = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(CallPressStyle())
                .accessibilityLabel("Minimise call")
            }
            Spacer()
            if showsRemoteVideo {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.other.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    CallStatusText(session: session).font(.caption)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: 52)
    }

    private var identity: some View {
        VStack(spacing: 14) {
            CallAvatar(party: record.other, size: 112)
            Text(record.other.name)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            CallStatusText(session: session)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var isEnded: Bool {
        if case .ended = session.phase { return true }
        return false
    }

    @ViewBuilder
    private var controls: some View {
        if session.phase == .incomingRinging {
            HStack(spacing: 72) {
                CallControlButton(symbol: "phone.down.fill", title: "Decline", style: .destructive) { calls.hangUp() }
                CallControlButton(symbol: record.mediaKind == .video ? "video.fill" : "phone.fill", title: "Accept", style: .accept) { calls.answer() }
            }
        } else if isEnded {
            CallControlButton(symbol: "phone.down.fill", title: "Ended", style: .destructive) {}
                .disabled(true)
                .opacity(0.5)
        } else {
            VStack(spacing: 28) {
                HStack(spacing: 22) {
                    CallControlButton(symbol: media?.isMuted == true ? "mic.slash.fill" : "mic.fill", title: "Mute",
                                      style: .toggle(media?.isMuted == true)) { calls.toggleMute() }
                    CallControlButton(symbol: "speaker.wave.2.fill", title: "Speaker",
                                      style: .toggle(media?.isSpeakerOn == true)) { calls.toggleSpeaker() }
                    if record.mediaKind == .video {
                        CallControlButton(symbol: media?.isCameraOn == false ? "video.slash.fill" : "video.fill", title: "Camera",
                                          style: .toggle(media?.isCameraOn == false)) { calls.toggleCamera() }
                        CallControlButton(symbol: "arrow.triangle.2.circlepath.camera.fill", title: "Flip", style: .toggle(false)) { calls.flipCamera() }
                            .disabled(media?.isCameraOn != true)
                    }
                }
                // Media controls wait for the engine; End is always available.
                .disabled(media == nil)
                CallControlButton(symbol: "phone.down.fill", title: "End", style: .destructive) { calls.hangUp() }
            }
        }
    }
}

struct CallStatusText: View {
    let session: CallManager.Session

    var body: some View {
        switch session.phase {
        case .outgoingRinging:
            Text("Ringing…")
        case .incomingRinging:
            Text(session.record.mediaKind == .video ? "Incoming video call" : "Incoming voice call")
        case .connecting:
            Text("Connecting…")
        case .reconnecting:
            Text("Reconnecting…")
        case .ended(let label):
            Text(label)
        case .active:
            if let start = session.connectedAt {
                // Only this label re-renders each second.
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(CallCopy.duration(ms: Int(context.date.timeIntervalSince(start) * 1000)))
                        .monospacedDigit()
                }
            } else {
                Text("Connected")
            }
        }
    }
}

struct CallAvatar: View {
    let party: CallParty
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.12))
            if let url = party.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(party.initials).font(.system(size: size * 0.36, weight: .semibold))
                }
            } else {
                Text(party.initials).font(.system(size: size * 0.36, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct CallControlButton: View {
    enum Style: Equatable {
        case toggle(Bool)
        case destructive
        case accept
    }

    let symbol: String
    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 66, height: 66)
                    .background { background }
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(CallPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var isOn: Bool { if case .toggle(true) = style { return true } else { return false } }

    private var foreground: Color {
        switch style {
        case .toggle(let on): on ? .black : .white
        case .destructive, .accept: .white
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .toggle(let on):
            if on { Circle().fill(.white) } else { Circle().fill(.ultraThinMaterial) }
        case .destructive:
            Circle().fill(Color.red)
        case .accept:
            Circle().fill(Color.green)
        }
    }
}

/// Quick, linear press feedback: no spring overshoot.
struct CallPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CallReturnPill: View {
    let session: CallManager.Session

    var body: some View {
        Button {
            CallManager.shared.isMinimized = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.record.mediaKind == .video ? "video.fill" : "phone.fill")
                Text(session.record.other.name).lineLimit(1)
                Text("·")
                CallStatusText(session: session)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.green.opacity(0.92), in: Capsule())
        }
        .buttonStyle(CallPressStyle())
        .padding(.top, 4)
        .accessibilityLabel("Return to call with \(session.record.other.name)")
    }
}

// MARK: - Video

/// Metal renderer for one WebRTC track. The coordinator keeps the renderer attached to exactly
/// one track and detaches it on teardown, so no frames are pushed to a dead view.
struct CallVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var mirrored = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        context.coordinator.attach(track, to: view)
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        context.coordinator.attach(track, to: view)
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.attach(nil, to: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var track: RTCVideoTrack?

        func attach(_ next: RTCVideoTrack?, to view: RTCMTLVideoView) {
            guard next !== track else { return }
            track?.remove(view)
            track = next
            next?.add(view)
        }
    }
}

// MARK: - Chat integration

/// Voice and video buttons for a 1:1 chat header. Rendered only when the server reports calls
/// enabled for this build's protocol; otherwise nothing is drawn (no disabled placeholder).
struct CallHeaderButtons: View {
    let conversationID: String
    private var calls: CallManager { CallManager.shared }

    var body: some View {
        HStack(spacing: 4) {
            if calls.capabilities.allows(.audio) {
                button(symbol: "phone", label: "Voice call", kind: .audio)
            }
            if calls.capabilities.allows(.video) {
                button(symbol: "video", label: "Video call", kind: .video)
            }
        }
    }

    private func button(symbol: String, label: String, kind: CallMediaKind) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            Task { await calls.startCall(conversationID: conversationID, mediaKind: kind) }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(calls.session != nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier("messages.conversation.call.\(kind.rawValue)")
    }
}

/// A call in the chat timeline ("Video call · 4:12", "Missed voice call").
struct CallHistoryRow: View {
    let record: CallRecord
    let canCallBack: Bool
    let onCallBack: (CallMediaKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CallCopy.isMissed(record) || record.state == .failed ? Color.red : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(CallCopy.historyTitle(record))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CallCopy.isMissed(record) ? Color.red : Color.primary)
                Text(record.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if canCallBack {
                Button {
                    onCallBack(record.mediaKind)
                } label: {
                    Image(systemName: record.mediaKind == .video ? "video.fill" : "phone.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(CallPressStyle())
                .accessibilityLabel(record.mediaKind == .video ? "Video call back" : "Call back")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, canCallBack ? 6 : 14)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("messages.call.\(record.id)")
    }

    private var symbol: String {
        if record.mediaKind == .video { return "video.fill" }
        if CallCopy.isMissed(record) { return "phone.arrow.down.left" }
        return record.direction == .outgoing ? "phone.arrow.up.right" : "phone.arrow.down.left"
    }
}
