import SwiftUI

struct ActivityRelativeTime {
    /// Cached: building a RelativeDateTimeFormatter per row is expensive in
    /// long feeds. Formatting is read-only after configuration.
    private nonisolated(unsafe) static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(from date: Date, now: Date = Date()) -> String {
        // Settings → Time & Units: absolute timestamps (12/24-hour) when relative is off.
        guard ModulaPreferences.relativeTimestamps else { return ModulaTimeFormat.absolute(date, now: now) }
        // Avoid "in 0 sec" / tiny future values from clock skew.
        if abs(now.timeIntervalSince(date)) < 45 { return String(localized: "now") }
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

struct ActivityUnreadIndicator: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        let accent = app.appearance.accent.color
        Circle()
            .fill(accent)
            .frame(width: 7, height: 7)
            .shadow(color: accent.opacity(0.7), radius: 4)
            .background {
                if !ModulaEffectGate.reduceMotion(systemReduceMotion) {
                    Circle()
                        .fill(accent.opacity(0.35))
                        .phaseAnimator([false, true]) { view, phase in
                            view.scaleEffect(phase ? 2.4 : 1).opacity(phase ? 0 : 0.8)
                        } animation: { phase in
                            phase ? .easeOut(duration: 1.4) : .linear(duration: 0.01).delay(0.6)
                        }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Small glass-rimmed glyph on the actor avatar saying what happened.
struct ActivityKindBadge: View {
    let kind: ActivityEventKind
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = Self.style(for: kind, accent: app.appearance.accent.color)
        Image(systemName: style.symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(
                Circle().fill(LinearGradient(colors: [style.tint, style.tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().stroke(ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas, lineWidth: 2))
            .shadow(color: style.tint.opacity(0.45), radius: 3, y: 1)
            .accessibilityHidden(true)
    }

    static func style(for kind: ActivityEventKind, accent: Color) -> (symbol: String, tint: Color) {
        switch kind {
        case .reaction: ("face.smiling.inverse", .orange)
        case .like: ("heart.fill", .pink)
        case .comment: ("bubble.left.fill", .blue)
        case .mention: ("at", .purple)
        case .repost: ("arrow.2.squarepath", .green)
        case .share: ("paperplane.fill", .teal)
        case .follow: ("person.fill.badge.plus", accent)
        case .followAccepted: ("person.fill.checkmark", accent)
        case .followRequest: ("person.crop.circle.badge.questionmark", .indigo)
        case .teamInvite: ("person.3.fill", .indigo)
        case .moduleEvent: ("shippingbox.fill", .mint)
        case .moduleUpdate: ("arrow.down.circle.fill", .mint)
        case .moliboo: ("pawprint.fill", .orange)
        case .system, .unknown: ("bell.fill", .gray)
        }
    }
}

struct ActivityActorStack: View {
    let actors: [ActivityActor]
    var size: CGFloat = 40
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(actors.prefix(3).enumerated()), id: \.element.id) { index, actor in
                ModulaAvatar(initials: actor.initials, size: size)
                    .overlay(Circle().stroke(ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas, lineWidth: 1.5))
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let names = actors.prefix(3).map(\.accessibilityName)
        if actors.count > 3 {
            return names.joined(separator: ", ") + ", and \(actors.count - 3) others"
        }
        return names.joined(separator: ", ")
    }
}

struct ActivitySubjectPreview: View {
    let preview: ActivityPreview
    var body: some View {
        Group {
            if let url = preview.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            } else if let text = preview.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(width: 72, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ActivitySectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .modulaGlass(in: Capsule(), interactive: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ActivityRequestActions: View {
    let busy: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Accept", action: onAccept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(busy)
                .accessibilityIdentifier("activity.request.accept")
            Button("Decline", role: .destructive, action: onDecline)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(busy)
                .accessibilityIdentifier("activity.request.decline")
        }
    }
}

struct ActivityRow: View {
    @Environment(AppEnvironment.self) private var app
    @AppStorage(ModulaPreferences.Key.focusFilterActive) private var focusFilterActive = false
    let event: ActivityEvent

    private var dimmedForFocus: Bool {
        guard focusFilterActive, ModulaPreferences.dimsActivityNow else { return false }
        return !(ModulaPreferences.focusAllowsMentions && event.kind.isMention)
    }
    var showActions = false
    var busy = false
    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityActorStack(actors: event.primaryActors, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    ActivityKindBadge(kind: event.kind)
                        .offset(x: 4, y: 4)
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(titleText)
                        .font(.subheadline.weight(event.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if !event.isRead { ActivityUnreadIndicator() }
                    Spacer(minLength: 4)
                    Text(ActivityRelativeTime.string(from: event.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let preview = event.preview?.text, showActions == false, event.preview?.thumbnailURL == nil {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if showActions {
                    ActivityRequestActions(
                        busy: busy,
                        onAccept: { onAccept?() },
                        onDecline: { onDecline?() }
                    )
                    .padding(.top, 4)
                }
            }
            if let preview = event.preview, preview.thumbnailURL != nil {
                ActivitySubjectPreview(preview: preview)
            }
        }
        .padding(.vertical, 11 * app.appearance.density.spacingScale)
        .padding(.horizontal, 10)
        .background {
            if !event.isRead {
                let accent = app.appearance.accent.color
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.11), accent.opacity(0.03)], startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(LinearGradient(colors: [accent.opacity(0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: event.isRead)
        // Settings → Focus → "Dim Activity list" while an iOS Focus filter is on;
        // mentions stay bright when "Still allow @mentions" is on.
        .opacity(dimmedForFocus ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.voiceOverSummary)
        .accessibilityIdentifier("activity.row.\(event.id)")
    }

    private var titleText: String {
        let names = event.primaryActors.map(\.displayName)
        let who: String
        switch names.count {
        case 0: who = "Someone"
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = "\(names[0]) + \(names.count - 1)"
        }
        return "\(who) \(event.descriptionText)"
    }
}

struct ActivityTimeline: View {
    @Environment(AppEnvironment.self) private var app
    let events: [ActivityEvent]
    var mode: ActivityMode
    var onOpen: (ActivityEvent) -> Void
    var onMarkRead: (ActivityEvent) -> Void
    var onAccept: (ActivityEvent) -> Void
    var onDecline: (ActivityEvent) -> Void
    var onLoadMore: () -> Void
    var hasMore: Bool
    var loadingMore: Bool
    /// Request row currently accepting/declining; its controls are disabled.
    var busyEventID: ActivityEventID? = nil
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.section) { group in
                ActivitySectionHeader(title: group.section.title)
                ForEach(group.events) { event in
                    let busy = busyEventID == event.id
                    Button {
                        if let route = event.destination.route {
                            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "activity", key: event.id), for: route)
                        }
                        onOpen(event)
                    } label: {
                        ActivityRow(
                            event: event,
                            showActions: mode == .requests && event.kind.isRequest,
                            busy: busy,
                            onAccept: { onAccept(event) },
                            onDecline: { onDecline(event) }
                        )
                        .modulaHeroSource("activity", key: event.id)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.982, haptic: nil))
                    .modulaScrollReveal()
                    .disabled(busy)
                    .opacity(busy ? 0.6 : 1)
                    .accessibilityValue(busy ? "Updating" : "")
                    .contextMenu {
                        if !event.isRead {
                            Button("Mark as Read", systemImage: "checkmark.circle") { onMarkRead(event) }
                        }
                        if let actor = event.primaryActors.first {
                            Button("Open Profile", systemImage: "person.crop.circle") {
                                app.navigation.push(.profile(actor.id, .overview))
                            }
                        }
                        Button("Notification Settings", systemImage: "bell.badge") {
                            app.navigation.open(.settings(.notifications(.root)))
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !event.isRead {
                            Button("Read") { onMarkRead(event) }
                                .tint(app.appearance.accent.color)
                        }
                    }
                    Divider().opacity(0.22).padding(.leading, 62)
                }
            }
            if hasMore {
                Button {
                    onLoadMore()
                } label: {
                    HStack {
                        Spacer()
                        if loadingMore { ProgressView() } else { Text("Load more") }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.load-more")
            }
        }
    }

    private var sections: [(section: ActivityTimelineSection, events: [ActivityEvent])] {
        var buckets: [ActivityTimelineSection: [ActivityEvent]] = [:]
        for event in events {
            let section: ActivityTimelineSection
            if let hint = event.groupHint?.lowercased() {
                switch hint {
                case "today": section = .today
                case "yesterday": section = .yesterday
                default: section = ActivityTimelineSection.section(for: event.createdAt)
                }
            } else {
                section = ActivityTimelineSection.section(for: event.createdAt)
            }
            buckets[section, default: []].append(event)
        }
        return ActivityTimelineSection.allCases.compactMap { section in
            guard let events = buckets[section], !events.isEmpty else { return nil }
            return (section, events)
        }
    }
}
