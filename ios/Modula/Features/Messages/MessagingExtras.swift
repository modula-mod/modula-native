import Foundation
import Observation
import UserNotifications

// Messaging batch 1: device-local chat tools. None of these call a new server route.
// Pinned messages, manual unread marks, quick replies and reminders live only on this iPhone.
// Scheduled messages are held on this iPhone and then sent with the real
// `POST /v1/conversations/:id/messages` route (via `MessagingStore.sendPrepared`).

// MARK: - Pinned messages (per chat, local)

struct PinnedChatMessage: Codable, Hashable, Sendable, Identifiable {
    var id: MessageID
    var conversationID: ConversationID
    var excerpt: String
    var senderName: String
    var pinnedAt: Date
}

enum MessagePinnedStore {
    static let key = "messages.pinnedMessages.v1"
    static let perChatLimit = 3
    static let excerptLength = 140

    static func load(_ defaults: UserDefaults = .standard) -> [ConversationID: [PinnedChatMessage]] {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode([ConversationID: [PinnedChatMessage]].self, from: data) else { return [:] }
        return value
    }

    static func save(_ value: [ConversationID: [PinnedChatMessage]], _ defaults: UserDefaults = .standard) {
        let trimmed = value.filter { !$0.value.isEmpty }
        if trimmed.isEmpty { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(trimmed) { defaults.set(data, forKey: key) }
    }

    /// Pins (newest first) or unpins. A fourth pin drops the oldest one.
    static func toggling(_ pin: PinnedChatMessage, in all: [ConversationID: [PinnedChatMessage]]) -> [ConversationID: [PinnedChatMessage]] {
        var all = all
        var items = all[pin.conversationID] ?? []
        if items.contains(where: { $0.id == pin.id }) {
            items.removeAll { $0.id == pin.id }
        } else {
            items.insert(pin, at: 0)
            if items.count > perChatLimit { items = Array(items.prefix(perChatLimit)) }
        }
        all[pin.conversationID] = items.isEmpty ? nil : items
        return all
    }

    static func excerpt(_ text: String) -> String {
        let plain = MessagePreviewText.plain(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.count <= excerptLength { return plain }
        return String(plain.prefix(excerptLength - 1)) + "…"
    }
}

// MARK: - Manual "Mark as unread" (local)

enum MessageManualUnreadStore {
    static let key = "messages.manualUnread.v1"
    static func load(_ defaults: UserDefaults = .standard) -> Set<ConversationID> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
    static func save(_ ids: Set<ConversationID>, _ defaults: UserDefaults = .standard) {
        if ids.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(ids.sorted(), forKey: key) }
    }
}

// MARK: - Scheduled messages (held locally, sent with the real send route)

struct ScheduledChatMessage: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var conversationID: ConversationID
    var text: String
    var sendAt: Date
    var createdAt: Date
    var attempts: Int = 0
    var failed = false
}

enum ScheduleValidation: Equatable, Sendable {
    case ok, empty, tooLong, tooSoon, tooFar, queueFull

    var message: String? {
        switch self {
        case .ok: nil
        case .empty: "Write a message to schedule."
        case .tooLong: "That message is too long to schedule."
        case .tooSoon: "Pick a time at least a minute from now."
        case .tooFar: "You can schedule up to 30 days ahead."
        case .queueFull: "You already have the most scheduled messages allowed."
        }
    }
}

enum MessageScheduleStore {
    static let key = "messages.scheduled.v1"
    static let maxPending = 50
    static let maxLength = 4000
    static let minLead: TimeInterval = 60
    static let maxLead: TimeInterval = 30 * 24 * 60 * 60
    static let maxAttempts = 3

    static func load(_ defaults: UserDefaults = .standard) -> [ScheduledChatMessage] {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode([ScheduledChatMessage].self, from: data) else { return [] }
        return value.sorted { $0.sendAt < $1.sendAt }
    }

    static func save(_ items: [ScheduledChatMessage], _ defaults: UserDefaults = .standard) {
        if items.isEmpty { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }

    static func validate(text: String, sendAt: Date, now: Date, pendingCount: Int) -> ScheduleValidation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxLength { return .tooLong }
        if sendAt.timeIntervalSince(now) < minLead { return .tooSoon }
        if sendAt.timeIntervalSince(now) > maxLead { return .tooFar }
        if pendingCount >= maxPending { return .queueFull }
        return .ok
    }

    /// Messages whose time has come and that have not given up after repeated failures.
    static func due(_ items: [ScheduledChatMessage], now: Date) -> [ScheduledChatMessage] {
        items.filter { !$0.failed && $0.sendAt <= now }.sorted { $0.sendAt < $1.sendAt }
    }
}

// MARK: - Quick replies (local text snippets, "/" in the composer)

enum MessageQuickReplyStore {
    static let key = "messages.quickReplies.v1"
    static let limit = 20
    static let maxLength = 500
    static let defaults = ["On my way!", "Sounds good 👍", "Can I call you later?", "Thanks so much!", "Running 5 minutes late"]

