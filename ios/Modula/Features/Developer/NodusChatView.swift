import AVFoundation
import Network
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Ships in Release behind NodusChatFeature; developer-only affordances stay behind
// NodusChatPresentation.developerWorkspace and the DEBUG-only Developer settings routes.
private enum NodusConnectorFollowUp {
    case knowledge, memory, library
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingConversations = false
    @State private var showingKnowledge = false
    @State private var showingRename = false
    @State private var confirmingSearchEnable = false
    @State private var renameText = ""
    @State private var correctionTarget: NodusMessage?
    @State private var correctionRating: NodusDeveloperRating = .wrong
    @State private var correctionText = ""
    @State private var savingCitation: NodusCitation?
    @State private var attachments: [NodusComposerAttachment] = []
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingPlugins = false
    @State private var showingMemory = false
    @State private var showingChatSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pluginQuery = ""
    @Namespace private var photoMorph
    @State private var expandedPhoto: String?
    @State private var showingModels = false
    @State private var showingSystemInfo = false
    @State private var showingConnectors = false
    @State private var showingPrompts = false
    @State private var showingThinkBudget = false
    @State private var connectorFollowUp: NodusConnectorFollowUp?
    @State private var copiedMessageID: UUID?
    @State private var sendTick = 0
    @State private var welcomeAppeared = false
    @State private var showingSkills = false
    @State private var showingFunctions = false
    @State private var showingPersona = false
    @State private var showingCustomise = false
    @State private var showingRemote = false
    @State private var creatingChat = false
    @State private var confirmingDelete = false
    @StateObject private var pathMonitor = NodusPathMonitor()
    @State private var speaker = AVSpeechSynthesizer()
    @StateObject private var dictation = NodusDictation()
    let presentation: NodusChatPresentation

    init(presentation: NodusChatPresentation = .developerWorkspace) {
        self.presentation = presentation
    }

    /// AppearanceStore accent (not the asset-catalog accent) so curated accents apply.
    private var accent: Color { app.appearance.liveAccent }

