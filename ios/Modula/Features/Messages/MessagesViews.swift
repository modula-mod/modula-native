import SwiftUI
import UIKit

struct MessagesRootView: View {
    let route: MessagesRoute
    @Environment(AppEnvironment.self) private var app

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
            case .conversation(let id):
                ConversationView(conversationID: id)
            }
        }
        .modulaCanvas()
        .navigationBarBackButtonHidden(false)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct ConversationListView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            MessagesScopePicker(selection: .inbox)
            searchField
            content
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .task { await app.messaging.loadInboxIfNeeded() }
        .refreshable { await app.messaging.refreshInbox() }
        .overlay(alignment: .bottom) { errorBanner }
        .accessibilityIdentifier("messages.inbox")
        .accessibilityValue(RouteSerializer.serialize(.messages(.inbox)))
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModulaSearchField(text: Bindable(app.messaging).conversationQuery, prompt: "Search conversations")
            if !app.messaging.conversationQuery.isEmpty {
                Text("Searches loaded conversations only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        let items = app.messaging.visibleConversations
        switch app.messaging.conversationState {
        case .loading where items.isEmpty:
            conversationSkeleton
        case .failed(let message) where items.isEmpty:
            ModulaErrorState(message: message) {
                Task { await app.messaging.refreshInbox() }
            }
        case _ where !app.messaging.capabilities.listConversations && items.isEmpty:
            ModulaEmptyState(
                title: "Messages",
                message: "Conversations will appear here when messaging is available.",
                symbol: "message"
            )
        case _ where items.isEmpty:
            ModulaEmptyState(
                title: "No conversations yet",
                message: "When someone messages you, it will show up here.",
                symbol: "message"
            )
        default:
            List {
                ForEach(items) { conversation in
                    Button {
                        app.navigation.push(.messages(.conversation(conversation.id)))
                        HapticEngine.shared.play(.navigation)
                    } label: {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: ModulaLayout.contentInset, bottom: 8, trailing: ModulaLayout.contentInset))
                    .onAppear {
                        if conversation.id == items.last?.id {
                            Task { await app.messaging.loadMoreConversations() }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .modulaSoftScrollEdge()
        }
    }

    private var conversationSkeleton: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Color.primary.opacity(0.08)).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)).frame(width: 140, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)).frame(height: 10)
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
            }
            Spacer()
        }
        .padding(.top, 16)
        .accessibilityLabel("Loading conversations")
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = app.messaging.actionError {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
                .onTapGesture { app.messaging.clearActionError() }
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
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
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
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(participant: conversation.participants.first, unread: conversation.isUnread)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title)
                        .font(.body.weight(conversation.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(Self.relative(conversation.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.lastMessage?.body ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if conversation.isUnread {
                        UnreadBadge(count: conversation.unreadCount)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("messages.row.\(conversation.id)")
    }

    private var accessibilityLabel: String {
        var parts = [conversation.title]
        if let preview = conversation.lastMessage?.body { parts.append(preview) }
        parts.append(Self.relative(conversation.updatedAt))
        if conversation.isUnread {
            parts.append("\(conversation.unreadCount) unread")
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
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ConversationAvatar: View {
    let participant: ConversationParticipant?
    var unread = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ModulaAvatar(initials: participant?.initials ?? "?", url: participant?.avatarURL, size: 48, name: participant?.displayName)
            .overlay(alignment: .bottomTrailing) {
                if unread {
                    ModulaNotificationDot(tone: .accent, size: 10)
                        .overlay(Circle().stroke(ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas, lineWidth: 2))
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            thread
            composer
        }
        .navigationBarTitleDisplayMode(.inline)
        .modulaSoftScrollEdge()
        .navigationTitle("")
        .task { await app.messaging.loadThreadIfNeeded(conversationID) }
        .refreshable { await app.messaging.refreshThread(conversationID) }
        .accessibilityIdentifier("messages.conversation.\(conversationID)")
        .accessibilityValue(RouteSerializer.serialize(.messages(.conversation(conversationID))))
    }

    private var conversation: Conversation? { app.messaging.conversation(id: conversationID) }

    private var header: some View {
        HStack(spacing: 10) {
            ConversationAvatar(participant: conversation?.participants.first)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation?.title ?? "Conversation")
                    .font(.headline)
                if let handle = conversation?.handleLabel {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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
            ModulaEmptyState(
                title: "No messages yet",
                message: app.messaging.capabilities.send ? "Write the first message." : "This conversation isn’t available yet.",
                symbol: "text.bubble"
            )
        default:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
                            let position = MessageGroupPosition.resolve(index: index, in: items)
                            MessageBubble(message: message, position: position) { action in
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
            largeText: dynamicTypeSize.isAccessibilitySize
        ) {
            Task {
                await app.messaging.send(
                    conversation: conversationID,
                    viewer: viewer
                )
            }
        }
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
                Text(message.body.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleFill, in: bubbleShape)
                    .foregroundStyle(message.isOwn ? Color.white : Color.primary)
                HStack(spacing: 8) {
                    if message.delivery == .failed {
                        Button("Retry") { onAction(.init(id: "retry", title: "Retry")) }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: ModulaLayout.minimumTouch)
                            .contentShape(Rectangle())
                    } else if app.messaging.capabilities.readReceipts, message.isOwn, message.delivery == .read {
                        Text("Read")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !message.isOwn { Spacer(minLength: 48) }
        }
        .modulaContextMenu(actions: actions, onSelect: onAction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(message.delivery == .failed ? "Not sent. Swipe up or down for Retry." : "")
        .accessibilityActions {
            if message.delivery == .failed {
                Button("Retry") { onAction(.init(id: "retry", title: "Retry")) }
            }
            Button("Copy") { onAction(.init(id: "copy", title: "Copy")) }
        }
        .accessibilityIdentifier("messages.bubble.\(message.id)")
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
            return app.appearance.accent.color
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
        var parts = [who, time, message.body.text]
        if message.delivery == .failed { parts.append("Failed to send") }
        if message.delivery == .sending { parts.append("Sending") }
        if app.messaging.capabilities.readReceipts, message.delivery == .read { parts.append("Read") }
        return parts.joined(separator: ", ")
    }
}

struct MessageComposer: View {
    @Binding var text: String
    var canSend: Bool
    var showsAttachments: Bool
    var largeText: Bool
    var onSend: () -> Void
    @AppStorage("settings.chats.enterToSend") private var enterToSend = false
    @AppStorage("settings.chats.spellCheck") private var spellCheck = true

    var body: some View {
        ModulaComposer(
            text: $text,
            prompt: "Add a message...",
            enabled: canSend,
            showsAttachmentButton: showsAttachments,
            returnSends: enterToSend,
            spellCheck: spellCheck,
            onSend: onSend
        )
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
        .accessibilityIdentifier("messages.composer")
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
        .task { await app.messaging.loadRequestsIfNeeded() }
        .refreshable { await app.messaging.refreshRequests() }
        .accessibilityIdentifier("messages.requests")
    }

    @ViewBuilder
    private var content: some View {
        switch app.messaging.requestState {
        case .loading where app.messaging.requests.isEmpty:
            ModulaLoadingState(title: "Loading requests")
        case .failed(let message) where app.messaging.requests.isEmpty:
            ModulaErrorState(message: message) {
                Task { await app.messaging.refreshRequests() }
            }
        case _ where !app.messaging.capabilities.messageRequests && app.messaging.requests.isEmpty:
            ModulaEmptyState(
                title: "No message requests",
                message: "People who aren’t connected yet will appear here when requests are available.",
                symbol: "person.crop.circle.badge.questionmark"
            )
        case _ where app.messaging.requests.isEmpty:
            ModulaEmptyState(
                title: "No message requests",
                message: "When someone wants to message you, it will show up here.",
                symbol: "person.crop.circle.badge.questionmark"
            )
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
            }
            .listStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ConversationAvatar(participant: request.sender)
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.sender.displayName)
                        .font(.body.weight(.semibold))
                    Text(request.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if canAct {
                HStack {
                    Button("Accept", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                    Button("Decline", role: .destructive, action: onDecline)
                        .disabled(busy)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(request.sender.displayName). \(request.preview)")
    }
}

struct NewConversationView: View {
    var body: some View {
        ModulaEmptyState(
            title: "New message",
            message: "Starting a conversation isn’t available yet.",
            symbol: "square.and.pencil"
        )
        .modulaSoftScrollEdge()
        .navigationTitle("New")
        .accessibilityIdentifier("messages.new")
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