    static func load(_ store: UserDefaults = .standard) -> [String] {
        store.stringArray(forKey: key) ?? defaults
    }

    static func save(_ items: [String], _ store: UserDefaults = .standard) {
        store.set(Array(items.prefix(limit)), forKey: key)
    }

    /// Adds to the front, ignoring blanks and case-insensitive duplicates.
    static func adding(_ raw: String, to items: [String]) -> [String] {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard !text.isEmpty else { return items }
        var next = items.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        next.insert(text, at: 0)
        return Array(next.prefix(limit))
    }

    /// Composer text that starts with "/" filters quick replies; nil when the shortcut isn't active.
    static func matches(for composerText: String, in items: [String]) -> [String]? {
        guard composerText.hasPrefix("/"), !composerText.contains("\n") else { return nil }
        let needle = composerText.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty { return items }
        return items.filter { $0.lowercased().contains(needle) }
    }
}

// MARK: - Message reminders (local notifications)

enum MessageReminderOption: String, CaseIterable, Identifiable, Sendable {
    case in20Minutes, in1Hour, in3Hours, tomorrowMorning
    var id: String { rawValue }

    var title: String {
        switch self {
        case .in20Minutes: "In 20 minutes"
        case .in1Hour: "In 1 hour"
        case .in3Hours: "In 3 hours"
        case .tomorrowMorning: "Tomorrow at 9 AM"
        }
    }

    func fireDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .in20Minutes: return now.addingTimeInterval(20 * 60)
        case .in1Hour: return now.addingTimeInterval(60 * 60)
        case .in3Hours: return now.addingTimeInterval(3 * 60 * 60)
        case .tomorrowMorning:
            let start = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}

enum MessageReminderPlanner {
    static func identifier(for messageID: MessageID) -> String { "messages.reminder.\(messageID)" }

    /// Opening the reminder goes back to the chat through the normal deep link handling.
    static func deepLink(for conversationID: ConversationID) -> String {
        let path = RouteSerializer.serialize(.messages(.conversation(conversationID)))
        return "modula://" + (path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }

    static func content(messageText: String, senderName: String, chatTitle: String, conversationID: ConversationID) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(chatTitle)"
        let excerpt = MessagePinnedStore.excerpt(messageText)
        content.body = excerpt.isEmpty ? "A message from \(senderName)" : "\(senderName): \(excerpt)"
        content.sound = .default
        content.userInfo = ["modula": ["deepLink": deepLink(for: conversationID), "conversationId": conversationID]]
        return content
    }

    static func seconds(until date: Date, now: Date) -> TimeInterval { max(5, date.timeIntervalSince(now)) }
}

// MARK: - Chat export