    /// All chat motion goes through ModulaMotion so the Motion personality and
    /// iOS Reduce Motion are respected.
    private func motion(_ role: ModulaMotion.Role) -> Animation? {
        ModulaMotion.animation(role, personality: app.appearance.motion, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            if presentation.showsDeveloperDiagnostics { Divider() }
            conversation
            composer
        }
        .overlay(alignment: .bottom) { photoStage }
        .animation(motion(.morph), value: expandedPhoto)
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
                        confirmingDelete = true
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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("intelligence.chat.close")
                }
            }
        }
        .task {
            pathMonitor.start()
            await model.configure(using: app)
        }
        .onDisappear { model.cancel() }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                Task { await model.deleteActive() }
                HapticEngine.shared.play(.warning)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its messages are removed from this iPhone. This can’t be undone.")
        }
        .sheet(isPresented: $showingConversations) {
            NodusLibraryBrowser(model: model)
        }
        .sheet(isPresented: $showingKnowledge) {
            NodusKnowledgeAttachmentSheet(model: model)
        }
        .sheet(isPresented: $showingPlugins) {
            NodusPluginSheet(
                query: $pluginQuery,
                memoryOn: model.activeConversation?.memoryEnabled == true,
                onSelect: handlePlugin
            )
        }
        .sheet(isPresented: $showingMemory) {
            NavigationStack { NodusMemoryView() }
        }
        .sheet(isPresented: $showingChatSettings) {
            NodusChatSettingsSheet(model: model)
        }
        .sheet(isPresented: $showingModels) {
            NodusModelSheet(identity: model.modelIdentity, availability: model.availability)
        }
        .sheet(isPresented: $showingSystemInfo) {
            NodusSystemInfoSheet(
                chats: model.conversations.count,
                projects: model.library.projects.count,
                folders: model.library.folders.count,
                prompts: model.library.prompts.count,
                personas: model.library.placements.filter { !$0.persona.isEmpty }.count,
                skills: model.library.placements.filter { !$0.skillIDs.isEmpty }.count
            )
        }
        .sheet(isPresented: $showingConnectors, onDismiss: followConnector) {
            NodusConnectorsSheet(model: model, draftCount: attachments.count, onLibrary: {
                connectorFollowUp = .library
                showingConnectors = false
            }, onKnowledge: {
                connectorFollowUp = .knowledge
                showingConnectors = false
            }, onMemory: {
                connectorFollowUp = .memory
                showingConnectors = false
            })
        }
        .sheet(isPresented: $showingPrompts) {
            NodusMarketplaceSheet(model: model)
        }
        .sheet(isPresented: $showingSkills) { NodusSkillsSheet(model: model) }
        .sheet(isPresented: $showingPersona) { NodusPersonaSheet(model: model) }
        .sheet(isPresented: $showingCustomise) { NodusCustomiseSheet(model: model) }
        .sheet(isPresented: $showingRemote) {
            NodusRemoteSheet(
                pathStatus: pathMonitor.status,
                interfaceName: pathMonitor.interfaceName,
                searchOn: model.activeConversation?.searchEnabled == true,
                webCitations: model.messages.reduce(0) { $0 + $1.citations.filter { $0.kind == .web }.count }
            )
        }
        .sheet(isPresented: $showingFunctions) {
            NodusFunctionsSheet(lastReply: model.messages.last(where: { $0.role == .nodus })?.text) { function in
                perform(function)
            }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .text, .plainText, .pdf, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await importFile(url) }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
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
        HStack(spacing: 12) {
            ZStack {
                if model.isGenerating {
                    NodusThinkingOrb(stage: model.progressStage, reduceMotion: reduceMotion, size: 36)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    NodusStudioGlyph(symbol: presentation.showsDeveloperDiagnostics ? "brain" : "sparkles", size: 36)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(motion(.morph), value: model.isGenerating)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.showsDeveloperDiagnostics ? (model.modelIdentity?.displayName ?? "Nodus R7 Experimental") : "Nodus")
                    .font(.headline)
                    .accessibilityIdentifier("nodus.chat.screen")
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: statusText)
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
                if model.activeConversation.flatMap({ model.library.placement(for: $0.id)?.important }) == true {
                    Image(systemName: "flag.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: model.messages.count)
                        .accessibilityLabel("Important")
                }
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
                description: Text("This experimental feature isn’t installed. Chats, Knowledge and Memory are still available.")
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
            welcome
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: model.messageDensity == "compact" ? 8 : 12) {
                        ForEach(model.messages) { message in
                            messageBubble(message).id(message.id)
                        }
                        if model.isGenerating {
                            NodusThinkingRow(text: model.progressText ?? "Thinking", stage: model.progressStage)
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                        }
                        newChatHandle
                    }
                    .padding()
                    .animation(motion(.morph), value: model.messages.map(\.id))
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: NodusMessage) -> some View {
        NodusMessageSwipe(
            onReply: { reply(to: message) },
            onFork: {
                if let conversation = model.activeConversation {
                    Task { await model.fork(conversation, through: message.id) }
                }
            },
            onLove: { model.toggleReaction(NodusReaction.heart.rawValue, on: message.id) }
        ) {
            messageContents(message)
        }
    }

    private func messageContents(_ message: NodusMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: model.messageDensity == "compact" ? 6 : 9) {
                if let image = model.attachmentImages[message.id] {
                    let geometryID = "message-\(message.id.uuidString)"
                    let open = expandedPhoto == geometryID
                    Button {
                        withAnimation(motion(.morph)) { expandedPhoto = geometryID }
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 112, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: open ? 22 : 14, style: .continuous))
                            .matchedGeometryEffect(id: geometryID, in: photoMorph, isSource: !open)
                    }
                    .buttonStyle(.plain)
                    .opacity(open ? 0 : 1)
                    .accessibilityLabel("Attached photo preview")
                    .accessibilityIdentifier("nodus.chat.photo.message")
                }
                Text(message.text)
                    .font(model.messageFont)
                    .textSelection(.enabled)
                if model.showMessageTimes {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let symbols = model.reactions[message.id], !symbols.isEmpty {
                    NodusMessageReactions(symbols: symbols)
                }
                if message.role == .nodus, message.id == latestNodusID, !model.isGenerating {
                    messageActions(message)
                }
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
            .padding(model.messageDensity == "compact" ? 8 : 12)
            .background {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(chatTint.color(accent: app.appearance.liveAccent).opacity(0.22))
                } else if presentation.showsDeveloperDiagnostics {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.secondary.opacity(0.11))
                }
            }
            .modifier(NodusReplyGlass(enabled: message.role == .nodus && !presentation.showsDeveloperDiagnostics && message.id == latestNodusID))
            .background {
                if message.role == .nodus, !presentation.showsDeveloperDiagnostics, message.id != latestNodusID {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            if message.role == .nodus { Spacer(minLength: 44) }
        }
        .contextMenu {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(to: message) }
            Menu("Message", systemImage: "text.bubble") {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = message.text
                }
                Button("Fork from here", systemImage: "arrow.triangle.branch") {
                    if let conversation = model.activeConversation {
                        Task { await model.fork(conversation, through: message.id) }
                    }
                }
                ShareLink(item: message.text) { Label("Share", systemImage: "square.and.arrow.up") }
                if message.role == .nodus {
                    Button("Again", systemImage: "arrow.clockwise") { regenerate() }
                }
            }
            Menu("React", systemImage: "face.smiling") {
                ForEach(NodusReaction.allCases, id: \.rawValue) { reaction in
                    Button(reaction.title, systemImage: reaction.rawValue) {
                        model.toggleReaction(reaction.rawValue, on: message.id)
                    }
                }
            }
            if message.role == .nodus {
                Menu("Remember", systemImage: "memorychip") {
                    Button("All Conversations") {
                        Task { await model.remember(message, scope: .global, using: app.nodusMemoryStore) }
                    }
                    Button("This Conversation") {
                        Task { await model.remember(message, scope: .conversation, using: app.nodusMemoryStore) }
                    }
                }
            }
            if let conversation = model.activeConversation {
                Menu("This chat", systemImage: "bubble.left.and.bubble.right") {
                    let placement = model.library.placement(for: conversation.id)
                    Button(placement?.important == true ? "Unmark Important" : "Mark Important", systemImage: "flag") {
                        Task { await model.setImportant(conversation, important: placement?.important != true) }
                    }
                    Button(placement?.favorite == true ? "Unfavorite" : "Favorite", systemImage: "star") {
                        Task { await model.setFavorite(conversation, favorite: placement?.favorite != true) }
                    }
                    Button(conversation.pinned ? "Unpin" : "Pin", systemImage: "pin") {
                        Task { await model.setPinned(conversation, pinned: !conversation.pinned) }
                    }
                    Button("Chat settings", systemImage: "slider.horizontal.3") { showingChatSettings = true }
                }
            }
        }
        .transition(.scale(scale: 0.94, anchor: message.role == .user ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
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

    private var composerCorner: CGFloat {
        showingCamera || expandedPhoto != nil ? 22 : 28
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = model.errorMessage ?? model.verificationStatus ?? model.evaluationStatus ?? dictation.status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("nodus.chat.composer-status")
            }
            VStack(alignment: .leading, spacing: 8) {
                activeContextChips
                attachmentStrip
                if showingCamera {
                    NodusInlineCamera(onCapture: { image in
                        let item = NodusComposerAttachment(title: "Photo", image: image)
                        withAnimation(motion(.morph)) {
                            attachments.append(item)
                            showingCamera = false
                            expandedPhoto = "draft-\(item.id.uuidString)"
                        }
                    }, onClose: { showingCamera = false })
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                if value.translation.height > 70 { showingCamera = false }
                            }
                    )
                }
                TextField("Ask Nodus…", text: $model.input, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitComposer() }
                    .disabled(model.availability != .available || model.isGenerating)
                    .accessibilityIdentifier("nodus.chat.input")

                HStack(spacing: 8) {
                    composerMenu
                    Button { showingChatSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chat settings")
                    .accessibilityIdentifier("nodus.chat.settings")
                    thinkControl
                    modeButton(
                        model.activeConversation?.searchEnabled == true ? "Search" : nil,
                        symbol: "network",
                        selected: model.activeConversation?.searchEnabled == true
                    ) { toggleSearch() }
                    Spacer(minLength: 4)
                    Button {
                        dictation.toggle(current: { model.input }, apply: { model.input = $0 })
                    } label: {
                        Image(systemName: dictation.isListening ? "waveform" : "mic")
                            .font(.body.weight(.semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                            .contentShape(Rectangle())
                            .foregroundStyle(dictation.isListening ? accent : Color.primary)
                            .symbolEffect(.variableColor.iterative, isActive: dictation.isListening)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate")
                    .accessibilityIdentifier("nodus.chat.dictate")
                    sendButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .modulaChrome(in: RoundedRectangle(cornerRadius: composerCorner, style: .continuous), opaque: false)
            .modulaMascotPerch()
            .overlay {
                NodusComposerPulse(
                    active: model.isGenerating,
                    corner: composerCorner,
                    color: app.appearance.liveAccent
                )
                RoundedRectangle(cornerRadius: composerCorner, style: .continuous)
                    .strokeBorder(app.appearance.liveAccent.opacity(composerFocused && !model.isGenerating ? 0.32 : 0), lineWidth: 1)
            }
            .scaleEffect(composerFocused && !reduceMotion ? 1.015 : 1, anchor: .bottom)
            .animation(motion(.morph), value: composerCorner)
            .animation(motion(.morph), value: composerFocused)
            .animation(.easeInOut(duration: 0.35), value: model.isGenerating)
            .modulaComposerMascot(.nodus, busy: model.isGenerating, text: model.input, attachmentCount: attachments.count, trailingInset: 30)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: sendTick)
        .sensoryFeedback(.selection, trigger: model.thinkStep)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { item in
                        if let image = item.image {
                            let geometryID = "draft-\(item.id.uuidString)"
                            NodusPhotoThumb(
                                image: image,
                                title: item.title,
                                open: expandedPhoto == geometryID,
                                namespace: photoMorph,
                                geometryID: geometryID,
                                onOpen: {
                                    withAnimation(motion(.morph)) { expandedPhoto = geometryID }
                                },
                                onRemove: { removeAttachment(item) }
                            )
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                                Button { removeAttachment(item) } label: {
                                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(item.title)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            Text("Tap a photo to preview. Swipe it away to remove. Nodus reads your words, not the picture.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var photoStage: some View {
        if let expandedPhoto, let image = photo(for: expandedPhoto) {
            NodusPhotoStage(
                image: image.image,
                title: image.title,
                namespace: photoMorph,
                geometryID: expandedPhoto,
                onClose: { self.expandedPhoto = nil }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
            .transition(.opacity)
        }
    }

    private func photo(for geometryID: String) -> (image: UIImage, title: String)? {
        if geometryID.hasPrefix("draft-"),
           let id = UUID(uuidString: String(geometryID.dropFirst("draft-".count))),
           let item = attachments.first(where: { $0.id == id }),
           let image = item.image {
            return (image, item.title)
        }
        if geometryID.hasPrefix("message-"),
           let id = UUID(uuidString: String(geometryID.dropFirst("message-".count))),
           let image = model.attachmentImages[id] {
            return (image, "Photo")
        }
        return nil
    }

    private func removeAttachment(_ item: NodusComposerAttachment) {
        if expandedPhoto == "draft-\(item.id.uuidString)" { expandedPhoto = nil }
        attachments.removeAll { $0.id == item.id }
    }

    /// Explicit New Chat control. The previous scroll over-pull trigger
    /// could start a chat accidentally while reading the bottom of a reply.
    private var newChatHandle: some View {
        Button {
            beginNewChat()
            HapticEngine.shared.play(.navigation)
        } label: {
            HStack(spacing: 10) {
                if creatingChat {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus.bubble")
                        .font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New chat")
                        .font(.subheadline.weight(.semibold))
                    Text("The new chat stays on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
            .modulaChrome(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), opaque: false)
            .contentShape(RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous))
        }
        .buttonStyle(NodusPressStyle())
        .disabled(creatingChat || model.isGenerating)
        .padding(.top, 6)
        .accessibilityLabel("New chat")
        .accessibilityIdentifier("nodus.chat.new-chat")
    }

    private func beginNewChat() {
        guard !creatingChat, !model.isGenerating else { return }
        creatingChat = true
        Task {
            await model.newConversation()
            composerFocused = true
            creatingChat = false
        }
    }

    private func perform(_ function: NodusChatFunction) {
        switch function {
        case .speak:
            if let text = model.messages.last(where: { $0.role == .nodus })?.text {
                speak(text)
            }
        case .note:
            if let conversation = model.activeConversation, let text = model.messages.last(where: { $0.role == .nodus })?.text {
                Task { await model.setNote(conversation, note: text) }
            }
        case .prompt:
            if let text = model.messages.last(where: { $0.role == .nodus })?.text {
                let projectID = model.activeConversation.flatMap { model.library.project(for: $0.id)?.id }
                Task { await model.savePrompt(title: "From chat", body: text, projectID: projectID) }
            }
        case .time:
            let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)
            let current = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
            model.input = current.isEmpty ? stamp : current + "\n" + stamp
            composerFocused = true
        }
    }

    private func speak(_ text: String) {
        if speaker.isSpeaking {
            speaker.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: String(text.prefix(900)))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speaker.speak(utterance)
    }

    private func followConnector() {
        let next = connectorFollowUp
        connectorFollowUp = nil
        switch next {
        case .knowledge: showingKnowledge = true
        case .memory: showingMemory = true
        case .library: showingConversations = true
        case nil: break
        }
    }

    private func reply(to message: NodusMessage) {
        let quoted = message.text.split(separator: "\n").prefix(4).joined(separator: "\n")
        model.input = "“\(quoted)”\n"
        composerFocused = true
    }

    @ViewBuilder
    private var activeContextChips: some View {
        let knowledgeCount = model.activeConversation?.attachedKnowledgeCollectionIDs.count ?? 0
        let memoryEnabled = model.activeConversation?.memoryEnabled == true
        let project = model.activeConversation.flatMap { model.library.project(for: $0.id) }
        let folder = model.activeConversation.flatMap { model.library.folder(for: $0.id) }
        if knowledgeCount > 0 || memoryEnabled || project != nil || folder != nil || !model.activePersona.isEmpty || !model.activeSkills.isEmpty {
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
                    if let project {
                        contextChip(project.name, symbol: project.symbol) { showingConversations = true }
                    }
                    if let folder {
                        contextChip(folder.name, symbol: "folder") { showingConversations = true }
                    }
                    if !model.activePersona.isEmpty {
                        contextChip("Persona", symbol: "person") { showingPersona = true }
                    }
                    if !model.activeSkills.isEmpty {
                        contextChip("Skills · \(model.activeSkills.count)", symbol: "wand.and.stars") { showingSkills = true }
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
                .background(accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var composerMenu: some View {
        Menu {
            Button("Knowledge", systemImage: "books.vertical") { showingKnowledge = true }
            Button("Browse Memory", systemImage: "memorychip") { showingMemory = true }
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
            Divider()
            Menu("Attach", systemImage: "paperclip") {
                Button("Camera", systemImage: "camera") { showingCamera = true }
                Button("Photos", systemImage: "photo") { showingPhotos = true }
                Button("Files", systemImage: "doc") { showingFiles = true }
            }
            Menu("Library", systemImage: "square.stack.3d.up") {
                Button("Projects", systemImage: "square.stack.3d.up") { showingConversations = true }
                Button("Folders", systemImage: "folder") { showingConversations = true }
                Button("New Chat", systemImage: "plus.bubble") {
                    Task { await model.newConversation(); composerFocused = true }
                }
                Button("Chat Settings", systemImage: "slider.horizontal.3") { showingChatSettings = true }
            }
            Menu("Info", systemImage: "info.circle") {
                Button("Models", systemImage: "brain") { showingModels = true }
                Button("Attached", systemImage: "link") { showingConnectors = true }
                Button("Remote", systemImage: "antenna.radiowaves.left.and.right") { showingRemote = true }
                Button("System Info", systemImage: "info.circle") { showingSystemInfo = true }
            }
            Menu("Studio", systemImage: "slider.horizontal.3") {
                Button("Skills", systemImage: "wand.and.stars") { showingSkills = true }
                Button("Persona", systemImage: "person") { showingPersona = true }
                Button("Customise", systemImage: "paintpalette") { showingCustomise = true }
                Button("Marketplace", systemImage: "storefront") { showingPrompts = true }
                Button("Reply tools", systemImage: "speaker.wave.2") { showingFunctions = true }
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .modulaChrome(in: Circle(), opaque: false)
                .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                .contentShape(Circle())
        }
        .accessibilityLabel("Add context")
        .accessibilityIdentifier("nodus.chat.add-context")
    }

    private var thinkControl: some View {
        modeButton(
            model.thinkStep == .standard ? nil : model.thinkStep.title,
            symbol: "brain",
            selected: model.thinkStep != .standard
        ) {
            Task {
                await model.setReasoningMode(model.thinkStep.reasoningMode == .deep ? .standard : .deep)
            }
        }
        .accessibilityValue(model.thinkStep.reasoningMode == .deep ? "On" : "Off")
        .accessibilityHint("Hold to set how long Nodus may write, and whether it reviews the draft.")
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            showingThinkBudget = true
        })
        .popover(isPresented: $showingThinkBudget, attachmentAnchor: .rect(.bounds)) {
            NodusThinkBudgetPopover(step: model.thinkStep) { steps in
                Task { await model.setThinkSteps(steps) }
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var sendButton: some View {
        let ready = model.isGenerating || model.canSend || !attachments.isEmpty
        return ModulaGlassSendButton(
            title: model.isGenerating ? "Stop" : "Send",
            systemImage: model.isGenerating ? "stop.fill" : "arrow.up",
            ready: ready,
            size: 38,
            tint: accent
        ) {
            model.isGenerating ? model.cancel() : submitComposer()
        }
        .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
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
        .background(selected ? accent.opacity(0.16) : Color.clear, in: Capsule())
        .frame(minWidth: ModulaLayout.minimumTouch, minHeight: ModulaLayout.minimumTouch)
        .contentShape(Capsule())
        .foregroundStyle(selected ? accent : Color.primary)
        .symbolEffect(.bounce, value: selected)
        .animation(motion(.morph), value: selected)
        .accessibilityLabel(symbol == "brain" ? "Think" : "Search")
        .accessibilityValue(selected ? "On" : "Off")
    }

    private func submitComposer() {
        guard !model.isGenerating else { return }
        var question = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = attachments.compactMap(\.note).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !notes.isEmpty {
            let block = notes.joined(separator: "\n\n")
            question = question.isEmpty ? block : question + "\n\n" + block
        }
        if question.isEmpty, !attachments.isEmpty {
            question = "Attached on this iPhone: " + attachments.map(\.title).joined(separator: ", ")
        }
        guard !question.isEmpty else { return }
        let images = attachments.compactMap { $0.image?.jpegData(compressionQuality: 0.82) }
        model.input = question
        withAnimation(motion(.morph)) {
            attachments.removeAll()
            expandedPhoto = nil
            showingCamera = false
        }
        dictation.stop()
        sendTick += 1
        model.send(using: app, imageData: images)
    }

    private var latestNodusID: UUID? {
        model.messages.last(where: { $0.role == .nodus })?.id
    }

    private func messageActions(_ message: NodusMessage) -> some View {
        HStack(spacing: 8) {
            replyAction(
                copiedMessageID == message.id ? "Copied" : "Copy",
                symbol: copiedMessageID == message.id ? "checkmark" : "doc.on.doc"
            ) {
                UIPasteboard.general.string = message.text
                withAnimation(motion(.morph)) { copiedMessageID = message.id }
                Task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    if copiedMessageID == message.id { copiedMessageID = nil }
                }
            }
            replyAction("Again", symbol: "arrow.clockwise") { regenerate() }
            replyAction("Reply", symbol: "arrowshape.turn.up.left") { reply(to: message) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func replyAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .modulaChrome(in: Capsule(), opaque: false)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(NodusPressStyle())
        .accessibilityLabel(title)
    }

    private func regenerate() {
        guard !model.isGenerating, let previous = model.messages.last(where: { $0.role == .user })?.text, !previous.isEmpty else { return }
        model.input = previous
        submitComposer()
    }

    private func handlePlugin(_ plugin: NodusComposerPlugin) {
        switch plugin {
        case .knowledge:
            showingKnowledge = true
        case .memory:
            showingMemory = true
        case .camera:
            showingCamera = true
        case .photos:
            showingPhotos = true
        case .files:
            showingFiles = true
        case .projects, .folders:
            showingConversations = true
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let attachment = NodusComposerAttachment(title: "Photo", image: image)
        withAnimation(motion(.morph)) {
            attachments.append(attachment)
            expandedPhoto = "draft-\(attachment.id.uuidString)"
        }
    }

    private func importFile(_ source: URL) async {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let name = source.lastPathComponent
        var note: String?
        if let data = try? Data(contentsOf: source), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            let excerpt = String(text.prefix(1500))
            note = "File note from \(name), kept on this iPhone:\n\(excerpt)"
        }
        let image = UIImage(contentsOfFile: source.path)
        let attachment = NodusComposerAttachment(title: name, image: image, note: note)
        withAnimation(motion(.morph)) {
            attachments.append(attachment)
            if image != nil { expandedPhoto = "draft-\(attachment.id.uuidString)" }
        }
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
                    .tint(model.ratings[message.id] == rating ? accent : nil)
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

    private var chatTint: NodusChatTint {
        let name = model.activeConversation.flatMap { model.library.placement(for: $0.id)?.color } ?? ""
        return NodusChatTint(rawValue: name) ?? .accent
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    NodusThinkingOrb(stage: .finalizing, reduceMotion: reduceMotion, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nodus")
                            .font(.title2.weight(.semibold))
                        Text("On this iPhone. Hold Think to set the reply budget.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(welcomeAppeared || reduceMotion ? 1 : 0)
                .offset(y: welcomeAppeared || reduceMotion ? 0 : 10)
                .animation(motion(.morph), value: welcomeAppeared)
                HStack(spacing: 8) {
                    welcomeChip("Marketplace", symbol: "storefront") { showingPrompts = true }
                    welcomeChip("Knowledge", symbol: "books.vertical") { showingKnowledge = true }
                    welcomeChip("Memory", symbol: "memorychip") { showingMemory = true }
                }
                HStack(spacing: 8) {
                    welcomeChip("Skills", symbol: "wand.and.stars") { showingSkills = true }
                    welcomeChip("Persona", symbol: "person") { showingPersona = true }
                    welcomeChip("Reply tools", symbol: "speaker.wave.2") { showingFunctions = true }
                }
                newChatHandle
                VStack(spacing: 8) {
                    ForEach(Array(NodusMarketCatalog.featured.enumerated()), id: \.element.id) { index, prompt in
                        Button {
                            model.input = prompt.body
                            composerFocused = true
                        } label: {
                            HStack(spacing: 12) {
                                NodusStudioGlyph(symbol: prompt.symbol)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prompt.title).foregroundStyle(.primary)
                                    Text(prompt.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .modulaChrome(in: RoundedRectangle(cornerRadius: 18, style: .continuous), opaque: false)
                        }
                        .buttonStyle(.plain)
                        .opacity(welcomeAppeared || reduceMotion ? 1 : 0)
                        .offset(y: welcomeAppeared || reduceMotion ? 0 : 14)
                        .animation(motion(.reveal)?.delay(reduceMotion ? 0 : 0.05 * Double(index + 1)), value: welcomeAppeared)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if reduceMotion { welcomeAppeared = true }
            else { withAnimation(motion(.morph)) { welcomeAppeared = true } }
        }
        .accessibilityIdentifier("nodus.chat.empty")
    }

    private func welcomeChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .modulaChrome(in: Capsule(), opaque: false)
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch model.availability {
        case .available:
            if model.isGenerating { return model.progressText ?? "Generating locally" }
            return model.loadState == .loading ? "Loading Nodus…" : "Ready · \(model.thinkStep.title) · stays local"
        case .modelNotInstalled: return "Model not installed"
        default: return model.availability.displayName
        }
    }
}


private struct NodusPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.4), value: configuration.isPressed)
    }
}

private final class NodusPathMonitor: ObservableObject, @unchecked Sendable {
    @Published var status = "Checking"
    @Published var interfaceName = "—"
    private let monitor = NWPathMonitor()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let label = Self.describe(path)
            let interface = Self.interfaceName(for: path)
            DispatchQueue.main.async {
                self?.status = label
                self?.interfaceName = interface
            }
        }
        monitor.start(queue: DispatchQueue(label: "nodus.path"))
    }

    private static func interfaceName(for path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular) { return "Cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "Wired" }
        if path.status != .satisfied { return "None" }
        return "Other"
    }

    private static func describe(_ path: NWPath) -> String {
        switch path.status {
        case .satisfied:
            if path.isConstrained { return "Online, constrained" }
            if path.isExpensive { return "Online, limited" }
            return "Online"
        case .unsatisfied:
            return "Offline"
        case .requiresConnection:
            return "Needs a connection"
        @unknown default:
            return "Unknown"
        }
    }
}

private struct NodusReplyGlass: ViewModifier {
    var enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.modulaChrome(in: RoundedRectangle(cornerRadius: 22, style: .continuous), opaque: false)
        } else {
            content
        }
    }
}

private struct NodusComposerPulse: View {
    var active: Bool
    var corner: CGFloat
    var color: Color

    var body: some View {
        Group {
            if active {
                PhaseAnimator([0.22, 0.72]) { phase in
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(color.opacity(phase), lineWidth: 1.2)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
            }
        }
        .allowsHitTesting(false)
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
// End of Release-shipped Nodus Chat surface.
