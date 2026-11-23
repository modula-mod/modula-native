import LocalAuthentication
import Photos
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Face ID / device passcode for hidden chats (device-local only)

enum MessagePrivacyAuth {
    /// Unlocks the hidden-chats folder with Face ID, Touch ID, or the iPhone passcode.
    /// If the device has no protection enrolled, this returns false so chats are not "hidden" behind nothing.
    static func confirm(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

/// Identifies a batch of conversations for a sheet presentation.
struct IdentifiedIDList: Identifiable {
    let ids: [ConversationID]
    var id: String { ids.joined(separator: ",") }
}


// MARK: - Delivery ticks (honest states only)

enum MessageDeliveryTicks {
    /// iMessage-style marks: one check for sent, two for delivered, two in accent for read.
    @ViewBuilder
    static func view(for delivery: MessageDeliveryState, showRead: Bool, accent: Color, failed: Bool = false) -> some View {
        if delivery == .failed {
            EmptyView()
        } else if delivery == .sending {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Sending…").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 3) {
                ticks(for: delivery, showRead: showRead, accent: accent)
                if let label = MessageTimeline.status(for: delivery) ?? (delivery == .read && showRead ? "Read" : nil) {
                    Text(label).font(.caption2).foregroundStyle(delivery == .read && showRead ? accent : Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("messages.bubble.status")
        }
    }

    @ViewBuilder
    private static func ticks(for delivery: MessageDeliveryState, showRead: Bool, accent: Color) -> some View {
        let tint: Color = (delivery == .read && showRead) ? accent : Color.secondary
        Image(systemName: "checkmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .overlay(alignment: .leading) {
                if delivery == .delivered || delivery == .read {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .offset(x: 4)
                }
            }
            .padding(.trailing, (delivery == .delivered || delivery == .read) ? 4 : 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Inbox search refinement (loaded chats only)

enum InboxSearchKind: String, CaseIterable, Identifiable {
    case all, links, images, voice, starred
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .links: "Links"
        case .images: "Photos"
        case .voice: "Voice"
        case .starred: "Starred"
        }
    }

    func matches(_ conversation: Conversation, query: String, starredIDs: Set<MessageID>, messages: [Message]) -> Bool {
        switch self {
        case .all:
            return true
        case .links:
            if let body = conversation.lastMessage?.body, MessageInlineContent.firstURL(in: body) != nil { return true }
            return messages.contains { MessageInlineContent.firstURL(in: $0.body.text) != nil }
        case .images:
            let hit: (String) -> Bool = { text in
                guard let url = MessageInlineContent.firstURL(in: text) else { return false }
                if case .image = MessageInlineContent.classify(url) { return true }
                return false
            }
            if let body = conversation.lastMessage?.body, hit(body) { return true }
            return messages.contains { hit($0.body.text) }
        case .voice:
            if conversation.lastMessage?.kind == .voice { return true }
            return messages.contains { $0.kind == .voice && !$0.isDeleted }
        case .starred:
            return messages.contains { starredIDs.contains($0.id) }
        }
    }
}

// MARK: - Archived / hidden / folder lists

struct ArchivedChatsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpen: (Conversation) -> Void

    var body: some View {
        let items = app.messaging.archivedConversations
        Group {
            if items.isEmpty {
                ContentUnavailableView("No archived chats", systemImage: "archivebox",
                                       description: Text("Archived chats stay on this device so you can unarchive them."))
            } else {
                List(items) { conversation in
                    Button { onOpen(conversation) } label: {
                        ConversationRow(conversation: conversation, pinned: app.messaging.isPinned(conversation.id),
                                        draft: app.messaging.draftPreview(for: conversation.id))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await app.messaging.unarchive(conversation.id) }
                        } label: { Label("Unarchive", systemImage: "arrow.uturn.backward") }
                        .tint(.primary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: ModulaLayout.contentInset, bottom: 6, trailing: ModulaLayout.contentInset))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("messages.archived")
    }
}

struct HiddenChatsView: View {
    @Environment(AppEnvironment.self) private var app
    var onOpen: (Conversation) -> Void

    var body: some View {
        let items = app.messaging.hiddenConversations
        Group {
            if items.isEmpty {
                ContentUnavailableView("No hidden chats", systemImage: "eye.slash",
                                       description: Text("Hidden chats stay on this iPhone and are locked behind Face ID or your device passcode."))
            } else {
                List(items) { conversation in
                    Button { onOpen(conversation) } label: {
                        ConversationRow(conversation: conversation, pinned: app.messaging.isPinned(conversation.id),
                                        draft: app.messaging.draftPreview(for: conversation.id))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            app.messaging.unhide(conversation.id)
                        } label: { Label("Unhide", systemImage: "eye") }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: ModulaLayout.contentInset, bottom: 6, trailing: ModulaLayout.contentInset))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Hidden")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("messages.hidden")
    }
}

struct FolderChatsView: View {
    let name: String
    @Environment(AppEnvironment.self) private var app
    var onOpen: (Conversation) -> Void

    var body: some View {
        let items = app.messaging.conversations(inFolder: name)
        Group {
            if items.isEmpty {
                ContentUnavailableView("Nothing in \(name)", systemImage: "folder",
                                       description: Text("Move a chat here from its context menu. Folders stay on this iPhone."))
            } else {
                List(items) { conversation in
                    Button { onOpen(conversation) } label: {
                        ConversationRow(conversation: conversation, pinned: app.messaging.isPinned(conversation.id),
                                        draft: app.messaging.draftPreview(for: conversation.id))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: ModulaLayout.contentInset, bottom: 6, trailing: ModulaLayout.contentInset))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("messages.folder.\(name)")
    }
}

struct MoveToFolderSheet: View {
    let ids: [ConversationID]
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if !app.messaging.folderNames.isEmpty {
                    Section("Folders on this iPhone") {
                        ForEach(app.messaging.folderNames, id: \.self) { name in
                            Button(name) { assign(name) }
                        }
                    }
                }
                Section("New folder") {
                    TextField("Folder name", text: $newName)
                        .textInputAutocapitalization(.words)
                    Button("Create and move") { assign(newName) }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    Button("Remove from folder", role: .destructive) { assign(nil) }
                }
            }
            .navigationTitle(ids.count == 1 ? "Move chat" : "Move \(ids.count) chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .modulaSheetStyle()
        .accessibilityIdentifier("messages.folder.sheet")
    }

    private func assign(_ name: String?) {
        for id in ids { app.messaging.setFolder(name, for: id) }
        HapticEngine.shared.play(.confirmation)
        dismiss()
    }
}

struct TimedMuteSheet: View {
    let ids: [ConversationID]
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(MessageMuteDuration.allCases) { duration in
                Button(duration.title) {
                    Task {
                        for id in ids { await app.messaging.mute(id: id, for: duration) }
                        dismiss()
                    }
                }
            }
            .navigationTitle(ids.count == 1 ? "Mute" : "Mute \(ids.count) chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .modulaSheetStyle()
        .accessibilityIdentifier("messages.mute.sheet")
    }
}

// MARK: - Thread search

struct ConversationSearchBar: View {
    @Binding var query: String
    @Binding var scope: MessageThreadSearchScope
    var fromCount: Int
    var total: Int
    var index: Int
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MessagesGlassSearchField(text: $query, prompt: "Search this chat")
                    .focused($focused)
                if total > 0 {
                    Text("\(index + 1)/\(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40)
                    Button(action: onPrevious) { Image(systemName: "chevron.up") }
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("Previous match")
                    Button(action: onNext) { Image(systemName: "chevron.down") }
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("Next match")
                }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("Close search")
            }
            ModulaSegmentedControl(segments: MessageThreadSearchScope.allCases.map { .init(id: $0, title: $0.title) },
                                   selection: $scope, compact: true, accessibilityLabel: "Search in",
                                   identifier: { "messages.thread-search.scope.\($0.title)" })
            Text("Search covers the messages loaded on this device.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
        .onAppear { focused = true }
        .accessibilityIdentifier("messages.thread.search")
    }
}

// MARK: - Recent tokens, GIF sheet, reaction picker

struct MessageRecentTokensRow: View {
    let tokens: [String]
    var onPick: (String) -> Void

    var body: some View {
        if !tokens.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tokens, id: \.self) { token in
                        Button {
                            onPick(token)
                        } label: {
                            recentLabel(token)
                                .frame(minWidth: 36, minHeight: 36)
                                .padding(.horizontal, 6)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: .selection))
                        .modulaGlass(in: Capsule(), interactive: true)
                        .accessibilityLabel("Insert \(token)")
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
            }
            .modulaHorizontalRail()
            .padding(.bottom, 4)
            .accessibilityIdentifier("messages.recentTokens")
        }
    }

    @ViewBuilder
    private func recentLabel(_ token: String) -> some View {
        MessageRecentTokenLabel(token: token)
    }
}

struct MessageGifPickerSheet: View {
    var onPick: (ModulaGif) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ModulaGifPicker(repository: GreenfieldGifRepository(client: app.client), onPick: { gif in
                onPick(gif)
                dismiss()
            })
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
        .accessibilityIdentifier("messages.gif.picker")
    }
}

struct MessageReactionPickerSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Type or paste an emoji", text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($typing)
                        .onSubmit(submitTyped)
                    Button("Add", action: submitTyped)
                        .disabled(extractedEmoji == nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
                        ForEach(PostEmojiReaction.catalog, id: \.0) { item in
                            Button {
                                HapticEngine.shared.play(.selection)
                                onPick(item.0)
                                dismiss()
                            } label: {
                                Text(item.0)
                                    .font(.system(size: 32))
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.1.split(separator: " ").first.map(String.init) ?? item.0)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
        .accessibilityIdentifier("messages.reaction.picker")
    }

    private var extractedEmoji: String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isEmoji else { return nil }
        return String(first)
    }

    private func submitTyped() {
        guard let emoji = extractedEmoji else { return }
        onPick(emoji)
        dismiss()
    }
}

private extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x2F }
    }
}

