import SwiftUI

struct ActivityRelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

struct ActivityUnreadIndicator: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Circle()
            .fill(app.appearance.accent.color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

struct ActivityActorStack: View {
    let actors: [ActivityActor]
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(actors.prefix(3).enumerated()), id: \.element.id) { index, actor in
                ModulaAvatar(initials: actor.initials, size: size)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 2)
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
    let event: ActivityEvent
    var showActions = false
    var busy = false
    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityActorStack(actors: event.primaryActors, size: 40)
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
        .padding(.vertical, 10 * app.appearance.density.spacingScale)
        .padding(.horizontal, 2)
        .background(event.isRead ? Color.clear : app.appearance.accent.color.opacity(0.05))
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

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.section) { group in
                ActivitySectionHeader(title: group.section.title)
                ForEach(group.events) { event in
                    let busy = busyEventID == event.id
                    Button {
                        onOpen(event)
                    } label: {
                        ActivityRow(
                            event: event,
                            showActions: mode == .requests && event.kind.isRequest,
                            busy: busy,
                            onAccept: { onAccept(event) },
                            onDecline: { onDecline(event) }
                        )
                    }
                    .buttonStyle(.plain)
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
                    Divider().opacity(0.35)
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
