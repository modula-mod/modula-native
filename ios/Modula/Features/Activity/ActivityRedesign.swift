import SwiftUI
import UIKit

// MARK: - Filter chips

/// Client-side categories over the loaded notifications feed. The API has no
/// per-category query for replies/reposts/Moliboos, so matching happens here.
enum ActivityChip: String, CaseIterable, Identifiable, Hashable {
    case all, mentions, replies, follows, reactions, reposts, modules, moliboos
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"; case .mentions: "Mentions"; case .replies: "Replies"
        case .follows: "Follows"; case .reactions: "Reactions"; case .reposts: "Reposts"
        case .modules: "Modules"; case .moliboos: "Moliboos"
        }
    }
    var symbol: String {
        switch self {
        case .all: "bell.fill"; case .mentions: "at"; case .replies: "arrowshape.turn.up.left.fill"
        case .follows: "person.2.fill"; case .reactions: "heart.fill"; case .reposts: "arrow.2.squarepath"
        case .modules: "shippingbox.fill"; case .moliboos: "pawprint.fill"
        }
    }
    func matches(_ event: ActivityEvent) -> Bool {
        switch self {
        case .all: true
        case .mentions: event.kind == .mention
        case .replies: event.kind == .comment
        case .follows: [.follow, .followRequest, .followAccepted].contains(event.kind)
        case .reactions: event.kind == .like || event.kind == .reaction
        case .reposts: event.kind == .repost || event.kind == .share
        case .modules: [.moduleEvent, .moduleUpdate].contains(event.kind)
        case .moliboos: event.kind == .moliboo
        }
    }
}

/// Liquid Glass chip strip. The selected chip grows an icon and an accent glass
/// fill that morphs between chips; unread counts ride along as small numerals.
struct ActivityChipBar: View {
    @Binding var selection: ActivityChip
    var unread: [ActivityChip: Int]
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Namespace private var chipSpace

    var body: some View {
        let accent = app.appearance.liveAccent
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ModulaGlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(ActivityChip.allCases) { chip in
                            chipButton(chip, accent: accent, calm: calm)
                                .id(chip)
                        }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.vertical, 6)
                }
            }
            .scrollClipDisabled()
            .onAppear { if selection != .all { proxy.scrollTo(selection, anchor: .center) } }
            .onChange(of: selection) { _, new in
                withAnimation(calm ? nil : .snappy(duration: 0.3)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.chips")
    }

    private func chipButton(_ chip: ActivityChip, accent: Color, calm: Bool) -> some View {
        let selected = chip == selection
        let count = unread[chip] ?? 0
        return Button {
            guard chip != selection else { return }
            withAnimation(calm ? .easeOut(duration: 0.12) : .snappy(duration: 0.34, extraBounce: 0.06)) { selection = chip }
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 5) {
                if selected {
                    Image(systemName: chip.symbol)
                        .font(.caption.weight(.bold))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                Text(chip.title).font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize()
                if count > 0, chip != .all {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : accent)
                        .contentTransition(.numericText(value: Double(count)))
                        .fixedSize()
                }
            }
            .fixedSize()
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                if selected {
                    Capsule()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                        .matchedGeometryEffect(id: "activity.chip.selection", in: chipSpace)
                }
            }
            .modulaGlass(in: Capsule(), interactive: true, tint: selected ? accent.opacity(0.35) : nil)
            .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
        .accessibilityLabel(count > 0 ? "\(chip.title), \(count) unread" : chip.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("activity.chip.\(chip.rawValue)")
    }
}

// MARK: - Grouping

