import SwiftUI
import UIKit

enum ActivityChip: String, CaseIterable, Identifiable, Hashable {
    case all, mentions, likes, follows, replies, reposts, modules
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"; case .mentions: "Mentions"; case .likes: "Likes"
        case .follows: "Follows"; case .replies: "Replies"; case .reposts: "Reposts"; case .modules: "Modules"
        }
    }
    var symbol: String {
        switch self {
        case .all: "sparkles"; case .mentions: "at"; case .likes: "heart.fill"
        case .follows: "person.2.fill"; case .replies: "arrowshape.turn.up.left.fill"
        case .reposts: "arrow.2.squarepath"; case .modules: "shippingbox.fill"
        }
    }
    /// Client-side matching on the loaded feed (the API has no per-category query for replies/reposts).
    func matches(_ event: ActivityEvent) -> Bool {
        switch self {
        case .all: true
        case .mentions: event.kind == .mention
        case .likes: event.kind == .like || event.kind == .reaction
        case .follows: [.follow, .followRequest, .followAccepted].contains(event.kind)
        case .replies: event.kind == .comment
        case .reposts: event.kind == .repost || event.kind == .share
        case .modules: [.moduleEvent, .moduleUpdate].contains(event.kind)
        }
    }
}

struct ActivityChipBar: View {
    @Binding var selection: ActivityChip
    var unread: [ActivityChip: Int]
    @Environment(AppEnvironment.self) private var app
    @Namespace private var chipSpace
    var body: some View {
        let accent = app.appearance.accent.color
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityChip.allCases) { chip in
                    let selected = chip == selection
                    Button {
                        guard chip != selection else { return }
                        withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) { selection = chip }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Text(chip.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule().fill(Color.primary)
                                    .matchedGeometryEffect(id: "activity.chip", in: chipSpace)
                            }
                        }
                        .modulaGlass(in: Capsule(), interactive: true)
                        .overlay(alignment: .topTrailing) {
                            if (unread[chip] ?? 0) > 0 {
                                Circle().fill(accent).frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                                    .offset(x: -2, y: 1)
                                    .accessibilityLabel("Unread")
                            }
                        }
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.93, haptic: nil))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("activity.chip.\(chip.rawValue)")
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset).padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        // Edge fade so the last chip ("Reposts") reads as scrollable, not clipped.
        .mask {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.9),
                .init(color: .black.opacity(0), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .background(.bar.opacity(0.001))
    }
}

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
    var voiceOver: String { "\(stackHeadline ?? who) \(stackHeadline == nil ? lead.descriptionText : ""). \(isRead ? "Read" : "Unread")." }
    /// Stacked cards read as one headline: "12 people liked your post".
    var isStack: Bool { events.count > 1 }
    var stackHeadline: String? {
        guard events.count > 1 else { return nil }
        if actors.count >= 2 { return "\(who) \(lead.descriptionText)" }
        return "\(who) · \(events.count) updates"
    }
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
                Text("+\(extra)").font(.caption.weight(.bold)).monospacedDigit()
                    .frame(width: size, height: size)
                    .modulaGlass(in: Circle(), interactive: false, tint: app.appearance.accent.color.opacity(0.18))
                    .overlay(Circle().stroke(canvas, lineWidth: 2))
            }
        }.accessibilityHidden(true)
    }
}

struct ActivityThumbnailFan: View {
    let urls: [URL]; var side: CGFloat = 50
    var body: some View {
        ZStack {
            ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.offset) { i, url in
                ModulaRemoteImage(url: url, cacheKey: "activity-thumb:\(url.absoluteString)", maximumPixelSize: 300) { phase in
                    switch phase {
                    case .success(let image): Image(uiImage: image).resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08))
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
                .rotationEffect(.degrees(Double(i) * 7))
                .offset(x: CGFloat(i) * 5, y: CGFloat(i) * -2)
            }
        }
        .frame(width: side + 12, height: side + 6).accessibilityHidden(true)
    }
}

