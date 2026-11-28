import SwiftUI
import Translation
import UIKit

// Views for messaging batch 1 (see MessagingExtras.swift). Glass is used for chrome only:
// the pinned bar, chips and toast. Lists and sheets keep normal surfaces.

// MARK: - Pinned messages bar

struct ChatPinnedMessagesBar: View {
    let conversationID: ConversationID
    var onJump: (MessageID) -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var index = 0
    @State private var showAll = false
    private var extras: MessagingExtras { .shared }

    var body: some View {
        let pins = extras.pins(for: conversationID)
        if !pins.isEmpty {
            let current = pins[min(index, pins.count - 1)]
            HStack(spacing: 10) {
                Button {
                    HapticEngine.shared.play(.selection)
                    onJump(current.id)
                    index = pins.count > 1 ? (index + 1) % pins.count : 0
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "pin.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(app.appearance.liveAccent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pins.count > 1 ? "Pinned \(min(index, pins.count - 1) + 1) of \(pins.count) · \(current.senderName)" : "Pinned · \(current.senderName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(app.appearance.liveAccent)
                                .lineLimit(1)
                            Text(current.excerpt.isEmpty ? "Message" : current.excerpt)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pinned message from \(current.senderName): \(current.excerpt)")
                .accessibilityHint(pins.count > 1 ? "Shows this message, then the next pin" : "Shows this message")
                Button {
                    showAll = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All pinned messages")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 6)
            .sheet(isPresented: $showAll) {
                ChatPinnedMessagesList(conversationID: conversationID) { id in
                    showAll = false
                    onJump(id)
                }
                .presentationDetents([.medium, .large])
            }
            .accessibilityIdentifier("messages.pinnedBar")
        }
    }
}

struct ChatPinnedMessagesList: View {
    let conversationID: ConversationID
    var onJump: (MessageID) -> Void
    @Environment(\.dismiss) private var dismiss
    private var extras: MessagingExtras { .shared }

    var body: some View {
        NavigationStack {
            List {
                let pins = extras.pins(for: conversationID)
                if pins.isEmpty {
                    Text("No pinned messages. Long-press a message and choose Pin.")
                        .foregroundStyle(.secondary)
                }
                ForEach(pins) { pin in
                    Button {
                        onJump(pin.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pin.senderName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(pin.excerpt.isEmpty ? "Message" : pin.excerpt).font(.body).foregroundStyle(.primary).lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Unpin", systemImage: "pin.slash", role: .destructive) {
                            extras.unpin(pin.id, in: conversationID)
                        }
                    }
                }
            }
            .navigationTitle("Pinned messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Pins are kept on this iPhone only. Up to \(MessagePinnedStore.perChatLimit) per chat.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

// MARK: - Scheduled messages

struct ChatScheduledChip: View {
    let conversationID: ConversationID
    var onTap: () -> Void
    @Environment(AppEnvironment.self) private var app
    private var extras: MessagingExtras { .shared }

    var body: some View {
        let items = extras.scheduled(for: conversationID)
        if !items.isEmpty {
            let failed = items.contains(where: \.failed)
            Button(action: onTap) {
                Label(failed ? "Scheduled message needs attention" : (items.count == 1 ? "1 scheduled message" : "\(items.count) scheduled messages"),
                      systemImage: failed ? "exclamationmark.circle" : "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(failed ? Color.red : app.appearance.liveAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .selection))
            .modulaGlass(in: Capsule(), interactive: true)
            .frame(minHeight: 44)
            .padding(.bottom, 2)
            .accessibilityIdentifier("messages.scheduledChip")
        }
    }
}

struct ChatScheduleSheet: View {
    let conversationID: ConversationID
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sendAt = Date().addingTimeInterval(60 * 60)
    @State private var error: String?
    private var extras: MessagingExtras { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Message", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityLabel("Message to schedule")
                    DatePicker("Send at", selection: $sendAt,
                               in: Date().addingTimeInterval(MessageScheduleStore.minLead)...Date().addingTimeInterval(MessageScheduleStore.maxLead))
                    Button {
                        schedule()
                    } label: {
                        Label("Schedule", systemImage: "clock.badge.checkmark")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !app.messaging.capabilities.send)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Scheduled messages are kept on this iPhone and sent when the time comes while Modula is open. If Modula is closed, they go out the next time you open it.")
                }
                let items = extras.scheduled(for: conversationID)
                if !items.isEmpty {
                    Section("Scheduled") {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text).lineLimit(3)
                                HStack(spacing: 6) {
                                    if item.failed {
                                        Label("Couldn't send", systemImage: "exclamationmark.circle").foregroundStyle(.red)
                                    } else {
                                        Label(item.sendAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .swipeActions {
                                Button("Cancel", systemImage: "trash", role: .destructive) { extras.cancelScheduled(item.id) }
                                if item.failed {
                                    Button("Retry", systemImage: "arrow.clockwise") {
                                        extras.retryScheduled(item.id)
                                        Task { await extras.dispatchDue(using: app.messaging) }
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Send now", systemImage: "paperplane") {
                                    Task {
                                        if await app.messaging.sendPrepared(text: item.text, conversation: conversationID) {
                                            extras.cancelScheduled(item.id)
                                        }
                                    }
                                }
                                Button("Cancel", systemImage: "trash", role: .destructive) { extras.cancelScheduled(item.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .onAppear {
            if text.isEmpty { text = app.messaging.drafts[conversationID] ?? "" }
        }
    }

    private func schedule() {
        let result = extras.schedule(text: text, at: sendAt, in: conversationID)
        if result == .ok {
            HapticEngine.shared.play(.confirmation)
            if (app.messaging.drafts[conversationID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                app.messaging.drafts[conversationID] = ""
            }
            text = ""
            error = nil
            extras.show("Message scheduled")
        } else {
            error = result.message
        }
    }
}

/// Sends due scheduled messages while a messaging screen is on screen and the app is active.
struct MessagingScheduleDispatcher: ViewModifier {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await MessagingExtras.shared.dispatchDue(using: app.messaging)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

extension View {
    func messagingScheduleDispatcher() -> some View { modifier(MessagingScheduleDispatcher()) }

    /// Small glass toast for local chat tools (pinned, reminder set, scheduled).
    func messagingExtrasToast() -> some View { modifier(MessagingExtrasToastModifier()) }
}

private struct MessagingExtrasToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = MessagingExtras.shared.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
                    .onAppear { UIAccessibility.post(notification: .announcement, argument: toast) }
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: MessagingExtras.shared.toast)
    }
}

// MARK: - Quick replies

struct MessageQuickReplySuggestions: View {
    let composerText: String
    var onPick: (String) -> Void
    private var extras: MessagingExtras { .shared }

    var body: some View {
        if let matches = MessageQuickReplyStore.matches(for: composerText, in: extras.quickReplies), !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                ModulaGlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        ForEach(matches, id: \.self) { reply in
                            Button {
                                HapticEngine.shared.play(.selection)
                                onPick(reply)
                            } label: {
                                Text(reply)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                            .modulaGlass(in: Capsule(), interactive: true)
                            .accessibilityLabel("Quick reply: \(reply)")
                            .accessibilityHint("Puts this reply in the message box")
                        }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                }
            }
            .scrollClipDisabled()
            .frame(minHeight: 44)
            .padding(.top, 6)
            .accessibilityIdentifier("messages.quickReplies")
        }
    }
}

struct QuickRepliesManagerView: View {
    @State private var newReply = ""
    private var extras: MessagingExtras { .shared }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New quick reply", text: $newReply)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(minHeight: 44)
                }
            } footer: {
                Text("Type / in any chat to pick one. Saved on this iPhone, up to \(MessageQuickReplyStore.limit).")
            }
            Section("Your quick replies") {
                ForEach(extras.quickReplies, id: \.self) { reply in
                    Text(reply).frame(minHeight: 44, alignment: .leading)
                }
                .onDelete { extras.removeQuickReplies(at: $0) }
                .onMove { extras.moveQuickReplies(from: $0, to: $1) }
            }
        }
        .navigationTitle("Quick replies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func add() {
        extras.addQuickReply(newReply)
        newReply = ""
        HapticEngine.shared.play(.confirmation)
    }
}

// MARK: - Select text, share

struct IdentifiedMessageText: Identifiable {
    let id = UUID()
    let text: String
}

struct MessageTextSelectionSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ModulaLayout.contentInset)
            }
            .navigationTitle("Select text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy all") {
                        UIPasteboard.general.string = text
                        HapticEngine.shared.play(.confirmation)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct MessageActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Chat info section

struct ChatToolsSection<Row: View>: View {
    let conversationID: ConversationID
    var title: String
    var exportText: () -> String
    var onSchedule: () -> Void
    @ViewBuilder var row: (String, String, String?, Bool) -> Row
    @Environment(AppEnvironment.self) private var app
    private var extras: MessagingExtras { .shared }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSchedule) {
                let count = extras.scheduled(for: conversationID).count
                row("Scheduled messages", "clock", count == 0 ? "None" : "\(count)", true)
            }
            .buttonStyle(.plain)
            .disabled(!app.messaging.capabilities.send)
            Divider().padding(.leading, 44)
            NavigationLink {
                QuickRepliesManagerView()
            } label: {
                row("Quick replies", "bolt", "\(extras.quickReplies.count)", true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            ShareLink(item: exportText(), subject: Text("Chat with \(title)")) {
                row("Export chat", "square.and.arrow.up", nil, false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shares the messages loaded on this iPhone as text")
            Divider().padding(.leading, 44)
            row("Disappearing messages", "timer", "Coming soon", false)
                .opacity(0.55)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Not available yet")
        }
    }
}

// MARK: - Conversation presenter

/// Everything batch 1 adds to a chat screen, kept in one modifier so ConversationView's
/// body stays small for the type checker.
struct ConversationExtrasPresenter: ViewModifier {
    let conversationID: ConversationID
    @Binding var selectingText: IdentifiedMessageText?
    @Binding var sharingText: IdentifiedMessageText?
    @Binding var showTranslate: Bool
    var translateText: String
    @Binding var showSchedule: Bool

    func body(content: Content) -> some View {
        content
            .sheet(item: $selectingText) { item in MessageTextSelectionSheet(text: item.text) }
            .sheet(item: $sharingText) { item in
                MessageActivitySheet(items: [item.text])
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSchedule) { ChatScheduleSheet(conversationID: conversationID) }
            .translationPresentation(isPresented: $showTranslate, text: translateText)
            .messagingScheduleDispatcher()
            .messagingExtrasToast()
            .onAppear { MessagingExtras.shared.clearUnreadMark(conversationID) }
            .onChange(of: conversationID) { _, id in MessagingExtras.shared.clearUnreadMark(id) }
    }
}

/// Top-of-thread chrome: pinned messages and scheduled messages.
struct ConversationExtrasHeader: View {
    let conversationID: ConversationID
    var onJump: (MessageID) -> Void
    var onScheduled: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChatPinnedMessagesBar(conversationID: conversationID, onJump: onJump)
            ChatScheduledChip(conversationID: conversationID, onTap: onScheduled)
        }
    }
}

enum MessageExtraActions {
    /// Extra long-press actions for a bubble. All local or on-device (Apple Translation).
    @MainActor static func items(for message: Message, local: Bool) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = []
        let hasText = !message.body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.kind != .voice
        if !local {
            let pinned = MessagingExtras.shared.isMessagePinned(message.id, in: message.conversationID)
            items.append(.init(id: "pinMessage", title: pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin"))
        }
        if hasText {
            items.append(.init(id: "selectText", title: "Select Text", systemImage: "selection.pin.in.out"))
            items.append(.init(id: "translate", title: "Translate", systemImage: "translate"))
            items.append(.init(id: "shareMessage", title: "Share", systemImage: "square.and.arrow.up"))
        }
        if !local {
            items.append(.init(id: "remind", title: "Remind Me", systemImage: "bell.badge",
                               children: MessageReminderOption.allCases.map { ModulaContextAction(id: "remind:\($0.rawValue)", title: $0.title) }))
        }
        return items
    }
}