struct ActivityCluster: Identifiable, Hashable {
    let events: [ActivityEvent]
    var id: String { events[0].id }
    var lead: ActivityEvent { events[0] }
    var isRead: Bool { events.allSatisfy(\.isRead) }
    var actors: [ActivityActor] {
        var seen = Set<String>(); var out: [ActivityActor] = []
        for e in events { for a in e.primaryActors where seen.insert(a.id).inserted { out.append(a) } }
        return out
    }
    var thumbnails: [URL] {
        var seen = Set<URL>()
        return events.compactMap(\.preview?.thumbnailURL).filter { seen.insert($0).inserted }
    }
    var who: String {
        let n = actors.map(\.displayName)
        switch n.count {
        case 0: return String(localized: "Someone")
        case 1: return n[0]
        case 2: return "\(n[0]) and \(n[1])"
        default: return "\(n[0]) and \(n.count - 1) others"
        }
    }
    var isStack: Bool { events.count > 1 }
    var voiceOver: String {
        let extra = actors.count <= 1 && events.count > 1 ? ", \(events.count) updates" : ""
        return "\(who) \(lead.descriptionText)\(extra). \(ActivityRelativeTime.string(from: lead.createdAt)). \(isRead ? "Read" : "Unread")."
    }
    /// A grouped follow cluster opens inline into the individual followers.
    var expandsInline: Bool { isStack && [.follow, .followAccepted].contains(lead.kind) }

    private static func groupKey(_ e: ActivityEvent) -> String? {
        let s = e.subject?.id ?? "\(e.destination)"
        switch e.kind {
        case .like, .reaction: return "like|\(s)"
        case .repost: return "repost|\(s)"
        case .share: return "share|\(s)"
        case .follow, .followAccepted: return "follow"
        default: return nil
        }
    }
    static func build(_ events: [ActivityEvent]) -> [ActivityCluster] {
        var order: [String] = []; var buckets: [String: [ActivityEvent]] = [:]
        for e in events {
            let k = groupKey(e) ?? "single|\(e.id)"
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(e)
        }
        return order.compactMap { buckets[$0].map(ActivityCluster.init(events:)) }
    }
}

// MARK: - Avatars and thumbnails

/// Instagram-style identity block: one avatar, or two offset avatars for a group,
/// or a tinted symbol tile for module/system events. The kind badge sits bottom-trailing.
struct ActivityIdentityBlock: View {
    let actors: [ActivityActor]
    let kind: ActivityEventKind
    var size: CGFloat = 46
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        let style = ActivityKindBadge.style(for: kind, accent: app.appearance.liveAccent)
        ZStack {
            if actors.count >= 2 {
                let small = size * 0.72
                ModulaAvatar(initials: actors[1].initials, url: actors[1].avatarURL, size: small, name: actors[1].displayName)
                    .offset(x: -(size - small) / 2, y: -(size - small) / 2)
                ModulaAvatar(initials: actors[0].initials, url: actors[0].avatarURL, size: small, name: actors[0].displayName)
                    .overlay(Circle().stroke(canvas, lineWidth: 2))
                    .offset(x: (size - small) / 2, y: (size - small) / 2)
            } else if let a = actors.first {
                ModulaAvatar(initials: a.initials, url: a.avatarURL, size: size, name: a.displayName)
            } else {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .fill(LinearGradient(colors: [style.tint, style.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if !actors.isEmpty { ActivityKindBadge(kind: kind).offset(x: 4, y: 4) }
        }
        .accessibilityHidden(true)
    }
}

struct ActivityStackedAvatars: View {
    let actors: [ActivityActor]; var size: CGFloat = 40
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        let shown = Array(actors.prefix(actors.count > 3 ? 2 : 3))
        let extra = actors.count - shown.count
        HStack(spacing: -size * 0.34) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                ModulaAvatar(initials: a.initials, url: a.avatarURL, size: size, name: a.displayName)
                    .overlay(Circle().stroke(canvas, lineWidth: 2)).zIndex(Double(10 - i))
            }
            if extra > 0 {
                Text("+\(extra)").font(.caption2.weight(.bold)).monospacedDigit()
                    .frame(width: size, height: size)
                    .modulaGlass(in: Circle(), interactive: false, tint: app.appearance.liveAccent.opacity(0.18))
                    .overlay(Circle().stroke(canvas, lineWidth: 2))
            }
        }.accessibilityHidden(true)
    }
}