// MARK: - Reply stack on a source message (loaded messages only)

struct MessageReplyStack: View {
    let count: Int
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text(count == 1 ? "1 reply" : "\(count) replies")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the replies loaded in this chat")
        .accessibilityIdentifier("messages.replyStack")
    }
}

enum MessageReplyGrouping {
    static func counts(in items: [Message]) -> [MessageID: Int] {
        var result: [MessageID: Int] = [:]
        for message in items {
            if let id = message.replyTo?.id, !id.isEmpty {
                result[id, default: 0] += 1
            }
        }
        return result
    }

    static func replies(to id: MessageID, in items: [Message]) -> [Message] {
        items.filter { $0.replyTo?.id == id }
    }
}

// MARK: - Multi-select messages

struct MessageSelectionBar: View {
    let count: Int
    var onCopy: () -> Void
    var onForward: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
            Spacer()
            Text(count == 1 ? "1 selected" : "\(count) selected")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Copy", action: onCopy)
                .disabled(count == 0)
            Button("Forward", action: onForward)
                .disabled(count == 0)
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .frame(minHeight: 48)
        .accessibilityIdentifier("messages.selection.bar")
    }
}

// MARK: - Chat lock (per chat, Face ID / passcode), message reminders, quick reactions (t235u)

/// Chats locked on this iPhone. Unlocks last until the app goes to the background.
@MainActor @Observable
final class ChatLockStore {
    static let shared = ChatLockStore()
    private static let key = "messages.lockedChats.v1"
    private(set) var locked: Set<ConversationID>
    private(set) var unlocked: Set<ConversationID> = []

