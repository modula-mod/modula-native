import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CreationStudioView: View {
    var route: ComposeRoute?
    var kind: CreationKind
    var draftID: String?

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
    @State private var store: CreationStudioStore?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var moreExplanation: CreationTool?
    @State private var publishTask: Task<Void, Never>?

    init(route: ComposeRoute) {
        self.route = route
        self.kind = CreationKind(route)
    }

    init(kind: CreationKind, draftID: String? = nil) {
        self.kind = kind
        self.draftID = draftID
    }

    var body: some View {
        Group {
            if let store {
                studio(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modulaCanvas()
        .onAppear(perform: bootstrap)
        .onDisappear {
            publishTask?.cancel()
            publishTask = nil
            store?.flush()
        }
        .onChange(of: app.auth.account?.accountId) { _, id in
            app.drafts.setAccountID(id)
        }
    }

    @ViewBuilder
    private func studio(_ store: CreationStudioStore) -> some View {
        VStack(spacing: 0) {
            header(store)
            if store.kindUnavailable {
                unavailable(store)
            } else {
                composer(store)
            }
        }
        .accessibilityIdentifier("compose.studio")
        .navigationBarBackButtonHidden(true)
        .modulaSoftScrollEdge()
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onKeyPress(.escape) {
            exitTapped(store)
            return .handled
        }
        .confirmationDialog("Continue your draft?", isPresented: restoreBinding(store), titleVisibility: .visible) {
            Button("Continue Draft") { store.continueDraft() }
            Button("Start New", role: .destructive) { store.startNew() }
        } message: {
            Text(store.restoreCandidate?.preview ?? "You have an unfinished post.")
        }
        .confirmationDialog("Save this draft?", isPresented: exitBinding(store), titleVisibility: .visible) {
            Button("Save Draft") {
                store.saveAndExit()
                close()
            }
            Button("Discard", role: .destructive) {
                store.discard()
                close()
            }
            Button("Continue Editing", role: .cancel) {}
        }
        .sheet(item: altTextBinding(store)) { media in
            NavigationStack {
                AltTextEditor(text: media.altText) { value in
                    store.setAltText(media.id, text: value)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await store.attachImages(items) }
            pickerItems = []
        }
        .onChange(of: videoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await store.attachVideos(items) }
            videoPickerItems = []
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf, .audio, .movie, .image,
                                  .init(filenameExtension: "doc") ?? .data,
                                  .init(filenameExtension: "docx") ?? .data,
                                  .init(filenameExtension: "ppt") ?? .data,
                                  .init(filenameExtension: "pptx") ?? .data,
                                  .init(filenameExtension: "xls") ?? .data,
                                  .init(filenameExtension: "xlsx") ?? .data,
                                  .zip],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { Task { await store.attachFiles(urls) } }
            if case .failure = result { store.publishError = "Couldn't open those files. Your draft is safe." }
        }
        .alert(
            moreExplanation?.title ?? "Unavailable",
            isPresented: Binding(
                get: { moreExplanation != nil },
                set: { if !$0 { moreExplanation = nil } }
            )
        ) {
            Button("OK", role: .cancel) { moreExplanation = nil }
        } message: {
            Text(store.capabilities.unavailableReason[kindForTool(moreExplanation)] ?? "This tool isn’t available yet.")
        }
    }

    private func header(_ store: CreationStudioStore) -> some View {
        HStack(spacing: 12) {
            Button(store.draft.isPublishing ? "Stop" : "Cancel") {
                if store.draft.isPublishing {
                    publishTask?.cancel()
                } else {
                    exitTapped(store)
                }
            }
                .fontDesign(.default)
                .accessibilitySortPriority(100)
            Spacer()
            DraftStatusView(saved: app.drafts.showSavedIndicator, publishing: store.draft.isPublishing)
                .accessibilitySortPriority(20)
            Button(store.draft.kind.publishLabel) {
                startPublishing(store)
            }
            .fontWeight(.semibold)
            .fontDesign(.default)
            .disabled(!store.canPublish)
            .accessibilityHint(store.publishHint ?? "Publishes this post")
            .accessibilitySortPriority(10)
            .accessibilityIdentifier("compose.publish")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .font(.body)
    }

    private func composer(_ store: CreationStudioStore) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    authorRow(store)
                    editor(store)
                    if !store.draft.media.isEmpty {
                        MediaAttachmentGrid(
                            media: store.draft.media,
                            fileURL: { app.draftMedia.fileURL($0) },
                            onMoveEarlier: { store.moveMedia(id: $0, earlier: true) },
                            onMoveLater: { store.moveMedia(id: $0, earlier: false) },
                            onRemove: store.removeMedia,
                            onAltText: { store.altTextMediaID = $0 },
                            onRotate: { id in Task { await store.rotateMedia(id) } },
                            reduceMotion: reduceMotion
                        )
                        .accessibilitySortPriority(70)
                    }
                    if store.capabilities.linkPost || store.draft.link != nil {
                        LinkPreviewEditor(
                            urlString: store.draft.link?.urlString ?? "",
                            preview: store.draft.link,
                            editableMetadata: false,
                            onChange: store.setLinkURL
                        )
                    }
                    if store.draft.kind == .poll || (store.capabilities.pollPost && store.draft.poll != nil) {
                        if let poll = store.draft.poll {
                            PollEditor(
                                poll: poll,
                                maxOptions: store.capabilities.maxPollOptions ?? 4,
                                onChange: store.setPoll
                            )
                        }
                    }
                    if let error = store.publishError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("compose.publish.error")
                    }
                    if store.draft.state == .failed {
                        HStack {
                            Button("Retry") { startPublishing(store) }
                            Button("Edit") { store.draft.state = .editing }
                        }
                        .fontDesign(.default)
                    }
                    UploadProgressSurface(
                        fraction: store.uploadFraction,
                        preparing: store.preparingMedia,
                        state: store.draft.state
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .modulaSoftScrollEdge()
            CreationToolDock(
                kind: store.draft.kind,
                capabilities: store.capabilities,
                developerMode: app.commandCapabilities().developerMode,
                photoPicker: {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: store.capabilities.carouselPost ? (store.capabilities.maxMediaCount ?? 10) : 1, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                            Text("Photo")
                                .font(.caption2)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(!store.capabilities.toolEnabled(.photo))
                },
                videoPicker: {
                    PhotosPicker(selection: $videoPickerItems, maxSelectionCount: 1, matching: .videos) {
                        VStack(spacing: 4) {
                            Image(systemName: "video")
                            Text("Video").font(.caption2)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(!store.capabilities.videoPost)
                },
                onTool: { tool in
                    handle(tool, store: store)
                }
            )
            .fontDesign(.default)
            .accessibilitySortPriority(40)
        }
    }

    private func authorRow(_ store: CreationStudioStore) -> some View {
        HStack(spacing: 10) {
            ModulaAvatar(
                initials: String((app.auth.account?.displayName ?? app.auth.account?.primaryHandle ?? "M").prefix(2)).uppercased(),
                size: 36
            )
            AudiencePicker(selection: Binding(
                get: { store.draft.audience },
                set: { store.setAudience($0) }
            ))
            .accessibilitySortPriority(90)
            Spacer()
        }
    }

    private func editor(_ store: CreationStudioStore) -> some View {
        TextEditor(text: Binding(
            get: { store.draft.text },
            set: { store.handlePaste($0) }
        ))
        .font(.body)
        .fontDesign(app.appearance.fontDesign)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 180)
        .focused($editorFocused)
        .overlay(alignment: .topLeading) {
            if store.draft.text.isEmpty {
                Text(placeholder(store))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Post text")
        .accessibilityIdentifier("compose.editor")
        .accessibilitySortPriority(80)
        .onChange(of: store.pasteLinkSuggestion) { _, url in
            _ = url
        }
        .alert("Add this link?", isPresented: Binding(
            get: { store.pasteLinkSuggestion != nil && store.capabilities.linkPost },
            set: { if !$0 { store.dismissPastedLink() } }
        )) {
            Button("Add Link") { store.acceptPastedLink() }
            Button("Keep as text", role: .cancel) { store.dismissPastedLink() }
        } message: {
            Text(store.pasteLinkSuggestion?.absoluteString ?? "")
        }
    }

    private func unavailable(_ store: CreationStudioStore) -> some View {
        ModulaEmptyState(
            title: store.draft.kind.title,
            message: store.unavailableCopy,
            symbol: "slash.circle"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("compose.unavailable")
    }

    private func placeholder(_ store: CreationStudioStore) -> String {
        switch store.draft.kind {
        case .story: "Add text"
        case .reel: "Caption"
        default: "What's happening?"
        }
    }

    private func handle(_ tool: CreationTool, store: CreationStudioStore) {
        if !store.capabilities.toolEnabled(tool) {
            moreExplanation = tool
            return
        }
        switch tool {
        case .photo:
            break
        case .link:
            if store.draft.link == nil {
                store.setLinkURL("https://")
            }
        case .poll:
            store.setPoll(store.draft.poll ?? PollDraft.blank(optionLimit: store.capabilities.maxPollOptions ?? 4))
        case .video:
            break
        case .more:
            showFileImporter = true
        }
    }

    private func bootstrap() {
        guard store == nil else { return }
        if let draftID {
            app.drafts.pendingResumeID = draftID
        }
        app.drafts.setAccountID(app.auth.account?.accountId)
        let accountID = app.auth.account?.accountId ?? ""
        let created = CreationStudioStore(
            kind: kind,
            accountID: accountID,
            originPath: RouteSerializer.serialize(app.navigation.currentRoute),
            drafts: app.drafts,
            mediaStore: app.draftMedia,
            publisher: app.publishing,
            uploader: app.mediaUploader,
            capabilities: app.creationCapabilities
        )
        if accountID.isEmpty {
            created.publishError = "Sign in to compose. Drafts stay with your account."
        }
        created.start()
        store = created
        editorFocused = !created.kindUnavailable
    }

    private func publish(_ store: CreationStudioStore) async {
        guard let post = await store.publish() else {
            if store.publishError?.contains("Sign in") == true {
                app.navigation.requestAuthentication(returningTo: route.map { .compose($0) } ?? .compose(.post))
            }
            return
        }
        app.postActions.ingest(post)
        app.home.ingestPublished(post)
        app.profile.ingestPublished(post)
        close()
    }

    private func startPublishing(_ store: CreationStudioStore) {
        guard publishTask == nil else { return }
        publishTask = Task {
            await publish(store)
            publishTask = nil
        }
    }

    private func exitTapped(_ store: CreationStudioStore) {
        switch store.requestExit() {
        case .dismiss: close()
        case .prompt: break
        }
    }

    private func kindForTool(_ tool: CreationTool?) -> CreationKind {
        switch tool {
        case .photo: .photo
        case .video: .video
        case .link: .link
        case .poll: .poll
        case .more, .none: kind
        }
    }

    private func close() {
        store?.flush()
        if app.navigation.presented != nil {
            app.navigation.presented = nil
        } else {
            app.navigation.close()
        }
        dismiss()
    }

    private func restoreBinding(_ store: CreationStudioStore) -> Binding<Bool> {
        Binding(get: { store.showRestorePrompt }, set: { store.showRestorePrompt = $0 })
    }

    private func exitBinding(_ store: CreationStudioStore) -> Binding<Bool> {
        Binding(get: { store.showExitPrompt }, set: { store.showExitPrompt = $0 })
    }

    private func altTextBinding(_ store: CreationStudioStore) -> Binding<CreationMedia?> {
        Binding(
            get: { store.draft.media.first { $0.id == store.altTextMediaID } },
            set: { store.altTextMediaID = $0?.id }
        )
    }
}
