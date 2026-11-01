import SwiftUI
import UIKit

struct MessagesRootView: View {
    let route: MessagesRoute
    @Environment(AppEnvironment.self) private var app
    @Environment(\.routeTransitionNamespace) private var routeTransitions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch route {
            case .inbox:
                ConversationListView()
            case .requests:
                MessageRequestsView()
            case .inMail(let mail):
                InMailRouteView(route: mail)
            case .new:
                NewConversationView()
            case .direct(let person):
                DirectMessageView(person: person)
            case .conversation(let id):
                ConversationView(conversationID: id)
                    .modulaZoomDestination(id: "conversation.\(id)", namespace: routeTransitions, reduceMotion: reduceMotion)
            }
        }
        .modulaCanvas()
        .navigationBarBackButtonHidden(false)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct ConversationListView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: InboxFilter = .all

    enum InboxFilter: String, CaseIterable, Identifiable {
        case all, unread, groups
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .unread: "Unread"
            case .groups: "Groups"
            }
        }
        func matches(_ c: Conversation) -> Bool {
            switch self {
            case .all: true
            case .unread: c.isUnread
            case .groups: c.kind == .group || c.participants.count > 1
            }
        }
    }

    var body: some View {
        content
            .modulaSoftScrollEdge()
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.navigation.push(.messages(.new))
                        HapticEngine.shared.play(.navigation)
                    } label: {
                        Label("New message", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("messages.compose")
                }
            }
            .task {
                #if DEBUG
                if MessagingDebugFixture.isEnabled {
                    if app.messaging.conversations.isEmpty { app.messaging.installDebugInbox(MessagingDebugFixture.inbox()) }
                    return
                }
                #endif
                await app.messaging.loadInboxIfNeeded()
            }
            .refreshable { await app.messaging.refreshInbox() }
            .overlay(alignment: .bottom) { errorBanner }
            .accessibilityIdentifier("messages.inbox")
            .accessibilityValue(RouteSerializer.serialize(.messages(.inbox)))
    }

    /// Scope, search and filters scroll with the list (like Messages), so the large title
    /// collapses normally instead of starting half-faded under a tall pinned bar.
    private var header: some View {
        VStack(spacing: 8) {
            MessagesScopePicker(selection: .inbox)
            MessagesGlassSearchField(text: Bindable(app.messaging).conversationQuery, prompt: "Search chats")
                .padding(.horizontal, ModulaLayout.contentInset)
            filterRow
        }
        .padding(.bottom, 6)
    }

    private var filterRow: some View {
        let all = app.messaging.visibleConversations
        let unread = all.filter(\.isUnread).count
        return ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(InboxFilter.allCases) { item in
                        let on = item == filter
                        Button {
                            guard item != filter else { return }
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { filter = item }
                            HapticEngine.shared.play(.selection)
                        } label: {
                            HStack(spacing: 5) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                if item == .unread, unread > 0 {
                                    Text("\(unread)").font(.caption2.weight(.bold)).monospacedDigit()
                                        .foregroundStyle(on ? Color.white.opacity(0.9) : app.appearance.liveAccent)
                                }
                            }
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background { if on { Capsule().fill(app.appearance.liveAccent) } }
                            .modulaGlass(in: Capsule(), interactive: true, tint: on ? app.appearance.liveAccent.opacity(0.35) : nil)
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("messages.filter.\(item.rawValue)")
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var content: some View {
        let items = app.messaging.visibleConversations.filter(filter.matches)
        let searching = !app.messaging.conversationQuery.trimmingCharacters(in: .whitespaces).isEmpty
        if items.isEmpty {
            VStack(spacing: 0) {
                header
                emptyState(searching: searching)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(items) { conversation in
                    Button {
                        open(conversation)
                    } label: {
                        ConversationRow(conversation: conversation, viewerID: app.auth.account?.accountId)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: ModulaLayout.contentInset, bottom: 6, trailing: ModulaLayout.contentInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if conversation.isUnread, app.messaging.capabilities.markRead {
                            Button {
                                Task { await app.messaging.markConversationRead(conversation.id) }
                            } label: { Label("Read", systemImage: "checkmark.message.fill") }
                            .tint(app.appearance.liveAccent)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let person = conversation.participants.first {
                            Button {
                                app.navigation.push(.profile(person.id, .overview))
                            } label: { Label("Profile", systemImage: "person.crop.circle") }
                            .tint(.gray)
                        }
                    }
                    .contextMenu { contextMenu(conversation) }
                    .onAppear {
                        if conversation.id == items.last?.id {
                            Task { await app.messaging.loadMoreConversations() }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .modulaSoftScrollEdge()
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: filter)
        }
    }

    @ViewBuilder
    private func emptyState(searching: Bool) -> some View {
        switch app.messaging.conversationState {
        case .loading:
            MessagesSkeletonList(label: "Loading conversations")
        case .failed(let message):
            MessagesFriendlyEmpty(scope: .inbox, retryMessage: message) {
                await app.messaging.refreshInbox()
            }
        case _ where searching || filter != .all:
            ContentUnavailableView {
                Label(searching ? "No matching chats" : (filter == .unread ? "You're all caught up" : "No group chats"),
                      systemImage: searching ? "magnifyingglass" : (filter == .unread ? "checkmark.bubble" : "person.3"))
            } description: {
                Text(searching ? "Search looks through the chats loaded on this device." : "Nothing here right now.")
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
        default:
            MessagesFriendlyEmpty(scope: .inbox)
        }
    }

    @ViewBuilder
    private func contextMenu(_ conversation: Conversation) -> some View {
        Button("Open Chat", systemImage: "bubble.left.and.bubble.right") { open(conversation) }
        if conversation.isUnread, app.messaging.capabilities.markRead {
            Button("Mark as Read", systemImage: "checkmark.message") {
                Task { await app.messaging.markConversationRead(conversation.id) }
            }
        }
        if let person = conversation.participants.first {
            Button("View Profile", systemImage: "person.crop.circle") { app.navigation.push(.profile(person.id, .overview)) }
        }
        Button("Copy Name", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = conversation.title
            HapticEngine.shared.play(.confirmation)
        }
    }

    private func open(_ conversation: Conversation) {
        app.navigation.push(.messages(.conversation(conversation.id)))
        HapticEngine.shared.play(.navigation)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = app.messaging.actionError {
            MessagesRetryBanner(message: "Showing saved messages. \(message)") {
                app.messaging.clearActionError()
                await app.messaging.refreshInbox()
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 12)
        }
    }
}

/// Liquid Glass search capsule (local filter over loaded chats).
struct MessagesGlassSearchField: View {
    @Binding var text: String
    var prompt = "Search"
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .modulaGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.search")
    }
}

extension View {
    /// Pins chrome under the nav bar; on iOS 26 `safeAreaBar` extends the soft scroll edge
    /// beneath it so rows blur progressively instead of sliding under it.
    @ViewBuilder
    func messagesTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let content = bar()
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .top, spacing: 0) { content }
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) { content.background(.bar) }
        }
    }
}

enum MessagesScope: Hashable {
    case inbox, inMail, requests
}

struct MessagesScopePicker: View {
    let selection: MessagesScope
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                MessagesGlassScopeControl(selection: selection, onSelect: navigate)
            } else {
                ModulaTabStrip(
                    items: [
                        ModulaTabItem(id: MessagesScope.inbox, title: "Chats", systemImage: "bubble.left"),
                        ModulaTabItem(id: MessagesScope.inMail, title: "In-Mail", systemImage: "envelope"),
                        ModulaTabItem(id: MessagesScope.requests, title: "Requests", systemImage: "person.badge.clock")
                    ],
                    selection: Binding(get: { selection }, set: navigate),
                    layout: .equalWidth,
                    compact: true,
                    accessibilityLabel: "Message sections"
                )
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 6)
        .accessibilityIdentifier("messages.scope")
    }

    private func navigate(_ scope: MessagesScope) {
        switch scope {
        case .inbox: app.navigation.replaceTop(with: .messages(.inbox))
        case .inMail: app.navigation.replaceTop(with: .messages(.inMail(.inbox)))
        case .requests: app.navigation.replaceTop(with: .messages(.requests))
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var viewerID: String? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.routeTransitionNamespace) private var routeTransitions

    private var isGroup: Bool { conversation.kind == .group || conversation.participants.count > 1 }
    private var lastIsOwn: Bool {
        guard let sender = conversation.lastMessage?.senderID, let viewerID else { return false }
        return sender == viewerID
    }

    var body: some View {
        let unread = conversation.isUnread
        let accent = app.appearance.liveAccent
        HStack(alignment: .center, spacing: 12) {
            ConversationAvatar(participants: conversation.participants, unread: unread, size: 54)
                .modulaZoomSource(id: "conversation.\(conversation.id)", namespace: routeTransitions)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(.body.weight(unread ? .semibold : .medium))
                        .lineLimit(1)
                    if isGroup {
                        Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(Self.relative(conversation.updatedAt))
                        .font(.caption.weight(unread ? .semibold : .regular))
                        .foregroundStyle(unread ? accent : Color.secondary)
                        .monospacedDigit()
                }
                HStack(alignment: .center, spacing: 8) {
                    previewText
                        .font(.subheadline)
                        .foregroundStyle(unread ? Color.primary.opacity(0.85) : Color.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if unread {
                        Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(accent))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("messages.row.\(conversation.id)")
    }

    private var previewText: Text {
        let body = conversation.lastMessage?.body ?? ""
        if body.isEmpty { return Text("No messages yet").italic() }
        if lastIsOwn { return Text("You: ").fontWeight(.medium) + Text(body) }
        if isGroup, let senderID = conversation.lastMessage?.senderID,
           let sender = conversation.participants.first(where: { $0.id == senderID }) {
            let first = sender.displayName.split(separator: " ").first.map(String.init) ?? sender.displayName
            return Text("\(first): ").fontWeight(.medium) + Text(body)
        }
        return Text(body)
    }

    private var accessibilityLabel: String {
        var parts = [conversation.title]
        if let preview = conversation.lastMessage?.body { parts.append(lastIsOwn ? "You: \(preview)" : preview) }
        parts.append(Self.relative(conversation.updatedAt))
        if conversation.isUnread {
            parts.append(String(localized: "\(conversation.unreadCount) unread"))
        } else {
            parts.append("Read")
        }
        return parts.joined(separator: ", ")
    }

    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    @MainActor static func relative(_ date: Date) -> String {
        guard ModulaPreferences.relativeTimestamps else { return ModulaTimeFormat.absolute(date) }
        if abs(Date().timeIntervalSince(date)) < 45 { return String(localized: "now") }
        return relativeFormatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }
}

struct ConversationAvatar: View {
    var participants: [ConversationParticipant]
    var unread = false
    var size: CGFloat = 48
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    init(participant: ConversationParticipant?, unread: Bool = false, size: CGFloat = 48) {
        self.participants = participant.map { [$0] } ?? []
        self.unread = unread
        self.size = size
    }

    init(participants: [ConversationParticipant], unread: Bool = false, size: CGFloat = 48) {
        self.participants = participants
        self.unread = unread
        self.size = size
    }

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        ZStack {
            if participants.count >= 2 {
                let small = size * 0.7
                ModulaAvatar(initials: participants[1].initials, url: participants[1].avatarURL, size: small, name: participants[1].displayName)
                    .offset(x: -(size - small) / 2, y: -(size - small) / 2)
                ModulaAvatar(initials: participants[0].initials, url: participants[0].avatarURL, size: small, name: participants[0].displayName)
                    .overlay(Circle().stroke(canvas, lineWidth: 2))
                    .offset(x: (size - small) / 2, y: (size - small) / 2)
            } else {
                let p = participants.first
                ModulaAvatar(initials: p?.initials ?? "?", url: p?.avatarURL, size: size, name: p?.displayName)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if unread {
                Circle().fill(app.appearance.liveAccent)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(canvas, lineWidth: 2))
                    .offset(x: 1, y: -1)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        ModulaUnreadIndicator(count: max(count, 1), tone: .accent, maximum: 9)
            .accessibilityHidden(true)
    }
}

struct ConversationView: View {
    let conversationID: ConversationID
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reply: ModulaComposerReply?
    @State private var replyQuote: String?
    @State private var composerFocused = false

    var body: some View {
        thread
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Composer floats over the thread so messages scroll under its glass.
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .modulaSoftScrollEdge()
            .navigationTitle(conversation?.title ?? "Conversation")
            .toolbar {
                ToolbarItem(placement: .principal) { header }
            }
        .task { await app.messaging.loadThreadIfNeeded(conversationID) }
        .refreshable { await app.messaging.refreshThread(conversationID) }
        .accessibilityIdentifier("messages.conversation.\(conversationID)")
        .accessibilityValue(RouteSerializer.serialize(.messages(.conversation(conversationID))))
    }

    private var conversation: Conversation? { app.messaging.conversation(id: conversationID) }

    /// Name and avatar in the navigation bar; a direct chat's header opens that profile.
    private var header: some View {
        Button {
            guard let conversation, conversation.kind == .direct, let person = conversation.participants.first else { return }
            HapticEngine.shared.play(.navigation)
            app.navigation.push(.profile(person.handle.isEmpty ? person.id : person.handle, .overview))
        } label: {
            HStack(spacing: 8) {
                ModulaAvatar(initials: conversation?.participants.first?.initials ?? "?",
                             url: conversation?.participants.first?.avatarURL, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(conversation?.title ?? "Conversation")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let handle = conversation?.handleLabel {
                        Text(handle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(conversation?.kind == .direct ? "Opens their profile" : "")
        .accessibilityIdentifier("messages.conversation.header")
    }

    @ViewBuilder
    private var thread: some View {
        let items = app.messaging.messages(for: conversationID)
        switch app.messaging.threadState[conversationID] ?? .idle {
        case .loading where items.isEmpty:
            ModulaLoadingState(title: "Loading messages")
        case .failed(let message) where items.isEmpty:
            ModulaErrorState(message: message) {
                Task { await app.messaging.refreshThread(conversationID) }
            }
        case _ where items.isEmpty:
            if app.messaging.capabilities.send {
                MessageStarterView(conversation: conversation) { text in
                    app.messaging.drafts[conversationID] = text
                    HapticEngine.shared.play(.selection)
                }
            } else {
                ModulaEmptyState(
                    title: "No messages yet",
                    message: "This conversation isn’t available yet.",
                    symbol: "text.bubble"
                )
            }
        default:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let lastOwnID = items.last(where: \.isOwn)?.id
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
                            let position = MessageGroupPosition.resolve(index: index, in: items)
                            if let label = MessageTimeline.separator(at: index, in: items) {
                                MessageTimeSeparator(label: label)
                                    .padding(.top, index == 0 ? 0 : 14)
                                    .padding(.bottom, 6)
                            }
                            MessageBubble(message: message, position: position, showsStatus: message.id == lastOwnID) { action in
                                handle(action, message: message)
                            }
                            // Tight spacing inside a run of messages, roomier between senders.
                            .padding(.top, index == 0 ? 0 : (position.startsGroup ? 10 : 2))
                            .id(message.id)
                            // New bubbles rise in from the composer; plain fade under Reduce Motion.
                            .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.vertical, 12)
                }
                // Chats open on the newest message and stay pinned there.
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .modulaSoftScrollEdge()
                .onChange(of: items.count) { _, _ in
                    scrollToLatest(items, proxy: proxy)
                }
                .onChange(of: items.last?.id) { _, _ in
                    scrollToLatest(items, proxy: proxy)
                }
            }
        }
    }

    private func scrollToLatest(_ items: [Message], proxy: ScrollViewProxy) {
        guard let last = items.last?.id else { return }
        withAnimation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    private var composer: some View {
        MessageComposer(
            text: Binding(
                get: { app.messaging.drafts[conversationID] ?? "" },
                set: { app.messaging.drafts[conversationID] = $0 }
            ),
            canSend: app.messaging.capabilities.send,
            showsAttachments: app.messaging.capabilities.attachments,
            largeText: dynamicTypeSize.isAccessibilitySize,
            reply: reply,
            onCancelReply: cancelReply,
            focus: $composerFocused
        ) {
            reply = nil
            replyQuote = nil
            IslandSendEffect.shared.fire("Message sent", accent: app.appearance.liveAccent)
            Task {
                await app.messaging.send(
                    conversation: conversationID,
                    viewer: viewer
                )
            }
        }
    }

    private func cancelReply() {
        if let replyQuote {
            let prefix = replyQuote + "\n"
            var draft = app.messaging.drafts[conversationID] ?? ""
            if draft.hasPrefix(prefix) {
                draft.removeFirst(prefix.count)
                app.messaging.drafts[conversationID] = draft
            }
        }
        reply = nil
        replyQuote = nil
    }

    private var viewer: ConversationParticipant {
        ConversationParticipant(
            id: app.auth.account?.accountId ?? "me",
            handle: app.auth.account?.primaryHandle ?? "",
            displayName: app.auth.account?.displayName ?? "You",
            avatarURL: nil
        )
    }

    private func handle(_ action: ModulaContextAction, message: Message) {
        switch action.id {
        case "copy":
            UIPasteboard.general.string = message.body.text
            HapticEngine.shared.play(.confirmation)
        case "retry":
            Task { await app.messaging.retry(message: message, viewer: viewer) }
        case "reply":
            // Swipe-to-reply (Settings → Gestures): quote the message into the composer.
            // There is no reply-to field on POST /v1/conversations/:id/messages, so the quote stays in the text.
            let quoted = message.body.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(3)
                .map { "> " + $0 }
                .joined(separator: "\n")
            let who = message.sender.handle.isEmpty ? message.sender.displayName : "@\(message.sender.handle)"
            reply = ModulaComposerReply(title: "Replying to \(who)", excerpt: message.body.text)
            replyQuote = quoted
            let existing = app.messaging.drafts[conversationID] ?? ""
            app.messaging.drafts[conversationID] = quoted + "\n" + existing
            composerFocused = true
            HapticEngine.shared.play(.selection)
        default:
            break
        }
    }
}

/// Position of a bubble inside a run of consecutive messages from the
/// same sender (within a few minutes). Drives corner shape, spacing and
/// whether the incoming avatar is shown (only on the last bubble).
enum MessageGroupPosition: Sendable {
    case single, first, middle, last

    var startsGroup: Bool { self == .single || self == .first }
    var endsGroup: Bool { self == .single || self == .last }

    static func resolve(index: Int, in items: [Message]) -> MessageGroupPosition {
        func joined(_ a: Message, _ b: Message) -> Bool {
            a.sender.id == b.sender.id
                && a.isOwn == b.isOwn
                && abs(b.sentAt.timeIntervalSince(a.sentAt)) < 5 * 60
        }
        let current = items[index]
        let joinsPrevious = index > 0 && joined(items[index - 1], current)
        let joinsNext = index + 1 < items.count && joined(current, items[index + 1])
        switch (joinsPrevious, joinsNext) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }
}

struct MessageBubble: View {
    let message: Message
    var position: MessageGroupPosition = .single
    /// Sending / Sent / Delivered under the newest own message only.
    var showsStatus = false
    var onAction: (ModulaContextAction) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    private static let avatarSize = 28.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isOwn {
                Spacer(minLength: 48)
            } else {
                // Avatar only on the last bubble of an incoming run; keep the
                // gutter elsewhere so the run stays aligned.
                Group {
                    if position.endsGroup {
                        ModulaAvatar(initials: message.sender.initials, url: message.sender.avatarURL, size: Self.avatarSize)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .accessibilityHidden(true)
            }
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 6) {
                let parsed = ModulaLocalSticker.extract(message.body.text)
                if !parsed.text.isEmpty {
                    Text(parsed.text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleFill, in: bubbleShape)
                        .foregroundStyle(message.isOwn ? Color.white : Color.primary)
                }
                if !parsed.stickers.isEmpty {
                    ModulaLocalStickerRow(stickers: parsed.stickers)
                }
                if let attachment = MessageInlineContent.detect(in: message.body.text) {
                    MessageInlineContentView(content: attachment)
                }
                HStack(spacing: 8) {
                    if message.delivery == .failed {
                        Button("Retry") { onAction(.init(id: "retry", title: "Retry")) }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: ModulaLayout.minimumTouch)
                            .contentShape(Rectangle())
                    } else if app.messaging.capabilities.readReceipts, ModulaPreferences.chatShowReadReceipts,
                              message.isOwn, message.delivery == .read {
                        Text("Read")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if showsStatus, message.isOwn, let status = MessageTimeline.status(for: message.delivery) {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                            .accessibilityIdentifier("messages.bubble.status")
                    }
                }
            }
            if !message.isOwn { Spacer(minLength: 48) }
        }
        .offset(x: replyOffset)
        .background(alignment: .leading) {
            if replyOffset > 8 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.secondary)
                    .opacity(min(1, replyOffset / Self.replyThreshold))
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
            }
        }
        .simultaneousGesture(swipeToReply)
        .modulaContextMenu(actions: actions, onSelect: onAction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(message.delivery == .failed ? "Not sent. Swipe up or down for Retry." : "")
        .accessibilityActions {
            if message.delivery == .failed {
                Button("Retry") { onAction(.init(id: "retry", title: "Retry")) }
            }
            Button("Copy") { onAction(.init(id: "copy", title: "Copy")) }
            Button("Reply") { onAction(.init(id: "reply", title: "Reply")) }
        }
        .accessibilityIdentifier("messages.bubble.\(message.id)")
    }

    @State private var replyOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let replyThreshold: CGFloat = 64

    /// Settings → Gestures → "Swipe to reply in chats". Horizontal drags only, so the
    /// thread still scrolls vertically; under Reduce Motion the bubble doesn't follow
    /// the finger but the gesture still quotes the message.
    private var swipeToReply: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard ModulaPreferences.swipeToReply,
                      value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
                if !reduceMotion { replyOffset = min(value.translation.width, Self.replyThreshold * 1.3) }
            }
            .onEnded { value in
                let triggered = ModulaPreferences.swipeToReply
                    && value.translation.width >= Self.replyThreshold
                    && abs(value.translation.width) > abs(value.translation.height) * 1.6
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { replyOffset = 0 }
                if triggered { onAction(.init(id: "reply", title: "Reply")) }
            }
    }

    /// Large outer corners, tighter corners where bubbles of a run meet.
    private var bubbleShape: UnevenRoundedRectangle {
        let large = 18.0, tight = 6.0
        let topJoin = !position.startsGroup
        let bottomJoin = !position.endsGroup
        if message.isOwn {
            return UnevenRoundedRectangle(
                topLeadingRadius: large,
                bottomLeadingRadius: large,
                bottomTrailingRadius: bottomJoin ? tight : large,
                topTrailingRadius: topJoin ? tight : large,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: topJoin ? tight : large,
            bottomLeadingRadius: bottomJoin ? tight : large,
            bottomTrailingRadius: large,
            topTrailingRadius: large,
            style: .continuous
        )
    }

    private var bubbleFill: Color {
        if message.isOwn {
            return app.appearance.liveAccent
        }
        let oled = scheme == .dark && app.appearance.darkStyle == .oled
        return oled ? Color.white.opacity(0.08) : Color.primary.opacity(0.08)
    }

    private var actions: [ModulaContextAction] {
        message.isOwn
            ? MessageContextActions.own(capabilities: app.messaging.capabilities, delivery: message.delivery)
            : MessageContextActions.other(capabilities: app.messaging.capabilities)
    }

    private var accessibilityLabel: String {
        let who = message.isOwn ? "You" : message.sender.displayName
        let time = ConversationRow.relative(message.sentAt)
        let parsed = ModulaLocalSticker.extract(message.body.text)
        var parts = [who, time]
        if !parsed.text.isEmpty { parts.append(parsed.text) }
        if !parsed.stickers.isEmpty { parts.append(parsed.stickers.map(\.label).joined(separator: ", ")) }
        if message.delivery == .failed { parts.append("Failed to send") }
        if message.delivery == .sending { parts.append("Sending") }
        if app.messaging.capabilities.readReceipts, ModulaPreferences.chatShowReadReceipts, message.delivery == .read { parts.append("Read") }
        return parts.joined(separator: ", ")
    }
}

struct MessageComposer: View {
    @Binding var text: String
    var canSend: Bool
    var showsAttachments: Bool
    var largeText: Bool
    var reply: ModulaComposerReply? = nil
    var onCancelReply: (() -> Void)? = nil
    var focus: Binding<Bool>? = nil
    var onSend: () -> Void
    @AppStorage("settings.chats.enterToSend") private var enterToSend = false
    @AppStorage("settings.chats.spellCheck") private var spellCheck = true
    @Environment(AppEnvironment.self) private var app
    @State private var showStickers = false

    var body: some View {
        let typing = showStickers || focus?.wrappedValue == true
        VStack(spacing: 0) {
            if showStickers {
                ModulaStickerPicker(client: app.client, initialSection: "sprout") { sticker in
                    insert(sticker)
                    showStickers = false
                }
                .frame(height: 300)
                .accessibilityIdentifier("messages.stickers")
            }
            HStack(alignment: .bottom, spacing: 0) {
                // The seal sits with the docked composer. While the keyboard is down it folds into the pill.
                if typing {
                    Button {
                        showStickers.toggle()
                        if showStickers { focus?.wrappedValue = false }
                    } label: {
                        Image(systemName: showStickers ? "keyboard" : "seal.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showStickers ? "Hide stickers" : "Stickers")
                    .accessibilityIdentifier("messages.stickers.button")
                }
                ModulaComposer(
                    text: $text,
                    prompt: "Add a message...",
                    enabled: canSend,
                    showsAttachmentButton: showsAttachments,
                    externalFocus: focus,
                    returnSends: enterToSend,
                    spellCheck: spellCheck,
                    reply: reply,
                    onCancelReply: onCancelReply,
                    collapsesWhenUnfocused: !showStickers,
                    onSend: onSend
                )
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
        .accessibilityIdentifier("messages.composer")
    }

    /// Server packs stay emoji. Sprout and other local packs travel as text tokens.
    private func insert(_ sticker: ModulaSticker) {
        let piece = ModulaLocalSticker.from(sticker)?.token ?? sticker.emoji
        if text.isEmpty {
            text = piece
        } else {
            text += (text.hasSuffix(" ") ? "" : " ") + piece
        }
    }
}

struct MessageRequestsView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            MessagesScopePicker(selection: .requests)
            content
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Requests")
        .task {
            #if DEBUG
            if MessagingDebugFixture.isEnabled {
                if app.messaging.requests.isEmpty { app.messaging.installDebugRequests(MessagingDebugFixture.requests()) }
                return
            }
            #endif
            await app.messaging.loadRequestsIfNeeded()
        }
        .refreshable { await app.messaging.refreshRequests() }
        .accessibilityIdentifier("messages.requests")
    }

    @ViewBuilder
    private var content: some View {
        switch app.messaging.requestState {
        case .loading where app.messaging.requests.isEmpty:
            MessagesSkeletonList(label: "Loading requests")
        case .failed(let message) where app.messaging.requests.isEmpty:
            MessagesFriendlyEmpty(scope: .requests, retryMessage: message) {
                await app.messaging.refreshRequests()
            }
        case _ where app.messaging.requests.isEmpty:
            MessagesFriendlyEmpty(scope: .requests)
        default:
            List(app.messaging.requests) { request in
                MessageRequestRow(
                    request: request,
                    busy: app.messaging.requestBusyIDs.contains(request.id),
                    canAct: app.messaging.capabilities.acceptRequest
                ) {
                    Task {
                        if let conversation = await app.messaging.acceptRequest(request) {
                            app.navigation.replaceTop(with: .messages(.conversation(conversation.id)))
                        }
                    }
                } onDecline: {
                    Task { await app.messaging.declineRequest(request) }
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    if app.messaging.capabilities.declineRequest {
                        Button(role: .destructive) {
                            Task { await app.messaging.declineRequest(request) }
                        } label: { Label("Decline", systemImage: "xmark") }
                    }
                }
                .swipeActions(edge: .leading) {
                    if app.messaging.capabilities.acceptRequest {
                        Button {
                            Task {
                                if let conversation = await app.messaging.acceptRequest(request) {
                                    app.navigation.replaceTop(with: .messages(.conversation(conversation.id)))
                                }
                            }
                        } label: { Label("Accept", systemImage: "checkmark") }
                        .tint(.green)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .modulaSoftScrollEdge()
        }
    }
}

struct MessageRequestRow: View {
    let request: MessageRequest
    var busy: Bool
    var canAct: Bool
    var onAccept: () -> Void
    var onDecline: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let accent = app.appearance.liveAccent
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ConversationAvatar(participant: request.sender, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.sender.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text("@\(request.sender.handle)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if !request.preview.isEmpty {
                        Text(request.preview)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.88))
                            .lineLimit(3)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
                            .padding(.top, 4)
                    }
                }
            }
            if canAct {
                HStack(spacing: 10) {
                    Button(action: onAccept) {
                        HStack(spacing: 6) {
                            if busy { ProgressView().controlSize(.mini).tint(.white) }
                            Text("Accept").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Capsule().fill(accent))
                        .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(0.4))
                    }
                    .accessibilityIdentifier("messages.request.accept")
                    Button(action: onDecline) {
                        Text("Decline").font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .accessibilityIdentifier("messages.request.decline")
                }
                .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: .lightImpact))
                .disabled(busy)
                .padding(.leading, 60)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(request.sender.displayName). \(request.preview)")
    }
}

/// Pick someone to talk to. Every row starts or opens a chat with that person (never a Follow button):
/// recent 1:1 chats first, then real suggested people (fixtures and machine-made accounts filtered).
struct NewConversationView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var people: [DiscoverPerson] = []

    private var recentDirect: [Conversation] {
        Array(app.messaging.conversations.filter { $0.kind == .direct && !$0.participants.isEmpty }.prefix(5))
    }

    /// Suggestions without people you already chat with (or yourself).
    private var suggestions: [DiscoverPerson] {
        let own = app.profile.ownProfile?.handle.lowercased()
        return people.filter { p in
            p.handle.lowercased() != own && app.messaging.directConversation(with: p.handle) == nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModulaGlassGroup(spacing: 10) {
                    VStack(spacing: 10) {
                        Button {
                            app.navigation.push(.search(.section(.people, nil)))
                            HapticEngine.shared.play(.navigation)
                        } label: {
                            Label("Search people", systemImage: "magnifyingglass")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).frame(height: 48)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityIdentifier("messages.new.search")
                        if app.inMail.capabilities.send {
                            Button {
                                app.navigation.push(.messages(.inMail(.compose)))
                                HapticEngine.shared.play(.navigation)
                            } label: {
                                Label("Write an In-Mail", systemImage: "envelope.badge.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).frame(height: 48)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Capsule(), interactive: true)
                        }
                    }
                }
                if !recentDirect.isEmpty {
                    section("Recent") {
                        ForEach(recentDirect) { c in
                            let p = c.participants[0]
                            MessagePersonRow(name: c.title, handle: p.handle, avatarURL: p.avatarURL ?? avatar(for: p.handle),
                                             detail: c.lastMessage?.body) {
                                app.navigation.push(.messages(.conversation(c.id)))
                            }
                            .accessibilityIdentifier("messages.new.recent.\(c.id)")
                        }
                    }
                }
                if !suggestions.isEmpty {
                    section("Suggested") {
                        ForEach(suggestions.prefix(8)) { person in
                            MessagePersonRow(name: person.displayName, handle: person.handle,
                                             avatarURL: person.avatarURL ?? avatar(for: person.handle),
                                             detail: person.followsViewer ? "Follows you" : nil) {
                                app.navigation.push(.messages(.direct(person.handle)))
                            }
                            .accessibilityIdentifier("messages.new.person.\(person.handle)")
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("New Message")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.messaging.loadInboxIfNeeded()
            guard ModulaPreferences.showsSuggestedPeople else { return }
            people = ((try? await GreenfieldDiscoverRepository(client: app.client).people(cursor: nil).items) ?? [])
                .filter { !ActivitySuggestedPeople.isFixture($0) }
        }
        .accessibilityIdentifier("messages.new")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).padding(.top, 10).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// Photo from a profile already loaded this session when the list payload has none.
    private func avatar(for handle: String) -> URL? {
        let key = handle.lowercased()
        return app.profile.sessions.values.lazy.compactMap(\.profile).first { $0.handle.lowercased() == key }?.avatarURL
    }
}

/// One person in the New Message picker: tap anywhere to chat.
struct MessagePersonRow: View {
    let name: String
    let handle: String
    var avatarURL: URL?
    var detail: String?
    var action: () -> Void

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Button {
            HapticEngine.shared.play(.navigation)
            action()
        } label: {
            HStack(spacing: 12) {
                ModulaAvatar(initials: initials, url: avatarURL, size: 44, name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(detail.map { "@\(handle) · \($0)" } ?? "@\(handle)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "bubble.left.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .modulaGlass(in: Circle(), interactive: false)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Message \(name), @\(handle)")
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview("Inbox unread") {
    ConversationRow(conversation: MessagingFixtures.unreadConversation)
}
#Preview("Bubble long") {
    MessageBubble(message: MessagingFixtures.thread()[3]) { _ in }
}
#endif


// MARK: - Messages v2 chrome

/// Liquid Glass segmented control for Chats / In-Mail / Requests.
/// The selected pill morphs between segments via `glassEffectID`.
@available(iOS 26.0, *)
struct MessagesGlassScopeControl: View {
    let selection: MessagesScope
    var onSelect: (MessagesScope) -> Void
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: MessagesScope?

    private static let items: [(MessagesScope, String, String)] = [
        (.inbox, "Chats", "bubble.left.and.bubble.right.fill"),
        (.inMail, "In-Mail", "envelope.fill"),
        (.requests, "Requests", "person.crop.circle.badge.clock")
    ]

    var body: some View {
        let current = displayed ?? selection
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Self.items, id: \.0) { item in
                    let isOn = item.0 == current
                    Button {
                        guard item.0 != current else { return }
                        HapticEngine.shared.play(.selection)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
                            displayed = item.0
                        }
                        onSelect(item.0)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.2)
                                .imageScale(.small)
                                .symbolEffect(.bounce, value: isOn && !reduceMotion)
                            Text(item.1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.subheadline.weight(isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Capsule())
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(Color.clear)
                                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.35)).interactive(), in: Capsule())
                                    .glassEffectID("messages.scope.selection", in: glass)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.1)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("messages.scope.\(item.1)")
                }
            }
            .padding(4)
            .glassEffect(.regular, in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message sections")
        .onChange(of: selection) { _, new in displayed = new }
    }
}

/// Shimmering skeleton rows used while a list loads.
struct MessagesSkeletonList: View {
    var label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    Circle().fill(Color.primary.opacity(0.08)).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Capsule().fill(Color.primary.opacity(0.09)).frame(width: CGFloat(110 + (index * 23) % 60), height: 12)
                            Spacer()
                            Capsule().fill(Color.primary.opacity(0.06)).frame(width: 28, height: 10)
                        }
                        Capsule().fill(Color.primary.opacity(0.06)).frame(height: 10)
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
            }
            Spacer()
        }
        .padding(.top, 14)
        .opacity(pulse ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Friendly per-tab empty state. When a load failed it adds an inline retry
/// banner and retries on its own with backoff — never a full-screen error.
struct MessagesFriendlyEmpty: View {
    let scope: MessagesScope
    var retryMessage: String? = nil
    var retry: (() async -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app
    @State private var float = false

    private var copy: (title: String, message: String, symbol: String) {
        switch scope {
        case .inbox: ("No chats yet", "Say hi from someone’s profile — your conversations will land here.", "bubble.left.and.bubble.right.fill")
        case .inMail: ("Your In-Mail is clear", "Longer, thoughtful messages live here. Tap the pencil to write one.", "envelope.open.fill")
        case .requests: ("No requests right now", "When someone new wants to chat, you’ll decide here first.", "person.crop.circle.badge.checkmark")
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if let retryMessage, let retry {
                MessagesRetryBanner(message: retryMessage, autoRetry: true, action: retry)
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 8)
            }
            Spacer(minLength: 24)
            Image(systemName: copy.symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 92, height: 92)
                .messagesGlass(Circle(), tint: Color.accentColor.opacity(0.18))
                .offset(y: float ? -4 : 4)
                .accessibilityHidden(true)
            Text(copy.title).font(.title3.weight(.semibold))
            Text(copy.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if scope == .inbox {
                Button {
                    app.navigation.push(.messages(.new))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Label("Start a chat", systemImage: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 22).frame(height: 44)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), tint: Color.accentColor)
                .padding(.top, 4)
                .accessibilityIdentifier("messages.empty.start")
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
        }
        .accessibilityIdentifier("messages.empty.\(String(describing: scope))")
    }
}

/// Compact inline glass banner with a retry button and optional
/// automatic retries (2s, 4s, 8s, 16s).
struct MessagesRetryBanner: View {
    let message: String
    var autoRetry = false
    let action: () async -> Void
    @State private var busy = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 6)
            Button {
                Task { await run() }
            } label: {
                Group {
                    if busy { ProgressView().controlSize(.small) } else { Text("Retry").font(.footnote.weight(.semibold)) }
                }
                .padding(.horizontal, GeneratedDesignContract.Spacing.sm)
                .frame(minHeight: GeneratedDesignContract.Layout.minimumTouchTarget)
                .contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
            .modulaAccentCTA()
            .disabled(busy)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .messagesGlass(Capsule())
        .task {
            guard autoRetry else { return }
            for delay in [2.0, 4.0, 8.0, 16.0] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                await run()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("messages.retryBanner")
    }

    private func run() async {
        guard !busy else { return }
        busy = true
        await action()
        busy = false
    }
}

extension View {
    /// Real Liquid Glass on iOS 26, material fallback on older systems.
    @ViewBuilder
    func messagesGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}


// MARK: - Thread timeline

enum MessageTimeline {
    /// A centred time label before a message that starts a new day or follows an hour-long gap.
    static func separator(at index: Int, in items: [Message], calendar: Calendar = .current, now: Date = Date()) -> String? {
        guard items.indices.contains(index) else { return nil }
        let current = items[index].sentAt
        if index > 0 {
            let previous = items[index - 1].sentAt
            if calendar.isDate(previous, inSameDayAs: current), current.timeIntervalSince(previous) < 60 * 60 { return nil }
        }
        return label(for: current, calendar: calendar, now: now)
    }

    static func label(for date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        timeStyle.timeZone = calendar.timeZone
        let time = date.formatted(timeStyle)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           (0..<7).contains(days) {
            var weekday = Date.FormatStyle().weekday(.wide)
            weekday.timeZone = calendar.timeZone
            return "\(date.formatted(weekday)) \(time)"
        }
        var day = Date.FormatStyle().day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { day = day.year() }
        day.timeZone = calendar.timeZone
        return "\(date.formatted(day)), \(time)"
    }

    /// Honest delivery wording from the server state; nothing for unknown.
    static func status(for delivery: MessageDeliveryState) -> String? {
        switch delivery {
        case .sending: "Sending…"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read, .failed, .unknown: nil
        }
    }
}

struct MessageTimeSeparator: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .modulaGlass(in: Capsule(), interactive: false)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Empty chat: who you're talking to and a few one-tap openers (they only fill the composer).
struct MessageStarterView: View {
    let conversation: Conversation?
    var onPick: (String) -> Void
    @Environment(AppEnvironment.self) private var app

    private let openers = ["👋", "Hey!", "How’s it going?"]

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 24)
            let person = conversation?.participants.first
            ModulaAvatar(initials: person?.initials ?? "?", url: person?.avatarURL, size: 84, name: person?.displayName)
            VStack(spacing: 4) {
                Text(conversation?.title ?? "New conversation")
                    .font(.title3.weight(.bold))
                if let handle = conversation?.handleLabel {
                    Text(handle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Say hi — your first message starts the chat.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(openers, id: \.self) { opener in
                        Button { onPick(opener) } label: {
                            Text(opener)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true)
                    }
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ModulaLayout.contentInset)
        .accessibilityIdentifier("messages.starter")
    }
}

// MARK: - Direct (profile → chat)

/// Opens the 1:1 chat with `person`. Looks the thread up in the inbox (loading it if needed) and swaps
/// itself for the live conversation. With no thread yet, the server has no "start a conversation"
/// endpoint, so this shows a starter addressed to them (In-Mail when it can send) instead of the inbox.
struct DirectMessageView: View {
    let person: String
    @Environment(AppEnvironment.self) private var app
    @State private var resolving = true

    private var handle: String { person.trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
    private var profile: ModulaProfile? {
        let key = handle.lowercased()
        return app.profile.sessions.values.lazy.compactMap(\.profile)
            .first { $0.handle.lowercased() == key || $0.id.lowercased() == key }
    }
    private var name: String { profile?.displayName ?? "@\(handle)" }
    private var initials: String {
        let parts = name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).prefix(2)).uppercased()
    }

    var body: some View {
        Group {
            if resolving {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening your chat with \(name)…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("messages.direct.resolving")
            } else {
                starter
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: person) { await resolve() }
        .accessibilityIdentifier("messages.direct")
        .accessibilityValue(RouteSerializer.serialize(.messages(.direct(person))))
    }

    private func resolve() async {
        if let found = app.messaging.directConversation(with: person) { open(found); return }
        await app.messaging.loadInboxIfNeeded()
        if let found = app.messaging.directConversation(with: person) { open(found); return }
        // Older threads may sit beyond the first page; one refresh before giving up.
        await app.messaging.refreshInbox()
        if let found = app.messaging.directConversation(with: person) { open(found); return }
        withAnimation(.smooth(duration: 0.2)) { resolving = false }
    }

    private func open(_ conversation: Conversation) {
        app.navigation.replaceTop(with: .messages(.conversation(conversation.id)))
    }

    private var starter: some View {
        ScrollView {
            VStack(spacing: 16) {
                ModulaAvatar(initials: initials, url: profile?.avatarURL, size: 88, name: name)
                    .padding(.top, 36)
                VStack(spacing: 4) {
                    Text(name).font(.title3.weight(.bold))
                    if profile != nil { Text("@\(handle)").font(.subheadline).foregroundStyle(.secondary) }
                }
                Text("No chat with \(profile?.displayName ?? "them") yet. When either of you starts one, it opens right here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                ModulaGlassGroup(spacing: 10) {
                    VStack(spacing: 10) {
                        if app.inMail.capabilities.send {
                            Button {
                                app.inMail.draft.toHandle = handle
                                app.navigation.replaceTop(with: .messages(.inMail(.compose)))
                                HapticEngine.shared.play(.navigation)
                            } label: {
                                Label("Write an In-Mail to \(profile?.displayName ?? "@\(handle)")", systemImage: "envelope.badge.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .modulaAccentCTA()
                            .accessibilityIdentifier("messages.direct.inmail")
                        }
                        Button {
                            app.navigation.replaceTop(with: .profile(handle, .overview))
                            HapticEngine.shared.play(.navigation)
                        } label: {
                            Label("View profile", systemImage: "person.crop.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityIdentifier("messages.direct.profile")
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("messages.direct.starter")
    }
}
