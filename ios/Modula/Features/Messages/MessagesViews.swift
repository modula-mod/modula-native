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
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        let items = app.messaging.visibleConversations
        switch app.messaging.conversationState {
        case .loading where items.isEmpty:
            MessagesSkeletonList(label: "Loading conversations")
        case .failed(let message) where items.isEmpty:
            MessagesFriendlyEmpty(scope: .inbox, retryMessage: message) {
                await app.messaging.refreshInbox()
            }
        case _ where items.isEmpty:
            MessagesFriendlyEmpty(scope: .inbox)
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
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            app.navigation.push(.messages(.conversation(conversation.id)))
                        } label: { Label("Open", systemImage: "arrow.up.right.bubble") }
                        .tint(.accentColor)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            UIPasteboard.general.string = conversation.title
                            HapticEngine.shared.play(.confirmation)
                        } label: { Label("Copy name", systemImage: "doc.on.doc") }
                        .tint(.gray)
                    }
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
            MessagesRetryBanner(message: "Showing saved messages. \(message)") {
                app.messaging.clearActionError()
                await app.messaging.refreshInbox()
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 12)
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
    @Environment(AppEnvironment.self) private var app
    @Environment(\.routeTransitionNamespace) private var routeTransitions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(participant: conversation.participants.first, unread: conversation.isUnread)
                .modulaZoomSource(id: "conversation.\(conversation.id)", namespace: routeTransitions)
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
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
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
            largeText: dynamicTypeSize.isAccessibilitySize
        ) {
            IslandSendEffect.shared.fire("Message sent", accent: app.appearance.accent.color)
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
        case "reply":
            // Swipe-to-reply (Settings → Gestures): quote the message into the composer.
            let quoted = message.body.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(3)
                .map { "> " + $0 }
                .joined(separator: "\n")
            let existing = app.messaging.drafts[conversationID] ?? ""
            app.messaging.drafts[conversationID] = quoted + "\n" + existing
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
                Text(message.body.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleFill, in: bubbleShape)
                    .foregroundStyle(message.isOwn ? Color.white : Color.primary)
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
        if app.messaging.capabilities.readReceipts, ModulaPreferences.chatShowReadReceipts, message.delivery == .read { parts.append("Read") }
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

/// Pick someone to talk to: real suggested people (fixtures filtered), each opening their
/// profile where Message / In-Mail lives. In-Mail compose is offered when it can send.
struct NewConversationView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    app.navigation.push(.search(.section(.people, nil)))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Label("Search people", systemImage: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).frame(height: 48)
                        .modulaGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
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
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                ActivitySuggestedPeople()
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("New Message")
        .navigationBarTitleDisplayMode(.inline)
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
                if busy { ProgressView().controlSize(.small) } else { Text("Retry").font(.footnote.weight(.semibold)) }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
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
