import SwiftUI
import UIKit
import AudioToolbox
import Contacts
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

/// Phone-style calling inside Messaging. Placing a call is gated on the server's `calls`
/// capability (a "Calling is coming soon" toast otherwise); everything else — favourites,
/// hidden recents, recent dials, contacts — works locally. Modula call IDs are app IDs, not
/// phone numbers.
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
            // Keypad is full-screen like Phone: no section picker, no title (back stays in the bar).
            if tab != .keypad {
                MessagesScopePicker(selection: .calls)
                if !app.calls.capabilities.canCall {
                    CallsComingSoonCard().padding(.horizontal, ModulaLayout.contentInset).padding(.bottom, 6)
                }
            }
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
        .navigationTitle(tab == .keypad ? "" : tab.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.22), value: tab)
        .task {
            await app.messaging.probeCapabilities()
            await app.messaging.loadInboxIfNeeded()
            await CallsDirectory.loadGraph(app)
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
                        Text(item.title).font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
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

// MARK: Directory (who you can call)

/// Someone in Calls › Contacts: your 1:1 chats merged with the people you follow / who follow you.
struct CallsContact: Identifiable, Hashable {
    let id: String
    let personID: String
    let handle: String
    let name: String
    let avatarURL: URL?
    var conversationID: String?
    var following = false
    var follower = false

    var mutual: Bool { following && follower }
    var participant: ConversationParticipant {
        ConversationParticipant(id: personID, handle: handle, displayName: name, avatarURL: avatarURL)
    }
    var initials: String { participant.initials }
    var sectionLetter: String {
        guard let first = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first,
              first.isLetter, first.isASCII else { return "#" }
        return String(first).uppercased()
    }
    var profileLink: URL? { handle.isEmpty ? nil : URL(string: "https://modula.digital/@\(handle)") }
}

@MainActor
enum CallsDirectory {
    static func key(handle: String, id: String) -> String { handle.isEmpty ? id : handle.lowercased() }

    /// Follow graph for the Following / Followers / Mutuals chips (same lists as your profile).
    static func loadGraph(_ app: AppEnvironment) async {
        guard let handle = app.auth.account?.primaryHandle, !handle.isEmpty else { return }
        async let following: Void = app.profile.loadFollowingIfNeeded(.me, handle: handle)
        async let followers: Void = app.profile.loadFollowersIfNeeded(.me, handle: handle)
        _ = await (following, followers)
    }

    static func all(_ app: AppEnvironment) -> [CallsContact] {
        var byKey: [String: CallsContact] = [:]
        for chat in app.messaging.conversations where chat.kind == .direct && chat.participants.count == 1 {
            let p = chat.participants[0]
            let k = key(handle: p.handle, id: p.id)
            byKey[k] = CallsContact(id: k, personID: p.id, handle: p.handle, name: p.displayName.isEmpty ? "@\(p.handle)" : p.displayName,
                                    avatarURL: p.avatarURL, conversationID: chat.id)
        }
        let session = app.profile.session(for: .me, handleHint: app.auth.account?.primaryHandle)
        let lists: [([ModulaProfile], Bool)] = [(session.following.items, true), (session.followers.items, false)]
        for (profiles, isFollowing) in lists {
            for profile in profiles {
                let k = key(handle: profile.handle, id: profile.id)
                var contact = byKey[k] ?? CallsContact(id: k, personID: profile.id, handle: profile.handle,
                                                       name: profile.displayName.isEmpty ? "@\(profile.handle)" : profile.displayName,
                                                       avatarURL: profile.avatarURL)
                if isFollowing { contact.following = true } else { contact.follower = true }
                byKey[k] = contact
            }
        }
        let hidden = CallsLocalStore.shared.hiddenContacts
        return byKey.values.filter { !hidden.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func contact(forConversation id: String, app: AppEnvironment) -> CallsContact? {
        all(app).first { $0.conversationID == id }
    }
}

/// Device-only Calls state: recent dials, default call type per favourite, hidden contacts.
@MainActor @Observable
final class CallsLocalStore {
    static let shared = CallsLocalStore()
    @ObservationIgnored private let defaults = UserDefaults.standard
    private(set) var recentDials: [String]
    private(set) var hiddenContacts: Set<String>
    private var favouriteKinds: [String: String]

    private init() {
        recentDials = UserDefaults.standard.stringArray(forKey: "calls.recentDials.v1") ?? []
        hiddenContacts = Set(UserDefaults.standard.stringArray(forKey: "calls.contacts.hidden.v1") ?? [])
        favouriteKinds = (UserDefaults.standard.dictionary(forKey: "calls.favourites.kind.v1") as? [String: String]) ?? [:]
    }

    func noteDial(_ entry: String) {
        let value = entry.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        recentDials.removeAll { $0 == value }
        recentDials.insert(value, at: 0)
        recentDials = Array(recentDials.prefix(8))
        defaults.set(recentDials, forKey: "calls.recentDials.v1")
    }

    func clearDials() {
        recentDials = []
        defaults.removeObject(forKey: "calls.recentDials.v1")
    }

    func hide(_ contactID: String) {
        hiddenContacts.insert(contactID)
        defaults.set(Array(hiddenContacts), forKey: "calls.contacts.hidden.v1")
    }

    func defaultKind(_ conversationID: String) -> CallMediaKind {
        favouriteKinds[conversationID] == CallMediaKind.video.rawValue ? .video : .audio
    }

    func setDefaultKind(_ kind: CallMediaKind, for conversationID: String) {
        favouriteKinds[conversationID] = kind.rawValue
        defaults.set(favouriteKinds, forKey: "calls.favourites.kind.v1")
    }
}

/// Shared call actions for the Calls screens (never starts anything when calls are off).
@MainActor
enum CallsActions {
    static func comingSoon(_ app: AppEnvironment) {
        app.navigation.flash("Calling is coming soon", symbol: "phone.badge.waveform")
    }

    static func call(_ conversationID: String, kind: CallMediaKind, app: AppEnvironment) {
        guard app.calls.canStartCall(kind) else { return comingSoon(app) }
        HapticEngine.shared.play(.selection)
        Task { await app.calls.startCall(conversationID: conversationID, mediaKind: kind) }
    }

    /// Calls need a 1:1 chat; for someone you haven't chatted with yet, open the starter chat.
    static func call(_ contact: CallsContact, kind: CallMediaKind, app: AppEnvironment) {
        if let id = contact.conversationID { return call(id, kind: kind, app: app) }
        guard app.calls.canStartCall(kind) else { return comingSoon(app) }
        app.navigation.flash("Say hi first, then you can call", symbol: "message")
        message(contact, app: app)
    }

    static func message(_ contact: CallsContact, app: AppEnvironment) {
        if let id = contact.conversationID {
            app.navigation.push(.messages(.conversation(id)))
        } else {
            app.navigation.push(.messages(.direct(contact.handle.isEmpty ? contact.personID : contact.handle)))
        }
    }

    static func profile(_ contact: CallsContact, app: AppEnvironment) {
        app.navigation.push(.profile(contact.handle.isEmpty ? contact.personID : contact.handle, .overview))
    }

    static func copyHandle(_ contact: CallsContact, app: AppEnvironment) {
        UIPasteboard.general.string = "@\(contact.handle)"
        app.navigation.flash("Handle copied", symbol: "doc.on.doc")
    }

    /// 1:1 chats with one other person (Favourites are keyed by these conversation ids).
    static func contacts(_ app: AppEnvironment) -> [(conversationID: String, person: ConversationParticipant)] {
        CallsDirectory.all(app).compactMap { c in c.conversationID.map { ($0, c.participant) } }
    }
}

/// Round glass voice/video button used in rows. Always looks normal; when calls are off the tap
/// shows the "coming soon" toast instead.
private struct CallRowButton: View {
    let kind: CallMediaKind
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
        .accessibilityLabel(kind == .video ? "Video call" : "Voice call")
    }
}

// MARK: Recents

/// Consecutive calls with the same person, kind and outcome (same day) collapse into one row "(3)".
struct CallsRecentGroup: Identifiable, Hashable {
    var records: [CallRecord]
    var id: String { records[0].id }
    var latest: CallRecord { records[0] }
}

enum CallsRecentGrouping {
    static func groups(_ records: [CallRecord]) -> [CallsRecentGroup] {
        var out: [CallsRecentGroup] = []
        for record in records {
            if let last = out.last?.latest,
               last.conversationID == record.conversationID, last.mediaKind == record.mediaKind,
               CallCopy.isMissed(last) == CallCopy.isMissed(record), last.direction == record.direction,
               Calendar.current.isDate(last.createdAt, inSameDayAs: record.createdAt) {
                out[out.count - 1].records.append(record)
            } else {
                out.append(CallsRecentGroup(records: [record]))
            }
        }
        return out
    }
}

struct CallsRecentsList: View {
    @Environment(AppEnvironment.self) private var app
    @State private var missedOnly = false
    @State private var editing = false
    @State private var confirmClear = false
    @State private var detail: CallsContact?

    var body: some View {
        let items = app.calls.recents.filter { !missedOnly || CallCopy.isMissed($0) }
        let groups = CallsRecentGrouping.groups(items)
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ModulaSegmentedControl("Recents filter", selection: $missedOnly,
                                       segments: [(false, "All"), (true, "Missed")], identifier: { $0 ? "calls.recents.missed" : "calls.recents.all" })
                if !app.calls.recents.isEmpty {
                    Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityIdentifier("calls.recents.edit")
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            if editing {
                Button("Clear All Recents") { confirmClear = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .transition(.opacity)
            }
            if groups.isEmpty {
                ModulaEmptyState(
                    title: app.calls.recentsLoading ? "Loading…" : (missedOnly ? "No missed calls" : "No recent calls"),
                    message: app.calls.capabilities.enabled ? "Your voice and video calls show up here." : "Calls you make and receive will show up here once calling is on.",
                    symbol: "clock"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        row(group)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", systemImage: "trash", role: .destructive) { hide(group) }
                            }
                    }
                    .onDelete { offsets in for i in offsets { hide(groups[i]) } }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(editing ? .active : .inactive))
            }
        }
        .task { await app.calls.loadRecents() }
        .refreshable { await app.calls.loadRecents() }
        .confirmationDialog("Clear all recents on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear All Recents", role: .destructive) {
                for record in app.calls.recents { app.calls.hideRecent(record.id) }
                editing = false
            }
        }
        .sheet(item: $detail) { contact in CallsContactCard(contact: contact) }
    }

    private func hide(_ group: CallsRecentGroup) {
        for record in group.records { app.calls.hideRecent(record.id) }
    }

    private func row(_ group: CallsRecentGroup) -> some View {
        let record = group.latest
        let missed = CallCopy.isMissed(record)
        let title = group.records.count > 1 ? "\(record.other.name) (\(group.records.count))" : record.other.name
        return HStack(spacing: 12) {
            Button { CallsActions.call(record.conversationID, kind: record.mediaKind, app: app) } label: {
                HStack(spacing: 12) {
                    ModulaAvatar(initials: record.other.initials, url: record.other.avatarURL, size: 40, name: record.other.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(missed ? .bold : .regular))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(subtitle(record), systemImage: symbol(record))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(timeLabel(record.createdAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Calls back")
            Button { detail = contact(for: record) } label: {
                Image(systemName: "info.circle").font(.title3).foregroundStyle(.primary).frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(record.other.name)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calls.recent.\(record.id)")
    }

    private func contact(for record: CallRecord) -> CallsContact {
        if let known = CallsDirectory.contact(forConversation: record.conversationID, app: app) { return known }
        let p = record.other
        return CallsContact(id: CallsDirectory.key(handle: p.handle, id: p.id), personID: p.id, handle: p.handle, name: p.name,
                            avatarURL: p.avatarURL, conversationID: record.conversationID)
    }

    private func timeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
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

// MARK: Favourites

struct CallsFavouritesList: View {
    @Environment(AppEnvironment.self) private var app
    @State private var picking = false
    @State private var editing = false
    private var local: CallsLocalStore { .shared }

    var body: some View {
        let contacts = CallsActions.contacts(app)
        let favourites = app.calls.favourites.compactMap { id in contacts.first { $0.conversationID == id } }
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if !favourites.isEmpty {
                    Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityIdentifier("calls.favourites.edit")
                }
                Spacer()
                Button { picking = true } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
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
            } else if editing {
                // Reorder / remove, and choose voice or video per favourite.
                List {
                    ForEach(favourites, id: \.conversationID) { item in
                        editRow(item.conversationID, person: item.person).listRowBackground(Color.clear)
                    }
                    .onMove { app.calls.moveFavourites(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in for i in offsets { app.calls.toggleFavourite(favourites[i].conversationID) } }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 18) {
                        ForEach(favourites, id: \.conversationID) { item in tile(item.conversationID, person: item.person) }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 6)
                }
            }
        }
        .sheet(isPresented: $picking) { picker(contacts) }
    }

    private func editRow(_ conversationID: String, person: ConversationParticipant) -> some View {
        let kind = local.defaultKind(conversationID)
        return HStack(spacing: 12) {
            ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 40, name: person.displayName)
            Text(person.displayName).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                local.setDefaultKind(kind == .video ? .audio : .video, for: conversationID)
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: kind == .video ? "video.fill" : "phone.fill")
                    .foregroundStyle(.primary).frame(width: 36, height: 36)
                    .modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(kind == .video ? "Default: video. Tap for voice" : "Default: voice. Tap for video")
        }
    }

    private func picker(_ contacts: [(conversationID: String, person: ConversationParticipant)]) -> some View {
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

    private func tile(_ conversationID: String, person: ConversationParticipant) -> some View {
        let kind = local.defaultKind(conversationID)
        return Button { CallsActions.call(conversationID, kind: kind, app: app) } label: {
            VStack(spacing: 6) {
                ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 76, name: person.displayName)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: kind == .video ? "video.fill" : "phone.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.modulaOnPrimary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.modulaPrimaryFill))
                    }
                Text(person.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
        .contextMenu {
            Button("Voice Call", systemImage: "phone") { CallsActions.call(conversationID, kind: .audio, app: app) }
            Button("Video Call", systemImage: "video") { CallsActions.call(conversationID, kind: .video, app: app) }
            Button("Message", systemImage: "message") { app.navigation.push(.messages(.conversation(conversationID))) }
            Button(kind == .video ? "Default: Voice" : "Default: Video", systemImage: "arrow.triangle.2.circlepath") {
                local.setDefaultKind(kind == .video ? .audio : .video, for: conversationID)
            }
            Button("Remove from Favourites", systemImage: "star.slash", role: .destructive) { app.calls.toggleFavourite(conversationID) }
        }
        .accessibilityLabel(person.displayName)
        .accessibilityHint(kind == .video ? "Starts a video call" : "Starts a voice call")
    }
}

// MARK: Contacts

struct CallsPersonRow: View {
    let contact: CallsContact
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            ModulaAvatar(initials: contact.initials, url: contact.avatarURL, size: 40, name: contact.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if !contact.handle.isEmpty {
                    Text("@\(contact.handle)").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            CallRowButton(kind: .audio) { CallsActions.call(contact, kind: .audio, app: app) }
            CallRowButton(kind: .video) { CallsActions.call(contact, kind: .video, app: app) }
        }
        .contentShape(Rectangle())
        .contextMenu { CallsContactMenu(contact: contact) }
        .accessibilityElement(children: .contain)
    }
}

/// Long-press menu for a contact (rows, keypad suggestions).
struct CallsContactMenu: View {
    let contact: CallsContact
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button("Call", systemImage: "phone") { CallsActions.call(contact, kind: .audio, app: app) }
        Button("Video", systemImage: "video") { CallsActions.call(contact, kind: .video, app: app) }
        Button("Message", systemImage: "message") { CallsActions.message(contact, app: app) }
        if let id = contact.conversationID {
            Button(app.calls.isFavourite(id) ? "Remove from Favourites" : "Add to Favourites",
                   systemImage: app.calls.isFavourite(id) ? "star.slash" : "star") { app.calls.toggleFavourite(id) }
        }
        if !contact.handle.isEmpty {
            Button("Copy Handle", systemImage: "doc.on.doc") { CallsActions.copyHandle(contact, app: app) }
        }
        if let link = contact.profileLink {
            ShareLink(item: link, subject: Text(contact.name), message: Text("\(contact.name) on Modula")) {
                Label("Share Contact", systemImage: "square.and.arrow.up")
            }
        }
        Button("View Profile", systemImage: "person.crop.circle") { CallsActions.profile(contact, app: app) }
    }
}

struct CallsContactsList: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, following, followers, mutuals, favourites
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .following: "Following"
            case .followers: "Followers"
            case .mutuals: "Mutuals"
            case .favourites: "Favourites"
            }
        }
    }

    @Environment(AppEnvironment.self) private var app
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var detail: CallsContact?
    @State private var importing = false

    private static let green = Color(red: 0.2, green: 0.78, blue: 0.35)

    private func matches(_ c: CallsContact, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let handleNeedle = needle.hasPrefix("@") ? String(needle.dropFirst()) : needle
        return c.name.lowercased().contains(needle) || c.handle.lowercased().hasPrefix(handleNeedle)
    }

    private func passes(_ c: CallsContact) -> Bool {
        switch filter {
        case .all: return true
        case .following: return c.following
        case .followers: return c.follower
        case .mutuals: return c.mutual
        case .favourites:
            guard let id = c.conversationID else { return false }
            return app.calls.isFavourite(id)
        }
    }

    private static func letterOrder(_ a: String, _ b: String) -> Bool {
        if a == "#" { return false }
        if b == "#" { return true }
        return a < b
    }

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let contacts = CallsDirectory.all(app).filter { passes($0) && matches($0, needle) }
        let sections = Dictionary(grouping: contacts, by: \.sectionLetter)
        let letters = sections.keys.sorted(by: Self.letterOrder)
        VStack(spacing: 6) {
            MessagesGlassSearchField(text: $query, prompt: "Search name or @handle")
                .padding(.horizontal, ModulaLayout.contentInset)
            ModulaSegmentedControl("Contacts filter", selection: $filter, options: Filter.allCases) { $0.title }
                .modulaEdgeToEdgeRail()
            ScrollViewReader { proxy in
                List {
                    if needle.isEmpty { header }
                    if contacts.isEmpty {
                        Text(needle.isEmpty ? "People you chat with or follow appear here." : "No one matches “\(query)”.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(letters, id: \.self) { letter in
                        Section {
                            ForEach(sections[letter] ?? []) { contact in contactRow(contact) }
                        } header: {
                            Text(letter).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .id("section-\(letter)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .trailing) {
                    if letters.count > 3 {
                        CallsSectionIndex(letters: letters) { letter in proxy.scrollTo("section-\(letter)", anchor: .top) }
                    }
                }
            }
        }
        .sheet(item: $detail) { contact in CallsContactCard(contact: contact) }
        .sheet(isPresented: $importing) { CallsDeviceContactsSheet() }
    }

    @ViewBuilder private var header: some View {
        CallsMyCard().listRowBackground(Color.clear).listRowSeparator(.hidden)
        Button { importing = true } label: {
            Label("Find friends from your iPhone Contacts", systemImage: "person.crop.circle.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("calls.contacts.import")
    }

    /// Tap: card. Swipe right: voice call. Swipe left: video / message. Hold: menu.
    private func contactRow(_ contact: CallsContact) -> some View {
        Button { detail = contact } label: { CallsPersonRow(contact: contact) }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { CallsActions.call(contact, kind: .audio, app: app) } label: { Label("Call", systemImage: "phone.fill") }
                    .tint(Self.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { CallsActions.message(contact, app: app) } label: { Label("Message", systemImage: "message.fill") }
                    .tint(Color(white: 0.45))
                Button { CallsActions.call(contact, kind: .video, app: app) } label: { Label("Video", systemImage: "video.fill") }
                    .tint(Color(white: 0.25))
            }
    }
}

/// A–Z scrubber on the trailing edge (drag or tap a letter).
struct CallsSectionIndex: View {
    let letters: [String]
    let jump: (String) -> Void
    @State private var last: String?
    private let rowHeight: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary)
                    .frame(width: 20, height: rowHeight)
            }
        }
        .padding(.vertical, 6)
        .modulaGlass(in: Capsule(), interactive: false)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let index = Int(((value.location.y - 6) / rowHeight).rounded(.down))
            guard letters.indices.contains(index), letters[index] != last else { return }
            last = letters[index]
            HapticEngine.shared.play(.selection)
            jump(letters[index])
        }.onEnded { _ in last = nil })
        .padding(.trailing, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Section index")
        .accessibilityHidden(true)
    }
}