struct ActivityThumbnail: View {
    let url: URL; var side: CGFloat = 46
    var body: some View {
        ModulaRemoteImage(url: url, cacheKey: "activity-thumb:\(url.absoluteString)", maximumPixelSize: 300) { phase in
            switch phase {
            case .success(let image): Image(uiImage: image).resizable().scaledToFill()
            default: Rectangle().fill(Color.primary.opacity(0.08))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Inline actions

struct ActivityFollowBackButton: View {
    let actor: ActivityActor
    var compact = false
    @Environment(AppEnvironment.self) private var app
    @State private var state: Phase = .idle
    enum Phase { case idle, busy, following }
    var body: some View {
        let accent = app.appearance.liveAccent
        Button {
            guard state == .idle else { return }
            withAnimation(.snappy) { state = .busy }
            Task {
                let ok = await app.profile.follow(profileID: actor.id, handle: actor.handle ?? actor.id)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { state = ok ? .following : .idle }
                if ok { app.navigation.flash("Following \(actor.displayName)", symbol: "person.badge.plus") }
            }
        } label: {
            HStack(spacing: 4) {
                if state == .busy { ProgressView().controlSize(.mini).tint(.white) }
                else if state == .following { Image(systemName: "checkmark").font(.caption2.weight(.bold)).transition(.scale.combined(with: .opacity)) }
                Text(state == .following ? "Following" : "Follow back").font(.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(state == .following ? Color.primary : Color.white)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(height: 32)
            .background {
                if state != .following { Capsule().fill(accent) }
            }
            .modulaGlass(in: Capsule(), interactive: true, tint: state == .following ? nil : accent.opacity(0.4))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: .lightImpact))
        .disabled(state != .idle)
        .accessibilityIdentifier("activity.follow-back")
    }
}

struct ActivityInlineReply: View {
    let postID: String; let parentCommentID: String?; let replyingTo: String; var onDone: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var text = ""; @State private var sending = false
    @FocusState private var focused: Bool
    var body: some View {
        let ready = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 8) {
            TextField("Reply to \(replyingTo)…", text: $text, axis: .vertical).lineLimit(1...4).font(.subheadline)
                .focused($focused).padding(.horizontal, 14).padding(.vertical, 9).modulaGlass(in: Capsule(), interactive: true)
                .submitLabel(.send).onSubmit(send)
            ModulaGlassSendButton(ready: ready, busy: sending, size: 38, tint: app.appearance.liveAccent, action: send)
        }
        .onAppear { focused = true }
    }
    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        Task {
            do {
                _ = try await GreenfieldPostRepository(client: app.client).createComment(postID: postID, text: body, parentID: parentCommentID)
                app.posts.adjustReplyCount(postID: postID, delta: 1)
                HapticEngine.shared.play(.success)
                app.navigation.flash("Reply sent", symbol: "arrowshape.turn.up.left.fill")
                text = ""; onDone()
            } catch {
                HapticEngine.shared.play(.failure)
                app.navigation.flash((error as? APIError)?.userFacingMessage ?? "Couldn't send reply", symbol: "exclamationmark.triangle")
            }
            sending = false
        }
    }
}

/// Small glass capsule used for in-row actions (Reply, View post).
struct ActivityPillButton: View {
    let title: String; let symbol: String
    var prominent = false
    let action: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let accent = app.appearance.liveAccent
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(prominent ? accent : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .modulaGlass(in: Capsule(), interactive: true, tint: prominent ? accent.opacity(0.16) : nil)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.93, haptic: .selection))
    }
}

// MARK: - Row

struct ActivityClusterCard: View {
    let cluster: ActivityCluster
    var showRequestActions = false; var busy = false
    var expanded = false
    var onAccept: () -> Void = {}; var onDecline: () -> Void = {}
    var onViewPost: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @AppStorage(ModulaPreferences.Key.focusFilterActive) private var focusFilterActive = false
    @State private var replying = false
    private var lead: ActivityEvent { cluster.lead }
    private var dimmed: Bool {
        guard focusFilterActive, ModulaPreferences.dimsActivityNow else { return false }
        return !(ModulaPreferences.focusAllowsMentions && lead.kind.isMention)
    }
    private var isConversation: Bool { lead.kind == .mention || lead.kind == .comment }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ActivityIdentityBlock(actors: cluster.actors, kind: lead.kind)
                VStack(alignment: .leading, spacing: 5) {
                    headline
                        .font(.subheadline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let t = lead.preview?.text, !t.isEmpty {
                        if isConversation {
                            Text(t)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.88))
                                .lineLimit(3)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
                        } else if cluster.thumbnails.isEmpty {
                            Text(t).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    if showRequestActions {
                        ActivityRequestActions(busy: busy, onAccept: onAccept, onDecline: onDecline).padding(.top, 2)
                    } else if isConversation, let postID = replyPostID, !replying {
                        HStack(spacing: 8) {
                            ActivityPillButton(title: "Reply", symbol: "arrowshape.turn.up.left.fill", prominent: true) {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { replying = true }
                            }
                            ActivityPillButton(title: "View post", symbol: "arrow.up.right") {
                                if let onViewPost { onViewPost() } else { app.navigation.push(.post(postID, .root)) }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            if replying, let postID = replyPostID {
                ActivityInlineReply(postID: postID, parentCommentID: lead.subject?.kind == .comment ? lead.subject?.id : nil,
                                    replyingTo: cluster.actors.first?.displayName ?? "them",
                                    onDone: { withAnimation(.snappy) { replying = false } })
                    .padding(.leading, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if !cluster.isRead {
                ActivityUnreadIndicator().offset(x: -12, y: 29)
            }
        }
        .contentShape(Rectangle())
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cluster.voiceOver)
        .accessibilityIdentifier("activity.row.\(lead.id)")
    }

    private var headline: Text {
        let time = Text(" · \(ActivityRelativeTime.string(from: lead.createdAt))").foregroundStyle(.tertiary)
        let names = cluster.actors
        let desc = Text(lead.descriptionText).foregroundStyle(Color.primary.opacity(0.85))
        let bold = { (s: String) in Text(s).fontWeight(.semibold) }
        switch names.count {
        case 0:
            return Text("\(desc)\(time)")
        case 1:
            let suffix = cluster.events.count > 1 ? Text(" · \(cluster.events.count)×").foregroundStyle(.secondary) : Text("")
            return Text("\(bold(names[0].displayName)) \(desc)\(suffix)\(time)")
        case 2:
            return Text("\(bold(names[0].displayName)) and \(bold(names[1].displayName)) \(desc)\(time)")
        default:
            return Text("\(bold(names[0].displayName)), \(bold(names[1].displayName)) and \(bold("\(names.count - 2) others")) \(desc)\(time)")
        }
    }

    @ViewBuilder private var trailing: some View {
        if showRequestActions {
            EmptyView()
        } else if cluster.events.count == 1, lead.kind == .follow, let a = cluster.actors.first {
            ActivityFollowBackButton(actor: a, compact: true)
        } else if cluster.expandsInline {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 30, height: 30)
                .modulaGlass(in: Circle(), interactive: false)
                .accessibilityHidden(true)
        } else if let u = cluster.thumbnails.first {
            ActivityThumbnail(url: u)
        }
    }

    private var replyPostID: String? {
        if case .post(let id) = lead.destination { return id }
        if lead.subject?.kind == .post { return lead.subject?.id }
        return nil
    }
}

// MARK: - Swipe

struct ActivityHorizontalPan: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat) -> Void; var onEnd: (CGFloat, CGFloat) -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let p = UIPanGestureRecognizer(); p.delegate = context.coordinator; return p
    }
    func handleUIGestureRecognizerAction(_ r: UIPanGestureRecognizer, context: Context) {
        let dx = r.translation(in: r.view).x
        switch r.state {
        case .changed: onChange(dx)
        case .ended: onEnd(dx, r.velocity(in: r.view).x)
        case .cancelled, .failed: onEnd(0, 0)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v = p.velocity(in: p.view)
            if let w = p.view?.window, p.location(in: w).x < 26 { return false }
            return abs(v.x) > abs(v.y) * 1.5
        }
    }
}

/// Swipe right: mark read. Swipe left: mute the person (or remove, for actor-less rows).
struct ActivitySwipeRow<Content: View>: View {
    let isRead: Bool; let onMarkRead: () -> Void; let onDelete: () -> Void
    var deleteTitle = "Mute"; var deleteSymbol = "speaker.slash.fill"
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var offset: CGFloat = 0; @State private var armed = false
    private let threshold: CGFloat = 86
    var body: some View {
        ZStack {
            HStack {
                if offset > 0 { action(isRead ? "checkmark.circle.fill" : "envelope.open.fill", isRead ? "Read" : "Mark read", app.appearance.liveAccent, offset) }
                Spacer(minLength: 0)
                if offset < 0 { action(deleteSymbol, deleteTitle, .orange, -offset) }
            }.padding(.horizontal, 6)
            content.offset(x: offset)
        }
        .gesture(ActivityHorizontalPan(onChange: changed, onEnd: ended))
        .accessibilityAction(named: "Mark as read") { onMarkRead() }
        .accessibilityAction(named: Text(deleteTitle)) { onDelete() }
    }
    private func action(_ symbol: String, _ title: String, _ tint: Color, _ reveal: CGFloat) -> some View {
        let p = min(reveal / threshold, 1)
        return VStack(spacing: 4) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tint))
                .modulaGlass(in: Circle(), interactive: false, tint: tint.opacity(0.5))
                .scaleEffect(armed ? 1.1 : 0.6 + 0.4 * p)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tint)
        }.opacity(Double(p)).animation(.spring(response: 0.3, dampingFraction: 0.6), value: armed)
    }
    private func changed(_ dx: CGFloat) {
        offset = abs(dx) > threshold ? (dx > 0 ? 1 : -1) * (threshold + (abs(dx) - threshold) * 0.35) : dx
        let now = abs(dx) > threshold
        if now != armed { armed = now; HapticEngine.shared.play(now ? .lightImpact : .selection) }
    }
    private func ended(_ dx: CGFloat, _ v: CGFloat) {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let commit = abs(dx) > threshold || (abs(dx) > 40 && abs(v) > 900)
        if commit && dx < 0 {
            withAnimation(calm ? .easeOut(duration: 0.12) : .easeIn(duration: 0.2)) { offset = -520 }
            HapticEngine.shared.play(.warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDelete() }
        } else {
            if commit && dx > 0 { onMarkRead(); HapticEngine.shared.play(.confirmation) }
            withAnimation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.76)) { offset = 0 }
        }
        armed = false
    }
}

