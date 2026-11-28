import AVFoundation
import Speech
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
        .modulaSheetStyle()
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
        .modulaSheetStyle()
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
    @Published var rate: Float = 1
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL, client: GreenfieldClient) async {
        if let player {
            if player.isPlaying { pause() } else { play(player) }
            return
        }
        guard let player = await prepare(url: url, client: client) else { return }
        play(player)
    }

    /// Scrubbing: seeks (loading first if needed) without starting playback.
    func seek(to fraction: CGFloat, url: URL, client: GreenfieldClient) async {
        let clamped = min(1, max(0, fraction))
        progress = clamped
        guard let player = await prepare(url: url, client: client), player.duration > 0 else { return }
        player.currentTime = player.duration * Double(clamped)
    }

    func cycleRate() {
        rate = rate == 1 ? 1.5 : (rate == 1.5 ? 2 : 1)
        player?.rate = rate
    }

    private func prepare(url: URL, client: GreenfieldClient) async -> AVAudioPlayer? {
        if let player { return player }
        loading = true
        defer { loading = false }
        guard let data = await MessageVoiceData.load(url: url, client: client),
              let player = try? AVAudioPlayer(data: data) else { return nil }
        player.delegate = self
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        self.player = player
        return player
    }

    private func play(_ player: AVAudioPlayer) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = rate
        player.play()
        isPlaying = true
        startTimer()
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
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

/// Voice-note bytes (file or authenticated media URL), shared by playback and transcription.
enum MessageVoiceData {
    static func load(url: URL, client: GreenfieldClient) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url) }
        return try? await client.mediaData(from: url, maximumBytes: 20_000_000)
    }
}

/// Voice transcripts. No server transcription capability exists, so this is on-device only
/// (SFSpeechRecognizer with `requiresOnDeviceRecognition`; audio never leaves the phone).
/// Permission is asked the first time someone opens a transcript. Results are cached on disk.
@MainActor @Observable
final class MessageVoiceTranscripts {
    static let shared = MessageVoiceTranscripts()

    enum Phase: Equatable { case idle, working, done(String), failed(String) }

    private(set) var phases: [String: Phase] = [:]
    /// Attachments whose transcript is expanded under the bubble.
    var expanded: Set<String> = []

    func phase(_ id: String) -> Phase {
        if let phase = phases[id] { return phase }
        if let cached = Self.cached(id) { return .done(cached) }
        return .idle
    }

    func show(_ attachment: MessageAttachment, client: GreenfieldClient) {
        expanded.insert(attachment.id)
        transcribe(attachment, client: client)
    }

    func toggle(_ attachment: MessageAttachment, client: GreenfieldClient) {
        if expanded.contains(attachment.id) { expanded.remove(attachment.id) } else { show(attachment, client: client) }
    }

    func transcribe(_ attachment: MessageAttachment, client: GreenfieldClient) {
        let id = attachment.id
        switch phase(id) {
        case .working, .done: return
        case .idle, .failed: break
        }
        guard let url = attachment.url else { phases[id] = .failed("This voice note isn't available."); return }
        phases[id] = .working
        Task {
            let result = await Self.recognize(url: url, client: client)
            switch result {
            case .success(let text):
                phases[id] = .done(text)
                Self.store(text, id: id)
            case .failure(let message):
                phases[id] = .failed(message.text)
            }
        }
    }

    struct Failure: Error { let text: String }