private struct ActivityCardChrome: ViewModifier {
    let unread: Bool
    @Environment(AppEnvironment.self) private var app
    func body(content: Content) -> some View {
        let accent = app.appearance.accent.color
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // Flat, list-style row (Instagram/Threads): a faint accent wash marks unread.
        content.padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(unread ? accent.opacity(0.08) : Color.clear) }
            .contentShape(shape)
            .animation(.easeOut(duration: 0.3), value: unread)
    }
}
private extension View { func activityCard(unread: Bool) -> some View { modifier(ActivityCardChrome(unread: unread)) } }

struct ActivityFollowBackButton: View {
    let actor: ActivityActor
    @Environment(AppEnvironment.self) private var app
    @State private var state: Phase = .idle
    enum Phase { case idle, busy, following }
    var body: some View {
        let accent = app.appearance.accent.color
        Button {
            guard state == .idle else { return }
            withAnimation(.snappy) { state = .busy }
            Task {
                let ok = await app.profile.follow(profileID: actor.id, handle: actor.handle ?? actor.id)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { state = ok ? .following : .idle }
                if ok { app.navigation.flash("Following \(actor.displayName)", symbol: "person.badge.plus") }
            }
        } label: {
            HStack(spacing: 5) {
                if state == .busy { ProgressView().controlSize(.mini).tint(.white) }
                else { Image(systemName: state == .following ? "checkmark" : "person.badge.plus").font(.caption.weight(.bold)).contentTransition(.symbolEffect(.replace)) }
                Text(state == .following ? "Following" : "Follow back").font(.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(state == .following ? Color.primary : Color.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background { if state != .following { Capsule().fill(LinearGradient(colors: [accent, accent.opacity(0.8)], startPoint: .top, endPoint: .bottom)).shadow(color: accent.opacity(0.35), radius: 6, y: 2) } }
            .modulaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: .lightImpact))
        .disabled(state != .idle)
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
            ModulaGlassSendButton(ready: ready, busy: sending, size: 38, tint: app.appearance.accent.color, action: send)
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

struct ActivityClusterCard: View {
    let cluster: ActivityCluster
    var showRequestActions = false; var busy = false
    var onAccept: () -> Void = {}; var onDecline: () -> Void = {}
    @Environment(AppEnvironment.self) private var app
    @AppStorage(ModulaPreferences.Key.focusFilterActive) private var focusFilterActive = false
    @State private var replying = false
    private var lead: ActivityEvent { cluster.lead }
    private var dimmed: Bool {
        guard focusFilterActive, ModulaPreferences.dimsActivityNow else { return false }
        return !(ModulaPreferences.focusAllowsMentions && lead.kind.isMention)
    }
    var body: some View {
        Group {
            if showRequestActions { requestCard }
            else if cluster.events.count == 1, [.follow, .followAccepted].contains(lead.kind), let a = cluster.actors.first { followCard(a) }
            else if lead.kind == .mention || lead.kind == .comment { conversationCard }
            else { compactCard }
        }
        .activityCard(unread: !cluster.isRead).opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .contain).accessibilityLabel(cluster.voiceOver)
        .accessibilityIdentifier("activity.row.\(lead.id)")
    }
    private var title: Text {
        if let headline = cluster.stackHeadline, cluster.actors.count >= 2 {
            return Text(headline).fontWeight(.semibold)
        }
        return Text(cluster.who).fontWeight(.semibold) + Text(" \(lead.descriptionText)").foregroundStyle(.secondary)
    }
    private var timeLine: some View {
        HStack(spacing: 5) {
            let st = ActivityKindBadge.style(for: lead.kind, accent: app.appearance.accent.color)
            Image(systemName: st.symbol).foregroundStyle(st.tint)
            Text(ActivityRelativeTime.string(from: lead.createdAt))
            if cluster.events.count > 1 { Text("· \(cluster.events.count) updates") }
            if !cluster.isRead { ActivityUnreadIndicator().padding(.leading, 2) }
        }.font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
    }
    private var avatars: some View {
        ActivityStackedAvatars(actors: cluster.actors, size: 40)
            .overlay(alignment: .bottomTrailing) { ActivityKindBadge(kind: lead.kind).offset(x: 5, y: 5) }
    }
    private var compactCard: some View {
        HStack(spacing: 12) {
            avatars
            VStack(alignment: .leading, spacing: 4) {
                title.font(.subheadline).lineLimit(3).multilineTextAlignment(.leading)
                if let t = lead.preview?.text, !t.isEmpty, cluster.thumbnails.isEmpty {
                    Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                timeLine
            }
            Spacer(minLength: 4)
            if let u = cluster.thumbnails.first { ActivityThumbnailFan(urls: [u], side: 46) }
        }
    }
    private func followCard(_ actor: ActivityActor) -> some View {
        HStack(spacing: 12) {
            ModulaAvatar(initials: actor.initials, url: actor.avatarURL, size: 52, name: actor.displayName)
                .padding(2.5)
                .overlay(Circle().stroke(AngularGradient(colors: [app.appearance.accent.color, .purple, .pink, app.appearance.accent.color], center: .center), lineWidth: 2))
                .overlay(alignment: .bottomTrailing) { ActivityKindBadge(kind: lead.kind).offset(x: 3, y: 3) }
            VStack(alignment: .leading, spacing: 3) {
                Text(actor.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let h = actor.handle { Text("@\(h)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text(lead.descriptionText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                timeLine
            }
            Spacer(minLength: 4)
            if lead.kind == .follow { ActivityFollowBackButton(actor: actor) }
        }
    }
    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                avatars
                VStack(alignment: .leading, spacing: 4) {
                    title.font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                    timeLine
                }
                Spacer(minLength: 4)
                if let u = cluster.thumbnails.first { ActivityThumbnailFan(urls: [u], side: 44) }
            }
            if let t = lead.preview?.text, !t.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Capsule().fill(app.appearance.accent.color.opacity(0.6)).frame(width: 3)
                    Text(t).font(.subheadline).lineLimit(4)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.045)))
            }
            if let postID = replyPostID {
                if replying {
                    ActivityInlineReply(postID: postID, parentCommentID: lead.subject?.kind == .comment ? lead.subject?.id : nil,
                                        replyingTo: cluster.actors.first?.displayName ?? "them",
                                        onDone: { withAnimation(.snappy) { replying = false } })
                } else {
                    HStack(spacing: 8) {
                        Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { replying = true } } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left.fill").font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.accent.color.opacity(0.14))
                        }.buttonStyle(ModulaPressStyle(scale: 0.93, haptic: .selection))
                        if let a = cluster.actors.first {
                            Button { app.navigation.push(.profile(a.id, .overview)) } label: {
                                Label("Profile", systemImage: "person.crop.circle").font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7).modulaGlass(in: Capsule(), interactive: true)
                            }.buttonStyle(ModulaPressStyle(scale: 0.93, haptic: .selection))
                        }
                    }.foregroundStyle(.primary)
                }
            }
        }
    }
    private var requestCard: some View {
        HStack(spacing: 12) {
            avatars
            VStack(alignment: .leading, spacing: 6) {
                title.font(.subheadline).lineLimit(2); timeLine
                ActivityRequestActions(busy: busy, onAccept: onAccept, onDecline: onDecline)
            }
            Spacer(minLength: 0)
        }
    }
    private var replyPostID: String? {
        if case .post(let id) = lead.destination { return id }
        if lead.subject?.kind == .post { return lead.subject?.id }
        return nil
    }
}

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