    private init() {
        locked = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isLocked(_ id: ConversationID) -> Bool { locked.contains(id) }
    func needsUnlock(_ id: ConversationID) -> Bool { locked.contains(id) && !unlocked.contains(id) }

    func setLocked(_ on: Bool, _ id: ConversationID) async -> Bool {
        if !on {
            // Turning it off needs the owner too.
            guard await Self.authenticate(reason: "Remove the lock from this chat") else { return false }
        }
        if on { locked.insert(id); unlocked.insert(id) } else { locked.remove(id) }
        UserDefaults.standard.set(Array(locked), forKey: Self.key)
        return true
    }

    func unlock(_ id: ConversationID) async -> Bool {
        guard await Self.authenticate(reason: "Unlock this chat") else { return false }
        unlocked.insert(id)
        return true
    }

    func relockAll() { unlocked = [] }

    static func authenticate(reason: String) async -> Bool {
        await MessagePrivacyAuth.confirm(reason: reason)
    }

    static var biometryTitle: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }
}

/// Glass cover over a locked chat until Face ID / passcode succeeds.
struct ChatLockOverlay: View {
    let conversationID: ConversationID
    let title: String
    @State private var failed = false
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .symbolEffect(.bounce, value: bounce)
            VStack(spacing: 6) {
                Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                Text("This chat is locked.").font(.subheadline).foregroundStyle(.secondary)
            }
            Button { attempt() } label: {
                Label("Unlock with \(ChatLockStore.biometryTitle)", systemImage: "faceid")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.modulaPrimary)
            if failed {
                Text("Couldn't unlock. Try again.").font(.footnote).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .background(Color(uiColor: .systemBackground).opacity(0.55))
        .ignoresSafeArea()
        .task { attempt() }
        .accessibilityIdentifier("messages.chatLock")
    }

