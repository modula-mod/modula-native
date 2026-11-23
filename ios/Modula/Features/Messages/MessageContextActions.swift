import Foundation
import SwiftUI

enum MessageContextActions {
    static func own(
        capabilities: MessagingBackendCapabilities,
        delivery: MessageDeliveryState
    ) -> [ModulaContextAction] {
        var items = [ModulaContextAction(id: "copy", title: "Copy", systemImage: "doc.on.doc"),
                     ModulaContextAction(id: "forward", title: "Forward", systemImage: "arrowshape.turn.up.right"),
                     ModulaContextAction(id: "speak", title: "Read Aloud", systemImage: "speaker.wave.2")]
        if capabilities.reply || capabilities.quoteReply {
            items.append(.init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left"))
        }
        if capabilities.edit {
            items.append(.init(id: "edit", title: "Edit", systemImage: "pencil"))
        }
        if capabilities.deleteOwn {
            items.append(.init(id: "delete", title: "Unsend", systemImage: "arrow.uturn.backward", role: .destructive))
        }
        if delivery == .failed {
            items.append(.init(id: "retry", title: "Retry", systemImage: "arrow.clockwise"))
        }
        return items
    }

    static func other(capabilities: MessagingBackendCapabilities) -> [ModulaContextAction] {
        var items = [ModulaContextAction(id: "copy", title: "Copy", systemImage: "doc.on.doc"),
                     ModulaContextAction(id: "forward", title: "Forward", systemImage: "arrowshape.turn.up.right"),
                     ModulaContextAction(id: "speak", title: "Read Aloud", systemImage: "speaker.wave.2")]
        if capabilities.reply || capabilities.quoteReply {
            items.append(.init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left"))
        }
        if capabilities.report {
            items.append(.init(id: "report", title: "Report", systemImage: "exclamationmark.bubble", role: .destructive))
        }
        return items
    }

    static func conversation(capabilities: MessagingBackendCapabilities) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = []
        if capabilities.mute {
            items.append(.init(id: "mute", title: "Mute", systemImage: "bell.slash"))
        }
        if capabilities.archive {
            items.append(.init(id: "archive", title: "Archive", systemImage: "archivebox"))
        }
        return items
    }
}

enum MessagingFixtures {
    static let now = Date(timeIntervalSince1970: 1_784_000_000)

    static let sophia = ConversationParticipant(
        id: "user-sophia",
        handle: "sophia.chen",
        displayName: "Sophia Chen",
        avatarURL: nil
    )
    static let marcus = ConversationParticipant(
        id: "user-marcus",
        handle: "marcus",
        displayName: "Marcus",
        avatarURL: nil
    )
    static let alex = ConversationParticipant(
        id: "user-alex",
        handle: "alex",
        displayName: "Alex",
        avatarURL: nil
    )
    static let me = ConversationParticipant(
        id: "user-me",
        handle: "me",
        displayName: "You",
        avatarURL: nil
    )

    static let unreadConversation = Conversation(
        id: "convo-sophia",
        kind: .direct,
        participants: [sophia],
        lastMessage: MessagePreview(
            id: "m-s-1",
            body: "Are you still working on the module SDK?",
            sentAt: now.addingTimeInterval(-120),
            senderID: sophia.id
        ),
        unreadCount: 2,
        updatedAt: now.addingTimeInterval(-120),
        titleOverride: nil
    )

    static let readConversation = Conversation(
        id: "convo-marcus",
        kind: .direct,
        participants: [marcus],
        lastMessage: MessagePreview(
            id: "m-m-1",
            body: "Sounds good.",
            sentAt: now.addingTimeInterval(-1260),
            senderID: marcus.id
        ),
        unreadCount: 0,
        updatedAt: now.addingTimeInterval(-1260),
        titleOverride: nil
    )

    static let request = MessageRequest(
        id: "req-alex",
        conversationID: "convo-alex",
        sender: alex,
        preview: "Wants to send you a message.",
        createdAt: now.addingTimeInterval(-3600)
    )

