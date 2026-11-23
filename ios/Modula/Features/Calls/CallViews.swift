import SwiftUI
import UIKit
import AudioToolbox
import Contacts
import Photos
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
            // Keypad and Contacts are full-height like Phone: no section bar (back stays in the bar).
            if tab == .favourites || tab == .recents {
                MessagesScopePicker(selection: .calls)
                if !app.calls.capabilities.canCall {
                    CallsComingSoonCard().padding(.horizontal, ModulaLayout.contentInset).padding(.bottom, 6)
                    if tab == .favourites {
                        ConnectPromoCard().padding(.horizontal, ModulaLayout.contentInset).padding(.bottom, 6)
                    }
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
            // Lists run to the bottom edge and scroll under the floating switcher; this keeps
            // the last rows reachable above it.
            .contentMargins(.bottom, Self.barClearance, for: .scrollContent)
        }
        // t232u: the glass pill floats straight over content: no band, no blur behind it.
        .overlay(alignment: .bottom) { tabBar }
        .modifier(CallsScrollEdges())
        .navigationTitle(tab == .keypad ? "" : tab.title)
        .navigationBarTitleDisplayMode(tab == .contacts ? .large : .inline)
        .animation(.snappy(duration: 0.22), value: tab)
        .task {
            await app.messaging.probeCapabilities()
            await app.messaging.loadInboxIfNeeded()
            await CallsDirectory.loadGraph(app)
        }
        .accessibilityIdentifier("calls.home")
    }

    /// Room the floating switcher takes above the home indicator (pill + its bottom padding).
    static let barClearance: CGFloat = 76

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

    /// Speed: `all` merged chats + following + followers and ran a localized sort on every call; the keypad
    /// alone called it 3–4 times per keystroke. The merged list is now cached behind a cheap signature of its
    /// inputs (ids, names, avatars, hidden set), so repeat calls are a hash pass instead of a rebuild + sort.
    nonisolated(unsafe) private static var cache: (signature: Int, contacts: [CallsContact])?

    static func all(_ app: AppEnvironment) -> [CallsContact] {
        let session = app.profile.session(for: .me, handleHint: app.auth.account?.primaryHandle)
        var hasher = Hasher()
        for chat in app.messaging.conversations where chat.kind == .direct && chat.participants.count == 1 {
            let p = chat.participants[0]
            hasher.combine(chat.id); hasher.combine(p.id); hasher.combine(p.handle); hasher.combine(p.displayName); hasher.combine(p.avatarURL)
        }
        hasher.combine(-1)
        for profile in session.following.items { hasher.combine(profile.id); hasher.combine(profile.displayName); hasher.combine(profile.avatarURL) }
        hasher.combine(-2)
        for profile in session.followers.items { hasher.combine(profile.id); hasher.combine(profile.displayName); hasher.combine(profile.avatarURL) }
        hasher.combine(CallsLocalStore.shared.hiddenContacts)
        let signature = hasher.finalize()
        if let cache, cache.signature == signature {
            ModulaSignpost.event("CallsDirectoryCacheHit")
            return cache.contacts
        }
        let contacts = ModulaSignpost.measure("CallsDirectoryBuild") { build(app, session: session) }
        cache = (signature, contacts)
        return contacts
    }

    private static func build(_ app: AppEnvironment, session: ProfileSessionState) -> [CallsContact] {
        var byKey: [String: CallsContact] = [:]
        for chat in app.messaging.conversations where chat.kind == .direct && chat.participants.count == 1 {
            let p = chat.participants[0]
            let k = key(handle: p.handle, id: p.id)
            byKey[k] = CallsContact(id: k, personID: p.id, handle: p.handle, name: p.displayName.isEmpty ? "@\(p.handle)" : p.displayName,
                                    avatarURL: p.avatarURL, conversationID: chat.id)
        }
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
            Image(systemName: kind == .video ? "video" : "phone")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 32, height: 32)
                .modulaGlass(in: Circle(), interactive: true)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
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
    @State private var noteFor: CallRecord?
    @State private var noteText = ""
    private var notes: CallNotesStore { CallNotesStore.shared }

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
            if !editing, !app.calls.recents.isEmpty {
                CallsStatsCard(records: app.calls.recents)
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .modulaAppear()
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
                            .swipeActions(edge: .leading) {
                                Button("Note", systemImage: "note.text") { editNote(group.latest) }
                                    .tint(.gray)
                            }
                            .contextMenu {
                                Button(notes.note(for: group.latest.id) == nil ? "Add Note" : "Edit Note", systemImage: "note.text") { editNote(group.latest) }
                                Button("Voice Call", systemImage: "phone") { CallsActions.call(group.latest.conversationID, kind: .audio, app: app) }
                                Button("Video Call", systemImage: "video") { CallsActions.call(group.latest.conversationID, kind: .video, app: app) }
                                Button("Message", systemImage: "message") { app.navigation.push(.messages(.conversation(group.latest.conversationID))) }
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
        .alert("Call Note", isPresented: Binding(get: { noteFor != nil }, set: { if !$0 { noteFor = nil } }), presenting: noteFor) { record in
            TextField("What was it about?", text: $noteText, axis: .vertical)
            Button("Save") {
                withAnimation(.snappy) { notes.set(noteText, for: record.id) }
                HapticEngine.shared.play(.success)
            }
            if notes.note(for: record.id) != nil {
                Button("Remove Note", role: .destructive) { notes.set("", for: record.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text("Only you can see notes. Saved on this iPhone for your call with \(record.other.name).")
        }
    }

    private func editNote(_ record: CallRecord) {
        noteText = notes.note(for: record.id) ?? ""
        noteFor = record
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
                        if let note = notes.note(for: record.id) {
                            Label(note, systemImage: "note.text")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Note: \(note)")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
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
                if let detail = extraLine {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

    private var extraLine: String? {
        let store = CallsPersonalStore.shared
        var parts: [String] = []
        if let days = store.upcomingBirthday(contact.id) {
            parts.append(days == 0 ? "Birthday today" : (days == 1 ? "Birthday tomorrow" : "Birthday in \(days) days"))
        }
        let labels = store.extras(contact.id).labels
        if !labels.isEmpty { parts.append(labels.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
    /// Filter id: a `Filter` raw value or "label:<name>" for a contact label.
    @State private var filterID = Filter.all.rawValue
    @State private var detail: CallsContact?
    @State private var importing = false

    private static let green = Color(red: 0.2, green: 0.78, blue: 0.35)

    private func matches(_ c: CallsContact, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let handleNeedle = needle.hasPrefix("@") ? String(needle.dropFirst()) : needle
        return c.name.lowercased().contains(needle) || c.handle.lowercased().hasPrefix(handleNeedle)
    }

    private func passes(_ c: CallsContact) -> Bool {
        if filterID.hasPrefix("label:") {
            return CallsPersonalStore.shared.extras(c.id).labels.contains(String(filterID.dropFirst(6)))
        }
        switch Filter(rawValue: filterID) ?? .all {
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
        let showsIndex = letters.count > 3 && needle.isEmpty
        let recent = needle.isEmpty && filterID == "all" ? CallsRecentlyCalledRow.people(app) : []
        ScrollViewReader { proxy in
            List {
                filterRail
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Recently called").padding(.horizontal, ModulaLayout.contentInset)
                        CallsRecentlyCalledRow(contacts: recent)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if needle.isEmpty { header }
                if contacts.isEmpty {
                    Text(needle.isEmpty ? "People you chat with or follow appear here." : "No one matches “\(query)”.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(letters, id: \.self) { letter in
                    Section {
                        ForEach(sections[letter] ?? []) { contact in
                            contactRow(contact)
                                .listRowInsets(EdgeInsets(top: 6, leading: ModulaLayout.contentInset, bottom: 6,
                                                          trailing: showsIndex ? 34 : ModulaLayout.contentInset))
                        }
                    } header: {
                        sectionTitle(letter)
                    }
                    .id("section-\(letter)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(4)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search name or @handle")
            .overlay(alignment: .trailing) {
                if showsIndex {
                    CallsSectionIndex(letters: letters) { letter in proxy.scrollTo("section-\(letter)", anchor: .top) }
                }
            }
        }
        .sheet(item: $detail) { contact in CallsContactCard(contact: contact) }
        .sheet(isPresented: $importing) { CallsDeviceContactsSheet() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    /// Shared full-width swipeable segmented rail (edge fades), plus your contact labels.
    private var filterRail: some View {
        var segments: [ModulaSegmentedControl<String>.Segment] = Filter.allCases.map { .init(id: $0.rawValue, title: $0.title) }
        for label in CallsPersonalStore.shared.usedLabels {
            segments.append(.init(id: "label:" + label, title: label))
        }
        return ModulaSegmentedControl(segments: segments, selection: $filterID, forceScroll: true,
                                      accessibilityLabel: "Contacts filter", identifier: { "calls.contacts.filter.\($0)" })
            .scrollInset(ModulaLayout.contentInset)
    }

    @ViewBuilder private var header: some View {
        CallsMyCard()
            .listRowInsets(EdgeInsets(top: 4, leading: ModulaLayout.contentInset, bottom: 4, trailing: ModulaLayout.contentInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        Button { importing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus").font(.subheadline).foregroundStyle(.secondary)
                Text("Find friends from iPhone Contacts").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true)
        .listRowInsets(EdgeInsets(top: 2, leading: ModulaLayout.contentInset, bottom: 8, trailing: ModulaLayout.contentInset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("calls.contacts.import")
    }

    /// Tap: card. Swipe right: voice call. Swipe left: video / message. Hold: menu.
    private func contactRow(_ contact: CallsContact) -> some View {
        Button { detail = contact } label: { CallsPersonRow(contact: contact) }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { CallsActions.call(contact, kind: CallsPersonalStore.shared.preferredKind(contact.id), app: app) } label: { Label("Call", systemImage: "phone.fill") }
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
    @State private var showsNumber = false

    private var handle: String { app.auth.account?.primaryHandle ?? "" }
    private var name: String { app.profile.ownProfile?.displayName ?? app.auth.account?.displayName ?? "@\(handle)" }
    private var link: URL? { handle.isEmpty ? nil : URL(string: "https://modula.digital/@\(handle)") }
    private var numberText: String {
        let store = ModulaNumberStore.shared
        guard store.enabled else { return "Modula Number off" }
        return "Modula Number " + ModulaNumberStore.grouped(store.number)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { showsNumber = true } label: {
                HStack(spacing: 12) {
                    ModulaAvatar(initials: String(name.prefix(1)).uppercased(), url: app.profile.ownProfile?.avatarURL, size: 44, name: name)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        Text(numberText).font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("My card, \(name). \(numberText)")
            .accessibilityHint("Opens your Modula Number")
            Button { showsQR = true } label: {
                Image(systemName: "qrcode").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .frame(width: 36, height: 36).modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(link == nil)
            .accessibilityLabel("Share my card")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .sheet(isPresented: $showsQR) {
            if let link { CallsMyCardQRSheet(name: name, handle: handle, callID: app.calls.myCallID, link: link) }
        }
        .sheet(isPresented: $showsNumber) { ModulaNumberSheet() }
        .task { await app.calls.loadMyCallID() }
        .accessibilityIdentifier("calls.contacts.myCard")
    }
}

struct CallsMyCardQRSheet: View {
    let name: String
    let handle: String
    let callID: String?
    let link: URL
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    qrCard
                    VStack(spacing: 4) {
                        Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                        Text("@\(handle)").foregroundStyle(.secondary)
                        if let callID { Text("Call ID \(CallsKeypadFormat.format(callID))").font(.subheadline.weight(.semibold)) }
                    }
                    ShareLink(item: link, subject: Text(name), message: Text("Call me on Modula: @\(handle)")) {
                        Label("Share My Card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.modulaPrimary)
                    HStack(spacing: 10) {
                        glassAction("Copy Handle", "doc.on.doc") {
                            UIPasteboard.general.string = "@\(handle)"
                            app.navigation.flash("Handle copied", symbol: "doc.on.doc")
                        }
                        glassAction("Save Image", "square.and.arrow.down") { saveImage() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("Done").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
        .modulaSheetStyle()
    }

    @ViewBuilder private var qrCard: some View {
        if let matrix = ModulaQRMatrix.make(link.absoluteString) {
            ModulaBrandedQRCode(matrix: matrix, style: .mono, accent: .black) {
                Image(systemName: "phone.fill").font(.title2.weight(.bold)).foregroundStyle(.black)
            }
            .frame(width: 220, height: 220)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
            .accessibilityLabel("QR code for @\(handle)")
        }
    }

    private func glassAction(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true)
    }

    @MainActor private func saveImage() {
        let card = VStack(spacing: 14) {
            qrCard
            Text(name).font(.title3.bold()).foregroundStyle(.black)
            Text("@\(handle) on Modula").font(.subheadline).foregroundStyle(.black.opacity(0.6))
        }
        .padding(28)
        .background(Color.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        Task {
            let ok = (try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) != nil
            app.navigation.flash(ok ? "Saved to Photos" : "Couldn't save. Check Photos access in Settings.", symbol: ok ? "checkmark.circle" : "exclamationmark.triangle")
        }
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
                    CallsContactExtrasSection(contact: contact)
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
                glyph
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

    /// Optically matched glyphs: Phone draws * and # larger than a plain text asterisk.
    @ViewBuilder private var glyph: some View {
        switch digit {
        case "*":
            Image(systemName: "asterisk").font(.system(size: 28, weight: .regular)).frame(height: 45)
        case "#":
            Image(systemName: "number").font(.system(size: 29, weight: .regular)).frame(height: 45)
        default:
            Text(digit).font(.system(size: 38, weight: .regular)).frame(height: 45)
        }
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
    @Environment(\.accessibilityReduceMotion) private var keypadReduceMotion
    @State private var entry = ""
    @State private var handleMode = false
    @State private var working = false
    @State private var note: String?
    @State private var showsAllMatches = false
    @State private var remote: [DiscoverPerson] = []
    @State private var speedDialDigit: CallsPreferencesSheet.SpeedDigit?
    @State private var showsPreferences = false
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
        let matches = t9
        return matches.count == 1 ? matches.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if handleMode {
                handlePanel
            } else {
                Spacer(minLength: 4)
                display
                suggestionRow
                Spacer(minLength: 10)
                grid
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, handleMode ? 0 : CallsHomeView.barClearance + 8)
        // ⋯ and Add-to-Favourites sit in the navigation bar, level with Back.
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) { topBarItems }
        }
        .sheet(item: $speedDialDigit) { CallsSpeedDialPicker(digit: $0.id) }
        .sheet(isPresented: $showsPreferences) { CallsPreferencesSheet() }
        .animation(.snappy(duration: 0.2), value: handleMode)
        .animation(.snappy(duration: 0.15), value: entry.isEmpty)
        .accessibilityIdentifier("calls.keypad")
    }

    // Add to favourites (once a known person is typed) · options.
    @ViewBuilder private var topBarItems: some View {
        if let id = matchedContact?.conversationID {
            let on = app.calls.isFavourite(id)
            Button {
                app.calls.toggleFavourite(id)
                app.navigation.flash(on ? "Removed from Favourites" : "Added to Favourites", symbol: "star")
            } label: {
                Image(systemName: on ? "star.fill" : "star")
            }
            .accessibilityLabel(on ? "Remove from Favourites" : "Add to Favourites")
        }
        Menu {
            Toggle(isOn: $tones) { Label("Key Tones", systemImage: "speaker.wave.2") }
            Button("Speed Dial & Call Settings", systemImage: "slider.horizontal.3") { showsPreferences = true }
            if !local.recentDials.isEmpty {
                Button("Clear Recent Dials", systemImage: "clock.arrow.circlepath") { local.clearDials() }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Keypad options")
    }

    private var display: some View {
        VStack(spacing: 6) {
            Text(entry.isEmpty ? " " : CallsKeypadFormat.format(entry))
                .font(.system(size: 40, weight: .regular).monospacedDigit())
                .foregroundStyle(.primary)
                // Digits roll in/out as they're typed or deleted (instant under Reduce Motion).
                .contentTransition(keypadReduceMotion ? .identity : .numericText(countsDown: false))
                .animation(keypadReduceMotion ? nil : .snappy(duration: 0.18), value: entry)
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
        .modulaHorizontalRail()
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
            // @ · call · delete share the digit columns, so all three line up under * 0 #.
            GridRow {
                handleKey
                CallsGreenCallButton(working: working) { place($0) }
                deleteKey
            }
        }
    }

    private var handleKey: some View {
            Button { switchToHandle() } label: {
                Text("@").font(.system(size: 30, weight: .regular)).foregroundStyle(.primary)
                    .frame(width: 80, height: 80)
                    .modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(CallPressStyle())
            .accessibilityLabel("Type a handle")
            .accessibilityIdentifier("calls.keypad.handle")
    }

    private var deleteKey: some View {
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
                LazyVStack(spacing: 0) {
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
            .contentMargins(.bottom, CallsHomeView.barClearance + 104, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                // Floats on its own shadow, no backdrop band; the list scrolls underneath.
                CallsGreenCallButton(working: working) { place($0) }
                    .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
                    .padding(.bottom, CallsHomeView.barClearance + 12)
                    .frame(maxWidth: .infinity)
            }
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
        VStack(spacing: 0) {
            Button { select(contact) } label: { CallsPersonRow(contact: contact) }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            Divider().padding(.leading, 52)
        }
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
        } else if let n = Int(key), (1...9).contains(n), entry.isEmpty {
            // Speed dial: hold 1–9 on an empty keypad.
            if let slot = CallsPersonalStore.shared.speedDial(key),
               let contact = CallsDirectory.all(app).first(where: { $0.id == slot.id }) {
                CallsActions.call(contact, kind: CallsPersonalStore.shared.preferredKind(contact.id), app: app)
            } else {
                speedDialDigit = CallsPreferencesSheet.SpeedDigit(id: key)
            }
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
                ModulaConnectMark(size: 34)
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
                ModulaConnectMark(size: 44)
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

// MARK: - Modula Connect brand (t237u)

/// The Modula Connect mark: a black/white squircle with a signal dot and two arcs.
/// Arcs pulse outward once on appear (static under Reduce Motion).
struct ModulaConnectMark: View {
    var size: CGFloat = 44
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            shape.fill(Color.modulaPrimaryFill)
            ModulaConnectGlyph(progress: lit || reduceMotion || !animated ? 1 : 0.0)
                .stroke(Color.modulaOnPrimary, style: StrokeStyle(lineWidth: max(1.6, size * 0.075), lineCap: .round))
                .frame(width: size * 0.58, height: size * 0.58)
            Circle().fill(Color.modulaOnPrimary)
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: -size * 0.12, y: size * 0.12)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { lit = true }
        }
        .accessibilityHidden(true)
    }
}

/// Two quarter arcs from the bottom-left corner; `progress` draws them in.
struct ModulaConnectGlyph: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let origin = CGPoint(x: rect.minX + rect.width * 0.29, y: rect.maxY - rect.height * 0.29)
        for (i, r) in [0.42, 0.72].enumerated() {
            let radius = rect.width * r
            let sweep = 90.0 * max(0, min(1, progress * 1.4 - Double(i) * 0.4))
            guard sweep > 0 else { continue }
            p.move(to: CGPoint(x: origin.x, y: origin.y - radius))
            p.addRelativeArc(center: origin, radius: radius, startAngle: .degrees(-90), delta: .degrees(sweep))
        }
        return p
    }
}

/// Mark + "Modula Connect" wordmark, optionally with the hero line.
struct ModulaConnectLogo: View {
    var markSize: CGFloat = 32
    var showsTagline = false
    var animated = true

    var body: some View {
        HStack(spacing: markSize * 0.32) {
            ModulaConnectMark(size: markSize, animated: animated)
            VStack(alignment: .leading, spacing: 1) {
                (Text("Modula ").font(.system(size: markSize * 0.5, weight: .regular))
                 + Text("Connect").font(.system(size: markSize * 0.5, weight: .heavy)))
                    .foregroundStyle(.primary)
                    .fixedSize()
                if showsTagline {
                    Text("Your number. Your way.")
                        .font(.system(size: max(11, markSize * 0.32), weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsTagline ? "Modula Connect. Your number. Your way." : "Modula Connect")
    }
}

/// Branded opening splash for the Connect module (instead of the generic "Opening…" card).
struct ConnectOpeningSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 18) {
            ModulaConnectMark(size: 76)
                .scaleEffect(breathe ? 1.04 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
            VStack(spacing: 4) {
                (Text("Modula ").font(.title2) + Text("Connect").font(.title2.weight(.heavy)))
                Text("Your number. Your way.").font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear { breathe = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening Modula Connect")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("module.host.loading")
    }
}

/// "Want a real phone number?" promo into Connect (Modula Number sheet, Calls).
struct ConnectPromoCard: View {
    @Environment(AppEnvironment.self) private var app
    var onOpen: (() -> Void)? = nil

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            onOpen?()
            app.navigation.open(.module(ConnectPreview.moduleID, localPath: nil))
        } label: {
            HStack(spacing: 14) {
                ModulaConnectMark(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Want a real phone number?").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Modula Connect gives you a UK number inside Modula. Preview.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        .modulaAppear(delay: 0.08)
        .accessibilityIdentifier("connect.promo")
    }
}

// MARK: - Calls personal (local) data: labels, birthday, notes, preferred kind, speed dial,
// blocked callers, quiet hours, ringtone. Everything here stays on this iPhone.

struct CallsContactExtras: Codable, Equatable {
    var labels: [String] = []
    var birthday: Date?
    var notes = ""
    var prefersVideo = false
}

@MainActor @Observable
final class CallsPersonalStore {
    static let shared = CallsPersonalStore()
    static let builtInLabels = ["Family", "Friends", "Work", "Close friends"]
    private static let key = "calls.personal.v1"

    struct Ringtone: Identifiable, Hashable {
        let id: String
        let title: String
        let soundID: UInt32?
    }
    static let ringtones: [Ringtone] = [
        Ringtone(id: "default", title: "iPhone ringtone", soundID: nil),
        Ringtone(id: "anticipate", title: "Anticipate", soundID: 1020),
        Ringtone(id: "bloom", title: "Bloom", soundID: 1021),
        Ringtone(id: "calypso", title: "Calypso", soundID: 1022),
        Ringtone(id: "descent", title: "Descent", soundID: 1024),
        Ringtone(id: "fanfare", title: "Fanfare", soundID: 1025),
        Ringtone(id: "ladder", title: "Ladder", soundID: 1026),
        Ringtone(id: "minuet", title: "Minuet", soundID: 1027),
        Ringtone(id: "noir", title: "Noir", soundID: 1029),
        Ringtone(id: "spell", title: "Spell", soundID: 1031),
        Ringtone(id: "telegraph", title: "Telegraph", soundID: 1033),
        Ringtone(id: "tiptoes", title: "Tiptoes", soundID: 1034),
    ]

    private struct Snapshot: Codable {
        var extras: [String: CallsContactExtras] = [:]
        var customLabels: [String] = []
        var speedDial: [String: String] = [:]
        var speedDialNames: [String: String] = [:]
        var blocked: [String: String] = [:]
        var quietEnabled = false
        var quietStart = 22 * 60
        var quietEnd = 7 * 60
        var quietAllowFavourites = true
        var ringtone = "default"
        var defaultVideo = false
    }

    private var state: Snapshot { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            state = saved
        } else {
            state = Snapshot()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // Per-contact extras
    func extras(_ contactID: String) -> CallsContactExtras { state.extras[contactID] ?? CallsContactExtras() }
    func setExtras(_ value: CallsContactExtras, for contactID: String) {
        state.extras[contactID] = value == CallsContactExtras() ? nil : value
    }
    var allLabels: [String] { Self.builtInLabels + state.customLabels.filter { !Self.builtInLabels.contains($0) } }
    /// Labels someone actually uses (for the Contacts filter rail).
    var usedLabels: [String] {
        let used = Set(state.extras.values.flatMap(\.labels))
        return allLabels.filter { used.contains($0) }
    }
    func addLabel(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !allLabels.contains(clean) else { return }
        state.customLabels.append(clean)
    }
    func preferredKind(_ contactID: String) -> CallMediaKind {
        if let e = state.extras[contactID] { return e.prefersVideo ? .video : .audio }
        return state.defaultVideo ? .video : .audio
    }
    /// Birthdays within the next `days` days (month/day match, any year).
    func upcomingBirthday(_ contactID: String, within days: Int = 7) -> Int? {
        guard let date = state.extras[contactID]?.birthday else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var parts = cal.dateComponents([.month, .day], from: date)
        parts.year = cal.component(.year, from: today)
        guard var next = cal.date(from: parts) else { return nil }
        if next < today, let bumped = cal.date(byAdding: .year, value: 1, to: next) { next = bumped }
        let delta = cal.dateComponents([.day], from: today, to: next).day ?? 999
        return delta <= days ? delta : nil
    }

    // Default call type
    var defaultVideo: Bool { get { state.defaultVideo } set { state.defaultVideo = newValue } }

    // Speed dial (keypad 1–9)
    func speedDial(_ digit: String) -> (id: String, name: String)? {
        guard let id = state.speedDial[digit] else { return nil }
        return (id, state.speedDialNames[digit] ?? id)
    }
    func setSpeedDial(_ digit: String, contact: CallsContact?) {
        state.speedDial[digit] = contact?.id
        state.speedDialNames[digit] = contact?.name
    }
    var speedDialDigits: [String] { (1...9).map(String.init).filter { state.speedDial[$0] != nil } }

    // Blocked callers (local: their calls never ring this iPhone)
    struct BlockedCaller: Identifiable, Hashable { let id: String; let name: String }
    var blocked: [BlockedCaller] {
        state.blocked.map { BlockedCaller(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func isBlocked(handle: String, id: String) -> Bool {
        state.blocked[CallsDirectory.key(handle: handle, id: id)] != nil
    }
    func setBlocked(_ blocked: Bool, contact: CallsContact) {
        state.blocked[contact.id] = blocked ? contact.name : nil
    }
    func unblock(_ key: String) { state.blocked[key] = nil }

    // Quiet hours (Do Not Disturb for calls)
    var quietEnabled: Bool { get { state.quietEnabled } set { state.quietEnabled = newValue } }
    var quietAllowFavourites: Bool { get { state.quietAllowFavourites } set { state.quietAllowFavourites = newValue } }
    var quietStart: Date {
        get { Self.date(minutes: state.quietStart) }
        set { state.quietStart = Self.minutes(newValue) }
    }
    var quietEnd: Date {
        get { Self.date(minutes: state.quietEnd) }
        set { state.quietEnd = Self.minutes(newValue) }
    }
    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    func inQuietHours(_ now: Date = Date()) -> Bool {
        guard state.quietEnabled else { return false }
        let m = Self.minutes(now)
        let s = state.quietStart, e = state.quietEnd
        if s == e { return true }
        return s < e ? (m >= s && m < e) : (m >= s || m < e)
    }

    /// Incoming call screening (blocked callers, quiet hours with optional favourites through).
    func silences(handle: String, id: String, conversationID: String, isFavourite: Bool) -> Bool {
        if isBlocked(handle: handle, id: id) { return true }
        if inQuietHours() { return !(state.quietAllowFavourites && isFavourite) }
        return false
    }

    // Ringtone (preview + choice; CallKit uses the iPhone ringtone until Modula ships sound files)
    var ringtone: String { get { state.ringtone } set { state.ringtone = newValue } }
    static func preview(_ tone: Ringtone) {
        if let id = tone.soundID { AudioServicesPlaySystemSound(id) } else { AudioServicesPlaySystemSound(1007) }
    }
}

/// Calls screens: soft top edge only. No bottom scroll-edge effect, so nothing draws a band
/// behind the floating switcher (t232u).
private struct CallsScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            content
        }
    }
}

/// Recents › stats: calls this week, talk time, missed, most called (from history on this iPhone).
struct CallsStatsCard: View {
    let records: [CallRecord]

    var body: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let week = records.filter { $0.createdAt >= weekAgo }
        let talkMs = week.compactMap(\.durationMs).reduce(0, +)
        let missed = week.filter { CallCopy.isMissed($0) }.count
        let top = Dictionary(grouping: week, by: { $0.other.name }).max { $0.value.count < $1.value.count }
        HStack(spacing: 0) {
            stat("\(week.count)", week.count == 1 ? "call this week" : "calls this week")
            divider
            stat(Self.talk(talkMs), "talk time")
            divider
            stat("\(missed)", "missed")
            if let top, top.value.count > 1 {
                divider
                stat(top.key, "most called")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calls.recents.stats")
    }

    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 30) }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    static func talk(_ ms: Int) -> String {
        let minutes = ms / 60_000
        if minutes < 1 { return ms > 0 ? "<1m" : "0m" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// Contacts › "Recently called": avatars of the last people you called, one tap to call again.
struct CallsRecentlyCalledRow: View {
    let contacts: [CallsContact]
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(contacts) { contact in
                    Button {
                        CallsActions.call(contact, kind: CallsPersonalStore.shared.preferredKind(contact.id), app: app)
                    } label: {
                        VStack(spacing: 6) {
                            ModulaAvatar(initials: contact.initials, url: contact.avatarURL, size: 52, name: contact.name)
                            Text(contact.name.split(separator: " ").first.map(String.init) ?? contact.name)
                                .font(.caption2.weight(.medium)).foregroundStyle(.primary)
                                .fixedSize()
                        }
                        .frame(minWidth: 60)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                    .contextMenu { CallsContactMenu(contact: contact) }
                    .accessibilityLabel("Call \(contact.name)")
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 4)
        }
        .modulaHorizontalRail()
        .accessibilityIdentifier("calls.contacts.recent")
    }

    /// Unique people from recents, newest first, matched to contacts.
    @MainActor static func people(_ app: AppEnvironment, limit: Int = 10) -> [CallsContact] {
        let all = CallsDirectory.all(app)
        var seen = Set<String>()
        var out: [CallsContact] = []
        for record in app.calls.recents where out.count < limit {
            guard let c = all.first(where: { $0.conversationID == record.conversationID || $0.personID == record.other.id }),
                  !seen.contains(c.id) else { continue }
            seen.insert(c.id)
            out.append(c)
        }
        return out
    }
}

/// Contact card › local details: labels, birthday, notes, preferred call type, block calls.
struct CallsContactExtrasSection: View {
    let contact: CallsContact
    @State private var extras = CallsContactExtras()
    @State private var newLabel = ""
    @State private var addingLabel = false
    @State private var hasBirthday = false

    private var store: CallsPersonalStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On this iPhone").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                labelsRow
                Divider()
                HStack {
                    Text("Default call")
                    Spacer()
                    ModulaSegmentedControl("Default call", selection: $extras.prefersVideo,
                                           segments: [(false, "Voice"), (true, "Video")], compact: true)
                        .fixedSize()
                }
                Divider()
                Toggle("Birthday", isOn: $hasBirthday)
                if hasBirthday {
                    DatePicker("Date", selection: Binding(get: { extras.birthday ?? Date() }, set: { extras.birthday = $0 }),
                               displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(.primary)
                }
                Divider()
                TextField("Notes", text: $extras.notes, axis: .vertical)
                    .lineLimit(2...6)
                Divider()
                Toggle("Block calls from \(contact.name)", isOn: Binding(
                    get: { store.isBlocked(handle: contact.handle, id: contact.personID) },
                    set: { store.setBlocked($0, contact: contact) }
                ))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
            Text("Labels, birthday, notes and call blocking stay on this iPhone.")
                .font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
        }
        .onAppear {
            extras = store.extras(contact.id)
            if extras.labels.isEmpty, extras == CallsContactExtras() { extras.prefersVideo = store.defaultVideo }
            hasBirthday = extras.birthday != nil
        }
        .onChange(of: extras) { _, value in store.setExtras(value, for: contact.id) }
        .onChange(of: hasBirthday) { _, on in
            if !on { extras.birthday = nil } else if extras.birthday == nil { extras.birthday = Date() }
        }
        .alert("New label", isPresented: $addingLabel) {
            TextField("Label", text: $newLabel)
            Button("Add") {
                store.addLabel(newLabel)
                let clean = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty, !extras.labels.contains(clean) { extras.labels.append(clean) }
                newLabel = ""
            }
            Button("Cancel", role: .cancel) { newLabel = "" }
        }
        .accessibilityIdentifier("calls.contact.extras")
    }

    private var labelsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.allLabels, id: \.self) { label in
                        let on = extras.labels.contains(label)
                        Button {
                            HapticEngine.shared.play(.selection)
                            if on { extras.labels.removeAll { $0 == label } } else { extras.labels.append(label) }
                        } label: {
                            Text(label).font(.subheadline.weight(.semibold))
                                .foregroundStyle(on ? Color.modulaOnPrimary : Color.primary)
                                .padding(.horizontal, 12).frame(minHeight: 32)
                                .background { if on { Capsule().fill(Color.modulaPrimaryFill) } }
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Button { addingLabel = true } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true)
                    .accessibilityLabel("New label")
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Keypad › hold 1–9 on an empty key: choose who that number calls.
struct CallsSpeedDialPicker: View {
    let digit: String
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let needle = query.lowercased()
        let people = CallsDirectory.all(app).filter { needle.isEmpty || $0.name.lowercased().contains(needle) || $0.handle.lowercased().hasPrefix(needle) }
        NavigationStack {
            List {
                if CallsPersonalStore.shared.speedDial(digit) != nil {
                    Button("Clear speed dial \(digit)", systemImage: "xmark.circle") {
                        CallsPersonalStore.shared.setSpeedDial(digit, contact: nil)
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                    .listRowBackground(Color.clear)
                }
                ForEach(people) { contact in
                    Button {
                        CallsPersonalStore.shared.setSpeedDial(digit, contact: contact)
                        app.navigation.flash("Hold \(digit) to call \(contact.name)", symbol: "star")
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ModulaAvatar(initials: contact.initials, url: contact.avatarURL, size: 36, name: contact.name)
                            Text(contact.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Search name or @handle")
            .navigationTitle("Speed dial \(digit)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
    }
}

/// Settings › Appearance › Calls preferences row.
struct CallsPreferencesRow: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "phone.badge.checkmark").font(.body.weight(.semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calls").font(.body.weight(.semibold))
                    Text("Default call, quiet hours, blocked callers, ringtone, speed dial")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        .sheet(isPresented: $open) { CallsPreferencesSheet() }
        .accessibilityIdentifier("settings.calls.preferences")
    }
}

struct CallsPreferencesSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pickingBlock = false
    @State private var speedDigit: SpeedDigit?

    struct SpeedDigit: Identifiable { let id: String }

    var body: some View {
        @Bindable var store = CallsPersonalStore.shared
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Default call")
                        Spacer()
                        ModulaSegmentedControl("Default call", selection: $store.defaultVideo,
                                               segments: [(false, "Voice"), (true, "Video")], compact: true)
                            .fixedSize()
                    }
                    .listRowBackground(CallsRowGlass())
                } footer: {
                    Text("Used by swipe-to-call, Recently called and speed dial. Each contact can override it.")
                }

                Section {
                    Toggle("Quiet hours", isOn: $store.quietEnabled)
                        .listRowBackground(CallsRowGlass())
                    if store.quietEnabled {
                        DatePicker("From", selection: $store.quietStart, displayedComponents: .hourAndMinute).tint(.primary)
                            .listRowBackground(CallsRowGlass())
                        DatePicker("Until", selection: $store.quietEnd, displayedComponents: .hourAndMinute).tint(.primary)
                            .listRowBackground(CallsRowGlass())
                        Toggle("Allow Favourites", isOn: $store.quietAllowFavourites)
                            .listRowBackground(CallsRowGlass())
                    }
                } header: {
                    Text("Do Not Disturb")
                } footer: {
                    Text(store.inQuietHours() ? "Quiet now: incoming Modula calls won't ring." : "Incoming Modula calls won't ring during these hours; they show in Recents as missed.")
                }

                Section {
                    ForEach(store.blocked) { entry in
                        HStack {
                            Text(entry.name).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Unblock") { store.unblock(entry.id) }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                .buttonStyle(.borderless)
                        }
                        .listRowBackground(CallsRowGlass())
                    }
                    Button { pickingBlock = true } label: { Label("Block a caller…", systemImage: "hand.raised") }
                        .foregroundStyle(.primary)
                        .listRowBackground(CallsRowGlass())
                } header: {
                    Text("Blocked callers")
                } footer: {
                    Text("Their Modula calls never ring this iPhone. They can still message you; block them in Chats to stop that too.")
                }

                Section {
                    ForEach(CallsPersonalStore.ringtones) { tone in
                        Button {
                            store.ringtone = tone.id
                            CallsPersonalStore.preview(tone)
                            HapticEngine.shared.play(.selection)
                        } label: {
                            HStack {
                                Text(tone.title).foregroundStyle(.primary)
                                Spacer()
                                if store.ringtone == tone.id { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.primary) }
                            }
                        }
                        .listRowBackground(CallsRowGlass())
                    }
                } header: {
                    Text("Ringtone")
                } footer: {
                    Text("Tap to preview. Calls that arrive while Modula is closed use your iPhone ringtone for now.")
                }

                Section {
                    ForEach((1...9).map(String.init), id: \.self) { digit in
                        Button { speedDigit = SpeedDigit(id: digit) } label: {
                            HStack {
                                Text(digit).font(.body.weight(.semibold).monospacedDigit()).frame(width: 24)
                                Text(store.speedDial(digit)?.name ?? "Not set")
                                    .foregroundStyle(store.speedDial(digit) == nil ? Color.secondary : Color.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .listRowBackground(CallsRowGlass())
                    }
                } header: {
                    Text("Speed dial")
                } footer: {
                    Text("On the keypad, touch and hold a number to call that person.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Calls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
            .sheet(isPresented: $pickingBlock) { CallsBlockPicker() }
            .sheet(item: $speedDigit) { CallsSpeedDialPicker(digit: $0.id) }
        }
        .presentationDetents([.large])
        .modulaSheetStyle()
        .accessibilityIdentifier("calls.preferences")
    }
}

private struct CallsBlockPicker: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let needle = query.lowercased()
        let store = CallsPersonalStore.shared
        let people = CallsDirectory.all(app).filter {
            !store.isBlocked(handle: $0.handle, id: $0.personID) && (needle.isEmpty || $0.name.lowercased().contains(needle) || $0.handle.lowercased().hasPrefix(needle))
        }
        NavigationStack {
            List(people) { contact in
                Button {
                    store.setBlocked(true, contact: contact)
                    app.navigation.flash("Calls from \(contact.name) blocked", symbol: "hand.raised")
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ModulaAvatar(initials: contact.initials, url: contact.avatarURL, size: 36, name: contact.name)
                        Text(contact.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Search name or @handle")
            .navigationTitle("Block a caller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MessagesDoneButton { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
    }
}

/// Glass list-row background for Calls lists and sheets.
struct CallsRowGlass: View {
    var body: some View { Color.clear.modulaGlass(in: Rectangle(), interactive: false) }
}

// MARK: - Modula Number (in-app number people can use to reach you; not a phone number)

@MainActor @Observable
final class ModulaNumberStore {
    static let shared = ModulaNumberStore()
    private static let key = "modula.number.v1"

    enum Reach: String, Codable, CaseIterable, Identifiable {
        case everyone, withSecret, followers, contacts, nobody
        var id: Self { self }
        var title: String {
            switch self {
            case .everyone: "Everyone with my number"
            case .withSecret: "Only with number + secret"
            case .followers: "People who follow me"
            case .contacts: "My contacts only"
            case .nobody: "Nobody"
            }
        }
        var symbol: String {
            switch self {
            case .everyone: "globe"
            case .withSecret: "key"
            case .followers: "person.2"
            case .contacts: "person.crop.circle"
            case .nobody: "nosign"
            }
        }
    }

    enum SecretKind: String, Codable, CaseIterable, Identifiable {
        case phrase, code
        var id: Self { self }
        var title: String { self == .phrase ? "Phrase" : "Code" }
    }

    struct Temporary: Codable, Identifiable, Hashable {
        var id = UUID().uuidString
        var number: String
        var label: String
        var created = Date()
        var expires: Date?
        var usesLeft: Int?
        var maxUses: Int?
        /// 0…1 left (time for expiring numbers, uses for counted ones) for the countdown ring.
        func remaining(at now: Date = Date()) -> Double {
            if let expires {
                let total = expires.timeIntervalSince(created)
                return total > 0 ? max(0, min(1, expires.timeIntervalSince(now) / total)) : 0
            }
            if let usesLeft, let maxUses, maxUses > 0 { return max(0, min(1, Double(usesLeft) / Double(maxUses))) }
            return 1
        }
        var isActive: Bool {
            if let expires, expires < Date() { return false }
            if let usesLeft, usesLeft <= 0 { return false }
            return true
        }
        var status: String {
            if !isActive { return "Expired" }
            if let usesLeft { return usesLeft == 1 ? "1 use left" : "\(usesLeft) uses left" }
            if let expires { return "Expires " + expires.formatted(.relative(presentation: .named)) }
            return "Active"
        }
    }

    struct Visit: Codable, Identifiable, Hashable {
        var id = UUID().uuidString
        var name: String
        var handle: String
        var kind: String
        var date = Date()
    }

    private struct Snapshot: Codable {
        var number = ModulaNumberStore.generate()
        var enabled = true
        var hidden = false
        var reach: Reach = .everyone
        var secretKind: SecretKind = .phrase
        var secret = ""
        var allowChat = true
        var allowVoice = true
        var allowVideo = true
        var numberOnlyToRequests = true
        var temporaries: [Temporary] = []
        var visits: [Visit] = []
    }

    private var state: Snapshot { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            state = saved
        } else {
            state = Snapshot()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    nonisolated static func generate() -> String {
        var digits = String(Int.random(in: 1...9))
        for _ in 0..<7 { digits += String(Int.random(in: 0...9)) }
        return digits
    }

    nonisolated static func grouped(_ number: String) -> String {
        guard number.count == 8 else { return CallsKeypadFormat.format(number) }
        return String(number.prefix(4)) + " " + String(number.suffix(4))
    }

    var number: String { state.number }
    var enabled: Bool { get { state.enabled } set { state.enabled = newValue } }
    var hidden: Bool { get { state.hidden } set { state.hidden = newValue } }
    var reach: Reach { get { state.reach } set { state.reach = newValue } }
    var secretKind: SecretKind { get { state.secretKind } set { state.secretKind = newValue } }
    var secret: String { get { state.secret } set { state.secret = newValue } }
    var allowChat: Bool { get { state.allowChat } set { state.allowChat = newValue } }
    var allowVoice: Bool { get { state.allowVoice } set { state.allowVoice = newValue } }
    var allowVideo: Bool { get { state.allowVideo } set { state.allowVideo = newValue } }
    var numberOnlyToRequests: Bool { get { state.numberOnlyToRequests } set { state.numberOnlyToRequests = newValue } }
    var temporaries: [Temporary] { state.temporaries }
    var visits: [Visit] { state.visits }

    var secretIsValid: Bool {
        switch state.secretKind {
        case .phrase: return state.secret.trimmingCharacters(in: .whitespaces).count >= 3
        case .code: return (4...6).contains(state.secret.count) && state.secret.allSatisfy(\.isNumber)
        }
    }

    var shareLink: URL { URL(string: "https://modula.digital/n/\(state.number)")! }

    func regenerate() {
        adopt(Self.generate())
    }

    /// Switch to a specific new number (the Refresh sheet previews it first).
    func adopt(_ number: String) {
        state.number = number
        state.visits = []
    }

    func addTemporary(label: String, expires: TimeInterval?, uses: Int?) {
        let temp = Temporary(number: Self.generate(), label: label,
                             expires: expires.map { Date().addingTimeInterval($0) }, usesLeft: uses, maxUses: uses)
        state.temporaries.insert(temp, at: 0)
    }

    func removeTemporary(_ id: String) { state.temporaries.removeAll { $0.id == id } }
    func clearExpired() { state.temporaries.removeAll { !$0.isActive } }
}

/// Settings › Appearance › Modula Number row.
struct ModulaNumberSettingsRow: View {
    @State private var open = false

    var body: some View {
        let store = ModulaNumberStore.shared
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.grid.3x3").font(.body.weight(.semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modula Number").font(.body.weight(.semibold))
                    Text(store.enabled ? ModulaNumberStore.grouped(store.number) + " · " + store.reach.title : "Off")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        .sheet(isPresented: $open) { ModulaNumberSheet() }
        .accessibilityIdentifier("settings.modulaNumber")
    }
}

/// "Modula Number" sheet (Calls › My card, Settings, inbox menu). One self-contained layout:
/// a ScrollView of glass cards, so it never inherits the presenter's List style (from Calls it
/// was presented inside a `.plain` List and its own List rendered edge to edge). Local preview
/// until the server declares number support (`calls.callIDs`); see CALLS-BACKEND.md.
struct ModulaNumberSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var heroScheme
    private var heroScrim: Color { heroScheme == .dark ? Color(hex: "#05040C") : Color(hex: "#F6F5FB") }
    @State private var refreshing = false
    @State private var confirmBlockRefresh = false
    @State private var showsQR = false
    @State private var copied = false
    @State private var shareBounce = 0
    @State private var qrBounce = 0
    @State private var revealSecret = false
    @State private var glow = false

    static let margin: CGFloat = 20
    private var isPreview: Bool { !app.calls.capabilities.callIDs }
    private var store: ModulaNumberStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    actionRow
                    ModulaNumberCard(footer: "Hidden: your number isn't shown on your profile or in calls. People who already have it can still reach you by your rules below.") {
                        toggleRow("Enabled", isOn: Binding(get: { store.enabled }, set: { v in animate { store.enabled = v } }))
                        ModulaNumberDivider()
                        toggleRow("Hide number from others", isOn: Binding(get: { store.hidden }, set: { v in animate { store.hidden = v } }))
                    }
                    if store.enabled {
                        Group {
                            reachSection
                            allowSection
                            temporarySection
                            safetySection
                            activitySection
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    ConnectPromoCard { dismiss() }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Modula Number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("Done").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $refreshing) {
                ModulaNumberRefreshSheet(old: store.number) { new in
                    refreshing = false
                    adopt(new)
                }
            }
            .confirmationDialog("Block everyone who used your number and get a new one?", isPresented: $confirmBlockRefresh, titleVisibility: .visible) {
                Button("Block & Get New Number", role: .destructive) {
                    adopt(ModulaNumberStore.generate())
                    app.navigation.flash("Old number retired", symbol: "hand.raised")
                }
            } message: { Text("Anyone who only had your old number can't reach you any more.") }
            .sheet(isPresented: $showsQR) { qrSheet }
        }
        // Self-contained: never pick up a List/Form style or tint from whoever presented it.
        .listStyle(.insetGrouped)
        .presentationDetents([.large])
        .modulaSheetStyle()
        .accessibilityIdentifier("modulaNumber.sheet")
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.snappy(duration: 0.3)) { change() } }
    }

    private func adopt(_ number: String) {
        animate { store.adopt(number) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 650))
            HapticEngine.shared.play(.success)
            withAnimation(.easeOut(duration: 0.25)) { glow = true }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.6)) { glow = false }
        }
        app.navigation.flash("New number: \(ModulaNumberStore.grouped(number))", symbol: "arrow.clockwise")
    }

    // MARK: Hero

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(spacing: 14) {
            HStack(spacing: 6) {
                statusPill(store.enabled ? "Enabled" : "Off", store.enabled ? "checkmark.circle.fill" : "pause.circle")
                if store.hidden { statusPill("Hidden", "eye.slash").transition(.scale.combined(with: .opacity)) }
                if isPreview { statusPill("Preview", "sparkles") }
            }
            ModulaNumberDigits(number: store.number, hidden: store.hidden, dimmed: !store.enabled, glow: glow)
            Text("Share it instead of your handle. It's a Modula number for chats and calls, not a phone number.")
                .font(.footnote).foregroundStyle(.primary.opacity(0.78)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                SpectralRibbonsView(accent: app.appearance.liveAccent, intensity: 0.75)
                // Legibility band behind the digits and caption (soft, no hard edge).
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: heroScrim.opacity(0.55), location: 0.32),
                                       .init(color: heroScrim.opacity(0.6), location: 0.78),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
            .accessibilityHidden(true)
        }
        .modulaGlass(in: shape, interactive: false)
        .clipShape(shape)
    }

    private func statusPill(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10).frame(minHeight: 26)
            .fixedSize()
            .modulaGlass(in: Capsule(), interactive: false)
    }

    // MARK: Actions (4 equal glass buttons)

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc", bounce: 0) {
                UIPasteboard.general.string = store.number
                app.navigation.flash("Number copied", symbol: "doc.on.doc")
                withAnimation(.snappy) { copied = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.snappy) { copied = false }
                }
            }
            ShareLink(item: store.shareLink, subject: Text("My Modula Number"),
                      message: Text("Reach me on Modula: \(ModulaNumberStore.grouped(store.number))")) {
                actionLabel("Share", "square.and.arrow.up", bounce: shareBounce)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .selection))
            .simultaneousGesture(TapGesture().onEnded { shareBounce += 1 })
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            actionButton("QR", "qrcode", bounce: qrBounce) {
                qrBounce += 1
                showsQR = true
            }
            actionButton("Refresh", "arrow.clockwise", bounce: 0) { refreshing = true }
        }
        .disabled(!store.enabled)
        .opacity(store.enabled ? 1 : 0.45)
    }

    private func actionLabel(_ title: String, _ symbol: String, bounce: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounce)
                .frame(height: 22)
            Text(title).font(.caption.weight(.semibold)).fixedSize()
                .contentTransition(.opacity)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 66)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionButton(_ title: String, _ symbol: String, bounce: Int, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(title, symbol, bounce: bounce) }
            .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .selection))
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            .accessibilityLabel(title)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }

    // MARK: Sections

    private var reachSection: some View {
        ModulaNumberCard(header: "Who can reach me", footer: reachFooter) {
            ForEach(Array(ModulaNumberStore.Reach.allCases.enumerated()), id: \.element) { index, option in
                if index > 0 { ModulaNumberDivider() }
                let on = store.reach == option
                Button {
                    HapticEngine.shared.play(.selection)
                    animate { store.reach = option }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbol).font(.body).frame(width: 24)
                        Text(option.title).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(app.appearance.liveAccent)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background { if on { Color.primary.opacity(0.06) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            if store.reach == .withSecret {
                ModulaNumberDivider()
                secretEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var reachFooter: String {
        guard store.reach == .withSecret else { return "Applies to anyone who finds you by number." }
        return "People need your number and this secret to start a chat or call."
    }

    @ViewBuilder private var secretEditor: some View {
        @Bindable var model = ModulaNumberStore.shared
        VStack(alignment: .leading, spacing: 10) {
            ModulaSegmentedControl("Secret type", selection: Binding(get: { model.secretKind }, set: { v in animate { model.secretKind = v; model.secret = "" } }),
                                   segments: ModulaNumberStore.SecretKind.allCases.map { ($0, $0.title) })
            HStack(spacing: 10) {
                Group {
                    if revealSecret {
                        TextField(model.secretKind == .phrase ? "Secret phrase" : "4–6 digit code", text: $model.secret)
                    } else {
                        SecureField(model.secretKind == .phrase ? "Secret phrase" : "4–6 digit code", text: $model.secret)
                    }
                }
                .keyboardType(model.secretKind == .code ? .numberPad : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { withAnimation(.snappy) { revealSecret.toggle() } } label: {
                    Image(systemName: revealSecret ? "eye.slash" : "eye")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealSecret ? "Hide secret" : "Show secret")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            let hint = ModulaNumberSecretStrength.evaluate(model.secret, kind: model.secretKind)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < hint.level ? Color.primary : Color.primary.opacity(0.15))
                        .frame(height: 4)
                }
            }
            .animation(.snappy, value: hint.level)
            Text(hint.text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(16)
    }

    private var allowSection: some View {
        ModulaNumberCard(header: "By number, allow", footer: "Messages from people who only have your number wait in Requests until you accept.") {
            toggleRow("Chats", isOn: Binding(get: { store.allowChat }, set: { store.allowChat = $0 }))
            ModulaNumberDivider()
            toggleRow("Voice calls", isOn: Binding(get: { store.allowVoice }, set: { store.allowVoice = $0 }))
            ModulaNumberDivider()
            toggleRow("Video calls", isOn: Binding(get: { store.allowVideo }, set: { store.allowVideo = $0 }))
            ModulaNumberDivider()
            toggleRow("New people go to Requests", isOn: Binding(get: { store.numberOnlyToRequests }, set: { store.numberOnlyToRequests = $0 }))
        }
    }

    private var temporarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModulaNumberSectionHeader(title: "Temporary numbers")
            ForEach(store.temporaries) { temp in
                ModulaTemporaryNumberCard(temp: temp) {
                    UIPasteboard.general.string = temp.number
                    app.navigation.flash("Temporary number copied", symbol: "doc.on.doc")
                } onDelete: {
                    animate { store.removeTemporary(temp.id) }
                }
                .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
            }
            Menu {
                Button("Expires in 24 hours", systemImage: "clock") { addTemp("24 hours", 86_400, nil) }
                Button("Expires in 7 days", systemImage: "calendar") { addTemp("7 days", 7 * 86_400, nil) }
                Button("Works once", systemImage: "1.circle") { addTemp("One use", nil, 1) }
                Button("Works 5 times", systemImage: "5.circle") { addTemp("5 uses", nil, 5) }
            } label: {
                Label("New temporary number", systemImage: "plus")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            if store.temporaries.contains(where: { !$0.isActive }) {
                Button("Clear expired") { animate { store.clearExpired() } }
                    .font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                    .padding(.leading, 16)
            }
            ModulaNumberSectionFooter(text: "For strangers, sellers or one-off meetups. They stop working on their own, and your main number stays private.")
        }
    }

    private func addTemp(_ label: String, _ expires: TimeInterval?, _ uses: Int?) {
        HapticEngine.shared.play(.selection)
        animate { store.addTemporary(label: label, expires: expires, uses: uses) }
    }

    private var safetySection: some View {
        ModulaNumberCard(footer: "One tap if your number gets passed around.") {
            Button { confirmBlockRefresh = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised").frame(width: 24)
                    Text("Block & get a new number")
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var activitySection: some View {
        ModulaNumberCard(header: "Reached you by number") {
            if store.visits.isEmpty {
                Text(isPreview ? "Shows here once Modula Numbers are live." : "No one has used your number yet.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(store.visits.enumerated()), id: \.element.id) { index, visit in
                    if index > 0 { ModulaNumberDivider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visit.name).fixedSize(horizontal: false, vertical: true)
                            Text("@\(visit.handle) · \(visit.kind)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(visit.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                }
            }
        }
    }

    private var qrSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let matrix = ModulaQRMatrix.make(store.shareLink.absoluteString) {
                    ModulaBrandedQRCode(matrix: matrix, style: .mono, accent: .black) {
                        Image(systemName: "circle.grid.3x3.fill").font(.title2.weight(.bold)).foregroundStyle(.black)
                    }
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
                    .transition(.scale.combined(with: .opacity))
                }
                Text(ModulaNumberStore.grouped(store.number)).font(.system(.title, design: .monospaced).weight(.semibold))
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showsQR = false } label: {
                        Text("Done").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium])
        .modulaSheetStyle()
    }
}

// MARK: Modula Number building blocks

/// Inset grouped glass card with an optional header/footer aligned to the card's 16pt content inset.
struct ModulaNumberCard<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header { ModulaNumberSectionHeader(title: header) }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let footer { ModulaNumberSectionFooter(text: footer) }
        }
    }
}

struct ModulaNumberSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ModulaNumberSectionFooter: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }
}

struct ModulaNumberDivider: View {
    var body: some View { Divider().padding(.leading, 16) }
}

/// Monospaced grouped digits that roll like an odometer (staggered per digit) when the number
/// changes, count in from zeros on appear, and blur to dots when hidden. Reduce Motion: cross-fade.
struct ModulaNumberDigits: View {
    let number: String
    let hidden: Bool
    var dimmed = false
    var glow = false
    var size: CGFloat = 46
    /// Roll from this number on appear (the Refresh sheet: old → new). nil = from zeros.
    var startFrom: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String?

    var body: some View {
        let chars = Array(ModulaNumberStore.grouped(shown ?? number))
        HStack(spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { index, char in
                if char == " " {
                    Text(" ")
                } else {
                    Text(hidden ? "•" : String(char))
                        .contentTransition(reduceMotion || hidden ? .opacity : .numericText(value: Double(char.wholeNumberValue ?? 0)))
                        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                   : .spring(response: 0.55, dampingFraction: 0.78).delay(Double(index) * 0.045), value: shown)
                        .animation(.easeInOut(duration: 0.25), value: hidden)
                }
            }
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .foregroundStyle(dimmed ? Color.secondary : Color.primary)
        .blur(radius: hidden && !reduceMotion ? 0.6 : 0)
        .shadow(color: Color.primary.opacity(glow ? 0.55 : 0), radius: glow ? 18 : 0)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .onAppear {
            guard shown == nil else { return }
            if reduceMotion { shown = number; return }
            shown = startFrom ?? String(repeating: "0", count: number.count)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                shown = number
            }
        }
        .onChange(of: number) { _, value in shown = value }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? "Number hidden" : "Modula Number " + number.map(String.init).joined(separator: " "))
    }
}

enum ModulaNumberSecretStrength {
    struct Hint { let level: Int; let text: String }

    static func evaluate(_ value: String, kind: ModulaNumberStore.SecretKind) -> Hint {
        switch kind {
        case .code:
            guard !value.isEmpty else { return Hint(level: 0, text: "Use 4 to 6 digits.") }
            guard value.allSatisfy(\.isNumber), (4...6).contains(value.count) else { return Hint(level: 1, text: "Use 4 to 6 digits.") }
            let digits = value.compactMap(\.wholeNumberValue)
            let same = Set(digits).count == 1
            let steps = zip(digits, digits.dropFirst()).map { $1 - $0 }
            let sequential = Set(steps).count == 1 && (steps.first == 1 || steps.first == -1)
            if same || sequential { return Hint(level: 1, text: "Easy to guess. Avoid repeats and runs like 1234.") }
            return Hint(level: value.count >= 6 ? 3 : 2, text: value.count >= 6 ? "Strong code." : "Good. Six digits is stronger.")
        case .phrase:
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { return Hint(level: trimmed.isEmpty ? 0 : 1, text: "Use at least 3 characters.") }
            let words = trimmed.split(separator: " ").count
            if trimmed.count >= 12 || words >= 3 { return Hint(level: 3, text: "Strong phrase.") }
            if trimmed.count >= 7 { return Hint(level: 2, text: "Good. A few words make it stronger.") }
            return Hint(level: 1, text: "Short phrases are easy to guess.")
        }
    }
}

/// Temporary number as a glass card with a countdown ring (time or uses left).
struct ModulaTemporaryNumberCard: View {
    let temp: ModulaNumberStore.Temporary
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var copied = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let left = temp.remaining(at: context.date)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
                    Circle().trim(from: 0, to: left)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: left)
                    Image(systemName: temp.expires != nil ? "clock" : "number")
                        .font(.caption.weight(.semibold))
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ModulaNumberStore.grouped(temp.number))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(temp.isActive ? Color.primary : Color.secondary)
                    Text("\(temp.label) · \(temp.status)").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if temp.isActive {
                    Button {
                        onCopy()
                        withAnimation(.snappy) { copied = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(.snappy) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true)
                    .accessibilityLabel("Copy temporary number")
                }
                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .modulaGlass(in: Circle(), interactive: true)
                .accessibilityLabel("More for this number")
            }
            .padding(14)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
            .opacity(temp.isActive ? 1 : 0.6)
        }
    }
}

/// Glass confirmation for Refresh: old number → new one rolling in. Shuffle for another.
struct ModulaNumberRefreshSheet: View {
    let old: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var candidate = ModulaNumberStore.generate()

    var body: some View {
        VStack(spacing: 18) {
            Text("Get a new number?").font(.title3.bold())
            VStack(spacing: 6) {
                Text("Current").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(ModulaNumberStore.grouped(old))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                Image(systemName: "arrow.down").font(.footnote.weight(.bold)).foregroundStyle(.secondary).padding(.vertical, 2)
                Text("New").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ModulaNumberDigits(number: candidate, hidden: false, size: 40, startFrom: old)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
            Text("Your old number stops working straight away. Temporary numbers keep working.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { onConfirm(candidate) } label: {
                Text("Use New Number").frame(maxWidth: .infinity)
            }
            .buttonStyle(.modulaPrimary)
            HStack(spacing: 10) {
                glass("Shuffle", "shuffle") {
                    HapticEngine.shared.play(.selection)
                    candidate = ModulaNumberStore.generate()
                }
                glass("Cancel", "xmark") { dismiss() }
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .modulaSheetStyle()
        .accessibilityIdentifier("modulaNumber.refresh")
    }

    private func glass(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true)
    }
}


// MARK: - Call notes (local, t235u)

@MainActor @Observable
final class CallNotesStore {
    static let shared = CallNotesStore()
    private static let key = "calls.notes.v1"
    private var notes: [String: String]

    private init() {
        notes = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func note(for callID: String) -> String? {
        guard let text = notes[callID], !text.isEmpty else { return nil }
        return text
    }

    func set(_ text: String, for callID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[callID] = trimmed.isEmpty ? nil : String(trimmed.prefix(500))
        UserDefaults.standard.set(notes, forKey: Self.key)
    }
}