enum ChatTranscriptExporter {
    static func transcript(title: String, messages: [Message], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        var lines = ["Chat with \(title)", "Exported from Modula · \(messages.count) messages", ""]
        for message in messages {
            let who = message.isOwn ? "You" : message.sender.displayName
            let body: String
            if message.isDeleted { body = "(unsent)" }
            else if message.kind == .voice { body = "(voice note)" }
            else { body = message.body.text }
            lines.append("[\(formatter.string(from: message.sentAt))] \(who): \(body)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Observable state

@MainActor @Observable
final class MessagingExtras {
    static let shared = MessagingExtras()

    private let defaults: UserDefaults
    private(set) var pinnedMessages: [ConversationID: [PinnedChatMessage]]
    private(set) var manualUnreadIDs: Set<ConversationID>
    private(set) var scheduled: [ScheduledChatMessage]
    private(set) var quickReplies: [String]
    var toast: String?
    private var dispatching = false
    private var toastTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedMessages = MessagePinnedStore.load(defaults)
        manualUnreadIDs = MessageManualUnreadStore.load(defaults)
        scheduled = MessageScheduleStore.load(defaults)
        quickReplies = MessageQuickReplyStore.load(defaults)
    }

    // Pins
    func pins(for id: ConversationID) -> [PinnedChatMessage] { pinnedMessages[id] ?? [] }
    func isMessagePinned(_ messageID: MessageID, in id: ConversationID) -> Bool {
        pins(for: id).contains { $0.id == messageID }
    }

    func togglePin(_ message: Message, now: Date = Date()) {
        let wasPinned = isMessagePinned(message.id, in: message.conversationID)
        let pin = PinnedChatMessage(
            id: message.id,
            conversationID: message.conversationID,
            excerpt: MessagePinnedStore.excerpt(message.kind == .voice ? "Voice note" : message.body.text),
            senderName: message.isOwn ? "You" : message.sender.displayName,
            pinnedAt: now
        )
        pinnedMessages = MessagePinnedStore.toggling(pin, in: pinnedMessages)
        MessagePinnedStore.save(pinnedMessages, defaults)
        show(wasPinned ? "Unpinned" : "Pinned in this chat")
    }

    func unpin(_ messageID: MessageID, in id: ConversationID) {
        var items = pins(for: id)
        items.removeAll { $0.id == messageID }
        pinnedMessages[id] = items.isEmpty ? nil : items
        MessagePinnedStore.save(pinnedMessages, defaults)
    }

    // Manual unread
    func isMarkedUnread(_ id: ConversationID) -> Bool { manualUnreadIDs.contains(id) }
    func markUnread(_ id: ConversationID) {
        manualUnreadIDs.insert(id)
        MessageManualUnreadStore.save(manualUnreadIDs, defaults)
    }
    func clearUnreadMark(_ id: ConversationID) {
        guard manualUnreadIDs.remove(id) != nil else { return }
        MessageManualUnreadStore.save(manualUnreadIDs, defaults)
    }

    // Scheduled
    func scheduled(for id: ConversationID) -> [ScheduledChatMessage] {
        scheduled.filter { $0.conversationID == id }.sorted { $0.sendAt < $1.sendAt }
    }

    @discardableResult
    func schedule(text: String, at date: Date, in id: ConversationID, now: Date = Date()) -> ScheduleValidation {
        let pending = scheduled.filter { !$0.failed }.count
        let result = MessageScheduleStore.validate(text: text, sendAt: date, now: now, pendingCount: pending)
        guard result == .ok else { return result }
        scheduled.append(ScheduledChatMessage(
            id: UUID().uuidString,
            conversationID: id,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sendAt: date,
            createdAt: now
        ))
        scheduled.sort { $0.sendAt < $1.sendAt }
        MessageScheduleStore.save(scheduled, defaults)
        return .ok
    }

    func cancelScheduled(_ itemID: String) {
        scheduled.removeAll { $0.id == itemID }
        MessageScheduleStore.save(scheduled, defaults)
    }

    func retryScheduled(_ itemID: String) {
        guard let index = scheduled.firstIndex(where: { $0.id == itemID }) else { return }
        scheduled[index].failed = false
        scheduled[index].attempts = 0
        if scheduled[index].sendAt > Date() { scheduled[index].sendAt = Date() }
        MessageScheduleStore.save(scheduled, defaults)
    }

    /// Sends every due message with the given sender (production: `MessagingStore.sendPrepared`).
    @discardableResult
    func dispatchDue(now: Date = Date(), send: (String, ConversationID) async -> Bool) async -> Int {
        guard !dispatching else { return 0 }
        dispatching = true
        defer { dispatching = false }
        var sent = 0
        for item in MessageScheduleStore.due(scheduled, now: now) {
            let ok = await send(item.text, item.conversationID)
            guard let index = scheduled.firstIndex(where: { $0.id == item.id }) else { continue }
            if ok {
                scheduled.remove(at: index)
                sent += 1
            } else {
                scheduled[index].attempts += 1
                if scheduled[index].attempts >= MessageScheduleStore.maxAttempts { scheduled[index].failed = true }
            }
        }
        MessageScheduleStore.save(scheduled, defaults)
        if sent > 0 { show(sent == 1 ? "Scheduled message sent" : "\(sent) scheduled messages sent") }
        return sent
    }

    func dispatchDue(using messaging: MessagingStore) async {
        guard messaging.capabilities.send, !scheduled.isEmpty else { return }
        await dispatchDue { text, id in await messaging.sendPrepared(text: text, conversation: id) }
    }

    // Quick replies
    func addQuickReply(_ text: String) {
        quickReplies = MessageQuickReplyStore.adding(text, to: quickReplies)
        MessageQuickReplyStore.save(quickReplies, defaults)
    }
    func removeQuickReplies(at offsets: IndexSet) {
        quickReplies = quickReplies.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        MessageQuickReplyStore.save(quickReplies, defaults)
    }
    func moveQuickReplies(from source: IndexSet, to destination: Int) {
        var items = quickReplies
        let moving = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) { items.remove(at: index) }
        let before = source.filter { $0 < destination }.count
        items.insert(contentsOf: moving, at: max(0, min(items.count, destination - before)))
        quickReplies = items
        MessageQuickReplyStore.save(quickReplies, defaults)
    }

    // Reminders
    func remind(about message: Message, chatTitle: String, option: MessageReminderOption, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            show("Turn on notifications for Modula to get reminders")
            return
        }
        let content = MessageReminderPlanner.content(
            messageText: message.kind == .voice ? "Voice note" : message.body.text,
            senderName: message.isOwn ? "You" : message.sender.displayName,
            chatTitle: chatTitle,
            conversationID: message.conversationID
        )
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: MessageReminderPlanner.seconds(until: option.fireDate(from: now), now: now), repeats: false
        )
        let request = UNNotificationRequest(identifier: MessageReminderPlanner.identifier(for: message.id), content: content, trigger: trigger)
        do {
            try await center.add(request)
            show("Reminder set · \(option.title.lowercased())")
        } catch {
            show("Couldn't set the reminder")
        }
    }

    // Toast
    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