    static func thread(conversationID: ConversationID = "convo-sophia") -> [Message] {
        [
            Message(
                id: "m1",
                conversationID: conversationID,
                sender: sophia,
                body: .text("Are you still working on the module SDK?"),
                sentAt: now.addingTimeInterval(-3600),
                delivery: .sent,
                isOwn: false,
                localDraft: nil
            ),
            Message(
                id: "m2",
                conversationID: conversationID,
                sender: me,
                body: .text("Yes — native messaging is next."),
                sentAt: now.addingTimeInterval(-3000),
                delivery: .sent,
                isOwn: true,
                localDraft: nil
            ),
            Message(
                id: "m3",
                conversationID: conversationID,
                sender: sophia,
                body: .text("Sounds good. See you tomorrow."),
                sentAt: now.addingTimeInterval(-120),
                delivery: .sent,
                isOwn: false,
                localDraft: nil
            ),
            Message(
                id: "m-long",
                conversationID: conversationID,
                sender: sophia,
                body: .text(String(repeating: "This is a long message for Dynamic Type wrapping. ", count: 6)),
                sentAt: now.addingTimeInterval(-60),
                delivery: .sent,
                isOwn: false,
                localDraft: nil
            ),
            Message(
                id: "m-fail",
                conversationID: conversationID,
                sender: me,
                body: .text("This send failed and must be retryable."),
                sentAt: now.addingTimeInterval(-30),
                delivery: .failed,
                isOwn: true,
                localDraft: "This send failed and must be retryable."
            )
        ]
    }
}

#if DEBUG
/// DEBUG-only screenshot seed (`--debug-messages-fixture`). Never compiled into Release,
/// never sent to the server. Times are relative to launch so labels read naturally.
enum MessagingDebugFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--debug-messages-fixture") }
    static let viewerID = "uitest-local-modules"

    static let sophia = ConversationParticipant(id: "fx-sophia", handle: "sophia.chen", displayName: "Sophia Chen", avatarURL: nil)
    static let marcus = ConversationParticipant(id: "fx-marcus", handle: "marcus", displayName: "Marcus Lee", avatarURL: nil)
    static let noor = ConversationParticipant(id: "fx-noor", handle: "noor", displayName: "Noor Haddad", avatarURL: nil)
    static let kai = ConversationParticipant(id: "fx-kai", handle: "kaij", displayName: "Kai Jensen", avatarURL: nil)
    static let me = ConversationParticipant(id: viewerID, handle: "modules", displayName: "You", avatarURL: nil)

    static func requests(now: Date = Date()) -> [MessageRequest] {
        let zoe = ConversationParticipant(id: "fx-zoe", handle: "zoe.adler", displayName: "Zoe Adler", avatarURL: nil)
        let ravi = ConversationParticipant(id: "fx-ravi", handle: "ravi", displayName: "Ravi Patel", avatarURL: nil)
        return [
            MessageRequest(id: "fx-req-zoe", conversationID: nil, sender: zoe,
                           preview: "Hi! Loved your Vault Notes module. Could I ask a couple of questions about the sync?",
                           createdAt: now.addingTimeInterval(-15 * 60)),
            MessageRequest(id: "fx-req-ravi", conversationID: nil, sender: ravi,
                           preview: "Hey, are you open to collaborating on a Moliboo outfit pack?",
                           createdAt: now.addingTimeInterval(-3 * 3600)),
        ]
    }

    static func inbox(now: Date = Date()) -> [Conversation] {
        func c(_ id: String, _ kind: ConversationKind, _ people: [ConversationParticipant], _ body: String, from: String?,
               minutes: Double, unread: Int, title: String? = nil) -> Conversation {
            let at = now.addingTimeInterval(-minutes * 60)
            return Conversation(id: id, kind: kind, participants: people,
                                lastMessage: MessagePreview(id: "\(id)-last", body: body, sentAt: at, senderID: from),
                                unreadCount: unread, updatedAt: at, titleOverride: title)
        }
        return [
            c("fx-sophia", .direct, [sophia], "Are you still working on the module SDK? I have a few ideas for the bridge.", from: sophia.id, minutes: 2, unread: 2),
            c("fx-crew", .group, [marcus, noor, kai], "Shipping the glass header tonight!", from: marcus.id, minutes: 24, unread: 5, title: "Design crew"),
            c("fx-marcus", .direct, [marcus], "Sounds good, see you tomorrow.", from: viewerID, minutes: 70, unread: 0),
            c("fx-noor", .direct, [noor], "Sent you the Vault Notes build notes.", from: noor.id, minutes: 60 * 26, unread: 0),
            c("fx-kai", .direct, [kai], "Haha that Moliboo is adorable", from: kai.id, minutes: 60 * 24 * 4, unread: 0),
        ]
    }