// MARK: - Requests entry

/// "Follow requests" entry at the top of All, from `GET /v1/connections/requests`.
struct ActivityRequestsEntry: View {
    let requests: [ActivityEvent]
    let action: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let actors = ActivityCluster(events: requests).actors
        let accent = app.appearance.liveAccent
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if actors.isEmpty {
                        Image(systemName: "person.badge.plus").font(.title3.weight(.semibold)).foregroundStyle(accent)
                            .frame(width: 46, height: 46).modulaGlass(in: Circle(), interactive: false, tint: accent.opacity(0.18))
                    } else {
                        ActivityIdentityBlock(actors: actors, kind: .followRequest)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow requests").font(.subheadline.weight(.semibold))
                    Text(actors.isEmpty ? "Review who wants to follow you" : ActivityCluster(events: requests).who)
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("\(requests.count)")
                    .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(minWidth: 22, minHeight: 22)
                    .background(Capsule().fill(accent))
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: .navigation))
        .accessibilityLabel("Follow requests, \(requests.count) pending")
        .accessibilityIdentifier("activity.requests-entry")
    }
}

// MARK: - Empty / loading

struct ActivityLivelyEmptyState: View {
    let title: String; let message: String; let symbol: String
    var footnote: String? = nil
    var actionTitle: String? = nil; var action: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        let accent = app.appearance.liveAccent
        let still = ModulaEffectGate.reduceMotion(reduceMotion)
        VStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: 1/30, paused: still)) { ctx in
                let t = still ? 0 : ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().fill(RadialGradient(colors: [accent.opacity(0.28), .clear], center: .center, startRadius: 4, endRadius: 80))
                        .frame(width: 160, height: 160).scaleEffect(1 + 0.05 * sin(t * 1.6))
                    Image(systemName: symbol).font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                        .rotationEffect(.degrees(still ? 0 : 6 * sin(t * 2.4) * max(0, sin(t * 0.8))), anchor: .top)
                        .frame(width: 76, height: 76)
                        .modulaGlass(in: Circle(), interactive: false, tint: accent.opacity(0.12), specular: true)
                }
            }
            .frame(height: 140).scaleEffect(appeared ? 1 : 0.8).opacity(appeared ? 1 : 0)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let footnote {
                    Text(footnote).font(.caption.weight(.semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.12)))
                        .padding(.top, 4)
                }
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).frame(height: 40)
                        .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(0.2))
                }.buttonStyle(ModulaPressStyle(scale: 0.94))
            }
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 12)
        .onAppear { withAnimation(still ? .none : .spring(response: 0.6, dampingFraction: 0.75)) { appeared = true } }
    }
}