struct ActivitySwipeRow<Content: View>: View {
    let isRead: Bool; let onMarkRead: () -> Void; let onDelete: () -> Void
    var deleteTitle = "Mute"; var deleteSymbol = "speaker.slash.fill"
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app
    @State private var offset: CGFloat = 0; @State private var armed = false
    private let threshold: CGFloat = 86
    var body: some View {
        ZStack {
            HStack {
                if offset > 0 { action(isRead ? "checkmark.circle.fill" : "envelope.open.fill", isRead ? "Read" : "Mark read", app.appearance.accent.color, offset) }
                Spacer(minLength: 0)
                if offset < 0 { action(deleteSymbol, deleteTitle, .orange, -offset) }
            }.padding(.horizontal, 18)
            content.offset(x: offset)
        }
        .gesture(ActivityHorizontalPan(onChange: changed, onEnd: ended))
        .accessibilityAction(named: "Mark as read") { onMarkRead() }
        .accessibilityAction(named: Text(deleteTitle)) { onDelete() }
    }
    private func action(_ symbol: String, _ title: String, _ tint: Color, _ reveal: CGFloat) -> some View {
        let p = min(reveal / threshold, 1)
        return VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(tint).shadow(color: tint.opacity(0.5), radius: armed ? 10 : 3))
                .scaleEffect(armed ? 1.12 : 0.6 + 0.4 * p)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tint)
        }.opacity(Double(p)).animation(.spring(response: 0.3, dampingFraction: 0.6), value: armed)
    }
    private func changed(_ dx: CGFloat) {
        offset = abs(dx) > threshold ? (dx > 0 ? 1 : -1) * (threshold + (abs(dx) - threshold) * 0.35) : dx
        let now = abs(dx) > threshold
        if now != armed { armed = now; HapticEngine.shared.play(now ? .lightImpact : .selection) }
    }
    private func ended(_ dx: CGFloat, _ v: CGFloat) {
        let commit = abs(dx) > threshold || (abs(dx) > 40 && abs(v) > 900)
        if commit && dx < 0 {
            withAnimation(.easeIn(duration: 0.2)) { offset = -520 }
            HapticEngine.shared.play(.warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDelete() }
        } else {
            if commit && dx > 0 { onMarkRead(); HapticEngine.shared.play(.confirmation) }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { offset = 0 }
        }
        armed = false
    }
}