    private static func recognize(url: URL, client: GreenfieldClient) async -> Result<String, Failure> {
        let status: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus() == .notDetermined
            ? await withCheckedContinuation { cont in SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) } }
            : SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else { return .failure(Failure(text: "Allow Speech Recognition in Settings to see transcripts.")) }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition else {
            return .failure(Failure(text: "On-device transcription isn't available for this language."))
        }
        guard let data = await MessageVoiceData.load(url: url, client: client) else {
            return .failure(Failure(text: "Couldn't load this voice note."))
        }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).\(ext)")
        guard (try? data.write(to: file)) != nil else { return .failure(Failure(text: "Couldn't read this voice note.")) }
        defer { try? FileManager.default.removeItem(at: file) }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let once = TranscriptOnce()
        return await withCheckedContinuation { cont in
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard once.claim() else { return }
                    let text = result.bestTranscription.formattedString
                    cont.resume(returning: text.isEmpty ? .failure(Failure(text: "No speech found.")) : .success(text))
                } else if error != nil {
                    guard once.claim() else { return }
                    cont.resume(returning: .failure(Failure(text: "No speech found.")))
                }
            }
        }
    }

    private final class TranscriptOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }

    private static func fileURL(_ id: String) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("VoiceTranscripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".txt")
    }

    private static func cached(_ id: String) -> String? {
        guard let url = fileURL(id) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func store(_ text: String, id: String) {
        guard let url = fileURL(id) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Compact voice bubble: play · scrubbable neutral waveform · time · speed, with a small
/// "Transcript" control that expands the on-device transcript underneath.
struct MessageVoicePlayer: View {
    let attachment: MessageAttachment
    var accent: Color
    /// Glyph on the play circle (the inverse of `accent`).
    var glyph: Color = .modulaOnPrimary
    @StateObject private var player = MessageAudioPlayer()
    @Environment(AppEnvironment.self) private var app
    private var transcripts: MessageVoiceTranscripts { .shared }

    var body: some View {
        let duration = attachment.durationMs ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    guard let url = attachment.url else { return }
                    Task { await player.toggle(url: url, client: app.client) }
                } label: {
                    Group {
                        if player.loading { ProgressView().controlSize(.small).tint(glyph) }
                        else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.footnote.weight(.bold)) }
                    }
                    .frame(width: 32, height: 32)
                    .foregroundStyle(glyph)
                    .background(accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(attachment.url == nil)
                .accessibilityLabel(player.isPlaying ? "Pause voice note" : "Play voice note")
                GeometryReader { geo in
                    ModulaWaveformView(
                        levels: attachment.waveform.isEmpty ? Array(repeating: 0.3, count: 32) : attachment.waveform.map { CGFloat($0) },
                        tint: accent,
                        progress: player.progress
                    )
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // Tap a spot to jump there; drag sideways to scrub (no zero-distance drag racing the bubble's long-press).
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard let url = attachment.url, geo.size.width > 0 else { return }
                        Task { await player.seek(to: location.x / geo.size.width, url: url, client: app.client) }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                guard let url = attachment.url, geo.size.width > 0 else { return }
                                Task { await player.seek(to: value.location.x / geo.size.width, url: url, client: app.client) }
                            }
                    )
                }
                .frame(width: 120, height: 24)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Int(player.progress * 100)) percent")
                .accessibilityAdjustableAction { direction in
                    guard let url = attachment.url else { return }
                    let step: CGFloat = direction == .increment ? 0.1 : -0.1
                    Task { await player.seek(to: player.progress + step, url: url, client: app.client) }
                }
                Text(String(format: "%d:%02d", duration / 60_000, (duration / 1000) % 60))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(accent.opacity(0.7))
                    .fixedSize()
                Button { player.cycleRate() } label: {
                    Text(player.rate == 1 ? "1×" : (player.rate == 1.5 ? "1.5×" : "2×"))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 34, minHeight: 22)
                        .background(Capsule().fill(accent.opacity(0.14)))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .frame(minHeight: 32)
                .accessibilityLabel("Playback speed \(player.rate == 1 ? "normal" : (player.rate == 1.5 ? "one and a half times" : "double"))")
            }
            transcriptArea
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityIdentifier("messages.voice")
    }

    @ViewBuilder
    private var transcriptArea: some View {
        let open = transcripts.expanded.contains(attachment.id)
        Button {
            withAnimation(.snappy(duration: 0.22)) { transcripts.toggle(attachment, client: app.client) }
        } label: {
            Label(open ? "Hide transcript" : "View transcript", systemImage: "text.quote")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent.opacity(0.75))
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("messages.voice.transcript")
        if open {
            Group {
                switch transcripts.phase(attachment.id) {
                case .idle, .working:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(accent)
                        Text("Transcribing on this iPhone…")
                    }
                case .done(let text):
                    Text(text).textSelection(.enabled)
                case .failed(let message):
                    Text(message)
                }
            }
            .font(.footnote)
            .foregroundStyle(accent.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 240, alignment: .leading)
            .padding(.bottom, 4)
            .transition(.opacity)
        }
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
                    .modulaHorizontalRail()
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
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary)
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
