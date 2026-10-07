import SwiftUI

struct ActivityScreen: View {
    let mode: ActivityMode
    @Environment(AppEnvironment.self) private var app
    @State private var requestBusyID: ActivityEventID?
    @State private var chip: ActivityChip = .all

    var body: some View {
        Group {
            if app.auth.account == nil {
                signedOut
            } else {
                signedIn
            }
        }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .modulaSidebarTrigger()
        .accessibilityIdentifier("activity.\(mode.rawValue)")
        .task(id: mode) {
            await app.activity.loadIfNeeded(mode, signedIn: app.auth.isSignedIn)
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            Task { await app.activity.refresh(mode, signedIn: app.auth.isSignedIn) }
        }
        .overlay(alignment: .bottom) {
            if let message = app.activity.actionError {
                ModulaErrorBanner(message: message, identifier: "activity.banner") {
                    app.activity.clearActionError()
                }
            }
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Sign in to see your activity", systemImage: "bell.badge")
        } description: {
            Text("Mentions, reactions, and requests appear here after you sign in.")
        } actions: {
            Button("Sign In") {
                app.navigation.requestAuthentication(returningTo: .activity(mode))
                HapticEngine.shared.play(.navigation)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("activity.sign-in")
        }
        .padding(.horizontal, ModulaLayout.contentInset)
    }

    private var signedIn: some View {
        let state = app.activity.state(for: mode)
        let dismissed = app.activity.dismissedIDs
        let visible = state.events.filter { !dismissed.contains($0.id) }
        let shown = visible.filter(chip.matches)
        let unread = state.unreadCount ?? visible.filter { !$0.isRead }.count
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ActivityPulseHeader(events: visible, unread: unread) {
                    Task { await app.activity.markAllRead(mode: mode) }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 4)
                .modulaPageEntrance()
                Section {
                    Group {
                        switch state.loadState {
                        case .loading where state.events.isEmpty:
                            ActivityCardSkeleton()
                        case .failed(let message) where state.events.isEmpty:
                            ModulaErrorState(message: message) {
                                Task { await app.activity.refresh(mode, signedIn: true) }
                            }
                            .padding(.top, 40)
                            .accessibilityIdentifier("activity.error")
                        case _ where shown.isEmpty:
                            empty.padding(.top, 20)
                        default:
                            ActivityClusterFeed(
                                events: shown, mode: mode, onOpen: open,
                                onMarkRead: { events in Task { await app.activity.markRead(events, mode: mode) } },
                                onDelete: { events in
                                    withAnimation(.snappy(duration: 0.3)) { app.activity.dismiss(events, mode: mode) }
                                    app.navigation.flash(events.count > 1 ? "\(events.count) notifications removed" : "Notification removed", symbol: "trash")
                                },
                                onAccept: { event in
                                    guard requestBusyID == nil else { return }
                                    Task { requestBusyID = event.id; await app.activity.accept(event); requestBusyID = nil }
                                },
                                onDecline: { event in
                                    guard requestBusyID == nil else { return }
                                    Task { requestBusyID = event.id; await app.activity.decline(event); requestBusyID = nil }
                                },
                                onLoadMore: { Task { await app.activity.loadMore(mode) } },
                                hasMore: state.nextCursor != nil && chip == .all,
                                loadingMore: state.loadState == .loadingMore,
                                busyEventID: requestBusyID
                            )
                            .id(chip)
                        }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                } header: {
                    if mode == .all { ActivityChipBar(selection: $chip, unread: chipUnread(visible)) }
                }
            }
            .animation(.snappy(duration: 0.32), value: chip)
            .padding(.bottom, 28)
            .modulaPullContentEffects()
        }
        .environment(\.modulaHeroScope, "activity.\(mode.rawValue)")
        .modulaSoftScrollEdge()
        .modulaShellPullActions { await app.activity.refresh(mode, signedIn: true) }
    }

    private func chipUnread(_ events: [ActivityEvent]) -> [ActivityChip: Int] {
        var out: [ActivityChip: Int] = [:]
        for chip in ActivityChip.allCases where chip != .all {
            out[chip] = events.filter { !$0.isRead && chip.matches($0) }.count
        }
        return out
    }