    static func thread(_ id: ConversationID, now: Date = Date()) -> [Message] {
        func m(_ mid: String, _ who: ConversationParticipant, _ text: String, minutes: Double, _ state: MessageDeliveryState = .sent) -> Message {
            Message(id: mid, conversationID: id, sender: who, body: .text(text), sentAt: now.addingTimeInterval(-minutes * 60),
                    delivery: state, isOwn: who.id == viewerID, localDraft: state == .failed ? text : nil)
        }
        let lines = ["Morning!", "Did the build go out?", "Yes, TestFlight is processing.", "Nice — the glass sidebar looks great.",
                     "Can you check the reels scrubber?", "On it.", "Buffered bar shows now.", "Love it"]
        var history: [Message] = []
        for day in stride(from: 5, through: 2, by: -1) {
            for (i, text) in lines.enumerated() {
                history.append(m("h\(day)-\(i)", i.isMultiple(of: 2) ? sophia : me, text, minutes: Double(day * 1440 - i * 7), .read))
            }
        }
        return history + [
            m("t1", sophia, "Hey! Did you see the new Activity tab?", minutes: 60 * 25),
            m("t2", me, "Yes, the glass chips came out really nice.", minutes: 60 * 25 - 2, .read),
            m("t3", sophia, "Are you still working on the module SDK?", minutes: 6),
            m("t4", sophia, "I have a few ideas for the bridge — mostly around permissions.", minutes: 5),
            m("t5", me, "Always. Send them over and I'll take a look tonight.", minutes: 4, .read),
            m("t6", me, "Also: https://modula.digital", minutes: 3, .delivered),
            m("t7", sophia, "Perfect, writing it up now", minutes: 2),
            m("t8", me, "This one didn't go through.", minutes: 1, .failed),
        ]
    }
}
#endif


// MARK: - Hold to react (iMessage-style focus)

/// What the long-pressed bubble hands to the conversation: the message, where its row sits on
/// screen, and the actions its menu offers (reactions come from the bar, not a submenu).
struct MessageFocusRequest: Identifiable, Equatable {
    var id: MessageID { message.id }
    let message: Message
    let position: MessageGroupPosition
    let frame: CGRect
    let actions: [ModulaContextAction]
    let canReact: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.frame == rhs.frame }
}

/// Places the reaction bar above and the menu below the lifted bubble, clamped to the screen.
/// Pure so it can be unit-tested.
enum MessageFocusLayout {
    static let barHeight: CGFloat = 52
    static let rowHeight: CGFloat = 46
    static let gap: CGFloat = 10

    struct Result: Equatable {
        /// Vertical shift applied to the bubble (and the bar/menu attached to it).
        var shift: CGFloat
        /// Height the bubble preview is clipped to (very long messages).
        var bubbleHeight: CGFloat
    }

    static func resolve(bubble: CGRect, menuCount: Int, hasBar: Bool, container: CGRect, safeTop: CGFloat, safeBottom: CGFloat) -> Result {
        let top = container.minY + safeTop + 8
        let bottom = container.maxY - safeBottom - 8
        let menuHeight = CGFloat(menuCount) * rowHeight
        let above = hasBar ? barHeight + gap : 0
        let below = menuCount > 0 ? menuHeight + gap : 0
        let available = max(80, bottom - top - above - below)
        let bubbleHeight = min(bubble.height, available)
        var minY = bubble.minY
        if minY - above < top { minY = top + above }
        if minY + bubbleHeight + below > bottom { minY = bottom - below - bubbleHeight }
        return Result(shift: minY - bubble.minY, bubbleHeight: bubbleHeight)
    }
}