/// "My card": your avatar, handle and Modula call ID, with a QR to share.
struct CallsMyCard: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showsQR = false
    @State private var claiming = false

    private var handle: String { app.auth.account?.primaryHandle ?? "" }
    private var name: String { app.profile.ownProfile?.displayName ?? app.auth.account?.displayName ?? "@\(handle)" }
    private var link: URL? { handle.isEmpty ? nil : URL(string: "https://modula.digital/@\(handle)") }
    private var callIDText: String {
        guard app.calls.capabilities.callIDs else { return "Call IDs coming soon" }
        return app.calls.myCallID.map { "Call ID \(CallsKeypadFormat.format($0))" } ?? "Claim a call ID"
    }

    var body: some View {
        HStack(spacing: 14) {
            ModulaAvatar(initials: String(name.prefix(1)).uppercased(), url: app.profile.ownProfile?.avatarURL, size: 56, name: name)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text("My card · @\(handle)").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { claiming = true } label: {
                    Text(callIDText).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button { showsQR = true } label: {
                Image(systemName: "qrcode").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    .frame(width: 44, height: 44).modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(link == nil)
            .accessibilityLabel("Share my card")
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .sheet(isPresented: $showsQR) {
            if let link { CallsMyCardQRSheet(name: name, handle: handle, callID: app.calls.myCallID, link: link) }
        }
        .sheet(isPresented: $claiming) { CallIDClaimSheet() }
        .task { await app.calls.loadMyCallID() }
        .accessibilityIdentifier("calls.contacts.myCard")
    }
}

struct CallsMyCardQRSheet: View {
    let name: String
    let handle: String
    let callID: String?
    let link: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let matrix = ModulaQRMatrix.make(link.absoluteString) {
                    ModulaBrandedQRCode(matrix: matrix, style: .mono, accent: .black) {
                        Image(systemName: "phone.fill").font(.title2.weight(.bold)).foregroundStyle(.black)
                    }
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
                    .accessibilityLabel("QR code for @\(handle)")
                }
                VStack(spacing: 4) {
                    Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("@\(handle)").foregroundStyle(.secondary)
                    if let callID { Text("Call ID \(CallsKeypadFormat.format(callID))").font(.subheadline.weight(.semibold)) }
                }
                ShareLink(item: link, subject: Text(name), message: Text("Call me on Modula: @\(handle)")) {
                    Label("Share My Card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.modulaPrimary)
                .padding(.horizontal, 24)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
        }
        .presentationDetents([.large])
        .modulaSheetStyle()
    }
}

/// Contact detail: big avatar, handle, actions, recent calls with them, shared groups, block/remove.
struct CallsContactCard: View {
    let contact: CallsContact
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmBlock = false

    private var recents: [CallRecord] {
        app.calls.recents.filter { $0.conversationID == contact.conversationID || $0.other.id == contact.personID }
    }
    private var groups: [Conversation] {
        app.messaging.conversations.filter { $0.kind == .group && $0.participants.contains { $0.id == contact.personID } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    identity
                    actions
                    if !recents.isEmpty { recentCalls }
                    if !groups.isEmpty { sharedGroups }
                    manage
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.vertical, 12)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
            .confirmationDialog("Block \(contact.name)?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    Task {
                        if await app.messaging.block(contact.participant) {
                            app.navigation.flash("Blocked", symbol: "hand.raised")
                            dismiss()
                        }
                    }
                }
            } message: { Text("They won't be able to message or call you.") }
        }
        .presentationDetents([.large])
        .modulaSheetStyle()
        .accessibilityIdentifier("calls.contact.card")
    }

    private var identity: some View {
        VStack(spacing: 8) {
            ModulaAvatar(initials: contact.initials, url: contact.avatarURL, size: 104, name: contact.name)
            Text(contact.name).font(.title.bold()).multilineTextAlignment(.center)
            if !contact.handle.isEmpty { Text("@\(contact.handle)").foregroundStyle(.secondary) }
            if contact.mutual { Text("You follow each other").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            action("Message", "message.fill") { dismiss(); CallsActions.message(contact, app: app) }
            action("Call", "phone.fill") { CallsActions.call(contact, kind: .audio, app: app) }
            action("Video", "video.fill") { CallsActions.call(contact, kind: .video, app: app) }
            action("In-Mail", "envelope.fill") { dismiss(); app.navigation.push(.messages(.inMail(.compose))) }
        }
    }

    private var recentCalls: some View {
        section("Recent calls") {
            ForEach(recents.prefix(6)) { record in
                HStack(spacing: 10) {
                    Image(systemName: record.mediaKind == .video ? "video" : (CallCopy.isMissed(record) ? "phone.down" : "phone"))
                        .frame(width: 22).foregroundStyle(.secondary)
                    Text(CallCopy.historyTitle(record)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(minHeight: 36)
            }
        }
    }

    private var sharedGroups: some View {
        section("Groups in common") {
            ForEach(groups) { chat in
                Button { dismiss(); app.navigation.push(.messages(.conversation(chat.id))) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill").frame(width: 22).foregroundStyle(.secondary)
                        Text(app.messaging.title(for: chat)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var manage: some View {
        section(nil) {
            if let id = contact.conversationID {
                row(app.calls.isFavourite(id) ? "Remove from Favourites" : "Add to Favourites", app.calls.isFavourite(id) ? "star.slash" : "star") {
                    app.calls.toggleFavourite(id)
                }
            }
            row("View Profile", "person.crop.circle") { dismiss(); CallsActions.profile(contact, app: app) }
            if !contact.handle.isEmpty { row("Copy Handle", "doc.on.doc") { CallsActions.copyHandle(contact, app: app) } }
            if let link = contact.profileLink {
                ShareLink(item: link, subject: Text(contact.name), message: Text("\(contact.name) on Modula")) {
                    rowLabel("Share Contact", "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            row("Remove from Contacts", "person.crop.circle.badge.minus") {
                CallsLocalStore.shared.hide(contact.id)
                dismiss()
            }
            if app.messaging.capabilities.block {
                row("Block \(contact.name)", "hand.raised") { confirmBlock = true }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption.weight(.semibold)).fixedSize()
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
        .accessibilityLabel(title)
    }

    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        }
    }

    private func row(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { rowLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.primary)
            Text(title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// iPhone Contacts → Modula, matched ON DEVICE only (names compared with people you already know
/// here). Nothing is uploaded; there's no server contact-matching capability.
struct CallsDeviceContactsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    enum Phase { case intro, loading, denied, done }
    @State private var phase: Phase = .intro
    @State private var onModula: [CallsContact] = []
    @State private var others: [String] = []
    private static let invite = URL(string: "https://modula.digital")!

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .intro:
                    Section {
                        Text("Modula checks your iPhone Contacts on this device to spot people you already know here. Nothing is uploaded.")
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Continue") { Task { await load() } }
                            .font(.body.weight(.semibold)).foregroundStyle(.primary)
                    }
                case .loading:
                    ProgressView("Checking on this iPhone…")
                case .denied:
                    Text("Contacts access is off. Turn it on in Settings › Privacy & Security › Contacts.")
                        .fixedSize(horizontal: false, vertical: true)
                case .done:
                    Section("On Modula") {
                        if onModula.isEmpty { Text("No matches yet.").foregroundStyle(.secondary) }
                        ForEach(onModula) { contact in CallsPersonRow(contact: contact) }
                    }
                    Section("Invite") {
                        ForEach(others.prefix(300), id: \.self) { name in
                            HStack {
                                Text(name).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                ShareLink(item: Self.invite, message: Text("Join me on Modula")) {
                                    Text("Invite").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
        }
        .modulaSheetStyle()
    }

    private func load() async {
        phase = .loading
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        guard granted else { phase = .denied; return }
        let names = await Task.detached(priority: .userInitiated) { () -> [String] in
            var out: [String] = []
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                if !name.isEmpty { out.append(name) }
            }
            return out
        }.value
        let known = CallsDirectory.all(app)
        var matched: [CallsContact] = []
        var rest: [String] = []
        for name in Set(names).sorted() {
            if let hit = known.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                if !matched.contains(hit) { matched.append(hit) }
            } else {
                rest.append(name)
            }
        }
        onModula = matched
        others = rest
        phase = .done
    }
}

// MARK: Keypad

enum CallsKeypadFormat {
    /// "8794" → "879 4", "1234567890" → "123 456 7890" (groups of three, a trailing four).
    static func format(_ digits: String) -> String {
        guard digits.count > 3, !digits.hasPrefix("@") else { return digits }
        var groups: [String] = []
        var rest = Substring(digits)
        while rest.count > 4 || (rest.count == 4 && groups.isEmpty) {
            groups.append(String(rest.prefix(3)))
            rest = rest.dropFirst(3)
        }
        if !rest.isEmpty { groups.append(String(rest)) }
        return groups.joined(separator: " ")
    }

    private static let t9: [Character: Character] = {
        var map: [Character: Character] = [:]
        let pairs: [(Character, String)] = [("2", "abc"), ("3", "def"), ("4", "ghi"), ("5", "jkl"), ("6", "mno"), ("7", "pqrs"), ("8", "tuv"), ("9", "wxyz")]
        for (digit, letters) in pairs {
            for letter in letters { map[letter] = digit }
        }
        return map
    }()

    static func t9Digits(_ text: String) -> String {
        String(text.lowercased().folding(options: .diacriticInsensitive, locale: nil).compactMap { t9[$0] })
    }

    /// People whose name (any word) or handle spells the typed digits on the keypad letters.
    static func t9Matches(_ digits: String, in contacts: [CallsContact]) -> [CallsContact] {
        guard digits.count >= 2, digits.allSatisfy(\.isNumber) else { return [] }
        return contacts.filter { c in
            var words = c.name.split(separator: " ").map { t9Digits(String($0)) }
            words.append(t9Digits(c.handle))
            return words.contains { $0.hasPrefix(digits) }
        }
    }
}

/// One round glass key (Phone sizes): digit with letters underneath, haptic + optional DTMF tone.
struct CallsKeypadKey: View {
    let digit: String
    let letters: String
    var tones = true
    let onTap: () -> Void
    var onLongPress: () -> Void = {}

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            if tones { Self.playTone(digit) }
            onTap()
        } label: {
            VStack(spacing: -2) {
                Text(digit).font(.system(size: digit == "*" ? 44 : 38, weight: .regular))
                Text(letters.isEmpty ? " " : letters)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .opacity(letters.isEmpty ? 0 : 1)
            }
            .foregroundStyle(.primary)
            .frame(width: 80, height: 80)
            .modulaGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
        }
        .buttonStyle(CallPressStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() })
        .accessibilityLabel(letters.isEmpty ? digit : "\(digit), \(letters)")
        .accessibilityHint(digit == "0" ? "Hold for plus" : (digit == "*" ? "Hold to type a handle" : ""))
        .accessibilityIdentifier("calls.key.\(digit)")
    }

    /// System DTMF sounds (1200–1211); system sounds stay quiet when the ringer is on silent.
    static func playTone(_ digit: String) {
        let id: Int
        switch digit {
        case "*": id = 1210
        case "#": id = 1211
        default:
            guard let n = Int(digit) else { return }
            id = 1200 + n
        }
        AudioServicesPlaySystemSound(SystemSoundID(id))
    }
}

/// Full-width bright-green call button. Tap: voice. Touch and hold: voice or video.
struct CallsGreenCallButton: View {
    var working = false
    let place: (CallMediaKind) -> Void
    static let green = Color(red: 0.2, green: 0.78, blue: 0.35)

    var body: some View {
        Button { place(.audio) } label: {
            Group {
                if working { ProgressView().tint(.white) } else { Image(systemName: "phone.fill").font(.system(size: 32, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .frame(width: 80, height: 80)
            .background(Circle().fill(Self.green))
        }
        .buttonStyle(CallPressStyle())
        .contextMenu {
            Button("Voice Call", systemImage: "phone") { place(.audio) }
            Button("Video Call", systemImage: "video") { place(.video) }
        }
        .accessibilityLabel("Call")
        .accessibilityHint("Touch and hold for voice or video")
        .accessibilityIdentifier("calls.keypad.call")
    }
}

/// Apple Phone-style full-screen keypad. The field takes a numeric Modula call ID or, via the "@"
/// key (or holding *), an @handle typed with the system keyboard with live search and avatars.
struct CallsKeypad: View {
    @Environment(AppEnvironment.self) private var app
    @AppStorage("calls.keypad.tones") private var tones = true
    @State private var entry = ""
    @State private var handleMode = false
    @State private var working = false
    @State private var note: String?
    @State private var showsAllMatches = false
    @State private var remote: [DiscoverPerson] = []
    @FocusState private var fieldFocused: Bool

    private static let keys: [(String, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    private var handleQuery: String { entry.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased() }
    private var caps: CallsCapabilities { app.calls.capabilities }
    private var local: CallsLocalStore { .shared }
    private var t9: [CallsContact] { CallsKeypadFormat.t9Matches(entry, in: CallsDirectory.all(app)) }
    private var handleContacts: [CallsContact] {
        let q = handleQuery
        return CallsDirectory.all(app).filter { q.isEmpty || $0.handle.lowercased().hasPrefix(q) || $0.name.lowercased().contains(q) }
    }
    private var matchedContact: CallsContact? {
        if handleMode { return handleContacts.first { $0.handle.lowercased() == handleQuery } }
        return t9.count == 1 ? t9.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if handleMode {
                handlePanel
            } else {
                Spacer(minLength: 4)
                display
                suggestionRow
                Spacer(minLength: 10)
                grid
                callRow.padding(.top, 18)
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.2), value: handleMode)
        .animation(.snappy(duration: 0.15), value: entry.isEmpty)
        .accessibilityIdentifier("calls.keypad")
    }

    // Options (left) · add to favourites (right, once a known person is typed).
    private var topBar: some View {
        HStack {
            Menu {
                Toggle(isOn: $tones) { Label("Key Tones", systemImage: "speaker.wave.2") }
                if !local.recentDials.isEmpty {
                    Button("Clear Recent Dials", systemImage: "clock.arrow.circlepath") { local.clearDials() }
                }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    .frame(width: 40, height: 40).modulaGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Keypad options")
            Spacer()
            if let id = matchedContact?.conversationID {
                let on = app.calls.isFavourite(id)
                Button {
                    app.calls.toggleFavourite(id)
                    app.navigation.flash(on ? "Removed from Favourites" : "Added to Favourites", symbol: "star")
                } label: {
                    Image(systemName: on ? "star.fill" : "person.crop.circle.badge.plus")
                        .font(.body.weight(.semibold)).foregroundStyle(.primary)
                        .frame(width: 40, height: 40).modulaGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(on ? "Remove from Favourites" : "Add to Favourites")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(minHeight: 44)
    }

    private var display: some View {
        VStack(spacing: 6) {
            Text(entry.isEmpty ? " " : CallsKeypadFormat.format(entry))
                .font(.system(size: 40, weight: .regular).monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Paste", systemImage: "doc.on.clipboard") { paste() }
                    if !entry.isEmpty {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry }
                    }
                }
                .accessibilityLabel(entry.isEmpty ? "No number entered" : entry)
                .accessibilityHint("Touch and hold to paste")
                .accessibilityIdentifier("calls.keypad.display")
            Text(note ?? hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: String {
        if entry.isEmpty { return "Call ID, or tap @ for a handle" }
        return caps.callIDs ? "Modula call ID" : "Call IDs are coming soon"
    }

    /// Phone's suggestion row: best match (+ "N more"), or recent dials while empty.
    @ViewBuilder private var suggestionRow: some View {
        let matches = t9
        if entry.isEmpty, !local.recentDials.isEmpty {
            recentDialsRow
        } else if let first = matches.first {
            HStack(spacing: 10) {
                Button { CallsActions.call(first, kind: .audio, app: app) } label: {
                    HStack(spacing: 8) {
                        ModulaAvatar(initials: first.initials, url: first.avatarURL, size: 26, name: first.name)
                        Text(first.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { CallsContactMenu(contact: first) }
                if matches.count > 1 {
                    Button("\(matches.count - 1) more") { showsAllMatches = true }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 36)
            .modulaGlass(in: Capsule(), interactive: false)
            .padding(.top, 6)
            .sheet(isPresented: $showsAllMatches) { allMatches(matches) }
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private var recentDialsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(local.recentDials, id: \.self) { dial in
                    Button {
                        entry = dial
                        handleMode = dial.hasPrefix("@")
                    } label: {
                        Label(CallsKeypadFormat.format(dial), systemImage: "clock")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                            .padding(.horizontal, 12).frame(minHeight: 32)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recent: \(dial)")
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minHeight: 44)
    }

    private func allMatches(_ matches: [CallsContact]) -> some View {
        NavigationStack {
            List(matches) { contact in
                Button {
                    showsAllMatches = false
                    CallsActions.call(contact, kind: .audio, app: app)
                } label: { CallsPersonRow(contact: contact) }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { showsAllMatches = false } } }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
    }

    private var grid: some View {
        Grid(horizontalSpacing: 26, verticalSpacing: 16) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let key = Self.keys[row * 3 + column]
                        CallsKeypadKey(digit: key.0, letters: key.1, tones: tones) {
                            append(key.0)
                        } onLongPress: {
                            longPress(key.0)
                        }
                    }
                }
            }
        }
    }

    private var callRow: some View {
        HStack {
            Button { switchToHandle() } label: {
                Text("@").font(.system(size: 30, weight: .regular)).foregroundStyle(.primary)
                    .frame(width: 80, height: 80)
                    .modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(CallPressStyle())
            .accessibilityLabel("Type a handle")
            .accessibilityIdentifier("calls.keypad.handle")
            Spacer()
            CallsGreenCallButton(working: working) { place($0) }
            Spacer()
            Button {
                if !entry.isEmpty { entry.removeLast() }
                note = nil
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: "delete.left.fill").font(.system(size: 26)).foregroundStyle(.primary).frame(width: 80, height: 80)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                entry = ""
                HapticEngine.shared.play(.selection)
            })
            .opacity(entry.isEmpty ? 0 : 1)
            .disabled(entry.isEmpty)
            .accessibilityLabel("Delete")
            .accessibilityHint("Hold to clear")
            .accessibilityHidden(entry.isEmpty)
        }
        .padding(.horizontal, 2)
    }

    // Handle mode: system keyboard, live search (your chats/follows first, then Modula people search).
    private var handlePanel: some View {
        let locals = Array(handleContacts.prefix(8))
        let localHandles = Set(locals.map { $0.handle.lowercased() })
        let others = Array(remote.filter { !localHandles.contains($0.handle.lowercased()) }.prefix(8))
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("@").font(.title2).foregroundStyle(.secondary)
                    TextField("handle", text: Binding(
                        get: { handleQuery },
                        set: { entry = "@" + $0.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: " ", with: "") }
                    ))
                    .font(.title2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.twitter)
                    .focused($fieldFocused)
                    .submitLabel(.go)
                    .onSubmit { place(.audio) }
                    .accessibilityIdentifier("calls.keypad.field")
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
                .modulaGlass(in: Capsule(), interactive: true)
                Button {
                    handleMode = false
                    entry = ""
                    fieldFocused = false
                } label: {
                    Image(systemName: "circle.grid.3x3.fill").font(.body.weight(.semibold)).foregroundStyle(.primary)
                        .frame(width: 52, height: 52).modulaGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to keypad")
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(locals) { contact in suggestion(contact) }
                    ForEach(others) { person in
                        suggestion(CallsContact(id: person.handle.lowercased(), personID: person.id, handle: person.handle,
                                                name: person.displayName.isEmpty ? "@\(person.handle)" : person.displayName,
                                                avatarURL: person.avatarURL))
                    }
                    if locals.isEmpty && others.isEmpty && !handleQuery.isEmpty {
                        Text("No one found for @\(handleQuery).").font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            CallsGreenCallButton(working: working) { place($0) }
        }
        .padding(.top, 8)
        .onAppear { fieldFocused = true }
        .task(id: handleQuery) {
            let q = handleQuery
            guard q.count >= 2 else { remote = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let page = try? await GreenfieldDiscoverRepository(client: app.client).search(query: q, entityType: "profile", cursor: nil)
            guard !Task.isCancelled else { return }
            let own = app.auth.account?.primaryHandle.lowercased()
            remote = (page?.results.compactMap(\.person) ?? []).filter { $0.handle.lowercased() != own }
        }
    }

    private func suggestion(_ contact: CallsContact) -> some View {
        Button { select(contact) } label: { CallsPersonRow(contact: contact) }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
    }

    private func select(_ contact: CallsContact) {
        entry = "@" + contact.handle
        fieldFocused = false
        HapticEngine.shared.play(.selection)
    }

    private func switchToHandle() {
        if !entry.hasPrefix("@") { entry = "@" }
        handleMode = true
        HapticEngine.shared.play(.selection)
    }

    private func longPress(_ key: String) {
        if key == "0" {
            entry.append("+")
            HapticEngine.shared.play(.selection)
        } else if key == "*" {
            switchToHandle()
        }
    }

    private func append(_ key: String) {
        guard entry.count < 24 else { return }
        entry.append(key)
        note = nil
    }

    private func paste() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        if raw.hasPrefix("@") || raw.contains(where: \.isLetter) {
            entry = "@" + raw.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            handleMode = true
        } else {
            entry = String(raw.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }.prefix(24))
        }
    }

    private func place(_ kind: CallMediaKind) {
        // Empty keypad + call = bring back the last dial (Phone behaviour).
        if entry.isEmpty || entry == "@", let last = local.recentDials.first {
            entry = last
            handleMode = last.hasPrefix("@")
            return
        }
        guard !entry.isEmpty, entry != "@", !working else { return }
        guard caps.canCall else { return CallsActions.comingSoon(app) }
        local.noteDial(entry)
        if handleMode || entry.hasPrefix("@") {
            let q = handleQuery
            if let chat = app.messaging.directConversation(with: q) {
                CallsActions.call(chat.id, kind: kind, app: app)
            } else {
                app.navigation.flash("Say hi first, then you can call", symbol: "message")
                app.navigation.push(.messages(.direct(q)))
            }
            return
        }
        // A single keypad-letters match (e.g. 2-6-2 → "Ana") calls them directly.
        if !caps.callIDs, t9.count == 1, let contact = t9.first {
            return CallsActions.call(contact, kind: kind, app: app)
        }
        guard caps.callIDs else {
            app.navigation.flash("Call IDs are coming soon", symbol: "number")
            return
        }
        guard CallIDFormat.isValid(entry, caps: caps) else {
            note = "Call IDs are \(caps.callIDMinLength)–\(caps.callIDMaxLength) digits."
            return
        }
        working = true
        let id = entry
        Task {
            defer { working = false }
            guard let found = await app.calls.lookupCallID(id) else {
                note = "No one has the call ID \(CallsKeypadFormat.format(id))."
                return
            }
            if let conversationID = found.conversationID {
                CallsActions.call(conversationID, kind: kind, app: app)
            } else if !found.party.handle.isEmpty {
                app.navigation.flash("Say hi first, then you can call", symbol: "message")
                app.navigation.push(.messages(.direct(found.party.handle)))
            }
        }
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