    private var empty: some View {
        let copy: (String, String, String) = {
            switch (mode, chip) {
            case (.all, .mentions): ("No mentions yet.", "When someone mentions you, you'll see it here.", "at")
            case (.all, .likes): ("No likes yet.", "Reactions to your posts land here.", "heart")
            case (.all, .follows): ("No new followers.", "New followers will show up here.", "person.2")
            case (.all, .modules): ("No module updates.", "Installs and updates for your modules appear here.", "shippingbox")
            case (.all, _): ("You're caught up.", "New activity will appear here.", "bell")
            case (.mentions, _): ("No mentions yet.", "When someone mentions you, you'll see it here.", "at")
            case (.requests, _): ("No pending requests.", "Follow and connection requests show up here.", "person.badge.plus")
            }
        }()
        return ActivityLivelyEmptyState(
            title: copy.0, message: copy.1, symbol: copy.2,
            actionTitle: "Find people to follow",
            action: { app.navigation.open(.discover(.people)); HapticEngine.shared.play(.navigation) }
        )
        .accessibilityIdentifier("activity.empty.\(mode.rawValue)")
    }

    private func open(_ event: ActivityEvent) {
        Task { await app.activity.markRead(event, mode: mode) }
        if let route = event.destination.route {
            app.navigation.open(route)
            HapticEngine.shared.play(.navigation)
        }
    }
}

struct ActivitySummarySheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mode: ActivityMode = {
            if case .activity(let mode) = app.navigation.currentRoute { return mode }
            return .all
        }()
        let summary = app.activity.summary(for: mode)
        List {
            Section("Overview") {
                LabeledContent("Unread", value: "\(summary.unreadCount)")
                LabeledContent("Mentions", value: "\(summary.mentionCount)")
                LabeledContent("Requests", value: "\(summary.requestCount)")
                LabeledContent("Reactions", value: "\(summary.reactionCount)")
                LabeledContent("Comments", value: "\(summary.commentCount)")
            }
            if !summary.mostActiveNames.isEmpty {
                Section("Most active") {
                    Text(summary.mostActiveNames.joined(separator: ", "))
                }
            }
            if !summary.highlights.isEmpty {
                Section("Highlights") {
                    ForEach(summary.highlights, id: \.self) { Text($0) }
                }
            }
            Section {
                Text(summary.source == .aggregates
                      ? "Deterministic summary from loaded Activity data. AI summaries can replace this later."
                      : "AI-generated summary")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Activity Summary")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("activity.summary")
    }
}

struct ActivityFilterSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Row being applied; blocks repeat taps and shows inline progress.
    @State private var applying: String?

    var body: some View {
        let mode: ActivityMode = {
            if case .activity(let mode) = app.navigation.currentRoute { return mode }
            return .all
        }()
        let current = app.activity.state(for: mode).filter
        List {
            Section("Status") {
                filterRow(id: "all", title: Self.allTitle(for: mode), symbol: "bell", selected: current == nil) {
                    apply(nil, id: "all")
                }
                filterRow(id: ActivityFilter.unread.rawValue, title: ActivityFilter.unread.title, symbol: ActivityFilter.unread.symbol, selected: current == .unread) {
                    apply(.unread, id: ActivityFilter.unread.rawValue)
                }
            }
            Section("Types") {
                ForEach([ActivityFilter.following, .mentions, .reactions, .comments, .requests, .modules, .system]) { filter in
                    filterRow(id: filter.rawValue, title: filter.title, symbol: filter.symbol, selected: current == filter) {
                        apply(filter, id: filter.rawValue)
                    }
                    .accessibilityIdentifier("activity.filter.\(filter.rawValue)")
                }
            }
            Section("Broader") {
                ForEach([ActivityFilter.people, .posts]) { filter in
                    filterRow(id: filter.rawValue, title: filter.title, symbol: filter.symbol, selected: current == filter) {
                        apply(filter, id: filter.rawValue)
                    }
                    .accessibilityIdentifier("activity.filter.\(filter.rawValue)")
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Options")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .accessibilityIdentifier("activity.filter")
    }

    /// User-facing mode names (never raw enum values).
    static func allTitle(for mode: ActivityMode) -> String {
        switch mode {
        case .all: "All Activity"
        case .mentions: "All Mentions"
        case .requests: "All Requests"
        }
    }

    private func apply(_ filter: ActivityFilter?, id: String) {
        guard applying == nil else { return }
        let mode: ActivityMode = {
            if case .activity(let mode) = app.navigation.currentRoute { return mode }
            return .all
        }()
        applying = id
        Task {
            await app.activity.setFilter(filter, mode: mode, signedIn: app.auth.isSignedIn)
            HapticEngine.shared.play(.selection)
            applying = nil
            dismiss()
        }
    }

    private func filterRow(id: String, title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if applying == id {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(app.appearance.accent.color)
                }
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Rectangle())
        }
        .disabled(applying != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

