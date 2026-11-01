import SwiftUI

struct ActivityScreen: View {
    let mode: ActivityMode
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var requestBusyID: ActivityEventID?
    @State private var chip: ActivityChip = .all
    /// Unread IDs captured at load, so read rows stay in "New" until the next refresh.
    @State private var newIDs: Set<ActivityEventID> = []
    @State private var scrollPosition = ScrollPosition(edge: .top)

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
            if mode == .all { await app.activity.loadIfNeeded(.requests, signedIn: app.auth.isSignedIn) }
            captureNew()
            // Value moment for the push soft pre-prompt (policy decides; never on first launch).
            if mode == .all {
                try? await Task.sleep(for: .seconds(1.2))
                app.push.noteMoment(.activityViewed)
            }
            #if DEBUG
            if let c = ActivityDebugFixture.initialChip { chip = c }
            if ActivityDebugFixture.startsScrolled {
                try? await Task.sleep(for: .seconds(1.5))
                scrollPosition.scrollTo(y: 300)
            }
            #endif
        }
        .onChange(of: app.activity.state(for: mode).lastRefresh) { _, _ in captureNew() }
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

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    private func captureNew() {
        newIDs = Set(app.activity.state(for: mode).events.filter { !$0.isRead }.map(\.id))
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Sign in to see your activity", systemImage: "bell.badge")
        } description: {
            Text("Mentions, reactions, and requests appear here after you sign in.")
        } actions: {
            Button {
                app.navigation.requestAuthentication(returningTo: .activity(mode))
                HapticEngine.shared.play(.navigation)
            } label: {
                Text("Sign In")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, GeneratedDesignContract.Spacing.lg)
                    .frame(minHeight: GeneratedDesignContract.Layout.minimumTouchTarget)
                    .contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
            .modulaAccentCTA()
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
        let requests = mode == .all ? app.activity.state(for: .requests).events.filter { !dismissed.contains($0.id) } : []
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if mode == .all, chip == .all || chip == .follows, !requests.isEmpty {
                    ActivityRequestsEntry(requests: requests) {
                        app.navigation.open(.activity(.requests))
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }
                Group {
                    switch state.loadState {
                    case .loading where state.events.isEmpty:
                        ActivityCardSkeleton()
                    case .failed(let message) where state.events.isEmpty:
                        ActivityLivelyEmptyState(
                            title: "Couldn't load activity",
                            message: message,
                            symbol: "wifi.exclamationmark",
                            actionTitle: "Try Again",
                            action: { Task { await app.activity.refresh(mode, signedIn: true) } }
                        )
                        .padding(.top, 40)
                        .accessibilityIdentifier("activity.error")
                    case _ where shown.isEmpty:
                        empty.padding(.top, 24)
                    default:
                        ActivityClusterFeed(
                            events: shown, mode: mode, newIDs: newIDs, onOpen: open,
                            onMarkRead: { events in Task { await app.activity.markRead(events, mode: mode) } },
                            onMarkAllRead: { Task { await app.activity.markAllRead(mode: mode) } },
                            onDelete: { events in
                                withAnimation(calm ? nil : .snappy(duration: 0.3)) { app.activity.dismiss(events, mode: mode) }
                                app.navigation.flash(events.count > 1 ? "\(events.count) notifications removed" : "Notification removed", symbol: "trash")
                            },
                            onMute: { cluster in mute(cluster) },
                            onAccept: { event in
                                guard requestBusyID == nil else { return }
                                Task { requestBusyID = event.id; await app.activity.accept(event); requestBusyID = nil }
                            },
                            onDecline: { event in
                                guard requestBusyID == nil else { return }
                                Task { requestBusyID = event.id; await app.activity.decline(event); requestBusyID = nil }
                            },
                            onLoadMore: { Task { await app.activity.loadMore(mode) } },
                            hasMore: state.nextCursor != nil,
                            loadingMore: state.loadState == .loadingMore,
                            busyEventID: requestBusyID
                        )
                        .id(chip)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .animation(calm ? nil : .snappy(duration: 0.3), value: chip)
            .padding(.bottom, 110)
            .modulaPullContentEffects()
        }
        .scrollPosition($scrollPosition)
        .environment(\.modulaHeroScope, "activity.\(mode.rawValue)")
        .modulaSoftScrollEdge()
        .activityTopBar(enabled: mode == .all) {
            ActivityChipBar(selection: $chip, unread: chipUnread(visible))
        }
        .modulaShellPullActions { await refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Mark All as Read", systemImage: "checkmark.circle") {
                        Task { await app.activity.markAllRead(mode: mode) }
                    }
                    .disabled(unread == 0)
                    if mode != .requests {
                        Button("Follow Requests", systemImage: "person.badge.plus") { app.navigation.open(.activity(.requests)) }
                    }
                    Divider()
                    Button("Notification Settings", systemImage: "bell.badge") {
                        app.navigation.open(.settings(.notifications(.root)))
                    }
                } label: {
                    Label("Activity options", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("activity.options")
            }
        }
    }

    private func refreshAll() async {
        await app.activity.refresh(mode, signedIn: true)
        if mode == .all { await app.activity.refresh(.requests, signedIn: true) }
    }

    /// Swipe left: mute the person behind the notification, and hide it.
    private func mute(_ cluster: ActivityCluster) {
        withAnimation(calm ? nil : .snappy(duration: 0.3)) { app.activity.dismiss(cluster.events, mode: mode) }
        guard let actor = cluster.actors.first else { return }
        Task {
            if await app.profile.mute(profileID: actor.id) {
                app.navigation.flash("Muted \(actor.displayName)", symbol: "speaker.slash")
            }
        }
    }

    private func chipUnread(_ events: [ActivityEvent]) -> [ActivityChip: Int] {
        var out: [ActivityChip: Int] = [:]
        for chip in ActivityChip.allCases where chip != .all {
            out[chip] = events.filter { !$0.isRead && chip.matches($0) }.count
        }
        return out
    }

    @ViewBuilder private var empty: some View {
        let copy: (String, String, String) = {
            switch (mode, chip) {
            case (.all, .mentions): ("No mentions yet", "When someone mentions you, you'll see it here.", "at")
            case (.all, .reactions): ("No reactions yet", "Likes and reactions to your posts land here.", "heart")
            case (.all, .follows): ("No new followers", "New followers will show up here.", "person.2")
            case (.all, .replies): ("No replies yet", "Replies to your posts and comments land here.", "arrowshape.turn.up.left")
            case (.all, .reposts): ("No reposts yet", "When someone reposts you, it shows up here.", "arrow.2.squarepath")
            case (.all, .modules): ("No module updates", "Installs and updates for your modules appear here.", "shippingbox")
            case (.all, .moliboos): ("Moliboo moments", "When your Moliboo levels up or a friend's Moliboo visits, it'll show up here.", "pawprint")
            case (.all, _): ("You're all caught up", "New likes, replies and follows will appear here.", "bell")
            case (.mentions, _): ("No mentions yet", "When someone mentions you, you'll see it here.", "at")
            case (.requests, _): ("No pending requests", "Follow and connection requests show up here.", "person.badge.plus")
            }
        }()
        let isMoliboo = chip == .moliboos
        let offersPeople = chip == .all || chip == .follows
        VStack(alignment: .leading, spacing: 0) {
            ActivityLivelyEmptyState(
                title: copy.0, message: copy.1, symbol: copy.2,
                footnote: isMoliboo ? "Coming soon" : nil,
                actionTitle: isMoliboo ? "Visit your Moliboo" : (offersPeople ? "Find people" : nil),
                action: emptyAction(moliboo: isMoliboo)
            )
            if chip == .all || chip == .follows { ActivitySuggestedPeople() }
        }
        .accessibilityIdentifier("activity.empty.\(mode.rawValue)")
    }

    private func emptyAction(moliboo: Bool) -> () -> Void {
        if moliboo {
            return { app.navigation.open(.settings(.moliboo)); HapticEngine.shared.play(.navigation) }
        }
        return { app.navigation.open(.discover(.people)); HapticEngine.shared.play(.navigation) }
    }

    private func open(_ event: ActivityEvent) {
        Task { await app.activity.markRead(event, mode: mode) }
        if let route = event.destination.route {
            app.navigation.open(route)
            HapticEngine.shared.play(.navigation)
        }
    }
}

private extension View {
    /// Pins the chip strip under the navigation bar. On iOS 26 `safeAreaBar` extends the
    /// scroll edge effect beneath it, so content blurs progressively under title + chips
    /// instead of sliding under the chips unblurred.
    @ViewBuilder
    func activityTopBar<Bar: View>(enabled: Bool, @ViewBuilder _ bar: () -> Bar) -> some View {
        if !enabled {
            self
        } else if #available(iOS 26.0, *) {
            let content = bar()
            self.safeAreaBar(edge: .top, spacing: 0) { content }
        } else {
            let content = bar()
            self.safeAreaInset(edge: .top, spacing: 0) { content.background(.bar) }
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
                        .foregroundStyle(app.appearance.liveAccent)
                }
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Rectangle())
        }
        .disabled(applying != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

