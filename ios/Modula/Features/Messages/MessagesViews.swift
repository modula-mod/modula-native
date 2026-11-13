import AVFoundation
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
    @State private var circleOpen = false
    @State private var showCompose = false

    /// "Your circle": the people from your most recent 1:1 chats (real data, no guessing).
    private var circle: [(ConversationID, ConversationParticipant)] {
        MessagingOrdering.conversationsNewestFirst(app.messaging.conversations)
            .filter { $0.kind == .direct && $0.participants.count == 1 }
            .prefix(8)
            .map { ($0.id, $0.participants[0]) }
    }

    enum InboxFilter: String, CaseIterable, Identifiable {
        case all, unread, needsReply, groups, favourites
        /// Four short choices (Hick's law). "Needs reply" stays reachable from code paths only.
        static var allCases: [InboxFilter] { [.all, .unread, .favourites, .groups] }
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .unread: "Unread"
            case .needsReply: "Needs reply"
            case .groups: "Groups"
            case .favourites: "Favourites"
            }
        }
        /// "Needs reply": the last message came from someone else (Zeigarnik effect: open loops are easy to
        /// spot and close). Uses the real `lastMessage.senderID` from `GET /v1/conversations`.
        func matches(_ c: Conversation, viewerID: String?, pinned: Set<ConversationID> = []) -> Bool {
            switch self {
            case .all: true
            case .unread: c.isUnread
            case .needsReply:
                if let sender = c.lastMessage?.senderID, let viewerID { sender != viewerID } else { false }
            case .groups: c.kind == .group || c.participants.count > 1
            case .favourites: pinned.contains(c.id)
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
                    HStack(spacing: 10) {
                        if !circle.isEmpty {
                            Button {
                                HapticEngine.shared.play(.selection)
                                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.62)) {
                                    circleOpen.toggle()
                                }
                            } label: {
                                MessagesCircleStack(people: Array(circle.prefix(3)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(circleOpen ? "Hide your circle" : "Show your circle")
                            .accessibilityIdentifier("messages.circle.toggle")
                        }
                        Button {
                            HapticEngine.shared.play(.navigation)
                            showCompose = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.bold))
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                        .modulaAccentCTA(in: Circle())
                        .accessibilityLabel("New message")
                        .accessibilityIdentifier("messages.compose")
                    }
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
                await app.messaging.loadRequestsIfNeeded()
                await app.messaging.probeCapabilities()
            }
            // No realtime route: a quiet 20 s poll keeps rows, unread counts and requests current.
            .task(id: "messages.inbox.poll") {
                #if DEBUG
                if MessagingDebugFixture.isEnabled { return }
                #endif
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled else { return }
                    await app.messaging.pollInbox()
                }
            }
            .refreshable {
                await app.messaging.refreshInbox()
                await app.messaging.refreshRequests()
            }
            .sheet(isPresented: $showCompose) {
                NavigationStack { NewConversationView(presentedAsSheet: true) }
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
            }
            .overlay(alignment: .bottom) { errorBanner }
            .accessibilityIdentifier("messages.inbox")
            .accessibilityValue(RouteSerializer.serialize(.messages(.inbox)))
    }

    /// Scope, search and filters scroll with the list (like Messages), so the large title
    /// collapses normally instead of starting half-faded under a tall pinned bar.
    private func header(matches: Int) -> some View {
        VStack(spacing: 8) {
            if circleOpen && !circle.isEmpty {
                circleRow
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            MessagesScopePicker(selection: .inbox)
            MessagesGlassSearchField(text: Bindable(app.messaging).conversationQuery, prompt: "Find a conversation")
                .padding(.horizontal, ModulaLayout.contentInset)
            searchScopeCaption(matches: matches)
            filterRow
        }
        .padding(.bottom, 6)
    }

    /// Roadmap #07: say exactly what a search covered, so a partial local search is never
    /// mistaken for a full account-history search.
    @ViewBuilder
    private func searchScopeCaption(matches: Int) -> some View {
        let query = app.messaging.conversationQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let loaded = app.messaging.conversations.count
            let found = matches == 1 ? "1 match" : "\(matches) matches"
            let scope = loaded == 1 ? "1 loaded conversation" : "\(loaded) loaded conversations"
            Label {
                Text("\(found) · searched \(scope) on this device: names, nicknames, handles and latest messages")
            } icon: {
                Image(systemName: "iphone")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ModulaLayout.contentInset + 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("messages.search.scope")
        }
    }

    /// The circle springs open into a scrollable row; tap a face to jump into that chat (Fitts: big targets).
    private var circleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, ModulaLayout.contentInset)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(circle, id: \.0) { item in
                        Button {
                            HapticEngine.shared.play(.navigation)
                            app.navigation.push(.messages(.conversation(item.0)))
                        } label: {
                            VStack(spacing: 6) {
                                ModulaAvatar(initials: item.1.initials, url: item.1.avatarURL, size: 58, name: item.1.displayName)
                                Text(item.1.displayName.split(separator: " ").first.map(String.init) ?? item.1.displayName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 66)
                            }
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                        .accessibilityLabel("Chat with \(item.1.displayName)")
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 4)
        .accessibilityIdentifier("messages.circle")
    }

    private var filterRow: some View {
        let all = app.messaging.visibleConversations
        let unread = all.filter(\.isUnread).count
        let needsReply = all.filter { InboxFilter.needsReply.matches($0, viewerID: app.auth.account?.accountId) }.count
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
                                if (item == .unread && unread > 0) || (item == .needsReply && needsReply > 0) {
                                    Text("\(item == .unread ? unread : needsReply)").font(.caption2.weight(.bold)).monospacedDigit()
                                        .foregroundStyle(app.appearance.liveAccent)
                                }
                            }
                            .foregroundStyle(on ? app.appearance.liveAccent : Color.primary)
                            .padding(.horizontal, 16).frame(height: 36)
                            .modulaGlass(in: Capsule(), interactive: true)
                            .overlay { if on { Capsule().strokeBorder(app.appearance.liveAccent, lineWidth: 1.5) } }
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
        let viewerID = app.auth.account?.accountId
        let pinned = Set(app.messaging.pinnedIDs)
        let items = app.messaging.visibleConversations.filter { filter.matches($0, viewerID: viewerID, pinned: pinned) }
        let searching = !app.messaging.conversationQuery.trimmingCharacters(in: .whitespaces).isEmpty
        if items.isEmpty {
            VStack(spacing: 0) {
                header(matches: items.count)
                emptyState(searching: searching)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List {
                header(matches: items.count)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if !app.messaging.requests.isEmpty, filter == .all, !searching {
                    requestsEntry
                }
                ForEach(items) { conversation in
                    Button {
                        open(conversation)
                    } label: {
                        ConversationRow(conversation: conversation, viewerID: app.auth.account?.accountId,
                                        pinned: app.messaging.isPinned(conversation.id),
                                        draft: app.messaging.draftPreview(for: conversation.id))
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
                        Button {
                            togglePin(conversation)
                        } label: {
                            Label(app.messaging.isPinned(conversation.id) ? "Unpin" : "Pin",
                                  systemImage: app.messaging.isPinned(conversation.id) ? "pin.slash.fill" : "pin.fill")
                        }
                        .tint(app.appearance.liveAccent)
                        if app.messaging.capabilities.archive {
                            Button {
                                Task { await app.messaging.archive(conversation.id) }
                            } label: { Label("Archive", systemImage: "archivebox.fill") }
                            .tint(.indigo)
                        }
                        if app.messaging.capabilities.mute {
                            Button {
                                Task { await app.messaging.toggleMute(conversation.id) }
                            } label: {
                                Label(conversation.isMuted ? "Unmute" : "Mute", systemImage: conversation.isMuted ? "bell.fill" : "bell.slash.fill")
                            }
                            .tint(.gray)
                        } else if let person = conversation.participants.first {
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
            ModulaEmptyState(
                title: searching ? "No matching chats"
                    : filter == .unread ? "You're all caught up"
                    : filter == .needsReply ? "Nobody's waiting on you"
                    : filter == .favourites ? "Pin a chat to make it a favourite" : "Group chats are coming soon",
                message: searching ? "Search looks through the chats loaded on this device." : "Nothing here right now.",
                symbol: searching ? "magnifyingglass" : (filter == .groups ? "person.3" : "sparkles")
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
        default:
            MessagesFriendlyEmpty(scope: .inbox)
        }
    }

    @ViewBuilder
    private func contextMenu(_ conversation: Conversation) -> some View {
        Button("Open Chat", systemImage: "bubble.left.and.bubble.right") { open(conversation) }
        Button(app.messaging.isPinned(conversation.id) ? "Unpin" : "Pin",
               systemImage: app.messaging.isPinned(conversation.id) ? "pin.slash" : "pin") { togglePin(conversation) }
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

    /// Instagram/WhatsApp pattern: strangers wait behind one calm row instead of mixing into chats
    /// (control + safety; the count creates a gentle open loop without shouting).
    private var requestsEntry: some View {
        let count = app.messaging.requests.count
        return Button {
            HapticEngine.shared.play(.navigation)
            app.navigation.replaceTop(with: .messages(.requests))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.clock")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .frame(width: 54, height: 54)
                    .modulaGlass(in: Circle(), interactive: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Message requests").font(.body.weight(.semibold))
                    Text(count == 1 ? "1 person wants to chat" : "\(count) people want to chat")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                    .modulaAccentCTA()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: ModulaLayout.contentInset, bottom: 6, trailing: ModulaLayout.contentInset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityLabel("Message requests, \(count) waiting")
        .accessibilityIdentifier("messages.requestsEntry")
    }

    private func togglePin(_ conversation: Conversation) {
        HapticEngine.shared.play(.selection)
        withAnimation(ModulaSurfaceMotion.animation(reduce: ModulaEffectGate.reduceMotion(reduceMotion))) {
            app.messaging.togglePin(conversation.id)
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
    var pinned = false
    /// Unsent text left in this chat's composer (device-local).
    var draft: String? = nil
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
                    Text(app.messaging.title(for: conversation))
                        .font(.body.weight(unread ? .semibold : .medium))
                        .lineLimit(1)
                    if isGroup {
                        Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if conversation.isMuted {
                        Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(accent)
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
                        Circle().fill(accent)
                            .frame(width: 10, height: 10)
                            .padding(.trailing, 4)
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
        if let draft {
            return Text("Draft: ").fontWeight(.semibold).foregroundStyle(app.appearance.liveAccent) + Text(draft)
        }
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
        var parts = [app.messaging.title(for: conversation)]
        if pinned { parts.append("Pinned") }
        if conversation.isMuted { parts.append("Muted") }
        if let draft { parts.append("Draft: \(draft)") }
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
        // Unread = an accent ring around the avatar (pre-attentive, no extra dot to parse).
        .overlay {
            if unread {
                let accent = app.appearance.liveAccent
                Circle()
                    .strokeBorder(AngularGradient(colors: [accent, accent.mix(with: .white, by: 0.35), accent], center: .center), lineWidth: 2.5)
                    .padding(-4)
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
    @State private var isAtBottom = true
    @State private var unseenCount = 0
    @State private var forwarding: Message?
    @State private var showInfo = false
    @State private var jumpTarget: MessageID?
    @State private var replyTarget: Message?
    @State private var editing: Message?
    @State private var unsending: Message?
    @State private var flyText: String?
    @State private var flyUp = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        thread
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { MessagesWallpaper(theme: app.messaging.wallpaper(for: conversationID)) }
            .overlay(alignment: .bottomTrailing) { flyOverlay }
            .background { keyboardShortcuts }
            .onChange(of: app.messaging.drafts[conversationID] ?? "") { _, new in
                if !new.isEmpty, editing == nil { app.messaging.noteTyping(conversationID) }
            }
            .confirmationDialog(
                "Unsend this message?",
                isPresented: Binding(get: { unsending != nil }, set: { if !$0 { unsending = nil } }),
                titleVisibility: .visible
            ) {
                Button("Unsend", role: .destructive) {
                    if let message = unsending { Task { await app.messaging.unsend(message) } }
                    unsending = nil
                }
            } message: {
                Text("It disappears for everyone in this chat.")
            }
            // Composer floats over the thread so messages scroll under its glass.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    smartReplies
                    composer
                }
            }
            .sheet(item: $forwarding) { message in
                ForwardMessageSheet(message: message, excluding: conversationID)
            }
            .sheet(isPresented: $showInfo) {
                ChatInfoSheet(conversationID: conversationID) { id in jumpTarget = id }
                    .messageLinkInspector()
            }
            // Roadmap #14: links in this chat (bubbles and Chat info) open an inspector first,
            // so the real destination is visible before leaving the conversation.
            .messageLinkInspector()
            .navigationBarTitleDisplayMode(.inline)
            .modulaSoftScrollEdge()
            .navigationTitle(conversation?.title ?? "Conversation")
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticEngine.shared.play(.navigation)
                        showInfo = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.bold))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                    .modulaAccentCTA(in: Circle())
                    .accessibilityLabel("Chat info")
                    .accessibilityIdentifier("messages.conversation.info")
                }
            }
        .task {
            await app.messaging.loadThreadIfNeeded(conversationID)
            await app.messaging.probeCapabilities()
        }
        .task(id: conversationID) { await pollLoop() }
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
                    Text(conversation.map { app.messaging.title(for: $0) } ?? "Conversation")
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
            MessagesThreadSkeleton()
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
                        olderHeader(items: items, proxy: proxy)
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
                        if let people = app.messaging.typingPeople[conversationID], !people.isEmpty {
                            MessagesTypingBubble(people: people)
                                .padding(.top, 10)
                                .id("messages.typing")
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.vertical, 12)
                }
                // Chats open on the newest message and stay pinned there.
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .modulaSoftScrollEdge()
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height + geo.contentInsets.bottom - 80
                } action: { _, atBottom in
                    guard atBottom != isAtBottom else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        isAtBottom = atBottom
                        if atBottom { unseenCount = 0 }
                    }
                }
                // Follow the conversation only when the reader is already at the end or just sent:
                // never yank someone reading history (respect for the user's place = control).
                .onChange(of: items.last?.id) { _, _ in
                    guard let last = items.last else { return }
                    if last.isOwn || isAtBottom {
                        scrollToLatest(items, proxy: proxy)
                    } else {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { unseenCount += 1 }
                    }
                }
                .onChange(of: jumpTarget) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
                    jumpTarget = nil
                }
                .overlay(alignment: .bottomTrailing) { jumpControl(items: items, proxy: proxy) }
            }
        }
    }

    /// On-device reply suggestions for the latest incoming message. Tapping only fills the composer
    /// (the user stays in control; nothing is sent for them and nothing leaves the device).
    @ViewBuilder
    private var smartReplies: some View {
        let items = app.messaging.messages(for: conversationID)
        let draftEmpty = (app.messaging.drafts[conversationID] ?? "").isEmpty
        if draftEmpty, let last = items.last, !last.isOwn {
            let options = MessageSmartReplies.suggestions(for: last.body.text)
            if !options.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    ModulaGlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(options, id: \.self) { option in
                                Button {
                                    app.messaging.drafts[conversationID] = option
                                    composerFocused = true
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    Text(option)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                                .modulaGlass(in: Capsule(), interactive: true)
                                .accessibilityHint("Puts this reply in the message box")
                            }
                        }
                        .padding(.horizontal, ModulaLayout.contentInset)
                    }
                }
                .scrollClipDisabled()
                .padding(.top, 6)
                .accessibilityIdentifier("messages.smartReplies")
            }
        }
    }

    /// Endless history: the top row pages in the previous server page and keeps the reader's place.
    @ViewBuilder
    private func olderHeader(items: [Message], proxy: ScrollViewProxy) -> some View {
        if app.messaging.threadHasMore[conversationID] == true {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Loading earlier messages")
                .onAppear {
                    let anchor = items.first?.id
                    Task {
                        if await app.messaging.loadOlderMessages(conversationID), let anchor {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                }
        }
    }

    /// Jump-to-latest button; becomes a "N new messages" pill when replies arrive off-screen.
    @ViewBuilder
    private func jumpControl(items: [Message], proxy: ScrollViewProxy) -> some View {
        if !isAtBottom {
            Button {
                HapticEngine.shared.play(.selection)
                unseenCount = 0
                scrollToLatest(items, proxy: proxy)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                    if unseenCount > 0 {
                        Text(unseenCount == 1 ? "1 new message" : "\(unseenCount) new messages")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, unseenCount > 0 ? 16 : 0)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
            .modulaAccentCTA()
            .padding(.trailing, ModulaLayout.contentInset)
            .padding(.bottom, 10)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
            .accessibilityLabel(unseenCount > 0 ? "\(unseenCount) new messages. Jump to latest" : "Jump to latest message")
            .accessibilityIdentifier("messages.jumpToLatest")
        }
    }

    /// No websocket/SSE route exists for messages, so an open chat re-reads its newest page every
    /// 4 s while the app is active. New incoming messages tap a light haptic.
    private func pollLoop() async {
        #if DEBUG
        if MessagingDebugFixture.isEnabled { return }
        #endif
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            guard scenePhase == .active else { continue }
            let added = await app.messaging.pollThread(conversationID)
            if added > 0 {
                HapticEngine.shared.play(.selection)
                announceIncoming(count: added)
            }
        }
    }

    /// Roadmap #13: tell VoiceOver users something arrived without moving their focus or
    /// reading the message aloud (they choose when to go and read it).
    private func announceIncoming(count: Int) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let sender = app.messaging.messages(for: conversationID).last(where: { !$0.isOwn })?.sender.displayName
        let text = count == 1
            ? "New message" + (sender.map { " from \($0)" } ?? "")
            : "\(count) new messages"
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
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
            sendNow()
        }
    }

    private func sendNow() {
        let text = (app.messaging.drafts[conversationID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let editing {
            self.editing = nil
            reply = nil
            app.messaging.drafts[conversationID] = ""
            Task {
                if !(await app.messaging.edit(editing, text: text)) { app.messaging.drafts[conversationID] = text }
            }
            return
        }
        let target = replyTarget
        reply = nil
        replyQuote = nil
        replyTarget = nil
        launchFlyIn(text)
        IslandSendEffect.shared.fire("Message sent", accent: app.appearance.liveAccent)
        Task { await app.messaging.send(conversation: conversationID, viewer: viewer, replyTo: target) }
    }

    /// The words lift off the composer and settle into the thread (peak-end: sending feels good).
    private func launchFlyIn(_ text: String) {
        guard !reduceMotion else { return }
        flyUp = false
        flyText = text
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { flyUp = true }
            try? await Task.sleep(for: .milliseconds(460))
            flyText = nil
            flyUp = false
        }
    }

    @ViewBuilder
    private var flyOverlay: some View {
        if let flyText {
            Text(flyText)
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(app.appearance.liveAccent))
                .frame(maxWidth: 280, alignment: .trailing)
                .scaleEffect(flyUp ? 1 : 0.9, anchor: .bottomTrailing)
                .offset(y: flyUp ? -96 : 0)
                .opacity(flyUp ? 0 : 1)
                .padding(.trailing, ModulaLayout.contentInset)
                .padding(.bottom, 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// iPad hardware keyboard: ⌘↩ send, ⌘I chat info, Esc cancels a reply or edit.
    private var keyboardShortcuts: some View {
        Group {
            Button("Send") { sendNow() }.keyboardShortcut(.return, modifiers: .command)
            Button("Chat info") { showInfo = true }.keyboardShortcut("i", modifiers: .command)
            Button("Cancel") { cancelReply() }.keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func cancelReply() {
        replyTarget = nil
        if editing != nil {
            editing = nil
            app.messaging.drafts[conversationID] = ""
        }
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
        case "forward":
            forwarding = message
        case "speak":
            MessageSpeech.speak(message.body.text)
        case "reply" where app.messaging.capabilities.reply:
            replyTarget = message
            replyQuote = nil
            let who = message.isOwn ? "yourself" : message.sender.displayName
            reply = ModulaComposerReply(title: "Replying to \(who)", excerpt: message.body.text)
            composerFocused = true
            HapticEngine.shared.play(.selection)
        case "edit":
            editing = message
            replyTarget = nil
            app.messaging.drafts[conversationID] = message.body.text
            reply = ModulaComposerReply(title: "Editing message", excerpt: message.body.text)
            composerFocused = true
        case "delete":
            unsending = message
        case "star":
            app.messaging.toggleStar(message.id)
        case "report":
            Task { _ = await app.messaging.report(message: message) }
        case let id where id.hasPrefix("react:"):
            Task { await app.messaging.toggleReaction(String(id.dropFirst(6)), on: message) }
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
                if let replyTo = message.replyTo, !message.isDeleted {
                    MessageReplyQuote(preview: replyTo)
                }
                if message.isDeleted {
                    Text(message.isOwn ? "You unsent a message" : "This message was unsent")
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(bubbleShape.strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                let parsed = ModulaLocalSticker.extract(message.isDeleted ? "" : message.body.text)
                if !parsed.text.isEmpty {
                    Text(MessageLinkText.attributed(parsed.text))
                        .font(.body)
                        .tint(message.isOwn ? Color.white : app.appearance.liveAccent)
                        .textSelection(.disabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background { bubbleBackground }
                        .foregroundStyle(message.isOwn ? Color.white : Color.primary)
                }
                if !parsed.stickers.isEmpty {
                    ModulaLocalStickerRow(stickers: parsed.stickers)
                }
                if let attachment = MessageInlineContent.detect(in: message.body.text) {
                    MessageInlineContentView(content: attachment)
                }
                if !message.reactions.isEmpty {
                    MessageReactionsRow(reactions: message.reactions) { emoji in
                        onAction(.init(id: "react:\(emoji)", title: emoji))
                    }
                    // The heart drops in with a little bounce.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3, anchor: message.isOwn ? .topTrailing : .topLeading).combined(with: .opacity))
                }
                HStack(spacing: 8) {
                    if app.messaging.isStarred(message.id) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(app.appearance.liveAccent)
                            .accessibilityHidden(true)
                    }
                    if message.editedAt != nil && !message.isDeleted {
                        Text("Edited").font(.caption2).foregroundStyle(.secondary)
                    }
                    if message.delivery == .failed {
                        Button("Retry") { onAction(.init(id: "retry", title: "Retry")) }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: ModulaLayout.minimumTouch)
                            .contentShape(Rectangle())
                    } else if app.messaging.capabilities.readReceipts, ModulaPreferences.chatShowReadReceipts,
                              showsStatus, message.isOwn, message.delivery == .read {
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
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55), value: message.reactions)
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
        // Double-tap to love a message (only when reactions are live).
        .onTapGesture(count: 2) {
            guard app.messaging.capabilities.reactions, !message.isDeleted, !message.id.hasPrefix("local-") else { return }
            onAction(.init(id: "react:❤️", title: "❤️"))
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
            ForEach(voiceOverActions) { action in
                Button(action.accessibilityLabel ?? action.title) { onAction(action) }
            }
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
        let large = 22.0, tight = 8.0
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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Sent: a soft top-lit accent gradient (one strong colour = "mine", Gestalt similarity).
    private var ownGradient: LinearGradient {
        let accent = app.appearance.liveAccent
        return LinearGradient(colors: [accent.mix(with: .white, by: 0.14), accent], startPoint: .top, endPoint: .bottom)
    }

    /// Received: Liquid Glass; a solid tint under Reduce Transparency.
    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isOwn {
            bubbleShape.fill(ownGradient)
        } else if reduceTransparency {
            bubbleShape.fill(bubbleFill)
        } else {
            Color.clear.modulaGlass(in: bubbleShape, interactive: false)
        }
    }

    private var bubbleFill: Color {
        if message.isOwn {
            return app.appearance.liveAccent
        }
        let oled = scheme == .dark && app.appearance.darkStyle == .oled
        return oled ? Color.white.opacity(0.08) : Color.primary.opacity(0.08)
    }

    private var actions: [ModulaContextAction] {
        if message.isDeleted { return [] }
        let caps = app.messaging.capabilities
        let local = message.id.hasPrefix("local-")
        var items = message.isOwn
            ? MessageContextActions.own(capabilities: caps, delivery: message.delivery)
            : MessageContextActions.other(capabilities: caps)
        if message.isOwn {
            items.removeAll { $0.id == "edit" && (local || Date().timeIntervalSince(message.sentAt) > 15 * 60) }
            items.removeAll { $0.id == "delete" && local }
        }
        let starred = app.messaging.isStarred(message.id)
        items.insert(.init(id: "star", title: starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star"), at: min(1, items.count))
        if caps.reactions, !local {
            let emojis = ["❤️", "👍", "😂", "😮", "😢", "🔥"]
            items.insert(.init(id: "react", title: "React", systemImage: "face.smiling",
                               children: emojis.map { ModulaContextAction(id: "react:\($0)", title: $0) }), at: 0)
        }
        return items
    }

    /// Roadmap #13: every action the long-press menu offers is also a named VoiceOver action
    /// (React, Star, Edit, Forward, Unsend…), with Copy and Reply always first as before.
    private var voiceOverActions: [ModulaContextAction] {
        var flat: [ModulaContextAction] = [
            .init(id: "copy", title: "Copy"),
            .init(id: "reply", title: "Reply"),
        ]
        for action in actions where !["copy", "reply", "retry"].contains(action.id) {
            if action.children.isEmpty {
                flat.append(action)
            } else {
                flat += action.children.map {
                    ModulaContextAction(id: $0.id, title: $0.title, accessibilityLabel: "\(action.title) \($0.title)")
                }
            }
        }
        return flat
    }

    private var accessibilityLabel: String {
        let who = message.isOwn ? "You" : message.sender.displayName
        let time = ConversationRow.relative(message.sentAt)
        let parsed = ModulaLocalSticker.extract(message.body.text)
        var parts = [who, time]
        if !parsed.text.isEmpty { parts.append(parsed.text) }
        if !parsed.stickers.isEmpty { parts.append(parsed.stickers.map(\.label).joined(separator: ", ")) }
        if message.isDeleted { parts.append("Unsent") }
        if message.replyTo != nil { parts.append("Reply") }
        if message.editedAt != nil { parts.append("Edited") }
        if !message.reactions.isEmpty {
            parts.append("Reactions: " + message.reactions.map { "\($0.emoji) \($0.count)" }.joined(separator: ", "))
        }
        if app.messaging.isStarred(message.id) { parts.append("Starred") }
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
                    prompt: "Say something good…",
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
                .background(alignment: .trailing) { MessagesComposerWave(idle: text.isEmpty && !typing) }
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
                    if app.messaging.capabilities.block {
                        Button {
                            Task { _ = await app.messaging.block(request.sender) }
                        } label: { Label("Block", systemImage: "hand.raised.fill") }
                        .tint(.orange)
                    }
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
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .modulaAccentCTA()
                    }
                    .accessibilityIdentifier("messages.request.accept")
                    Button(action: onDecline) {
                        Text("Decline").font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity).frame(height: 44)
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
    var presentedAsSheet = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// From the sheet: close it first, then open the chat underneath.
    private func go(_ route: AppRoute) {
        if presentedAsSheet {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                app.navigation.push(route)
            }
        } else {
            app.navigation.push(route)
        }
    }
    @State private var people: [DiscoverPerson] = []
    @State private var query = ""
    @State private var results: [DiscoverPerson] = []
    @State private var searchingPeople = false

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
                        MessagesGlassSearchField(text: $query, prompt: "Find a friend")
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
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResultsSection
                } else {
                if !recentDirect.isEmpty {
                    section("Your circle") {
                        ForEach(recentDirect) { c in
                            let p = c.participants[0]
                            MessagePersonRow(name: c.title, handle: p.handle, avatarURL: p.avatarURL ?? avatar(for: p.handle),
                                             detail: "In your circle") {
                                go(.messages(.conversation(c.id)))
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
                                go(.messages(.direct(person.handle)))
                            }
                            .accessibilityIdentifier("messages.new.person.\(person.handle)")
                        }
                    }
                }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .modulaSoftScrollEdge()
        .navigationTitle("A little hello.")
        .navigationBarTitleDisplayMode(presentedAsSheet ? .large : .inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).frame(width: 34, height: 34).contentShape(Circle())
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: .lightImpact))
                    .modulaAccentCTA(in: Circle())
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            await app.messaging.loadInboxIfNeeded()
            guard ModulaPreferences.showsSuggestedPeople else { return }
            people = ((try? await GreenfieldDiscoverRepository(client: app.client).people(cursor: nil).items) ?? [])
                .filter { !ActivitySuggestedPeople.isFixture($0) }
        }
        // Real people search (`GET /v1/search?entityType=profile`), debounced 250 ms.
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { results = []; searchingPeople = false; return }
            searchingPeople = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let page = try? await GreenfieldDiscoverRepository(client: app.client).search(query: q, entityType: "profile", cursor: nil)
            guard !Task.isCancelled else { return }
            let own = app.profile.ownProfile?.handle.lowercased()
            results = (page?.results.compactMap(\.person) ?? []).filter { $0.handle.lowercased() != own }
            searchingPeople = false
        }
        .accessibilityIdentifier("messages.new")
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if searchingPeople && results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .accessibilityLabel("Searching people")
        } else if results.isEmpty {
            Text("No one matches “\(query)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
        } else {
            section("People") {
                ForEach(results) { person in
                    MessagePersonRow(name: person.displayName, handle: person.handle,
                                     avatarURL: person.avatarURL ?? avatar(for: person.handle),
                                     detail: person.followsViewer ? "Follows you" : nil) {
                        if let existing = app.messaging.directConversation(with: person.handle) {
                            go(.messages(.conversation(existing.id)))
                        } else {
                            go(.messages(.direct(person.handle)))
                        }
                    }
                    .accessibilityIdentifier("messages.new.result.\(person.handle)")
                }
            }
        }
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
        case .inbox: ("Your chats will bloom here", "Say hi to someone — a little hello goes a long way.", "bubble.left.and.bubble.right.fill")
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
            if scope == .inbox {
                MolibooEmptyArt(mood: .wave, size: 76)
                    .offset(y: float ? -4 : 4)
                    .accessibilityHidden(true)
            } else {
            Image(systemName: copy.symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(app.appearance.liveAccent)
                .frame(width: 92, height: 92)
                .messagesGlass(Circle(), tint: app.appearance.liveAccent.opacity(0.18))
                .offset(y: float ? -4 : 4)
                .accessibilityHidden(true)
            }
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
                .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
                .modulaAccentCTA()
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
                .overlay(alignment: .bottomTrailing) {
                    // A little Moliboo waves you in.
                    MolibooEmptyArt(mood: .wave, size: 40)
                        .offset(x: 30, y: 10)
                        .accessibilityHidden(true)
                }
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
/// itself for the live conversation. With no thread yet it is a real new chat: the composer is always
/// there, and the first send creates the conversation (`POST /v1/conversations` with the text), then
/// swaps in the live thread. Failed first sends stay as a red bubble with tap-to-retry.
struct DirectMessageView: View {
    let person: String
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resolving = true
    @State private var composerFocused = false

    private var handle: String { person.trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
    private var key: ConversationID { MessagingStore.pendingDirectKey(handle) }
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
    private var pending: [Message] { app.messaging.messages(for: key) }

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
                newChat
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .modulaSoftScrollEdge()
        .task(id: person) { await resolve() }
        .accessibilityIdentifier("messages.direct")
        .accessibilityValue(RouteSerializer.serialize(.messages(.direct(person))))
    }

    private func resolve() async {
        if let found = app.messaging.directConversation(with: person) { open(found); return }
        await app.messaging.loadInboxIfNeeded()
        if let found = app.messaging.directConversation(with: person) { open(found); return }
        // Older threads may sit beyond the first page; one refresh before showing a new chat.
        await app.messaging.refreshInbox()
        if let found = app.messaging.directConversation(with: person) { open(found); return }
        withAnimation(.smooth(duration: 0.2)) { resolving = false }
    }

    private func open(_ conversation: Conversation) {
        app.navigation.replaceTop(with: .messages(.conversation(conversation.id)))
    }

    private var viewer: ConversationParticipant {
        ConversationParticipant(
            id: app.auth.account?.accountId ?? "me",
            handle: app.auth.account?.primaryHandle ?? "",
            displayName: app.auth.account?.displayName ?? "You",
            avatarURL: nil
        )
    }

    private var composer: some View {
        MessageComposer(
            text: Binding(
                get: { app.messaging.drafts[key] ?? "" },
                set: { app.messaging.drafts[key] = $0 }
            ),
            canSend: app.messaging.capabilities.startConversation,
            showsAttachments: false,
            largeText: dynamicTypeSize.isAccessibilitySize,
            focus: $composerFocused
        ) {
            Task {
                if let conversation = await app.messaging.startDirect(handle: handle, viewer: viewer) {
                    IslandSendEffect.shared.fire("Message sent", accent: app.appearance.liveAccent)
                    open(conversation)
                }
            }
        }
    }

    @ViewBuilder
    private var newChat: some View {
        if pending.isEmpty {
            ScrollView {
                VStack(spacing: 14) {
                    ModulaAvatar(initials: initials, url: profile?.avatarURL, size: 88, name: name)
                        .padding(.top, 36)
                    VStack(spacing: 4) {
                        Text(name).font(.title3.weight(.bold))
                        if profile != nil { Text("@\(handle)").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Text("Say hi — your first message starts the chat.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    ModulaGlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(["👋", "Hey!", "How’s it going?"], id: \.self) { opener in
                                Button {
                                    app.messaging.drafts[key] = opener
                                    composerFocused = true
                                    HapticEngine.shared.play(.selection)
                                } label: {
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
                    Button {
                        app.navigation.push(.profile(handle, .overview))
                        HapticEngine.shared.play(.navigation)
                    } label: {
                        Label("View profile", systemImage: "person.crop.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityIdentifier("messages.direct.profile")
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("messages.direct.starter")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(pending) { message in
                        MessageBubble(message: message, showsStatus: true) { action in
                            if action.id == "retry" { retry(message) }
                            if action.id == "copy" { UIPasteboard.general.string = message.body.text }
                        }
                        .onTapGesture { if message.delivery == .failed { retry(message) } }
                        .accessibilityHint(message.delivery == .failed ? "Not sent. Double tap to retry." : "")
                    }
                    if pending.contains(where: { $0.delivery == .failed }) {
                        Text("Not sent — tap the message to try again.")
                            .font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("messages.direct.failed")
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private func retry(_ message: Message) {
        Task {
            if let conversation = await app.messaging.retryStartDirect(message: message, handle: handle, viewer: viewer) {
                open(conversation)
            }
        }
    }
}


// MARK: - Bubble details

/// Detects links in message text so they are tappable (opened by the system `openURL`).
enum MessageLinkText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector, text.contains(".") else { return result }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let r = Range(match.range, in: text),
                  let lower = AttributedString.Index(r.lowerBound, within: result),
                  let upper = AttributedString.Index(r.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
            result[lower..<upper].underlineStyle = .single
        }
        return result
    }
}

/// The small curved tail on the last bubble of a run (drawn for the trailing side; mirrored for incoming).
struct MessageBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY * 0.9))
        p.addQuadCurve(to: CGPoint(x: rect.minX - 1, y: rect.maxY - 1),
                       control: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Bubble-shaped placeholder while a chat loads (layout matches the real thread, so nothing jumps).
struct MessagesThreadSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private let rows: [(own: Bool, width: CGFloat)] = [
        (false, 190), (false, 120), (true, 220), (false, 160), (true, 96), (true, 180), (false, 210)
    ]

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    if row.own { Spacer(minLength: 48) }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(row.own ? 0.11 : 0.07))
                        .frame(width: row.width, height: 38)
                    if !row.own { Spacer(minLength: 48) }
                }
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, 16)
        .opacity(pulse ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading messages")
    }
}


// MARK: - Smart replies, read aloud, forward, chat info

/// Tiny on-device heuristics; no text leaves the phone.
enum MessageSmartReplies {
    static func suggestions(for text: String) -> [String] {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 400 else { return [] }
        let words = Set(t.split { !$0.isLetter }.map(String.init))
        if t.contains("thank") { return ["You’re welcome!", "Anytime 😊", "❤️"] }
        if t.hasSuffix("?") {
            if words.contains("when") || t.contains("what time") { return ["Later today?", "Tomorrow works", "Let me check"] }
            if t.contains("how are") || t.contains("how’s it") || t.contains("how's it") { return ["Good, you?", "Pretty great!", "Busy but good"] }
            return ["Yes!", "Not sure yet", "Let me check"]
        }
        if !words.isDisjoint(with: ["hey", "hi", "hello", "yo", "hiya"]) { return ["Hey! 👋", "Hi!", "What’s up?"] }
        if !words.isDisjoint(with: ["haha", "lol", "lmao"]) || t.contains("😂") { return ["😂", "Haha", "Too good"] }
        return ["👍", "Sounds good", "Love it"]
    }
}

/// VoiceOver-independent read-aloud from the long-press menu.
@MainActor
enum MessageSpeech {
    private static let synthesizer = AVSpeechSynthesizer()
    static func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: text))
    }
}

/// Forward a message to other chats with the real send route. Each row confirms in place.
struct ForwardMessageSheet: View {
    let message: Message
    let excluding: ConversationID
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sentTo: Set<ConversationID> = []
    @State private var busy: Set<ConversationID> = []

    var body: some View {
        NavigationStack {
            List(app.messaging.visibleConversations.filter { $0.id != excluding }) { conversation in
                HStack(spacing: 12) {
                    ConversationAvatar(participants: conversation.participants, size: 40)
                    Text(conversation.title).font(.body.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        busy.insert(conversation.id)
                        Task {
                            if await app.messaging.sendPrepared(text: message.body.text, conversation: conversation.id) {
                                sentTo.insert(conversation.id)
                                HapticEngine.shared.play(.success)
                            }
                            busy.remove(conversation.id)
                        }
                    } label: {
                        Text(sentTo.contains(conversation.id) ? "Sent" : "Send")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .lightImpact))
                    .modulaAccentCTA()
                    .disabled(sentTo.contains(conversation.id) || busy.contains(conversation.id))
                    .accessibilityLabel(sentTo.contains(conversation.id) ? "Sent to \(conversation.title)" : "Send to \(conversation.title)")
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(app.appearance.liveAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("messages.forward")
    }
}

/// Chat info: who, quick actions, search inside this chat and the links you've shared.
struct ChatInfoSheet: View {
    let conversationID: ConversationID
    var onJump: (MessageID) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var nickname = ""
    @State private var confirmBlock = false
    @State private var blocked = false

    private var conversation: Conversation? { app.messaging.conversation(id: conversationID) }
    private var messages: [Message] { app.messaging.messages(for: conversationID) }
    private var starred: [Message] { messages.filter { app.messaging.isStarred($0.id) }.reversed() }

    /// Personal, device-only touches: a nickname, a wallpaper and your starred messages.
    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nickname").font(.headline).accessibilityAddTraits(.isHeader)
                TextField(conversation?.title ?? "Nickname", text: $nickname)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .submitLabel(.done)
                    .onSubmit { app.messaging.setNickname(nickname, for: conversationID) }
                Text("Only you see this name.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallpaper").font(.headline).accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    ForEach(MessagesWallpaperTheme.allCases) { theme in
                        let on = app.messaging.wallpaper(for: conversationID) == theme
                        Button {
                            app.messaging.setWallpaper(theme, for: conversationID)
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Circle()
                                .fill(theme.swatch(accent: app.appearance.liveAccent))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(on ? app.appearance.liveAccent : Color.primary.opacity(0.15), lineWidth: on ? 3 : 1))
                                .padding(2)
                                .contentShape(Circle())
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                        .accessibilityLabel(theme.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if !starred.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Starred").font(.headline).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                    ForEach(starred.prefix(20)) { message in
                        Button {
                            dismiss()
                            onJump(message.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "star.fill").foregroundStyle(app.appearance.liveAccent)
                                Text(message.body.text).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { nickname = app.messaging.nicknames[conversationID] ?? "" }
        .onDisappear { app.messaging.setNickname(nickname, for: conversationID) }
    }
    private var matches: [Message] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return Array(messages.filter { $0.body.text.lowercased().contains(q) }.reversed().prefix(50))
    }
    private var links: [URL] {
        var seen = Set<URL>()
        return messages.reversed().compactMap { MessageInlineContent.firstURL(in: $0.body.text) }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConversationAvatar(participants: conversation?.participants ?? [], size: 84)
                        .padding(.top, 8)
                    VStack(spacing: 2) {
                        Text(conversation?.title ?? "Chat").font(.title3.weight(.bold))
                        if let handle = conversation?.handleLabel {
                            Text(handle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        if let person = conversation?.participants.first {
                            actionTile("Profile", symbol: "person.crop.circle") {
                                dismiss()
                                app.navigation.push(.profile(person.handle.isEmpty ? person.id : person.handle, .overview))
                            }
                        }
                        actionTile(app.messaging.isPinned(conversationID) ? "Unpin" : "Pin",
                                   symbol: app.messaging.isPinned(conversationID) ? "pin.slash" : "pin") {
                            app.messaging.togglePin(conversationID)
                            HapticEngine.shared.play(.selection)
                        }
                        if app.messaging.capabilities.mute {
                            actionTile(conversation?.isMuted == true ? "Unmute" : "Mute",
                                       symbol: conversation?.isMuted == true ? "bell" : "bell.slash") {
                                Task { await app.messaging.toggleMute(conversationID) }
                            }
                        }
                        actionTile("Nudge", symbol: "hand.wave") {
                            HapticEngine.shared.play(.confirmation)
                            Task { _ = await app.messaging.sendPrepared(text: "👋", conversation: conversationID) }
                        }
                    }
                    personalSection
                    MessagesGlassSearchField(text: $query, prompt: "Search this chat")
                    if !query.isEmpty {
                        searchResults
                    } else if !links.isEmpty {
                        linksSection
                    }
                    Text("Search covers the messages loaded on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let person = conversation?.participants.first, app.messaging.capabilities.block {
                        Button(role: .destructive) {
                            confirmBlock = true
                        } label: {
                            Text(blocked ? "Blocked" : "Block \(person.displayName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .disabled(blocked)
                        .confirmationDialog("Block \(person.displayName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
                            Button("Block", role: .destructive) {
                                Task { blocked = await app.messaging.block(person) }
                            }
                        } message: {
                            Text("They won't be able to message you. You can unblock them from their profile.")
                        }
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Chat info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(app.appearance.liveAccent)
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("messages.info")
    }

    private func actionTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3.weight(.semibold))
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(width: 76, height: 64)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .lightImpact))
        .modulaAccentCTA(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var searchResults: some View {
        if matches.isEmpty {
            Text("No messages match “\(query)”.").font(.subheadline).foregroundStyle(.secondary).padding(.top, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { message in
                    Button {
                        dismiss()
                        onJump(message.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(message.isOwn ? "You" : message.sender.displayName) · \(MessageTimeline.label(for: message.sentAt))")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(message.body.text).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared links").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(links.prefix(20), id: \.self) { url in
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(app.appearance.liveAccent)
                        Text(url.host() ?? url.absoluteString).font(.subheadline).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .modulaGlass(in: Capsule(), interactive: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Three overlapping faces from your circle (top right of the inbox).
struct MessagesCircleStack: View {
    let people: [(ConversationID, ConversationParticipant)]
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        HStack(spacing: -12) {
            ForEach(Array(people.enumerated()), id: \.offset) { index, item in
                ModulaAvatar(initials: item.1.initials, url: item.1.avatarURL, size: 30, name: item.1.displayName)
                    .overlay(Circle().stroke(canvas, lineWidth: 2))
                    .zIndex(Double(people.count - index))
            }
        }
        .frame(height: 36)
        .contentShape(Rectangle())
    }
}


// MARK: - Messaging v2 pieces

struct MessageReplyQuote: View {
    let preview: MessageReplyPreview
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(app.appearance.liveAccent).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(preview.senderName).font(.caption.weight(.semibold)).foregroundStyle(app.appearance.liveAccent)
                Text(preview.deleted ? "Unsent message" : preview.body)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

struct MessageReactionsRow: View {
    let reactions: [MessageReaction]
    var onTap: (String) -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactions, id: \.emoji) { reaction in
                Button {
                    onTap(reaction.emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(reaction.emoji).font(.footnote)
                        if reaction.count > 1 {
                            Text("\(reaction.count)").font(.caption2.weight(.semibold)).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 26)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .overlay { if reaction.mine { Capsule().strokeBorder(app.appearance.liveAccent, lineWidth: 1.2) } }
                }
                .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
            }
        }
        .padding(.top, -10)
    }
}

/// Three soft dots in a glass pill while the other person types (v2 typing route).
struct MessagesTypingBubble: View {
    let people: [ConversationParticipant]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ModulaAvatar(initials: people.first?.initials ?? "?", url: people.first?.avatarURL, size: 28)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .offset(y: bounce && !reduceMotion ? -3 : 0)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.15),
                            value: bounce
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .modulaGlass(in: Capsule(), interactive: false)
            Spacer(minLength: 48)
        }
        .onAppear { bounce = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(people.first?.displayName ?? "Someone") is typing")
    }
}

/// Per-chat wallpaper (device only). Soft, low-contrast washes so bubbles always stay legible.
enum MessagesWallpaperTheme: String, CaseIterable, Identifiable, Sendable {
    case none, accent, dusk, ocean, meadow, ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No wallpaper"
        case .accent: "Accent glow"
        case .dusk: "Dusk"
        case .ocean: "Ocean"
        case .meadow: "Meadow"
        case .ember: "Ember"
        }
    }

    func colors(accent: Color) -> [Color] {
        switch self {
        case .none: []
        case .accent: [accent, accent.opacity(0.2)]
        case .dusk: [.purple, .pink]
        case .ocean: [.blue, .teal]
        case .meadow: [.green, .mint]
        case .ember: [.orange, .red]
        }
    }

    func swatch(accent: Color) -> AnyShapeStyle {
        self == .none
            ? AnyShapeStyle(Color.primary.opacity(0.08))
            : AnyShapeStyle(LinearGradient(colors: colors(accent: accent), startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct MessagesWallpaper: View {
    let theme: MessagesWallpaperTheme
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if theme != .none {
            let strength = reduceTransparency ? 0.08 : (scheme == .dark ? 0.22 : 0.16)
            LinearGradient(
                colors: theme.colors(accent: app.appearance.liveAccent).map { $0.opacity(strength) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// The idle composer's soft liquid edge. It melts away when you start typing.
struct MessagesComposerWave: View {
    var idle: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var drift = false

    var body: some View {
        MessagesLiquidEdge(amplitude: idle ? 1 : 0, phase: drift ? 1 : 0)
            .fill(app.appearance.liveAccent.opacity(reduceTransparency ? 0.35 : 0.22))
            .frame(width: 30)
            .padding(.vertical, 4)
            .offset(x: idle ? 14 : -6)
            .opacity(idle ? 1 : 0)
            .shadow(color: app.appearance.liveAccent.opacity(0.25), radius: 6, y: 2)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7), value: idle)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { drift = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct MessagesLiquidEdge: Shape {
    var amplitude: CGFloat
    var phase: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amplitude, phase) }
        set { amplitude = newValue.first; phase = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let a = w * 0.35 * amplitude
        let shift = (phase - 0.5) * h * 0.15
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w * 0.4, y: 0))
        p.addCurve(
            to: CGPoint(x: w * 0.4, y: h),
            control1: CGPoint(x: w * 0.4 + a * 1.6, y: h * 0.25 + shift),
            control2: CGPoint(x: w * 0.4 - a * 0.4, y: h * 0.75 + shift)
        )
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
