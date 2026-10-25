import SwiftUI

/// Modula's share sheet: preview, recent chats, quick actions, and the system sheet under "More".
struct ModulaShareSheet: View {
    let payload: SharePayload
    /// Richer code card for a profile (verified badge, avatar) than the payload alone carries.
    var codeSubject: ModulaCodeSubject? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var showCollectionPicker = false
    @State private var showPeoplePicker = false
    @State private var peopleMode: PeoplePickerMode = .message
    @State private var copied = false
    @State private var showCode = false
    @State private var post: SocialPost?

    private var reduceMotion: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }
    private var accent: Color { app.appearance.accent.color }

    private var destinations: [ShareDestination] {
        ShareDestinationRegistry.destinations(
            for: payload,
            messagingSend: app.messaging.capabilities.send,
            inMailCompose: app.inMail.capabilities.send,
            collectionsAvailable: app.collections.capabilities.localCollections
        )
    }

    private func has(_ kind: ShareDestinationKind) -> Bool { destinations.contains { $0.kind == kind } }

    /// Most recent direct and group chats — the "send to" row.
    private var recentChats: [Conversation] {
        guard app.messaging.capabilities.send else { return [] }
        return Array(app.messaging.visibleConversations.filter { $0.kind != .request }.prefix(12))
    }

    private var canRepost: Bool {
        if case .post = payload { return app.postActions.capabilities.repost && post != nil }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ShareHeroPreview(payload: payload, post: post)
                    // Only when there are chats to show; Message still opens the people picker.
                    if !recentChats.isEmpty { sendToRow }
                    quickActions
                    linkRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .modulaSoftScrollEdge()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityIdentifier("share.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await app.messaging.loadInboxIfNeeded()
            if case .post(let id, _, _, _) = payload, post == nil {
                post = try? await app.postActions.loadPost(id: id)
            }
        }
        .sheet(isPresented: $showCode) {
            ModulaCodeView(subject: codeSubject ?? ModulaCodeSubject(payload: payload)) { showCode = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCollectionPicker) {
            if case .post(let id, _, _, _) = payload {
                CollectionPicker(postID: id)
            }
        }
        .sheet(isPresented: $showPeoplePicker) {
            PeoplePicker(mode: peopleMode, selectionLimit: 1) { people in
                guard let person = people.first else { return }
                switch peopleMode {
                case .message:
                    if let chat = app.messaging.visibleConversations.first(where: { chat in
                        chat.kind == .direct && chat.participants.contains { $0.id == person.id || $0.handle == person.handle }
                    }) {
                        send(to: chat)
                    } else {
                        UIPasteboard.general.string = ShareCoordinator.messageBodyFallback(for: payload)
                        dismiss()
                        app.navigation.open(.messages(.new))
                        app.navigation.flash("Link copied — paste it to \(person.displayName)", symbol: "bubble.left")
                    }
                case .inMail:
                    var draft = ShareCoordinator.inMailPrefill(for: payload)
                    draft.toHandle = person.handle ?? person.id
                    app.inMail.draft = draft
                    dismiss()
                    app.navigation.open(.messages(.inMail(.compose)))
                case .share:
                    break
                }
            }
        }
        .accessibilityIdentifier("share.universal")
    }

    // MARK: Send to

    private var sendToRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send to")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ShareBubble(title: "Search", accent: accent) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 58, height: 58)
                            .modulaGlass(in: Circle(), interactive: true)
                    } action: {
                        peopleMode = .message
                        showPeoplePicker = true
                        HapticEngine.shared.play(.selection)
                    }
                    .accessibilityIdentifier("share.sendTo.search")
                    ForEach(recentChats) { chat in
                        let person = chat.participants.first
                        ShareBubble(title: chat.title, accent: accent) {
                            ModulaAvatar(initials: person?.initials ?? String(chat.title.prefix(1)), url: person?.avatarURL, size: 58, name: chat.title)
                                .overlay(alignment: .bottomTrailing) {
                                    if chat.kind == .group {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(4)
                                            .background(accent, in: Circle())
                                    }
                                }
                        } action: {
                            send(to: chat)
                        }
                        .accessibilityHint("Opens the chat with this link ready to send")
                    }
                    if recentChats.isEmpty {
                        Text("Your recent chats show up here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(height: 58)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    /// Prefills the chat's draft with the link and opens it — the user still taps Send.
    private func send(to chat: Conversation) {
        HapticEngine.shared.play(.confirmation)
        let link = ShareCoordinator.messageBodyFallback(for: payload)
        let existing = (app.messaging.drafts[chat.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        app.messaging.drafts[chat.id] = existing.isEmpty ? link : existing + "\n" + link
        dismiss()
        app.navigation.open(.messages(.conversation(chat.id)))
    }

    // MARK: Quick actions

    private var quickActions: some View {
        // One swipeable row so every action is visible at the half-height detent.
        return ScrollView(.horizontal, showsIndicators: false) {
        ModulaGlassGroup(spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                ShareActionTile(title: copied ? "Copied" : "Copy Link", symbol: copied ? "checkmark" : "link", accent: accent, highlighted: copied) {
                    copyLink()
                }
                .accessibilityIdentifier("share.destination.copyLink")
                if has(.qr) {
                    ShareActionTile(title: "QR Code", symbol: "qrcode", accent: accent) {
                        HapticEngine.shared.play(.selection)
                        showCode = true
                    }
                    .accessibilityIdentifier("share.destination.qr")
                }
                if canRepost, let post {
                    let reposted = app.postActions.resolved(post).reposted
                    ShareActionTile(title: reposted ? "Reposted" : "Repost", symbol: "arrow.2.squarepath", accent: accent, highlighted: reposted) {
                        Task { await app.postActions.toggleRepost(post) }
                    }
                    .accessibilityIdentifier("share.destination.repost")
                }
                if has(.saveToCollection) {
                    ShareActionTile(title: "Save", symbol: "rectangle.stack.badge.plus", accent: accent) {
                        HapticEngine.shared.play(.selection)
                        showCollectionPicker = true
                    }
                    .accessibilityIdentifier("share.destination.saveToCollection")
                }
                if has(.messages) {
                    ShareActionTile(title: "Message", symbol: "bubble.left.and.bubble.right", accent: accent) {
                        peopleMode = .message
                        showPeoplePicker = true
                        HapticEngine.shared.play(.selection)
                    }
                    .accessibilityIdentifier("share.destination.messages")
                }
                if has(.inMail) {
                    ShareActionTile(title: "In-Mail", symbol: "envelope", accent: accent) {
                        peopleMode = .inMail
                        showPeoplePicker = true
                        HapticEngine.shared.play(.selection)
                    }
                    .accessibilityIdentifier("share.destination.inMail")
                }
                ShareLink(item: payload.canonicalURL, subject: Text(payload.title), message: Text(payload.title)) {
                    ShareActionTileLabel(title: "More", symbol: "ellipsis", accent: accent, highlighted: false)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { HapticEngine.shared.play(.lightImpact) })
                .accessibilityLabel("More sharing options")
                .accessibilityIdentifier("share.destination.systemShare")
            }
            .padding(.vertical, 2)
        }
        }
        .scrollClipDisabled()
    }

    private var linkRow: some View {
        Button(action: copyLink) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
                Text(payload.canonicalURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(copied ? "Copied" : "Copy")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true)
        .accessibilityLabel("Copy link \(payload.canonicalURL.absoluteString)")
        .accessibilityIdentifier("share.link")
    }

    private func copyLink() {
        UIPasteboard.general.string = ShareCoordinator.copyLink(payload)
        HapticEngine.shared.play(.confirmation)
        withAnimation(reduceMotion ? nil : .snappy) { copied = true }
        ModulaToastCenter.shared.show("Link copied", symbol: "link", tone: .info)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(reduceMotion ? nil : .snappy) { copied = false }
        }
    }
}

/// Round avatar/glyph with a name under it (Send to row).
private struct ShareBubble<Glyph: View>: View {
    let title: String
    var accent: Color
    @ViewBuilder var glyph: () -> Glyph
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                glyph()
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 66)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Quick-action tile: round Liquid Glass glyph with a label.
private struct ShareActionTile: View {
    let title: String
    let symbol: String
    var accent: Color
    var highlighted = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ShareActionTileLabel(title: title, symbol: symbol, accent: accent, highlighted: highlighted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct ShareActionTileLabel: View {
    let title: String
    let symbol: String
    var accent: Color
    var highlighted: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(highlighted ? Color.white : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 58, height: 58)
                .modulaGlass(in: Circle(), interactive: true, tint: highlighted ? accent : nil, prominent: highlighted)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 74)
        .contentShape(Rectangle())
    }
}

/// Rich preview card at the top of the share sheet.
private struct ShareHeroPreview: View {
    let payload: SharePayload
    var post: SocialPost?
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 14) {
            glyph
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(app.appearance.accent.color)
                Text(payload.title)
                    .font(.headline)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, specular: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Share preview, \(payload.title)")
        .accessibilityIdentifier("share.preview")
    }

    private var kind: String {
        switch payload {
        case .profile: "Profile"
        case .post: "Post"
        case .module: "Module"
        case .link: "Link"
        }
    }

    private var detail: String? {
        switch payload {
        case .profile(_, _, let handle, _): handle.map { "@\($0)" }
        case .post(_, let author, _, _): (post?.author?.displayName ?? author).map { "by \($0)" }
        case .module(_, _, let publisher): publisher
        case .link(let url, _): url.host
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch payload {
        case .profile(_, let name, _, let avatarURL):
            ModulaAvatar(initials: String((name ?? payload.title).prefix(1)).uppercased(), url: avatarURL, size: 60)
        case .post(_, _, _, let hasMedia):
            if let author = post?.author {
                ModulaAvatar(initials: String(author.displayName.prefix(1)), url: author.avatarURL, size: 60)
            } else {
                tile(hasMedia ? "photo" : "text.alignleft")
            }
        case .module:
            tile("shippingbox")
        case .link:
            tile("safari")
        }
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(app.appearance.accent.color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Kept for callers/tests that still reference the old list preview.
struct SharePreview: View {
    let payload: SharePayload
    var body: some View { ShareHeroPreview(payload: payload) }
}

typealias ModulaSharePreview = SharePreview
typealias ModulaShareDestination = ShareDestination

struct ShareDestinationRow: View {
    let destination: ShareDestination
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: destination.icon.systemName)
            }
        }
        .accessibilityLabel(destination.title)
        .accessibilityHint(destination.subtitle ?? "")
        .accessibilityIdentifier("share.destination.\(destination.kind.rawValue)")
    }
}

