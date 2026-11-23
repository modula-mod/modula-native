import AVFoundation
import SwiftUI

// MARK: - Who reacted (16)

struct MessageReactorsSheet: View {
    let message: Message
    var onToggle: (String) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let rows = app.messaging.reactionDetails[message.id], !rows.isEmpty {
                    ForEach(rows) { row in
                        Section {
                            ForEach(row.actors) { person in
                                HStack(spacing: 12) {
                                    ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.displayName).font(.body.weight(.medium))
                                        if !person.handle.isEmpty { Text("@\(person.handle)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(row.emoji)
                                Text(row.count == 1 ? "1 person" : "\(row.count) people")
                                Spacer()
                                if app.messaging.capabilities.reactions {
                                    Button(row.mine ? "Remove" : "Add") { onToggle(row.emoji) }
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No names yet", systemImage: "face.smiling", description: Text("We couldn't load who sent these reactions."))
                }
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await app.messaging.loadReactionDetails(message) }
        .accessibilityIdentifier("messages.reactors")
    }
}

// MARK: - Seen by (30)

struct MessageReceiptsSheet: View {
    let message: Message
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let receipts = app.messaging.receiptsByMessage[message.id] {
                    if receipts.receiptsDisabled {
                        Text("Read receipts are off, so this list isn't available.")
                            .foregroundStyle(.secondary)
                    } else {
                        if !receipts.readBy.isEmpty {
                            Section("Seen") {
                                ForEach(receipts.readBy) { row in
                                    HStack {
                                        Text(row.participant.displayName)
                                        Spacer()
                                        if let readAt = row.readAt {
                                            Text(MessageTimeline.label(for: readAt)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        if !receipts.notYet.isEmpty {
                            Section("Not yet") {
                                ForEach(receipts.notYet) { person in
                                    Text(person.displayName)
                                }
                            }
                        }
                        if receipts.hiddenCount > 0 {
                            Text("\(receipts.hiddenCount) hidden because of privacy or blocks.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Seen by")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await app.messaging.loadReceipts(message) }
        .accessibilityIdentifier("messages.receipts")
    }
}

// MARK: - Voice note playback (19)

@MainActor
private final class MessageAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: CGFloat = 0
    @Published var loading = false
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL, client: GreenfieldClient) async {
        if let player {
            if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true; startTimer() }
            return
        }
        loading = true
        defer { loading = false }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await client.mediaData(from: url, maximumBytes: 20_000_000)
        }
        guard let data, let player = try? AVAudioPlayer(data: data) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.delegate = self
        self.player = player
        player.play()
        isPlaying = true
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.progress = CGFloat(player.currentTime / player.duration)
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 0
            self.timer?.invalidate()
        }
    }
}

struct MessageVoicePlayer: View {
    let attachment: MessageAttachment
    var accent: Color
    @StateObject private var player = MessageAudioPlayer()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let duration = attachment.durationMs ?? 0
        HStack(spacing: 10) {
            Button {
                guard let url = attachment.url else { return }
                Task { await player.toggle(url: url, client: app.client) }
            } label: {
                Group {
                    if player.loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                }
                .frame(width: 36, height: 36)
                .foregroundStyle(.white)
                .background(accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(attachment.url == nil)
            .accessibilityLabel(player.isPlaying ? "Pause voice note" : "Play voice note")
            ModulaWaveformView(
                levels: attachment.waveform.isEmpty ? Array(repeating: 0.3, count: 32) : attachment.waveform.map { CGFloat($0) },
                tint: accent,
                progress: player.progress
            )
            .frame(height: 28)
            Text(String(format: "%d:%02d", duration / 60_000, (duration / 1000) % 60))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: 280)
        .accessibilityIdentifier("messages.voice")
    }
}

// MARK: - Presence (34)

struct MessagePresenceLabel: View {
    let item: PresenceItem?
    var hiddenByPrivacy: Bool

    var body: some View {
        if hiddenByPrivacy {
            EmptyView()
        } else if let item {
            switch item.status {
            case .online:
                Text("Online").font(.caption2).foregroundStyle(.secondary)
            case .hidden:
                EmptyView()
            case .offline:
                if let last = item.lastActiveAt {
                    Text("Last seen \(MessageTimeline.label(for: last))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - New group (27)

struct NewGroupView: View {
    var presentedAsSheet = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var query = ""
    @State private var people: [DiscoverPerson] = []
    @State private var selected: [DiscoverPerson] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Group name", text: $title)
                TextField("Description (optional)", text: $description, axis: .vertical)
            }
            Section("People") {
                MessagesGlassSearchField(text: $query, prompt: "Search people to add")
                if !selected.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selected) { person in
                                Button {
                                    selected.removeAll { $0.id == person.id }
                                } label: {
                                    Label(person.displayName, systemImage: "xmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 32)
                                }
                                .buttonStyle(.plain)
                                .modulaGlass(in: Capsule(), interactive: true)
                            }
                        }
                    }
                }
                ForEach(filtered) { person in
                    Button {
                        if selected.contains(where: { $0.id == person.id }) {
                            selected.removeAll { $0.id == person.id }
                        } else if selected.count < max(0, app.messaging.capabilities.maxGroupMembers - 1) {
                            selected.append(person)
                        }
                    } label: {
                        HStack {
                            Text(person.displayName)
                            Spacer()
                            if selected.contains(where: { $0.id == person.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(app.appearance.liveAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("New group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { if presentedAsSheet { Button("Close") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { Task { await create() } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
        }
        .task {
            people = ((try? await GreenfieldDiscoverRepository(client: app.client).people(cursor: nil).items) ?? [])
                .filter { !ActivitySuggestedPeople.isFixture($0) }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let page = try? await GreenfieldDiscoverRepository(client: app.client).search(query: q, entityType: "profile", cursor: nil)
            guard !Task.isCancelled else { return }
            let own = app.profile.ownProfile?.handle.lowercased()
            let found = (page?.results.compactMap(\.person) ?? []).filter { $0.handle.lowercased() != own }
            // Merge search hits into the list so they can be selected.
            for person in found where !people.contains(where: { $0.id == person.id }) {
                people.append(person)
            }
        }
        .accessibilityIdentifier("messages.newGroup")
    }

    private var filtered: [DiscoverPerson] {
        let own = app.profile.ownProfile?.handle.lowercased()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return people.filter { person in
            person.handle.lowercased() != own
            && (needle.isEmpty || person.handle.lowercased().contains(needle) || person.displayName.lowercased().contains(needle))
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        let handles = selected.map { $0.handle.isEmpty ? $0.id : $0.handle }
        if let conversation = await app.messaging.createGroup(title: title, description: description, handles: handles) {
            if presentedAsSheet { dismiss() }
            app.navigation.push(.messages(.conversation(conversation.id)))
        } else {
            error = app.messaging.actionError ?? "Couldn't create the group."
        }
    }
}

// MARK: - Group info (28)

struct GroupInfoView: View {
    let conversationID: ConversationID
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var addQuery = ""
    @State private var confirmLeave = false
    @State private var removing: String?

    private var group: GroupDetail? { app.messaging.groups[conversationID] }

    var body: some View {
        List {
            if let group {
                if group.canAdmin {
                    Section("Group") {
                        TextField("Name", text: $title)
                        TextField("Description", text: $description, axis: .vertical)
                        Button("Save") {
                            Task { _ = await app.messaging.renameGroup(conversationID, title: title, description: description.isEmpty ? nil : description) }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section("Group") {
                        Text(group.title)
                        if let description = group.description, !description.isEmpty { Text(description).foregroundStyle(.secondary) }
                    }
                }
                Section("Members · \(group.members.filter { $0.state == "active" }.count)") {
                    ForEach(group.members.filter { $0.state == "active" }) { member in
                        HStack(alignment: .center, spacing: 12) {
                            ModulaAvatar(initials: member.participant.initials, url: member.participant.avatarURL, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.isMe ? "You" : member.participant.displayName)
                                Text(member.role.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if group.isOwner, !member.isMe {
                                Menu("Role") {
                                    Button("Member") { Task { _ = await app.messaging.setGroupRole(conversationID, actor: member.participant.id, role: .member) } }
                                    Button("Admin") { Task { _ = await app.messaging.setGroupRole(conversationID, actor: member.participant.id, role: .admin) } }
                                    Button("Make owner") { Task { _ = await app.messaging.setGroupRole(conversationID, actor: member.participant.id, role: .owner) } }
                                }
                            }
                            if group.canAdmin, !member.isMe, !(member.role == .owner), !(member.role == .admin && !group.isOwner) {
                                Button("Remove", role: .destructive) {
                                    Task { _ = await app.messaging.removeGroupMember(conversationID, actor: member.participant.id) }
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                if group.canAdmin {
                    Section("Add people") {
                        HStack {
                            TextField("Handle", text: $addQuery)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Add") {
                                let handle = addQuery.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                                guard !handle.isEmpty else { return }
                                addQuery = ""
                                Task { _ = await app.messaging.addGroupMembers(conversationID, handles: [handle]) }
                            }
                        }
                    }
                }
                Section {
                    Button("Leave group", role: .destructive) { confirmLeave = true }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Group info")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.messaging.loadGroup(conversationID)
            if let group = app.messaging.groups[conversationID] {
                title = group.title
                description = group.description ?? ""
            }
        }
        .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    if await app.messaging.leaveGroup(conversationID) {
                        dismiss()
                        app.navigation.open(.messages(.inbox))
                    }
                }
            }
        }
        .accessibilityIdentifier("messages.groupInfo")
    }
}
