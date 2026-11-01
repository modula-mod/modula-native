import SwiftUI

/// Modula's share sheet (X-style, dense): search, a horizontal people row, then two rows of
/// real share actions. Selecting someone checks them, slides the action rows away, and brings
/// up a message field with an accent Send button. Two or more people retitle it "Send separately".
struct ModulaShareSheet: View {
    let payload: SharePayload
    /// Richer code card for a profile (verified badge, avatar) than the payload alone carries.
    var codeSubject: ModulaCodeSubject? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var noteFocused: Bool

    @State private var showCollectionPicker = false
    @State private var showPeoplePicker = false
    @State private var copied = false
    @State private var showCode = false
    @State private var post: SocialPost?
    @State private var suggestions: [DiscoverPerson] = []
    @State private var searchPeople: [DiscoverPerson] = []
    @State private var searching = false
    @State private var query = ""
    @State private var selectedKeys: [String] = []
    @State private var known: [String: ShareRecipient] = [:]
    @State private var note = ""
    @State private var sending = false
    @State private var sendError: String?

    private var reduceMotion: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }
    private var accent: Color { app.appearance.liveAccent }
    private var canMessage: Bool { app.messaging.capabilities.send }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.62)
    }

    private var slide: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var destinations: [ShareDestination] {
        ShareDestinationRegistry.destinations(
            for: payload,
            messagingSend: app.messaging.capabilities.send,
            inMailCompose: app.inMail.capabilities.send,
            collectionsAvailable: app.collections.capabilities.localCollections
        )
    }

    private func has(_ kind: ShareDestinationKind) -> Bool { destinations.contains { $0.kind == kind } }

    private var canRepost: Bool {
        if case .post = payload { return app.postActions.capabilities.repost && post != nil }
        return false
    }

    private var audience: [ShareRecipient] {
        ShareAudience.recipients(
            conversations: app.messaging.conversations,
            suggestions: suggestions + searchPeople,
            ownID: app.auth.account?.accountId,
            ownHandle: app.auth.account?.primaryHandle
        )
    }

    private var visiblePeople: [ShareRecipient] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return audience }
        return audience.filter {
            $0.displayName.lowercased().contains(trimmed) || $0.handle.lowercased().contains(trimmed)
        }
    }

    private var selectedPeople: [ShareRecipient] {
        selectedKeys.compactMap { known[$0] }
    }

    private var hasRecipients: Bool { canMessage && !selectedKeys.isEmpty }
    private var canSend: Bool { hasRecipients && !sending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ShareHeroPreview(payload: payload, post: post)
                    if canMessage {
                        peopleSection
                    }
                    // Enhancements-50: X-style dense layout — two action rows live in the sheet
                    // body; the bottom bar only appears (with Send) once someone is selected.
                    if selectedKeys.isEmpty {
                        actionRows
                            .transition(slide)
                    }
                }
                .animation(motion, value: selectedKeys.isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .modulaSoftScrollEdge()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if canMessage && !selectedKeys.isEmpty { bottomBar.transition(slide) }
            }
            .animation(motion, value: selectedKeys.isEmpty)
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
        .task { await loadPeople() }
        .task(id: query) { await search() }
        .onChange(of: audience.map(\.key)) { _, _ in remember(audience) }
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
            PeoplePicker(mode: .inMail, selectionLimit: 1) { people in
                guard let person = people.first else { return }
                var draft = ShareCoordinator.inMailPrefill(for: payload)
                draft.toHandle = person.handle ?? person.id
                app.inMail.draft = draft
                dismiss()
                app.navigation.open(.messages(.inMail(.compose)))
            }
        }
        .accessibilityIdentifier("share.universal")
    }

    // MARK: People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaGlassSearchField(prompt: "Search people", text: $query)
                .accessibilityIdentifier("share.people.search")
            if visiblePeople.isEmpty {
                Text(emptyPeopleCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("share.people.empty")
            } else {
                // Enhancements-50: dense horizontal people row (avatar + name, check badge).
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 4) {
                        ForEach(visiblePeople) { person in
                            personCell(person)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
                .accessibilityIdentifier("share.people")
            }
        }
    }

    private var emptyPeopleCopy: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if searching && !trimmed.isEmpty { return "Searching…" }
        if !trimmed.isEmpty { return "No one matches that." }
        return "People you chat with show up here."
    }

    private func personCell(_ person: ShareRecipient) -> some View {
        let on = selectedKeys.contains(person.key)
        return Button {
            toggle(person)
        } label: {
            VStack(spacing: 6) {
                ModulaAvatar(initials: initials(person.displayName), url: person.avatarURL, size: 58, name: person.displayName)
                    .overlay(Circle().strokeBorder(on ? accent : Color.clear, lineWidth: 2.5).padding(-3))
                    .overlay(alignment: .bottomTrailing) {
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, accent)
                                .background(Circle().fill(Color(uiColor: .systemBackground)).padding(2))
                                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        }
                    }
                    .scaleEffect(on && !reduceMotion ? 0.94 : 1)
                Text(person.displayName)
                    .font(.caption)
                    .foregroundStyle(on ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(motion, value: on)
        .accessibilityLabel(person.displayName)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityHint(person.hasDirectChat ? "Adds them to this send" : "No direct chat yet")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("share.person.\(person.key)")
    }

    private func personRow(_ person: ShareRecipient) -> some View {
        let on = selectedKeys.contains(person.key)
        return Button {
            toggle(person)
        } label: {
            HStack(spacing: 12) {
                ModulaAvatar(initials: initials(person.displayName), url: person.avatarURL, size: 44, name: person.displayName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(person.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                check(on: on)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.displayName)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityHint(person.hasDirectChat ? "Adds them to this send" : "No direct chat yet")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("share.person.\(person.key)")
    }

    private func check(on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title3.weight(.semibold))
            .foregroundStyle(on ? accent : Color.secondary.opacity(0.55))
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .symbolEffect(.bounce, value: reduceMotion ? false : on)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    private func toggle(_ person: ShareRecipient) {
        known[person.key] = person
        withAnimation(motion) {
            if let index = selectedKeys.firstIndex(of: person.key) {
                selectedKeys.remove(at: index)
                if selectedKeys.isEmpty { noteFocused = false }
            } else {
                let wasEmpty = selectedKeys.isEmpty
                selectedKeys.append(person.key)
                if wasEmpty { noteFocused = true }
            }
        }
        HapticEngine.shared.play(.selection)
    }

    private func remember(_ people: [ShareRecipient]) {
        for person in people {
            if known[person.key] == nil || person.conversationID != nil {
                known[person.key] = person
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("share.send.error")
            }
            HStack(alignment: .center, spacing: 10) {
                messageField
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canMessage { sendButton }
            }
            .animation(motion, value: selectedKeys.isEmpty)
            .animation(motion, value: selectedKeys.count)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            if reduceTransparency {
                Color(uiColor: .systemBackground).ignoresSafeArea(edges: .bottom)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var messageField: some View {
        TextField("Write a message", text: $note, axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.plain)
            .focused($noteFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
            .accessibilityLabel("Write a message")
            .accessibilityIdentifier("share.message")
    }

    private var sendButton: some View {
        Button(action: sendSelected) {
            HStack(spacing: 8) {
                if sending {
                    ProgressView().controlSize(.small).tint(.white)
                } else if selectedKeys.count >= 2 {
                    stackedAvatars
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
                if selectedKeys.isEmpty && !sending {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                } else if !selectedKeys.isEmpty {
                    Text(selectedKeys.count >= 2 ? "Send separately" : "Send")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, selectedKeys.isEmpty ? 0 : 16)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaAccentCTA()
        .disabled(!canSend)
        .accessibilityLabel(sendLabel)
        .accessibilityIdentifier(selectedKeys.count >= 2 ? "share.sendSeparately" : "share.send")
    }

    private var sendLabel: String {
        if sending { return "Sending" }
        if selectedKeys.count >= 2 { return "Send separately" }
        if selectedKeys.isEmpty { return "Send" }
        return "Send"
    }

    private var stackedAvatars: some View {
        HStack(spacing: -8) {
            ForEach(Array(selectedPeople.prefix(3))) { person in
                ModulaAvatar(initials: initials(person.displayName), url: person.avatarURL, size: 22, name: person.displayName)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share to").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            modulaActionRow
            linkActionRow
        }
    }

    /// Row 1: actions inside Modula.
    private var modulaActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 12) {
                HStack(alignment: .top, spacing: 6) {
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
                    if has(.inMail) {
                        ShareActionTile(title: "In-Mail", symbol: "envelope", accent: accent) {
                            showPeoplePicker = true
                            HapticEngine.shared.play(.selection)
                        }
                        .accessibilityIdentifier("share.destination.inMail")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
    }

    /// Row 2: link-level actions (copy, system share targets).
    private var linkActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 12) {
                HStack(alignment: .top, spacing: 6) {
                    ShareActionTile(title: copied ? "Copied" : "Copy Link", symbol: copied ? "checkmark" : "link", accent: accent, highlighted: copied) {
                        copyLink()
                    }
                    .accessibilityIdentifier("share.destination.copyLink")
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

    // MARK: Actions

    private func loadPeople() async {
        await app.messaging.loadInboxIfNeeded()
        if case .post(let id, _, _, _) = payload, post == nil {
            post = try? await app.postActions.loadPost(id: id)
        }
        let loaded = (try? await GreenfieldDiscoverRepository(client: app.client).people(cursor: nil).items) ?? app.discover.people.items
        suggestions = loaded.filter { !ModulaFixtureFilter.isFixture(name: $0.displayName, handle: $0.handle) }
        remember(audience)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchPeople = []
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let page = try? await GreenfieldDiscoverRepository(client: app.client).search(query: trimmed, entityType: "profile", cursor: nil)
        guard !Task.isCancelled else { return }
        searchPeople = (page?.results.compactMap(\.person) ?? []).filter {
            !ModulaFixtureFilter.isFixture(name: $0.displayName, handle: $0.handle)
        }
        searching = false
        remember(audience)
    }

    private func sendSelected() {
        guard canSend else { return }
        let keys = selectedKeys
        let note = note
        let payload = payload
        sending = true
        sendError = nil
        HapticEngine.shared.play(.confirmation)
        Task { await deliver(keys: keys, note: note, payload: payload) }
    }

    private func deliver(keys: [String], note: String, payload: SharePayload) async {
        await app.messaging.refreshInbox()
        var pages = 0
        while app.messaging.conversationHasMore, pages < 4, keys.contains(where: { conversationID(for: $0) == nil }) {
            let before = app.messaging.conversations.count
            await app.messaging.loadMoreConversations()
            pages += 1
            if app.messaging.conversations.count == before { break }
        }
        remember(audience)

        let text = ShareOutboundMessage.text(note: note, payload: payload)
        var sent: [String] = []
        var noChat: [String] = []
        var failed: [String] = []
        for key in keys {
            let person = known[key] ?? audience.first(where: { $0.key == key })
            guard let person else {
                failed.append(key)
                continue
            }
            guard let conversationID = conversationID(for: key) else {
                noChat.append(person.displayName)
                continue
            }
            let ok = await app.messaging.sendPrepared(text: text, conversation: conversationID)
            if ok { sent.append(key) } else { failed.append(person.displayName) }
        }

        withAnimation(motion) {
            selectedKeys.removeAll { sent.contains($0) }
            sending = false
        }
        if sent.count == keys.count {
            HapticEngine.shared.play(.success)
            let separately = keys.count >= 2
            dismiss()
            app.navigation.flash(separately ? "Sent separately" : "Sent", symbol: "paperplane.fill")
        } else {
            HapticEngine.shared.play(.failure)
            let copy = failureCopy(noChat: noChat, failed: failed, sentCount: sent.count)
            sendError = copy.isEmpty ? "Couldn't send." : copy
        }
    }

    private func conversationID(for key: String) -> ConversationID? {
        ShareAudience.directConversationID(matching: key, in: app.messaging.conversations)
    }

    private func failureCopy(noChat: [String], failed: [String], sentCount: Int) -> String {
        var parts: [String] = []
        if sentCount > 0 { parts.append("Sent to \(sentCount).") }
        if !noChat.isEmpty { parts.append("No chat with \(noChat.joined(separator: ", ")) yet.") }
        if !failed.isEmpty { parts.append("Couldn't send to \(failed.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
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
                    .foregroundStyle(app.appearance.liveAccent)
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
            .background(app.appearance.liveAccent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