struct ActivityCardSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 64, height: 14).padding(.vertical, 10)
            ForEach(0..<7, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color.primary.opacity(0.09)).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color.primary.opacity(0.09)).frame(height: 12)
                        Capsule().fill(Color.primary.opacity(0.06)).frame(width: i.isMultiple(of: 2) ? 150 : 100, height: 10)
                    }.padding(.top, 8)
                    Spacer(minLength: 12)
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)).frame(width: 46, height: 46)
                        .opacity(i % 3 == 1 ? 0 : 1)
                }
                .padding(.vertical, 10)
            }
        }
        .modulaShimmer(!ModulaEffectGate.reduceMotion(reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading activity")
        .accessibilityIdentifier("activity.loading")
    }
}

// MARK: - Feed

struct ActivityClusterFeed: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modulaHeroScope) private var heroScope
    let events: [ActivityEvent]; var mode: ActivityMode
    /// IDs that were unread when the feed loaded; they stay in "New" after being read
    /// so rows don't jump sections under the finger.
    var newIDs: Set<ActivityEventID> = []
    var onOpen: (ActivityEvent) -> Void
    var onMarkRead: ([ActivityEvent]) -> Void
    var onMarkAllRead: (() -> Void)? = nil
    var onDelete: ([ActivityEvent]) -> Void
    var onMute: (ActivityCluster) -> Void = { _ in }
    var onAccept: (ActivityEvent) -> Void; var onDecline: (ActivityEvent) -> Void
    var onLoadMore: () -> Void; var hasMore: Bool; var loadingMore: Bool
    var busyEventID: ActivityEventID? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var expanded: Set<String> = []
    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.section) { group in
                sectionHeader(group.section, clusters: group.clusters)
                ForEach(group.clusters) { cluster in
                    row(cluster)
                    if cluster.expandsInline && expanded.contains(cluster.id) {
                        expandedFollowers(cluster)
                    }
                }
            }
            if hasMore {
                HStack { Spacer(); if loadingMore { ProgressView() } else { Text("Load more").font(.subheadline.weight(.semibold)) }; Spacer() }
                    .frame(height: 48)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onLoadMore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("activity.load-more")
                    .onAppear { if !loadingMore { onLoadMore() } }
            }
        }
    }

    private func sectionHeader(_ section: ActivityTimelineSection, clusters: [ActivityCluster]) -> some View {
        let unread = clusters.reduce(0) { $0 + $1.events.filter { !$0.isRead }.count }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title).font(.headline)
            if section == .new, unread > 0 {
                Text("\(unread)")
                    .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 7).frame(minHeight: 20)
                    .background(Capsule().fill(app.appearance.liveAccent))
                    .contentTransition(.numericText(value: Double(unread)))
            }
            Spacer(minLength: 8)
            if section == .new, unread > 0, let onMarkAllRead {
                Button("Mark all read", action: onMarkAllRead)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .accessibilityIdentifier("activity.mark-all")
            }
        }
        .padding(.top, section == sections.first?.section ? 6 : 22)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func row(_ cluster: ActivityCluster) -> some View {
        let lead = cluster.lead; let busy = busyEventID == lead.id
        let isOpen = expanded.contains(cluster.id)
        let hasActor = !cluster.actors.isEmpty
        ActivitySwipeRow(
            isRead: cluster.isRead,
            onMarkRead: { onMarkRead(cluster.events) },
            onDelete: { hasActor ? onMute(cluster) : onDelete(cluster.events) },
            deleteTitle: hasActor ? "Mute" : "Remove",
            deleteSymbol: hasActor ? "speaker.slash.fill" : "trash.fill"
        ) {
            Button {
                if cluster.expandsInline { toggle(cluster); return }
                open(lead, cluster: cluster)
            } label: {
                ActivityClusterCard(
                    cluster: cluster,
                    showRequestActions: mode == .requests && lead.kind.isRequest,
                    busy: busy, expanded: isOpen,
                    onAccept: { onAccept(lead) }, onDecline: { onDecline(lead) },
                    onViewPost: { open(lead, cluster: cluster) }
                )
                .modulaHeroSource("activity", key: lead.id)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.985, haptic: nil))
            .disabled(busy).opacity(busy ? 0.6 : 1)
            .accessibilityHint(cluster.expandsInline ? (isOpen ? "Collapses the list" : "Shows all \(cluster.actors.count) people") : "")
        }
        .contextMenu { contextMenu(cluster) }
    }

    @ViewBuilder private func contextMenu(_ cluster: ActivityCluster) -> some View {
        if !cluster.isRead { Button("Mark as Read", systemImage: "checkmark.circle") { onMarkRead(cluster.events) } }
        if let a = cluster.actors.first {
            Button("View \(a.displayName)", systemImage: "person.crop.circle") { app.navigation.push(.profile(a.id, .overview)) }
            Button("Mute \(a.displayName)", systemImage: "speaker.slash") { onMute(cluster) }
        }
        Button("Remove Notification", systemImage: "trash", role: .destructive) { onDelete(cluster.events) }
        Divider()
        Button("Notification Settings", systemImage: "bell.badge") { app.navigation.open(.settings(.notifications(.root))) }
    }

    private func open(_ event: ActivityEvent, cluster: ActivityCluster) {
        if let route = event.destination.route {
            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "activity", key: event.id), for: route)
        }
        onMarkRead(cluster.events); onOpen(event)
    }

    private func toggle(_ cluster: ActivityCluster) {
        HapticEngine.shared.play(expanded.contains(cluster.id) ? .selection : .contextOpen)
        withAnimation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82)) {
            if expanded.contains(cluster.id) { expanded.remove(cluster.id) }
            else { expanded.insert(cluster.id); onMarkRead(cluster.events) }
        }
    }

    /// Grouped follows open inline into each person with their own Follow back.
    private func expandedFollowers(_ cluster: ActivityCluster) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cluster.events.prefix(20).enumerated()), id: \.element.id) { index, event in
                if let a = event.primaryActors.first {
                    HStack(spacing: 12) {
                        Button { app.navigation.push(.profile(a.id, .overview)) } label: {
                            HStack(spacing: 10) {
                                ModulaAvatar(initials: a.initials, url: a.avatarURL, size: 36, name: a.displayName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text([a.handle.map { "@\($0)" }, ActivityRelativeTime.string(from: event.createdAt)].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }.buttonStyle(.plain)
                        Spacer(minLength: 8)
                        ActivityFollowBackButton(actor: a, compact: true)
                    }
                    .padding(.vertical, 7)
                    .transition(calm ? .opacity : .offset(y: -CGFloat(index + 1) * 12).combined(with: .opacity))
                }
            }
        }
        .padding(.leading, 58)
        .padding(.bottom, 6)
    }

    private var sections: [(section: ActivityTimelineSection, clusters: [ActivityCluster])] {
        var buckets: [ActivityTimelineSection: [ActivityEvent]] = [:]
        for e in events {
            let sec: ActivityTimelineSection
            if newIDs.contains(e.id) || (newIDs.isEmpty && !e.isRead) { sec = .new }
            else if e.groupHint?.lowercased() == "today" { sec = .today }
            else { sec = ActivityTimelineSection.section(for: e.createdAt) }
            buckets[sec, default: []].append(e)
        }
        return ActivityTimelineSection.allCases.compactMap { sec in
            guard let ev = buckets[sec], !ev.isEmpty else { return nil }
            return (sec, ActivityCluster.build(ev))
        }
    }
}

