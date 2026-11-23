import LocalAuthentication
import Photos
import SwiftUI
import UIKit

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
    case all, links, images, starred
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .links: "Links"
        case .images: "Images"
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
                        .tint(app.appearance.liveAccent)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MessageThreadSearchScope.allCases) { item in
                        let on = item == scope
                        Button {
                            scope = item
                        } label: {
                            Text(item.title)
                                .font(.caption.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 32)
                                .background(on ? app.appearance.liveAccent.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
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
            .padding(.bottom, 4)
            .accessibilityIdentifier("messages.recentTokens")
        }
    }

    @ViewBuilder
    private func recentLabel(_ token: String) -> some View {
        if let sticker = ModulaLocalSticker.extract(token).stickers.first {
            Text(sticker.label).font(.caption)
        } else {
            Text(token).font(.title3)
        }
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
