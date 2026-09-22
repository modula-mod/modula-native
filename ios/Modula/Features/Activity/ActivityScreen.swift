import SwiftUI

struct ActivityScreen: View {
    let mode: ActivityMode
    @Environment(AppEnvironment.self) private var app
    @State private var requestBusyID: ActivityEventID?

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
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .onTapGesture { app.activity.clearActionError() }
                    .accessibilityIdentifier("activity.banner")
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
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let unread = state.unreadCount, unread > 0 {
                    Text("\(unread) unread")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(app.appearance.accent.color)
                        .padding(.top, 4)
                }
                switch state.loadState {
                case .loading where state.events.isEmpty:
                    skeleton
                case .failed(let message) where state.events.isEmpty:
                    ModulaErrorState(message: message) {
                        Task { await app.activity.refresh(mode, signedIn: true) }
                    }
                    .padding(.top, 40)
                    .accessibilityIdentifier("activity.error")
                case _ where state.events.isEmpty:
                    empty
                        .padding(.top, 28)
                default:
                    ActivityTimeline(
                        events: state.events,
                        mode: mode,
                        onOpen: open,
                        onMarkRead: { event in
                            Task { await app.activity.markRead(event, mode: mode) }
                        },
                        onAccept: { event in
                            Task {
                                requestBusyID = event.id
                                await app.activity.accept(event)
                                requestBusyID = nil
                            }
                        },
                        onDecline: { event in
                            Task {
                                requestBusyID = event.id
                                await app.activity.decline(event)
                                requestBusyID = nil
                            }
                        },
                        onLoadMore: {
                            Task { await app.activity.loadMore(mode) }
                        },
                        hasMore: state.nextCursor != nil,
                        loadingMore: state.loadState == .loadingMore
                    )
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
            .modulaPullContentEffects()
        }
        .modulaSoftScrollEdge()
        .modulaShellPullActions {
            await app.activity.refresh(mode, signedIn: true)
        }
    }

    private var empty: some View {
        let copy: (String, String, String) = {
            switch mode {
            case .all: ("You're caught up.", "New activity will appear here.", "bell")
            case .mentions: ("No mentions yet.", "When someone mentions you, you'll see it here.", "at")
            case .requests: ("No pending requests.", "Follow and connection requests show up here.", "person.badge.plus")
            }
        }()
        return ModulaEmptyState(title: copy.0, message: copy.1, symbol: copy.2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityIdentifier("activity.empty.\(mode.rawValue)")
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Color.primary.opacity(0.08)).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)).frame(width: 160, height: 10)
                    }
                }
            }
        }
        .padding(.top, 12)
        .accessibilityIdentifier("activity.loading")
        .redacted(reason: .placeholder)
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

    var body: some View {
        let mode: ActivityMode = {
            if case .activity(let mode) = app.navigation.currentRoute { return mode }
            return .all
        }()
        let current = app.activity.state(for: mode).filter
        List {
            Section("Status") {
                filterRow(title: "All in \(mode.rawValue.capitalized)", symbol: "bell", selected: current == nil) {
                    Task {
                        await app.activity.setFilter(nil, mode: mode, signedIn: app.auth.isSignedIn)
                        dismiss()
                    }
                }
                filterRow(title: ActivityFilter.unread.title, symbol: ActivityFilter.unread.symbol, selected: current == .unread) {
                    apply(.unread)
                }
            }
            Section("Types") {
                ForEach([ActivityFilter.following, .mentions, .reactions, .comments, .requests, .modules, .system]) { filter in
                    filterRow(title: filter.title, symbol: filter.symbol, selected: current == filter) {
                        apply(filter)
                    }
                    .accessibilityIdentifier("activity.filter.\(filter.rawValue)")
                }
            }
            Section("Broader") {
                ForEach([ActivityFilter.people, .posts]) { filter in
                    filterRow(title: filter.title, symbol: filter.symbol, selected: current == filter) {
                        apply(filter)
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

    private func apply(_ filter: ActivityFilter) {
        let mode: ActivityMode = {
            if case .activity(let mode) = app.navigation.currentRoute { return mode }
            return .all
        }()
        Task {
            await app.activity.setFilter(filter, mode: mode, signedIn: app.auth.isSignedIn)
            HapticEngine.shared.play(.selection)
            dismiss()
        }
    }

    private func filterRow(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
        }
    }
}