    private func attempt() {
        Task {
            let ok = await ChatLockStore.shared.unlock(conversationID)
            withAnimation(.snappy) { failed = !ok }
            if !ok { bounce += 1; HapticEngine.shared.play(.warning) } else { HapticEngine.shared.play(.success) }
        }
    }
}

/// "Remind me" on a message: a local notification that opens the chat.
@MainActor
enum MessageReminders {
    enum When: String, CaseIterable, Identifiable {
        case twentyMinutes, hour, tonight, tomorrow
        var id: Self { self }
        var title: String {
            switch self {
            case .twentyMinutes: "In 20 minutes"
            case .hour: "In 1 hour"
            case .tonight: "Tonight (20:00)"
            case .tomorrow: "Tomorrow morning (09:00)"
            }
        }
        func date(from now: Date = Date()) -> Date {
            let cal = Calendar.current
            switch self {
            case .twentyMinutes: return now.addingTimeInterval(20 * 60)
            case .hour: return now.addingTimeInterval(3600)
            case .tonight:
                let tonight = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
                return tonight > now ? tonight : now.addingTimeInterval(3 * 3600)
            case .tomorrow:
                let next = cal.date(byAdding: .day, value: 1, to: now) ?? now
                return cal.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next
            }
        }
    }

    static func schedule(_ message: Message, chatTitle: String, when: When, app: AppEnvironment) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                app.navigation.flash("Allow notifications to get reminders", symbol: "bell.slash")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Reminder: \(chatTitle)"
            let text = message.body.text.trimmingCharacters(in: .whitespacesAndNewlines)
            content.body = text.isEmpty ? "A message you wanted to come back to." : String(text.prefix(160))
            content.sound = .default
            content.userInfo = ["modula": ["deepLink": "modula:/" + RouteSerializer.serialize(.messages(.conversation(message.conversationID))),
                                           "conversationId": message.conversationID]]
            let fire = when.date()
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let request = UNNotificationRequest(identifier: "reminder.\(message.id)",
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            do {
                try await center.add(request)
                app.navigation.flash("I'll remind you \(fire.formatted(date: .omitted, time: .shortened))", symbol: "alarm")
            } catch {
                app.navigation.flash("Couldn't set the reminder", symbol: "exclamationmark.triangle")
            }
        }
    }
}

/// Your six hold-to-react emoji (Chats › title menu › Quick Reactions).
enum QuickReactionPrefs {
    static let key = "messages.quickReactions.v1"
    static let defaults = ["❤️", "👍", "😂", "😮", "😢", "🔥"]
    static var current: [String] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        return saved.count == 6 ? saved : defaults
    }
    static func save(_ emoji: [String]) { UserDefaults.standard.set(Array(emoji.prefix(6)), forKey: key) }
}

struct QuickReactionsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picks = QuickReactionPrefs.current
    @State private var slot = 0
    private static let palette = ["❤️", "👍", "😂", "😮", "😢", "🔥", "🙏", "👏", "🎉", "💯", "😍", "🥹", "😅", "🤔", "👀", "😡",
                                  "🤯", "🥳", "😴", "🤝", "💪", "✨", "✅", "❌", "🙌", "😎", "🫶", "💀", "🤣", "😭", "👌", "⚡️"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Tap a slot, then pick an emoji.").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in
                            Button {
                                HapticEngine.shared.play(.selection)
                                withAnimation(.snappy) { slot = i }
                            } label: {
                                Text(picks[i]).font(.system(size: 30))
                                    .scaleEffect(slot == i ? 1.12 : 1)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.primary, lineWidth: slot == i ? 2 : 0)
                                    }
                                    .contentTransition(.opacity)
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                            .accessibilityLabel("Slot \(i + 1), \(picks[i])")
                            .accessibilityAddTraits(slot == i ? .isSelected : [])
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(Self.palette, id: \.self) { emoji in
                            Button {
                                HapticEngine.shared.play(.selection)
                                withAnimation(.snappy) {
                                    if let existing = picks.firstIndex(of: emoji) { picks.swapAt(existing, slot) } else { picks[slot] = emoji }
                                    slot = (slot + 1) % 6
                                }
                            } label: {
                                Text(emoji).font(.system(size: 26)).frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                        }
                    }
                    Button("Restore default") { withAnimation(.snappy) { picks = QuickReactionPrefs.defaults } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .modulaGlass(in: Capsule(), interactive: true)
                }
                .padding(20)
            }
            .navigationTitle("Quick Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    MessagesDoneButton {
                        QuickReactionPrefs.save(picks)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .modulaSheetStyle()
    }
}
