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
        // Always visible in 1:1 chats; disabled ("coming soon") until the server turns calls on.
        HStack(spacing: 4) {
            button(symbol: "phone", label: "Voice call", kind: .audio)
            button(symbol: "video", label: "Video call", kind: .video)
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
        .disabled(calls.session != nil || !calls.capabilities.allows(kind))
        .opacity(calls.capabilities.allows(kind) ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityHint(calls.capabilities.allows(kind) ? "" : "Calling is coming soon")
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
                .foregroundStyle(Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(CallCopy.historyTitle(record))
                    .font(.footnote.weight(.semibold))
                    .fontWeight(CallCopy.isMissed(record) ? .bold : .semibold)
                    .foregroundStyle(Color.primary)
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
        .modulaGlass(in: Capsule(), interactive: false)
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

// MARK: - Calls tab (Messages › Calls): Favourites / Recents / Contacts / Keypad

/// Phone-style calling inside Messaging. Everything is gated on the server's `calls` capability:
/// without it the screens still show (history empty, keypad visible) but every call control is
/// disabled with a "Calling is coming soon" note. Modula call IDs are app IDs, not phone numbers.
struct CallsHomeView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favourites, recents, contacts, keypad
        var id: String { rawValue }
        var title: String {
            switch self {
            case .favourites: "Favourites"
            case .recents: "Recents"
            case .contacts: "Contacts"
            case .keypad: "Keypad"
            }
        }
        var symbol: String {
            switch self {
            case .favourites: "star.fill"
            case .recents: "clock.fill"
            case .contacts: "person.crop.circle.fill"
            case .keypad: "circle.grid.3x3.fill"
            }
        }
    }

    @Environment(AppEnvironment.self) private var app
    @AppStorage("calls.tab") private var tabRaw = Tab.recents.rawValue
    private var tab: Tab { Tab(rawValue: tabRaw) ?? .recents }

    var body: some View {
        VStack(spacing: 0) {
            MessagesScopePicker(selection: .calls)
            if !app.calls.capabilities.canCall { CallsComingSoonCard().padding(.horizontal, ModulaLayout.contentInset).padding(.bottom, 6) }
            Group {
                switch tab {
                case .favourites: CallsFavouritesList()
                case .recents: CallsRecentsList()
                case .contacts: CallsContactsList()
                case .keypad: CallsKeypad()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .modulaSoftScrollEdge()
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.messaging.probeCapabilities()
            await app.messaging.loadInboxIfNeeded()
        }
        .accessibilityIdentifier("calls.home")
    }

    /// Apple Phone-style bottom switcher, in glass.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { item in
                let on = item == tab
                Button {
                    tabRaw = item.rawValue
                    HapticEngine.shared.play(.selection)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 19, weight: .semibold))
                        Text(item.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background { if on { Capsule().fill(Color.primary.opacity(0.1)) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("calls.tab.\(item.rawValue)")
            }
        }
        .padding(5)
        .modulaGlass(in: Capsule(), interactive: false)
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, 6)
    }
}

struct CallsComingSoonCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.badge.waveform")
                .font(.title3.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Calling is coming soon").font(.subheadline.weight(.semibold))
                Text("Voice and video calls aren't switched on for your account yet.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calls.comingSoon")
    }
}

/// Shared call actions for the Calls screens (never starts anything when calls are off).
@MainActor
enum CallsActions {
    static func call(_ conversationID: String, kind: CallMediaKind, app: AppEnvironment) {
        guard app.calls.canStartCall(kind) else {
            app.navigation.flash("Calling is coming soon", symbol: "phone.badge.waveform")
            return
        }
        HapticEngine.shared.play(.selection)
        Task { await app.calls.startCall(conversationID: conversationID, mediaKind: kind) }
    }