struct ActivityLivelyEmptyState: View {
    let title: String; let message: String; let symbol: String
    var actionTitle: String? = nil; var action: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        let accent = app.appearance.accent.color
        let still = ModulaEffectGate.reduceMotion(reduceMotion)
        VStack(spacing: 18) {
            TimelineView(.animation(minimumInterval: 1/30, paused: still)) { ctx in
                let t = still ? 0 : ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().fill(RadialGradient(colors: [accent.opacity(0.35), .clear], center: .center, startRadius: 4, endRadius: 90))
                        .frame(width: 180, height: 180).scaleEffect(1 + 0.06 * sin(t * 1.6))
                    ForEach(0..<6, id: \.self) { i in
                        let a = t * (0.7 + Double(i) * 0.08) + Double(i) * .pi / 3
                        let r = 58.0 + Double(i % 2) * 12
                        Circle().fill(i.isMultiple(of: 2) ? accent : Color.pink.opacity(0.85))
                            .frame(width: i.isMultiple(of: 3) ? 7 : 5, height: i.isMultiple(of: 3) ? 7 : 5)
                            .shadow(color: accent.opacity(0.7), radius: 4)
                            .offset(x: cos(a) * r, y: sin(a) * r * 0.55)
                    }
                    Image(systemName: symbol).font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .rotationEffect(.degrees(still ? 0 : 9 * sin(t * 3.2) * max(0, sin(t * 0.9))), anchor: .top)
                        .frame(width: 88, height: 88)
                        .modulaGlass(in: Circle(), interactive: false, tint: accent.opacity(0.12), specular: true)
                }
            }.frame(height: 170).scaleEffect(appeared ? 1 : 0.7).opacity(appeared ? 1 : 0)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "sparkle.magnifyingglass").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(0.2), prominent: true)
                }.buttonStyle(ModulaPressStyle(scale: 0.94))
            }
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24)
        .onAppear { withAnimation(still ? .none : .spring(response: 0.6, dampingFraction: 0.7)) { appeared = true } }
    }
}

