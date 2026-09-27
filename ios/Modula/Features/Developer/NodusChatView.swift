import SwiftUI

#if DEBUG
enum NodusChatPresentation: Equatable {
    case developerWorkspace
    case accessorySheet

    var showsDeveloperDiagnostics: Bool { self == .developerWorkspace }
}

struct NodusChatView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = NodusChatViewModel()
    @FocusState private var composerFocused: Bool
    @State private var showingConversations = false
    @State private var showingKnowledge = false
    @State private var showingRename = false
    @State private var confirmingSearchEnable = false
    @State private var renameText = ""
    @State private var correctionTarget: NodusMessage?
    @State private var correctionRating: NodusDeveloperRating = .wrong
    @State private var correctionText = ""
    @State private var savingCitation: NodusCitation?
    let presentation: NodusChatPresentation

    init(presentation: NodusChatPresentation = .developerWorkspace) {
        self.presentation = presentation
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            if presentation.showsDeveloperDiagnostics { Divider() }
            conversation
            composer
        }
        .modulaCanvas()
        .navigationTitle(model.activeConversation?.title ?? "Nodus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingConversations = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Conversations")
                    .accessibilityIdentifier("nodus.chat.conversations")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("New Chat", systemImage: "plus") { Task { await model.newConversation() } }
                    Button("Rename", systemImage: "pencil") {
                        renameText = model.activeConversation?.title ?? ""
                        showingRename = true
                    }
                    Button("Clear", systemImage: "eraser") { model.clear() }
                        .disabled(model.messages.isEmpty)
                    Button("Delete Chat", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteActive() }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Chat actions")
                .accessibilityIdentifier("nodus.chat.actions")
                if presentation.showsDeveloperDiagnostics {
                    ShareLink(item: app.nodusEvaluationStore.exportURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Nodus evaluations")
                } else {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("intelligence.chat.close")
                }
            }
        }
        .task { await model.configure(using: app) }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showingConversations) {
            NodusConversationListSheet(model: model)
        }
        .sheet(isPresented: $showingKnowledge) {
            NodusKnowledgeAttachmentSheet(model: model)
        }
        .sheet(item: $correctionTarget) { message in
            correctionSheet(message)
        }
        .sheet(item: $savingCitation) { citation in
            NodusSaveSearchSourceSheet(citation: citation)
        }
        .alert("Rename Chat", isPresented: $showingRename) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { Task { await model.renameActive(to: renameText) } }
        }
        .confirmationDialog("Enable Online Search?", isPresented: $confirmingSearchEnable) {
            Button("Enable Online Search") { Task { await model.setSearchEnabled(true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The search query will be sent to the configured search provider. Nodus model inference remains local.")
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.showsDeveloperDiagnostics ? "brain" : "sparkles")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.showsDeveloperDiagnostics ? (model.modelIdentity?.displayName ?? "Nodus R7 Experimental") : "Nodus")
                    .font(.headline)
                    .accessibilityIdentifier("nodus.chat.screen")
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if presentation.showsDeveloperDiagnostics {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Experimental").foregroundStyle(.orange)
                    Text(NodusIntelligenceProvider.providerID)
                    Text("Local · 4-bit")
                }
                .font(.caption.weight(.medium))
            } else {
                Text("Experimental")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, presentation.showsDeveloperDiagnostics ? 10 : 8)
    }

    @ViewBuilder private var conversation: some View {
        if model.availability == .modelNotInstalled && model.messages.isEmpty {
            ContentUnavailableView(
                "Nodus model not installed",
                systemImage: "brain.head.profile",
                description: Text("A verified experimental developer bundle was not found. Chats, Knowledge, and Memory remain available.")
            )
            .accessibilityIdentifier("nodus.chat.model-not-installed")
        } else if model.availability != .available && model.messages.isEmpty {
            ContentUnavailableView(
                model.availability.displayName,
                systemImage: "exclamationmark.triangle",
                description: Text("Nodus cannot execute on this device. No fallback model will be used.")
            )
            .accessibilityIdentifier("nodus.chat.unavailable")
        } else if model.messages.isEmpty {
            ContentUnavailableView {
                Label("Local Intelligence", systemImage: "brain")
            } description: {
                Text("Start a local conversation. Think, Search, Knowledge, and Memory are independently controlled.")
            }
            .accessibilityIdentifier("nodus.chat.empty")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { message in
                            messageBubble(message).id(message.id)
                        }
                        if model.isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.progressText ?? "Thinking…")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .accessibilityIdentifier("nodus.chat.generating")
                        }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: NodusMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 9) {
                Text(message.text).textSelection(.enabled)
                if let answer = message.answer {
                    responseBadges(message, answer: answer)
                    if !message.citations.isEmpty { sourceList(message.citations) }
                    HStack(spacing: 8) {
                        if answer.verificationRecommended {
                            Button("Verify") {
                                Task { await model.queueVerification(for: message, store: app.nodusVerificationStore) }
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                        }
                        Menu("Remember this") {
                            Button("All Conversations") {
                                Task { await model.remember(message, scope: .global, using: app.nodusMemoryStore) }
                            }
                            Button("This Conversation") {
                                Task { await model.remember(message, scope: .conversation, using: app.nodusMemoryStore) }
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                    }
                    if presentation.showsDeveloperDiagnostics {
                        evaluationControls(for: message)
                        responseDetails(message, answer: answer)
                    }
                }
            }
            .padding(12)
            .background {
                if message.role == .user || presentation.showsDeveloperDiagnostics {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.11))
                }
            }
            if message.role == .nodus { Spacer(minLength: 44) }
        }
    }

    private func responseBadges(_ message: NodusMessage, answer: NodusAnswer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Label(answer.confidence.band.displayName, systemImage: "gauge.with.dots.needle.33percent")
                Label(answer.freshness.displayName, systemImage: "clock")
            }
            if message.details?.searchedWeb == true {
                Label("Searched the web", systemImage: "network")
            }
            if message.details?.reasoningMode == .deep {
                Label("Thought more deeply", systemImage: "brain")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func sourceList(_ citations: [NodusCitation]) -> some View {
        DisclosureGroup("Sources · \(citations.count)") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(citations) { citation in
                    HStack(alignment: .top) {
                        if let url = citation.url {
                            Link(destination: url) { sourceLabel(citation) }
                        } else {
                            sourceLabel(citation)
                        }
                        Spacer()
                        if citation.kind == .web {
                            Button("Save") { savingCitation = citation }
                                .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }

    private func sourceLabel(_ citation: NodusCitation) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(citation.title).lineLimit(2)
            Text([citation.collectionName, citation.sourceName, citation.location].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func responseDetails(_ message: NodusMessage, answer: NodusAnswer) -> some View {
        DisclosureGroup("Details") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                detail("Model", "R7 Experimental")
                detail("Stage", model.modelIdentity?.stage.displayName ?? "Experimental candidate")
                detail("Provider", NodusIntelligenceProvider.providerID)
                detail("Mode", message.details?.reasoningMode.displayName ?? "Standard")
                detail("Search", message.details?.searchEnabled == true ? "On" : "Off")
                detail("Knowledge chunks", "\(message.details?.knowledgeChunkCount ?? 0)")
                detail("Memory items", "\(message.details?.memoryItemIDs.count ?? 0)")
                detail("Sources", "\(message.citations.count)")
                detail("Confidence", answer.confidence.band.displayName)
                detail("Freshness", answer.freshness.displayName)
                detail("Passes", "\(message.details?.inferencePasses ?? 1)")
                detail("Generation", message.details?.generationDuration.map { String(format: "%.2f s", $0) } ?? "—")
                detail("Request", message.requestID?.uuidString ?? "—")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = model.errorMessage ?? model.verificationStatus ?? model.evaluationStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                activeContextChips
                TextField("Ask Nodus…", text: $model.input, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { if model.canSend { model.send(using: app) } }
                    .disabled(model.availability != .available || model.isGenerating)
                    .accessibilityIdentifier("nodus.chat.input")

                HStack(spacing: 8) {
                    composerMenu
                    modeButton(
                        model.activeConversation?.reasoningMode == .deep ? "Think" : nil,
                        symbol: "brain",
                        selected: model.activeConversation?.reasoningMode == .deep
                    ) {
                        Task {
                            await model.setReasoningMode(model.activeConversation?.reasoningMode == .deep ? .standard : .deep)
                        }
                    }
                    modeButton(
                        model.activeConversation?.searchEnabled == true ? "Search" : nil,
                        symbol: "network",
                        selected: model.activeConversation?.searchEnabled == true
                    ) { toggleSearch() }
                    Spacer(minLength: 4)
                    sendButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var activeContextChips: some View {
        let knowledgeCount = model.activeConversation?.attachedKnowledgeCollectionIDs.count ?? 0
        let memoryEnabled = model.activeConversation?.memoryEnabled == true
        if knowledgeCount > 0 || memoryEnabled {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if knowledgeCount > 0 {
                        contextChip("Knowledge · \(knowledgeCount)", symbol: "books.vertical") {
                            showingKnowledge = true
                        }
                    }
                    if memoryEnabled {
                        contextChip("Memory", symbol: "memorychip") {
                            Task { await model.setMemoryEnabled(false) }
                        }
                    }
                }
            }
            .disabled(model.isGenerating)
        }
    }

    private func contextChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var composerMenu: some View {
        Menu {
            Button("New Chat", systemImage: "plus.bubble") {
                Task { await model.newConversation(); composerFocused = true }
            }
            Button("Knowledge", systemImage: "books.vertical") { showingKnowledge = true }
            Button(
                model.activeConversation?.memoryEnabled == true ? "Turn Memory Off" : "Turn Memory On",
                systemImage: "memorychip"
            ) {
                Task { await model.setMemoryEnabled(model.activeConversation?.memoryEnabled != true) }
            }
            Button(
                model.activeConversation?.searchEnabled == true ? "Turn Search Off" : "Turn Search On",
                systemImage: "network"
            ) { toggleSearch() }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .accessibilityLabel("Add context")
        .accessibilityIdentifier("nodus.chat.add-context")
    }

    private var sendButton: some View {
        Button {
            model.isGenerating ? model.cancel() : model.send(using: app)
        } label: {
            Image(systemName: model.isGenerating ? "stop.fill" : "arrow.up")
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(model.isGenerating || model.canSend ? Color.accentColor : Color.secondary.opacity(0.28), in: Circle())
                .foregroundStyle(.white)
        }
        .disabled(!model.isGenerating && !model.canSend)
        .accessibilityLabel(model.isGenerating ? "Stop" : "Send")
        .accessibilityIdentifier(model.isGenerating ? "nodus.chat.stop" : "nodus.chat.send")
    }

    private func modeButton(_ title: String?, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let title {
                Label(title, systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, title == nil ? 0 : 9)
        .frame(minWidth: 34, minHeight: 34)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: Capsule())
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .accessibilityLabel(symbol == "brain" ? "Think" : "Search")
        .accessibilityValue(selected ? "On" : "Off")
    }

    private func toggleSearch() {
        if model.activeConversation?.searchEnabled == true {
            Task { await model.setSearchEnabled(false) }
        } else {
            confirmingSearchEnable = true
        }
    }

    private func evaluationControls(for message: NodusMessage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NodusDeveloperRating.allCases, id: \.self) { rating in
                    Button(rating.displayName) {
                        if rating.needsCorrection {
                            correctionRating = rating
                            correctionText = ""
                            correctionTarget = message
                        } else {
                            Task { await model.rate(rating, message: message, store: app.nodusEvaluationStore) }
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .tint(model.ratings[message.id] == rating ? Color.accentColor : nil)
                    .accessibilityIdentifier("nodus.chat.rating.\(rating.rawValue)")
                }
            }
        }
    }

    private func correctionSheet(_ message: NodusMessage) -> some View {
        NavigationStack {
            Form {
                Section("Nodus answer") { Text(message.text).foregroundStyle(.secondary) }
                Section("Correct answer / note") {
                    TextField("What should Nodus have said?", text: $correctionText, axis: .vertical)
                        .lineLimit(3 ... 10)
                }
                Section {
                    Text("This creates a local Learning Candidate. It does not update model weights or start training.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(correctionRating.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { correctionTarget = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.rate(
                                correctionRating, message: message, store: app.nodusEvaluationStore,
                                correction: correctionText, learningStore: app.nodusVerificationStore
                            )
                            correctionTarget = nil
                        }
                    }
                    .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func detail(_ name: String, _ value: String) -> some View {
        GridRow { Text(name); Text(value).textSelection(.enabled) }
    }

    private var statusText: String {
        switch model.availability {
        case .available:
            if model.isGenerating { return model.progressText ?? "Generating locally" }
            return model.loadState == .loading ? "Loading Nodus…" : "Ready · generation stays local"
        case .modelNotInstalled: return "Model not installed"
        default: return model.availability.displayName
        }
    }
}

private struct NodusConversationListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: NodusChatViewModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Button { Task { await model.newConversation(); dismiss() } } label: {
                    Label("New Chat", systemImage: "plus.circle.fill")
                }
                ForEach(model.conversations) { conversation in
                    Button {
                        model.select(conversation)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conversation.title).font(.body.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text(conversation.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(conversation.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack(spacing: 8) {
                                if conversation.reasoningMode == .deep { Label("Think", systemImage: "brain") }
                                if conversation.searchEnabled { Label("Search", systemImage: "network") }
                                if !conversation.attachedKnowledgeCollectionIDs.isEmpty {
                                    Label("\(conversation.attachedKnowledgeCollectionIDs.count)", systemImage: "books.vertical")
                                }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search chats")
            .onChange(of: query) { _, value in Task { await model.searchConversations(value) } }
            .navigationTitle("Nodus")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .accessibilityIdentifier("nodus.conversations")
        }
    }
}

private struct NodusKnowledgeAttachmentSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: NodusChatViewModel
    @State private var collections: [NodusKnowledgeCollection] = []
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(collections) { collection in
                Button {
                    if selection.contains(collection.id) { selection.remove(collection.id) }
                    else { selection.insert(collection.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(collection.name)
                            Text(collection.isReadOnly ? "System Knowledge · Read-only" : "User Knowledge")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection.contains(collection.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
            .navigationTitle("Knowledge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") { Task { await model.setKnowledgeCollections(selection); dismiss() } }
                }
            }
            .task {
                collections = await app.nodusKnowledgeStore.collections()
                selection = model.activeConversation?.attachedKnowledgeCollectionIDs ?? []
            }
        }
    }
}

private struct NodusSaveSearchSourceSheet: View {
    let citation: NodusCitation
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [NodusKnowledgeCollection] = []
    @State private var selectedID = NodusKnowledgeStore.myKnowledgeCollectionID
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Text(citation.title)
                    Text(citation.sourceName).font(.caption).foregroundStyle(.secondary)
                }
                Section("Save to Knowledge") {
                    Picker("Collection", selection: $selectedID) {
                        ForEach(collections) { Text($0.name).tag($0.id) }
                    }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Save Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(collections.isEmpty)
                }
            }
            .task {
                collections = await app.nodusKnowledgeStore.collections().filter { !$0.isReadOnly }
                if !collections.contains(where: { $0.id == selectedID }), let first = collections.first {
                    selectedID = first.id
                }
            }
        }
    }

    private func save() async {
        do {
            _ = try await app.nodusKnowledgeStore.add(
                title: citation.title, sourceType: .web,
                sourceName: citation.sourceName, sourceURL: citation.url,
                text: citation.excerpt ?? citation.title, collectionID: selectedID
            )
            dismiss()
        } catch {
            status = error.localizedDescription
        }
    }
}
#endif