    /// 1:1 chats with one other person: the Contacts list.
    static func contacts(_ app: AppEnvironment) -> [(conversationID: String, person: ConversationParticipant)] {
        app.messaging.conversations
            .filter { $0.kind == .direct && $0.participants.count == 1 }
            .map { ($0.id, $0.participants[0]) }
            .sorted { $0.person.displayName.localizedCaseInsensitiveCompare($1.person.displayName) == .orderedAscending }
    }
}

/// Round glass voice/video button used in rows.
private struct CallRowButton: View {
    let kind: CallMediaKind
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind == .video ? "video.fill" : "phone.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .modulaGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(CallPressStyle())
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(kind == .video ? "Video call" : "Voice call")
        .accessibilityHint(enabled ? "" : "Calling is coming soon")
    }
}

struct CallsRecentsList: View {
    @Environment(AppEnvironment.self) private var app
    @State private var missedOnly = false

    var body: some View {
        let items = app.calls.recents.filter { !missedOnly || CallCopy.isMissed($0) }
        VStack(spacing: 6) {
            ModulaSegmentedControl("Recents filter", selection: $missedOnly,
                                   segments: [(false, "All"), (true, "Missed")], identifier: { $0 ? "calls.recents.missed" : "calls.recents.all" })
                .padding(.horizontal, ModulaLayout.contentInset)
            if items.isEmpty {
                ModulaEmptyState(
                    title: app.calls.recentsLoading ? "Loading…" : (missedOnly ? "No missed calls" : "No recent calls"),
                    message: app.calls.capabilities.enabled ? "Your voice and video calls show up here." : "Calls you make and receive will show up here once calling is on.",
                    symbol: "clock"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { record in
                        row(record)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", systemImage: "trash", role: .destructive) { app.calls.hideRecent(record.id) }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task { await app.calls.loadRecents() }
        .refreshable { await app.calls.loadRecents() }
    }

    private func row(_ record: CallRecord) -> some View {
        let missed = CallCopy.isMissed(record)
        return HStack(spacing: 12) {
            Button { CallsActions.call(record.conversationID, kind: record.mediaKind, app: app) } label: {
                HStack(spacing: 12) {
                    ModulaAvatar(initials: record.other.initials, url: record.other.avatarURL, size: 40, name: record.other.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.other.name)
                            .font(.body.weight(missed ? .bold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Label(subtitle(record), systemImage: symbol(record))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(record.createdAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                app.navigation.push(.messages(.conversation(record.conversationID)))
            } label: {
                Image(systemName: "info.circle").font(.title3).foregroundStyle(.primary).frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(record.other.name)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calls.recent.\(record.id)")
    }

    private func subtitle(_ record: CallRecord) -> String {
        let kind = record.mediaKind == .video ? "Video" : "Voice"
        if CallCopy.isMissed(record) { return "Missed \(kind.lowercased()) call" }
        let direction = record.direction == .outgoing ? "Outgoing" : "Incoming"
        if let ms = record.durationMs, ms > 0 { return "\(kind) · \(direction) · \(CallCopy.duration(ms: ms))" }
        return "\(kind) · \(direction)"
    }

    private func symbol(_ record: CallRecord) -> String {
        if record.mediaKind == .video { return "video" }
        if CallCopy.isMissed(record) { return "phone.down" }
        return record.direction == .outgoing ? "phone.arrow.up.right" : "phone.arrow.down.left"
    }
}

struct CallsFavouritesList: View {
    @Environment(AppEnvironment.self) private var app
    @State private var picking = false

    var body: some View {
        let contacts = CallsActions.contacts(app)
        let favourites = app.calls.favourites.compactMap { id in contacts.first { $0.conversationID == id } }
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { picking = true } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true)
                .accessibilityIdentifier("calls.favourites.add")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            if favourites.isEmpty {
                ModulaEmptyState(title: "No favourites", message: "Add people you call often for one-tap calling.", symbol: "star")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(favourites, id: \.conversationID) { item in
                        CallsPersonRow(conversationID: item.conversationID, person: item.person)
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button("Remove", systemImage: "star.slash") { app.calls.toggleFavourite(item.conversationID) }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                List(contacts, id: \.conversationID) { item in
                    Button {
                        app.calls.toggleFavourite(item.conversationID)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        HStack(spacing: 12) {
                            ModulaAvatar(initials: item.person.initials, url: item.person.avatarURL, size: 36, name: item.person.displayName)
                            Text(item.person.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: app.calls.isFavourite(item.conversationID) ? "star.fill" : "star")
                                .foregroundStyle(.primary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationTitle("Add Favourites")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { picking = false } } }
            }
            .modulaSheetStyle()
        }
    }
}

struct CallsPersonRow: View {
    let conversationID: String
    let person: ConversationParticipant
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let calls = app.calls
        HStack(spacing: 12) {
            ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 40, name: person.displayName)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName).font(.body).lineLimit(1)
                if !person.handle.isEmpty {
                    Text("@\(person.handle)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            CallRowButton(kind: .audio, enabled: calls.canStartCall(.audio)) { CallsActions.call(conversationID, kind: .audio, app: app) }
            CallRowButton(kind: .video, enabled: calls.canStartCall(.video)) { CallsActions.call(conversationID, kind: .video, app: app) }
        }
        .contextMenu {
            Button(calls.isFavourite(conversationID) ? "Remove from Favourites" : "Add to Favourites",
                   systemImage: calls.isFavourite(conversationID) ? "star.slash" : "star") { calls.toggleFavourite(conversationID) }
            Button("Message", systemImage: "message") { app.navigation.push(.messages(.conversation(conversationID))) }
        }
        .accessibilityElement(children: .contain)
    }
}

struct CallsContactsList: View {
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let contacts = CallsActions.contacts(app).filter {
            needle.isEmpty || $0.person.displayName.lowercased().contains(needle) || $0.person.handle.lowercased().contains(needle)
        }
        let sections = Dictionary(grouping: contacts) { item in
            item.person.displayName.first.map { $0.isLetter ? String($0).uppercased() : "#" } ?? "#"
        }
        VStack(spacing: 6) {
            MessagesGlassSearchField(text: $query, prompt: "Search contacts")
                .padding(.horizontal, ModulaLayout.contentInset)
            if contacts.isEmpty {
                ModulaEmptyState(title: needle.isEmpty ? "No contacts yet" : "No matches",
                                 message: "People you chat with one-to-one appear here.", symbol: "person.crop.circle")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections.keys.sorted(), id: \.self) { letter in
                        Section(letter) {
                            ForEach(sections[letter] ?? [], id: \.conversationID) { item in
                                CallsPersonRow(conversationID: item.conversationID, person: item.person)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// Apple Phone-style keypad. The field takes a numeric Modula call ID or an @handle (typing a
/// letter or "@" switches to handle search with suggestions from your 1:1 chats).
struct CallsKeypad: View {
    @Environment(AppEnvironment.self) private var app
    @State private var entry = ""
    @State private var typing = false
    @State private var working = false
    @State private var note: String?
    @FocusState private var fieldFocused: Bool

    private static let keys: [(String, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    private var isHandle: Bool { entry.hasPrefix("@") || entry.contains(where: \.isLetter) }
    private var handleQuery: String { entry.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased() }
    private var caps: CallsCapabilities { app.calls.capabilities }

    private var canPlace: Bool {
        guard caps.canCall, !entry.isEmpty, !working else { return false }
        return isHandle ? !handleQuery.isEmpty : (caps.callIDs && CallIDFormat.isValid(entry, caps: caps))
    }

    var body: some View {
        VStack(spacing: 14) {
            field
            if isHandle { suggestions } else { Spacer(minLength: 0) }
            if !isHandle || !typing {
                grid
                callRow
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.2), value: isHandle)
        .accessibilityIdentifier("calls.keypad")
    }

    private var field: some View {
        VStack(spacing: 4) {
            if typing {
                TextField("Call ID or @handle", text: $entry)
                    .font(.system(size: 30, weight: .regular))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .submitLabel(.go)
                    .onSubmit { place(.audio) }
                    .accessibilityIdentifier("calls.keypad.field")
            } else {
                Button {
                    typing = true
                    fieldFocused = true
                } label: {
                    Text(entry.isEmpty ? "Call ID or @handle" : entry)
                        .font(.system(size: entry.isEmpty ? 20 : 34, weight: .regular))
                        .foregroundStyle(entry.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Type a handle with the keyboard")
            }
            Text(note ?? hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var hint: String {
        if !caps.canCall { return "Calling is coming soon." }
        if isHandle { return "Calling someone you already chat with." }
        if !caps.callIDs { return "Modula call IDs are coming soon. Type @ to call a handle." }
        return "Enter a Modula call ID (\(caps.callIDMinLength)–\(caps.callIDMaxLength) digits). Not a phone number."
    }

    private var suggestions: some View {
        let matches = CallsActions.contacts(app).filter {
            handleQuery.isEmpty || $0.person.handle.lowercased().hasPrefix(handleQuery) || $0.person.displayName.lowercased().contains(handleQuery)
        }.prefix(8)
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(matches), id: \.conversationID) { item in
                    CallsPersonRow(conversationID: item.conversationID, person: item.person)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
                }
                if matches.isEmpty {
                    Text("No one you chat with matches “\(handleQuery)”.").font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var grid: some View {
        Grid(horizontalSpacing: 22, verticalSpacing: 16) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let key = Self.keys[row * 3 + column]
                        CallsKeypadKey(digit: key.0, letters: key.1) {
                            entry.append(key.0)
                            note = nil
                        } onLongPress: {
                            if key.0 == "0" { entry.append("+") }
                        }
                    }
                }
            }
        }
    }

    private var callRow: some View {
        HStack {
            Color.clear.frame(width: 78, height: 78)
            Spacer()
            Button { place(.audio) } label: {
                Group {
                    if working { ProgressView().tint(.white) } else { Image(systemName: "phone.fill").font(.system(size: 30, weight: .semibold)) }
                }
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(Circle().fill(Color(red: 0.2, green: 0.62, blue: 0.29)))
                .modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(CallPressStyle())
            .disabled(!canPlace)
            .opacity(canPlace ? 1 : 0.4)
            .accessibilityLabel("Call")
            .accessibilityHint(caps.canCall ? "" : "Calling is coming soon")
            .accessibilityIdentifier("calls.keypad.call")
            Spacer()
            Button {
                if !entry.isEmpty { entry.removeLast() }
                note = nil
            } label: {
                Image(systemName: "delete.left").font(.title2).foregroundStyle(.primary).frame(width: 78, height: 78)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in entry = "" })
            .opacity(entry.isEmpty ? 0 : 1)
            .disabled(entry.isEmpty)
            .accessibilityLabel("Delete")
            .accessibilityHint("Hold to clear")
        }
        .padding(.horizontal, 6)
    }

    private func place(_ kind: CallMediaKind) {
        guard canPlace else { return }
        if isHandle {
            if let chat = app.messaging.directConversation(with: handleQuery) {
                CallsActions.call(chat.id, kind: kind, app: app)
            } else {
                note = "Start a chat with @\(handleQuery) first, then call."
                app.navigation.push(.messages(.direct(handleQuery)))
            }
            return
        }
        working = true
        Task {
            defer { working = false }
            guard let found = await app.calls.lookupCallID(entry) else {
                note = "No one has the call ID \(entry)."
                return
            }
            if let conversationID = found.conversationID {
                CallsActions.call(conversationID, kind: kind, app: app)
            } else if !found.party.handle.isEmpty {
                note = "Start a chat with \(found.party.name) first, then call."
                app.navigation.push(.messages(.direct(found.party.handle)))
            }
        }
    }
}

/// One round glass key: digit with letters underneath (Phone app layout).
struct CallsKeypadKey: View {
    let digit: String
    let letters: String
    let onTap: () -> Void
    var onLongPress: () -> Void = {}

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            onTap()
        } label: {
            VStack(spacing: -2) {
                Text(digit).font(.system(size: digit == "*" ? 40 : 34, weight: .regular))
                Text(letters.isEmpty ? " " : letters)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .opacity(letters.isEmpty ? 0 : 1)
            }
            .foregroundStyle(.primary)
            .frame(width: 78, height: 78)
            .modulaGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
        }
        .buttonStyle(CallPressStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() })
        .accessibilityLabel(letters.isEmpty ? digit : "\(digit), \(letters)")
        .accessibilityIdentifier("calls.key.\(digit)")
    }
}

// MARK: - Settings › Calls: claim a Modula call ID

struct CallIDSettingsRow: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showsSheet = false

    var body: some View {
        Button { showsSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "number").font(.body.weight(.semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modula call ID").font(.headline)
                    Text(app.calls.capabilities.callIDs ? (app.calls.myCallID ?? "Not claimed") : "Coming soon")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(isPresented: $showsSheet) { CallIDClaimSheet() }
        .task { await app.calls.loadMyCallID() }
        .accessibilityIdentifier("settings.calls.callID")
    }
}

struct CallIDClaimSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        let caps = app.calls.capabilities
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("A short number people can type on the Modula keypad to call you. It's an app ID, not a phone number, and it never reaches the phone network.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let current = app.calls.myCallID {
                    HStack {
                        Text("Your ID").foregroundStyle(.secondary)
                        Spacer()
                        Text(current).font(.title3.monospacedDigit().weight(.semibold)).textSelection(.enabled)
                    }
                    .padding(16)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
                }
                TextField(caps.callIDs ? "\(caps.callIDMinLength)–\(caps.callIDMaxLength) digits" : "Coming soon", text: $draft)
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
                    .disabled(!caps.callIDs)
                    .onChange(of: draft) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(caps.callIDMaxLength))
                        if digits != value { draft = digits }
                        error = nil
                    }
                    .accessibilityIdentifier("calls.callID.field")
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                if !caps.callIDs {
                    Label("Claiming call IDs is coming soon.", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    saving = true
                    Task {
                        error = await app.calls.claimCallID(draft)
                        saving = false
                        if error == nil { HapticEngine.shared.play(.success); draft = "" }
                    }
                } label: {
                    Text(saving ? "Claiming…" : (app.calls.myCallID == nil ? "Claim ID" : "Change ID")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.modulaPrimaryWide)
                .disabled(!caps.callIDs || saving || !CallIDFormat.isValid(draft, caps: caps))
                .accessibilityIdentifier("calls.callID.claim")
                Spacer()
            }
            .padding(ModulaLayout.contentInset)
            .navigationTitle("Modula Call ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
    }
}


// MARK: - Modula Connect (preview) entry points

enum ConnectPreview {
    /// Bundled React Native module (runtime/src/modules/connect), mock data only.
    static let moduleID = "digital.modula.connect"
}

/// Settings › Connect › Phone Numbers: opens the Connect preview module.
struct ConnectPhoneNumbersRow: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button { app.navigation.open(.module(ConnectPreview.moduleID, localPath: nil)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "simcard").font(.body.weight(.semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone Numbers").font(.headline)
                    Text("Modula Connect · Preview").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("settings.connect.phoneNumbers")
    }
}

/// Modules Dock: a built-in tile for the Connect preview (it isn't a catalogue product).
struct ConnectDockTile: View {
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "phone.connection.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modula Connect").font(.subheadline.weight(.semibold))
                    Text("Get your Modula Number · Preview").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("accessory.module.connect")
    }
}