struct ActivityPulseHeader: View {
    let events: [ActivityEvent]; let unread: Int; var onMarkAll: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        let accent = app.appearance.accent.color
        let likes = events.filter { !$0.isRead && ($0.kind == .like || $0.kind == .reaction) }.count
        let mentions = events.filter { !$0.isRead && $0.kind.isMention }.count
        let follows = events.filter { !$0.isRead && [.follow, .followAccepted, .followRequest].contains($0.kind) }.count
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(unread > 0 ? "\(unread)" : "All").font(.largeTitle.weight(.bold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(unread)))
                    .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                Text(unread > 0 ? "new since you last looked" : "caught up").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) { pill("heart.fill", likes, .pink); pill("at", mentions, .purple); pill("person.fill.badge.plus", follows, accent) }
            if unread > 0 {
                Button(action: onMarkAll) {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(accent)
                        .frame(width: 40, height: 40).modulaGlass(in: Circle(), interactive: true)
                }.buttonStyle(ModulaPressStyle(scale: 0.9, haptic: .confirmation))
                .accessibilityLabel("Mark all as read").accessibilityIdentifier("activity.mark-all")
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [accent.opacity(0.16), .clear, Color.pink.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false, specular: true)
        .animation(.snappy, value: unread)
    }
    private func pill(_ s: String, _ c: Int, _ t: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: s).font(.caption.weight(.bold)).foregroundStyle(t).symbolEffect(.bounce, value: c)
            Text("\(c)").font(.caption2.weight(.bold)).monospacedDigit().contentTransition(.numericText(value: Double(c)))
        }.frame(width: 38, height: 44)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false, tint: t.opacity(0.1))
        .opacity(c > 0 ? 1 : 0.55)
    }
}

struct ActivityClusterFeed: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modulaHeroScope) private var heroScope
    let events: [ActivityEvent]; var mode: ActivityMode
    var onOpen: (ActivityEvent) -> Void
    var onMarkRead: ([ActivityEvent]) -> Void
    var onDelete: ([ActivityEvent]) -> Void
    var onMute: (ActivityCluster) -> Void = { _ in }
    var onAccept: (ActivityEvent) -> Void; var onDecline: (ActivityEvent) -> Void
    var onLoadMore: () -> Void; var hasMore: Bool; var loadingMore: Bool
    var busyEventID: ActivityEventID? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Stacked clusters the user fanned out.
    @State private var expanded: Set<String> = []
    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(sections, id: \.section) { group in
                ActivitySectionHeader(title: group.section.title)
                ForEach(group.clusters) { cluster in
                    let lead = cluster.lead; let busy = busyEventID == lead.id
                    let stacks = cluster.isStack && mode != .requests
                    let isOpen = expanded.contains(cluster.id)
                    ActivitySwipeRow(isRead: cluster.isRead, onMarkRead: { onMarkRead(cluster.events) }, onDelete: { onMute(cluster) }) {
                        Button {
                            if stacks {
                                toggle(cluster)
                                return
                            }
                            if let route = lead.destination.route {
                                ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "activity", key: lead.id), for: route)
                            }
                            onMarkRead(cluster.events); onOpen(lead)
                        } label: {
                            ActivityClusterCard(cluster: cluster, showRequestActions: mode == .requests && lead.kind.isRequest,
                                                busy: busy, onAccept: { onAccept(lead) }, onDecline: { onDecline(lead) })
                            .overlay(alignment: .topTrailing) {
                                if stacks {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                                        .padding(10)
                                        .accessibilityHidden(true)
                                }
                            }
                            .background(alignment: .bottom) {
                                if stacks && !isOpen { ActivityStackPlates(depth: min(cluster.events.count - 1, 2)) }
                            }
                            .padding(.bottom, stacks && !isOpen ? CGFloat(min(cluster.events.count - 1, 2)) * 6 : 0)
                            .modulaHeroSource("activity", key: lead.id)
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil)).disabled(busy).opacity(busy ? 0.6 : 1)
                        .accessibilityHint(stacks ? (isOpen ? "Collapses the stack" : "Fans out \(cluster.events.count) notifications") : "")
                    }
                    .modulaScrollReveal()
                    .contextMenu {
                        if !cluster.isRead { Button("Mark as Read", systemImage: "checkmark.circle") { onMarkRead(cluster.events) } }
                        if let a = cluster.actors.first {
                            Button("Open Profile", systemImage: "person.crop.circle") { app.navigation.push(.profile(a.id, .overview)) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(cluster.events) }
                    }
                    if stacks && isOpen {
                        fannedEvents(cluster)
                    }
                }
            }
            if hasMore {
                Button(action: onLoadMore) {
                    HStack { Spacer(); if loadingMore { ProgressView() } else { Text("Load more").font(.subheadline.weight(.semibold)) }; Spacer() }
                        .padding(.vertical, 12).modulaGlass(in: Capsule(), interactive: true)
                }.buttonStyle(ModulaPressStyle()).padding(.top, 6)
                .accessibilityIdentifier("activity.load-more")
                .onAppear { if !loadingMore { onLoadMore() } }
            }
        }
    }
    private func toggle(_ cluster: ActivityCluster) {
        HapticEngine.shared.play(expanded.contains(cluster.id) ? .selection : .contextOpen)
        withAnimation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.8)) {
            if expanded.contains(cluster.id) {
                expanded.remove(cluster.id)
            } else {
                expanded.insert(cluster.id)
                onMarkRead(cluster.events)
            }
        }
    }

    /// The stack fans out into its individual notifications, each sliding out from
    /// under the one above (staggered), and collapses back on a second tap.
    @ViewBuilder
    private func fannedEvents(_ cluster: ActivityCluster) -> some View {
        let shown = Array(cluster.events.prefix(12).enumerated())
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shown, id: \.element.id) { index, event in
                Button {
                    if let route = event.destination.route {
                        ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "activity", key: event.id), for: route)
                    }
                    onMarkRead([event]); onOpen(event)
                } label: {
                    ActivityClusterCard(cluster: ActivityCluster(events: [event]))
                        .scaleEffect(0.97, anchor: .leading)
                        .modulaHeroSource("activity", key: event.id)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: .selection))
                .transition(
                    calm ? .opacity : .asymmetric(
                        insertion: .offset(y: -CGFloat(index + 1) * 26)
                            .combined(with: .scale(scale: 0.92, anchor: .top))
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.44, dampingFraction: 0.78).delay(Double(index) * 0.035)),
                        removal: .offset(y: -CGFloat(index + 1) * 18).combined(with: .opacity)
                    )
                )
            }
            if cluster.events.count > 12 {
                Text("and \(cluster.events.count - 12) more")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 2).padding(.vertical, 6).padding(.leading, 4)
        }
    }

    private var sections: [(section: ActivityTimelineSection, clusters: [ActivityCluster])] {
        var buckets: [ActivityTimelineSection: [ActivityEvent]] = [:]
        for e in events {
            let sec: ActivityTimelineSection
            // Client-side buckets: Today / This week / Earlier.
            sec = e.groupHint?.lowercased() == "today" ? .today : ActivityTimelineSection.section(for: e.createdAt)
            buckets[sec, default: []].append(e)
        }
        return ActivityTimelineSection.allCases.compactMap { sec in
            guard let ev = buckets[sec], !ev.isEmpty else { return nil }
            return (sec, ActivityCluster.build(ev))
        }
    }
}

