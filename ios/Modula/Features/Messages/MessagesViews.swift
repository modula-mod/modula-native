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
            .messagesTopBar {
                VStack(spacing: 8) {
                    MessagesScopePicker(selection: .inbox)
                    MessagesGlassSearchField(text: Bindable(app.messaging).conversationQuery, prompt: "Search chats")
                        .padding(.horizontal, ModulaLayout.contentInset)
                    filterRow
                }
                .padding(.bottom, 6)
            }
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
                                        .foregroundStyle(on ? Color.white.opacity(0.9) : app.appearance.accent.color)
                                }
                            }
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background { if on { Capsule().fill(app.appearance.accent.color) } }
                            .modulaGlass(in: Capsule(), interactive: true, tint: on ? app.appearance.accent.color.opacity(0.35) : nil)
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
        switch app.messaging.conversationState {
        case .loading where items.isEmpty:
            MessagesSkeletonList(label: "Loading conversations")
        case .failed(let message) where items.isEmpty:
            MessagesFriendlyEmpty(scope: .inbox, retryMessage: message) {
                await app.messaging.refreshInbox()
            }
        case _ where items.isEmpty && (searching || filter != .all):
            ContentUnavailableView {
                Label(searching ? "No matching chats" : (filter == .unread ? "You're all caught up" : "No group chats"),
                      systemImage: searching ? "magnifyingglass" : (filter == .unread ? "checkmark.bubble" : "person.3"))
            } description: {
                Text(searching ? "Search looks through the chats loaded on this device." : "Nothing here right now.")
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
        case _ where items.isEmpty:
            MessagesFriendlyEmpty(scope: .inbox)
        default:
            List {
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
                            .tint(app.appearance.accent.color)
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
        let accent = app.appearance.accent.color
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
                Circle().fill(app.appearance.accent.color)
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
    @State private var replyTo: Message?
    @State private var awayFromBottom = false

    var body: some View {
        thread
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .overlay(alignment: .bottomTrailing) { jumpToLatest }
            .navigationBarTitleDisplayMode(.inline)
            .modulaSoftScrollEdge()
            .navigationTitle(conversation?.title ?? "Chat")
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                if let person = conversation?.participants.first {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("View Profile", systemImage: "person.crop.circle") { app.navigation.push(.profile(person.id, .overview)) }
                            Button("Copy Name", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = conversation?.title
                                HapticEngine.shared.play(.confirmation)
                            }
                            Divider()
                            Button("Chat Settings", systemImage: "gearshape") { app.navigation.open(.settings(.chats(.root))) }
                        } label: {
                            Label("Chat options", systemImage: "ellipsis")
                        }
                        .accessibilityIdentifier("messages.conversation.options")
                    }
                }
            }
            .task {
                #if DEBUG
                if MessagingDebugFixture.isEnabled {
                    if app.messaging.conversations.isEmpty { app.messaging.installDebugInbox(MessagingDebugFixture.inbox()) }
                    if app.messaging.messages(for: conversationID).isEmpty {
                        app.messaging.installDebugThread(conversationID, messages: MessagingDebugFixture.thread(conversationID))
                    }
                    return
                }
                #endif
                await app.messaging.loadThreadIfNeeded(conversationID)
            }
            .refreshable { await app.messaging.refreshThread(conversationID) }
            .accessibilityIdentifier("messages.conversation.\(conversationID)")
            .accessibilityValue(RouteSerializer.serialize(.messages(.conversation(conversationID))))
    }

    private var conversation: Conversation? { app.messaging.conversation(id: conversationID) }
    private var isGroup: Bool { (conversation?.participants.count ?? 0) > 1 || conversation?.kind == .group }

    /// Glass identity capsule in the nav bar; taps through to the profile.
    private var header: some View {
        Button {
            if let person = conversation?.participants.first, !isGroup {
                app.navigation.push(.profile(person.id, .overview))
                HapticEngine.shared.play(.navigation)
            }
        } label: {
            HStack(spacing: 8) {
                ConversationAvatar(participants: conversation?.participants ?? [], size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(conversation?.title ?? "Chat")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
            .modulaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([conversation?.title, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(isGroup ? "" : "Opens profile")
        .accessibilityIdentifier("messages.conversation.header")
    }

    private var subtitle: String? {
        if isGroup, let n = conversation?.participants.count { return "\(n + 1) members" }
        return conversation?.handleLabel
    }

    @ViewBuilder
    private var thread: some View {
        let items = app.messaging.messages(for: conversationID)
        switch app.messaging.threadState[conversationID] ?? .idle {
        case .loading where items.isEmpty:
            ProgressView("Loading messages")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where items.isEmpty:
            VStack(spacing: 12) {
                MessagesRetryBanner(message: message, autoRetry: true) {
                    await app.messaging.refreshThread(conversationID)
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                Spacer()
            }
            .padding(.top, 12)
        case _ where items.isEmpty:
            emptyThread
        default:
            let lastOwnID = items.last(where: \.isOwn)?.id
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
                            let position = MessageGroupPosition.resolve(index: index, in: items)
                            if let stamp = MessageTimeline.stamp(index: index, in: items) {
                                MessageTimeStamp(text: stamp)
                                    .padding(.top, index == 0 ? 4 : 16)
                                    .padding(.bottom, 6)
                            }
                            MessageBubble(
                                message: message, position: position,
                                showsSender: isGroup && position.startsGroup,
                                showsStatus: message.id == lastOwnID || message.delivery == .failed
                            ) { action in
                                handle(action, message: message)
                            }
                            .padding(.top, index == 0 ? 0 : (position.startsGroup ? 10 : 2))
                            .id(message.id)
                            .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity))
                        }
                        Color.clear.frame(height: 1).id("messages.bottom")
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .modulaSoftScrollEdge()
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentSize.height - (geo.contentOffset.y + geo.containerSize.height) > 320
                } action: { _, away in
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { awayFromBottom = away }
                }
                .onChange(of: items.count) { _, _ in scrollToLatest(proxy) }
                .onChange(of: items.last?.id) { _, _ in scrollToLatest(proxy) }
                .onChange(of: jumpRequests) { _, _ in scrollToLatest(proxy) }
            }
        }
    }

    @State private var jumpRequests = 0

    @ViewBuilder
    private var jumpToLatest: some View {
        if awayFromBottom {
            Button {
                jumpRequests += 1
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
            .padding(.trailing, ModulaLayout.contentInset)
            .padding(.bottom, 84)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Jump to latest message")
            .accessibilityIdentifier("messages.jump-latest")
        }
    }

    private var emptyThread: some View {
        let person = conversation?.participants.first
        return VStack(spacing: 12) {
            Spacer(minLength: 40)
            ConversationAvatar(participants: conversation?.participants ?? [], size: 84)
            Text(conversation?.title ?? "New chat").font(.title3.weight(.semibold))
            if let handle = conversation?.handleLabel {
                Text(handle).font(.subheadline).foregroundStyle(.secondary)
            }
            if app.messaging.capabilities.send {
                Button {
                    let first = person?.displayName.split(separator: " ").first.map(String.init) ?? ""
                    app.messaging.drafts[conversationID] = first.isEmpty ? "Hi 👋" : "Hi \(first) 👋"
                    HapticEngine.shared.play(.selection)
                } label: {
                    Text("👋  Say hi").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).frame(height: 40)
                        .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.accent.color.opacity(0.2))
                }
                .buttonStyle(ModulaPressStyle(scale: 0.94))
                .padding(.top, 6)
            } else {
                Text("This conversation isn’t available yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("messages.thread.empty")
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        withAnimation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
            proxy.scrollTo("messages.bottom", anchor: .bottom)
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
            reply: replyTo.map { ModulaComposerReply(title: "Replying to \($0.isOwn ? "yourself" : $0.sender.displayName)", excerpt: $0.body.text) },
            onCancelReply: { withAnimation(reduceMotion ? nil : .snappy) { replyTo = nil } }
        ) {
            // The API has no reply-to field yet, so a reply is sent as a quoted line.
            if let replyTo {
                let quote = replyTo.body.text.split(separator: "\n").first.map { "> " + $0.prefix(120) } ?? ""
                let draft = app.messaging.drafts[conversationID] ?? ""
                app.messaging.drafts[conversationID] = quote + "\n" + draft
                self.replyTo = nil
            }
            IslandSendEffect.shared.fire("Message sent", accent: app.appearance.accent.color)
            Task {
                await app.messaging.send(conversation: conversationID, viewer: viewer)
            }
        }
        .background(alignment: .bottom) {
            // Soft canvas wash so bubbles fade under the glass composer instead of colliding.
            LinearGradient(colors: [.clear, Color(uiColor: .systemBackground).opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
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
            app.navigation.flash("Copied", symbol: "doc.on.doc")
        case "retry":
            Task { await app.messaging.retry(message: message, viewer: viewer) }
        case "reply":
            withAnimation(reduceMotion ? nil : .snappy) { replyTo = message }
            HapticEngine.shared.play(.selection)
        default:
            break
        }
    }
}

/// Day and time separators: a day label when the calendar day changes, and a
/// time label after an hour-long gap inside the same day.
enum MessageTimeline {
    @MainActor private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    @MainActor private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f
    }()

    @MainActor static func stamp(index: Int, in items: [Message], calendar: Calendar = .current) -> String? {
        let current = items[index].sentAt
        let time = ModulaPreferences.relativeTimestamps ? timeFormatter.string(from: current) : ModulaTimeFormat.absolute(current)
        if index == 0 || !calendar.isDate(items[index - 1].sentAt, inSameDayAs: current) {
            let day: String
            if calendar.isDateInToday(current) { day = String(localized: "Today") }
            else if calendar.isDateInYesterday(current) { day = String(localized: "Yesterday") }
            else { day = dayFormatter.string(from: current) }
            return "\(day) \(time)"
        }
        if current.timeIntervalSince(items[index - 1].sentAt) > 3600 { return time }
        return nil
    }
}

struct MessageTimeStamp: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
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
    var showsSender = false
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
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
                if showsSender, !message.isOwn {
                    Text(message.sender.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
                Text(message.body.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(bubbleFill, in: bubbleShape)
                    .foregroundStyle(message.isOwn ? Color.white : Color.primary)
                    .opacity(message.delivery == .sending ? 0.7 : 1)
                    .overlay(alignment: .trailing) {
                        if message.delivery == .failed {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.red)
                                .offset(x: 26)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.trailing, message.delivery == .failed ? 26 : 0)
                if let attachment = MessageInlineContent.detect(in: message.body.text) {
                    MessageInlineContentView(content: attachment)
                }
                if showsStatus { statusLine }
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

    @ViewBuilder
    private var statusLine: some View {
        if message.delivery == .failed {
            Button {
                onAction(.init(id: "retry", title: "Retry"))
            } label: {
                Label("Not delivered · Tap to retry", systemImage: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(minHeight: ModulaLayout.minimumTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("messages.retry")
        } else if message.isOwn {
            let showRead = app.messaging.capabilities.readReceipts && ModulaPreferences.chatShowReadReceipts
            let label: (String, String)? = switch message.delivery {
            case .sending: ("Sending…", "clock")
            case .read where showRead: ("Read \(ConversationRow.relative(message.sentAt))", "checkmark.circle.fill")
            case .read, .delivered: ("Delivered", "checkmark.circle")
            case .sent, .unknown: ("Sent", "checkmark")
            case .failed: nil
            }
            if let label {
                Label(label.0, systemImage: label.1)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(message.delivery == .read && showRead ? app.appearance.accent.color : Color.secondary)
                    .contentTransition(.opacity)
                    .padding(.trailing, 4)
                    .accessibilityIdentifier("messages.status")
            }
        }
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

    private var bubbleFill: AnyShapeStyle {
        if message.isOwn {
            let accent = app.appearance.accent.color
            return AnyShapeStyle(LinearGradient(colors: [accent.opacity(0.92), accent], startPoint: .top, endPoint: .bottom))
        }
        let oled = scheme == .dark && app.appearance.darkStyle == .oled
        return AnyShapeStyle(oled ? Color.white.opacity(0.1) : Color.primary.opacity(0.07))
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
    var reply: ModulaComposerReply? = nil
    var onCancelReply: (() -> Void)? = nil
    var onSend: () -> Void
    @AppStorage("settings.chats.enterToSend") private var enterToSend = false
    @AppStorage("settings.chats.spellCheck") private var spellCheck = true

    var body: some View {
        ModulaComposer(
            text: $text,
            prompt: "Message",
            enabled: canSend,
            showsAttachmentButton: showsAttachments,
            returnSends: enterToSend,
            spellCheck: spellCheck,
            reply: reply,
            onCancelReply: onCancelReply,
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