/// Empty state with real suggestions from `GET /v1/discover` (suggestedProfiles).
struct ActivitySuggestedPeople: View {
    @Environment(AppEnvironment.self) private var app
    @State private var people: [DiscoverPerson] = []
    @State private var followed: Set<String> = []

    /// Seed/test accounts from staging never belong in suggestions.
    static func isFixture(_ person: DiscoverPerson) -> Bool {
        ModulaFixtureFilter.isFixture(name: person.displayName, handle: person.handle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !people.isEmpty {
                Text("Suggested for you").font(.headline).padding(.top, 18).padding(.bottom, 4)
                ForEach(people.prefix(6)) { person in
                    HStack(spacing: 12) {
                        Button { app.navigation.push(.profile(person.id, .overview)) } label: {
                            HStack(spacing: 12) {
                                ModulaAvatar(initials: String(person.displayName.prefix(2)).uppercased(), url: person.avatarURL, size: 44, name: person.displayName)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(person.followsViewer ? "@\(person.handle) · Follows you" : "@\(person.handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }.buttonStyle(.plain)
                        Spacer(minLength: 6)
                        let done = followed.contains(person.id) || person.isFollowing
                        Button {
                            guard !done else { return }
                            Task {
                                if await app.profile.follow(profileID: person.id, handle: person.handle) {
                                    followed.insert(person.id); HapticEngine.shared.play(.success)
                                }
                            }
                        } label: {
                            Text(done ? "Following" : (person.followsViewer ? "Follow back" : "Follow"))
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14).frame(height: 32)
                                .modulaGlass(in: Capsule(), interactive: true, tint: done ? nil : app.appearance.liveAccent.opacity(0.25))
                        }.buttonStyle(.plain).disabled(done)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .task {
            guard ModulaPreferences.showsSuggestedPeople else { return }
            people = ((try? await GreenfieldDiscoverRepository(client: app.client).people(cursor: nil).items) ?? [])
                .filter { !Self.isFixture($0) }
        }
    }
}


/// Seed/test accounts from staging never belong in suggestions or Catch up.
enum ModulaFixtureFilter {
    static func isFixture(name: String, handle: String) -> Bool {
        let name = name.lowercased()
        let handle = handle.lowercased()
        let markers = ["fixture", "alpha", "test", "block ", "phase ", "qa_", "demo_", "searchable", "seed", "dummy", "sample"]
        if markers.contains(where: { name.contains($0) || handle.contains($0.trimmingCharacters(in: .whitespaces)) }) { return true }
        // Generated seed accounts end in a hex suffix ("Searchable Founder 3fa9c2", "user_9b1e4d7a").
        let hexSuffix = #"[\s_\-][0-9a-f]{5,}$"#
        return name.range(of: hexSuffix, options: .regularExpression) != nil
            || handle.range(of: hexSuffix, options: .regularExpression) != nil
            || handle.hasPrefix("vps-") || handle.contains("-checked-")
            || looksGenerated(handle)
    }

    /// Machine-made handles such as "b14bmsb2xub7n73r", "p6smrq8pwcc" or "macb17863988517690": letters and
    /// digits only, 8+ long, and either 2+ digits with 3+ letter/digit switches or 40%+ digits (6+). Real handles ("andrei.modula", "sam2024") don't qualify.
    static func looksGenerated(_ handle: String) -> Bool {
        let h = handle.lowercased()
        guard h.count >= 8, h.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        let digits = h.filter(\.isNumber).count
        // Long digit runs ("macb17863988517690"): mostly numbers.
        if digits >= 6 && digits * 5 >= h.count * 2 { return true }
        guard digits >= 2 else { return false }
        var switches = 0
        var last: Bool?
        for c in h {
            let isDigit = c.isNumber
            if let last, last != isDigit { switches += 1 }
            last = isDigit
        }
        return switches >= 3
    }
}