/// Paper-stack plates peeking out under a grouped notification card.
struct ActivityStackPlates: View {
    var depth: Int
    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach((1...max(depth, 1)).reversed(), id: \.self) { level in
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .padding(.horizontal, CGFloat(level) * 10)
                    .frame(height: 40)
                    .offset(y: CGFloat(level) * 6)
                    .opacity(1 - Double(level) * 0.25)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ActivityCardSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 12) {
                    HStack(spacing: -12) { ForEach(0..<(i % 3 + 1), id: \.self) { _ in Circle().fill(Color.primary.opacity(0.09)).frame(width: 40, height: 40) } }
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(Color.primary.opacity(0.09)).frame(height: 11)
                        Capsule().fill(Color.primary.opacity(0.06)).frame(width: 120, height: 9)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)).frame(width: 48, height: 48)
                }.activityCard(unread: false)
            }
        }
        .modulaShimmer(!ModulaEffectGate.reduceMotion(reduceMotion))
        .accessibilityIdentifier("activity.loading")
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
        VStack(alignment: .leading, spacing: 10) {
            if !people.isEmpty {
                ModulaSectionHeader(title: "Suggested for you").padding(.top, 8)
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
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .modulaGlass(in: Capsule(), interactive: true, tint: done ? nil : app.appearance.accent.color.opacity(0.25))
                        }.buttonStyle(.plain).disabled(done)
                    }
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
    }
}