typealias ModulaShareActionRow = ShareDestinationRow

enum PeoplePickerMode: Sendable {
    case message
    case inMail
    case share
}

struct PeoplePickerPerson: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let handle: String?
}

struct PeoplePicker: View {
    var mode: PeoplePickerMode
    var selectionLimit: Int = 1
    var onSelect: ([PeoplePickerPerson]) -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<String> = []

    /// Device-local recent recipients — IDs only, never message content.
    @State private var recentIDs: [String] = PeopleRecentsStore.load()

    private var results: [PeoplePickerPerson] {
        // Reuse Discover/profile search surfaces — no new people API.
        let fromList = app.discover.people.items
        let fromDashboard = app.discover.trending.dashboard?.people ?? []
        let merged = fromList.isEmpty ? fromDashboard : fromList
        let mapped = merged.map {
            PeoplePickerPerson(id: $0.id, displayName: $0.displayName, handle: $0.handle)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return mapped }
        return mapped.filter {
            $0.displayName.lowercased().contains(trimmed)
                || ($0.handle?.lowercased().contains(trimmed) ?? false)
        }
    }

    private var recentPeople: [PeoplePickerPerson] {
        let all = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        return recentIDs.compactMap { all[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ModulaSearchField(text: $query, prompt: "Search people")
                }
                if query.isEmpty, !recentPeople.isEmpty {
                    Section("Recent") {
                        ForEach(recentPeople) { person in
                            PeoplePickerRow(person: person, selected: selection.contains(person.id)) {
                                toggle(person)
                            }
                        }
                    }
                }
                Section(query.isEmpty ? "People" : "Search results") {
                    ForEach(results) { person in
                        PeoplePickerRow(person: person, selected: selection.contains(person.id)) {
                            toggle(person)
                        }
                    }
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        let people = results.filter { selection.contains($0.id) }
                        PeopleRecentsStore.record(ids: people.map(\.id))
                        onSelect(people)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .accessibilityIdentifier("people.picker")
    }

    private var title: String {
        switch mode {
        case .message: "New Message"
        case .inMail: "In-Mail"
        case .share: "Share with"
        }
    }

    private func toggle(_ person: PeoplePickerPerson) {
        if selection.contains(person.id) {
            selection.remove(person.id)
        } else if selectionLimit == 1 {
            selection = [person.id]
        } else if selection.count < selectionLimit {
            selection.insert(person.id)
        }
        HapticEngine.shared.play(.selection)
    }
}

struct PeoplePickerRow: View {
    let person: PeoplePickerPerson
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ModulaAvatar(initials: String(person.displayName.prefix(1)), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.body.weight(.medium))
                    if let handle = person.handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityLabel(person.displayName)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

enum PeopleRecentsStore {
    private static let key = "n4d.people.recents"
    private static let limit = 12

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(ids: [String]) {
        var next = load().filter { !ids.contains($0) }
        next.insert(contentsOf: ids, at: 0)
        if next.count > limit { next = Array(next.prefix(limit)) }
        UserDefaults.standard.set(next, forKey: key)
    }
}