struct MessageFocusOverlay: View {
    let request: MessageFocusRequest
    var currentReaction: String?
    var onSelect: (ModulaContextAction) -> Void
    var onMoreReactions: () -> Void
    var onDismiss: () -> Void

    static let quickReactions = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.frame(in: .global)
            let layout = MessageFocusLayout.resolve(
                bubble: request.frame,
                menuCount: request.actions.count,
                hasBar: request.canReact,
                container: container,
                safeTop: proxy.safeAreaInsets.top,
                safeBottom: proxy.safeAreaInsets.bottom
            )
            let origin = CGPoint(x: request.frame.minX - container.minX, y: request.frame.minY - container.minY + layout.shift)
            let alignment: HorizontalAlignment = request.message.isOwn ? .trailing : .leading
            ZStack(alignment: .topLeading) {
                backdrop
                VStack(alignment: alignment, spacing: MessageFocusLayout.gap) {
                    if request.canReact { reactionBar.scaleEffect(shown ? 1 : 0.6, anchor: request.message.isOwn ? .bottomTrailing : .bottomLeading) }
                    MessageBubble(message: request.message, position: request.position, showsStatus: false, isPreview: true) { _ in }
                        .frame(width: request.frame.width, height: layout.bubbleHeight, alignment: .top)
                        .clipped()
                        .scaleEffect(shown && !reduceMotion ? 1.03 : 1, anchor: request.message.isOwn ? .trailing : .leading)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                        .allowsHitTesting(false)
                    if !request.actions.isEmpty { actionMenu.scaleEffect(shown ? 1 : 0.6, anchor: request.message.isOwn ? .topTrailing : .topLeading) }
                }
                .frame(width: request.frame.width, alignment: request.message.isOwn ? .trailing : .leading)
                .offset(x: origin.x, y: origin.y - (request.canReact ? MessageFocusLayout.barHeight + MessageFocusLayout.gap : 0))
                .opacity(shown ? 1 : 0)
            }
            .frame(width: container.width, height: container.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .onAppear {
            HapticEngine.shared.play(.contextOpen)
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.78)) { shown = true }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .accessibilityAction(.escape) { dismiss() }
        .accessibilityIdentifier("messages.focus")
    }

    private var backdrop: some View {
        Group {
            if reduceTransparency {
                Color.black.opacity(0.55)
            } else {
                Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.18))
            }
        }
        .opacity(shown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityLabel("Close message menu")
        .accessibilityAddTraits(.isButton)
    }

    private var reactionBar: some View {
        HStack(spacing: 2) {
            ForEach(Self.quickReactions, id: \.self) { emoji in
                Button {
                    select(.init(id: "react:\(emoji)", title: emoji))
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 42, height: 42)
                        .background {
                            if currentReaction == emoji { Circle().fill(app.appearance.liveAccent.opacity(0.25)) }
                        }
                }
                .buttonStyle(ModulaPressStyle(scale: 0.85, haptic: .selection))
                .accessibilityLabel(currentReaction == emoji ? "Remove \(emoji) reaction" : "React \(emoji)")
            }
            Button {
                onMoreReactions()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More reactions")
        }
        .padding(.horizontal, 8)
        .frame(height: MessageFocusLayout.barHeight)
        .modulaGlass(in: Capsule(), interactive: true)
        .accessibilityIdentifier("messages.focus.reactions")
    }

    private var actionMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(request.actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    select(action)
                } label: {
                    HStack {
                        Text(action.title)
                        Spacer(minLength: 16)
                        if let symbol = action.systemImage { Image(systemName: symbol) }
                    }
                    .font(.body)
                    .foregroundStyle(action.role == .destructive ? Color.red : Color.primary)
                    .padding(.horizontal, 16)
                    .frame(height: MessageFocusLayout.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("messages.focus.action.\(action.id)")
                if index < request.actions.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .frame(width: 240)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
        .accessibilityIdentifier("messages.focus.menu")
    }

    private func select(_ action: ModulaContextAction) {
        onSelect(action)
        dismiss()
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { shown = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 140))
            onDismiss()
        }
    }
}
