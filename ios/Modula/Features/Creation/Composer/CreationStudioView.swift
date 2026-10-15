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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var editorFocused: Bool
    @State private var store: CreationStudioStore?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
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
                if store.saveAndExit() { close() }
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
        let accent = app.appearance.accent.color
        return HStack(spacing: 12) {
            Button {
                if store.draft.isPublishing {
                    publishTask?.cancel()
                } else {
                    exitTapped(store)
                }
            } label: {
                Text(store.draft.isPublishing ? "Stop" : "Cancel")
                    .font(.body.weight(.medium))
                    .foregroundStyle(store.draft.isPublishing ? Color.red.opacity(0.9) : Color.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .modulaGlass(in: Capsule(), interactive: true, specular: true)
            }
            .buttonStyle(.plain)
            .fontDesign(.default)
            .accessibilitySortPriority(100)

            Spacer(minLength: 8)

            if app.drafts.saveError != nil {
                Label("Not saved", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .accessibilityLabel(app.drafts.saveError ?? "Draft not saved")
            } else {
                DraftStatusView(saved: app.drafts.showSavedIndicator, publishing: store.draft.isPublishing)
                    .accessibilitySortPriority(20)
            }

            Button {
                startPublishing(store)
            } label: {
                Text(store.draft.kind.publishLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(store.canPublish ? Color.white : accent.opacity(0.55))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .modulaGlass(
                        in: Capsule(),
                        interactive: store.canPublish,
                        tint: accent,
                        prominent: store.canPublish,
                        specular: true
                    )
            }
            .buttonStyle(.plain)
            .fontDesign(.default)
            .disabled(!store.canPublish)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.canPublish)
            .accessibilityHint(store.publishHint ?? "Publishes this post")
            .accessibilitySortPriority(10)
            .accessibilityIdentifier("compose.publish")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
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
            // Settings → Photos → "Explain Limited Library" — quiet secondary footnote.
            if ModulaPreferences.explainLimitedLibrary, store.draft.media.isEmpty,
               store.capabilities.toolEnabled(.photo) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    Text("Modula only sees the photos you pick — it never needs access to your whole library.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fontDesign(.default)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            // Pinned above the tool dock so a failed publish is always visible,
            // instead of sitting at the bottom of a long draft in grey text.
            if let error = store.publishError {
                ModulaErrorBanner(message: error, identifier: "compose.publish.error") {
                    store.publishError = nil
                }
                .padding(.top, ModulaSpacing.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    HapticEngine.shared.play(.failure)
                    AccessibilityNotification.Announcement(error).post()
                }
            }
            CreationToolDock(
                kind: store.draft.kind,
                capabilities: store.capabilities,
                developerMode: app.commandCapabilities().developerMode,
                accent: app.appearance.accent.color,
                photoPicker: {
                    let accent = app.appearance.accent.color
                    HStack(spacing: 6) {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: store.capabilities.carouselPost ? (store.capabilities.maxMediaCount ?? 10) : 1,
                            matching: .images
                        ) {
                            CreationToolChipLabel(
                                title: "Photo",
                                symbol: "photo.on.rectangle.angled",
                                accent: accent,
                                enabled: store.capabilities.toolEnabled(.photo),
                                emphasized: true
                            )
                        }
                        .disabled(!store.capabilities.toolEnabled(.photo))
                        if store.capabilities.toolEnabled(.photo), UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showsCamera = true
                            } label: {
                                CreationToolChipLabel(
                                    title: "Camera",
                                    symbol: "camera.fill",
                                    accent: accent,
                                    enabled: true,
                                    emphasized: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Camera")
                            .accessibilityIdentifier("compose.tool.camera")
                        }
                    }
                },
                videoPicker: {
                    PhotosPicker(selection: $videoPickerItems, maxSelectionCount: 1, matching: .videos) {
                        CreationToolChipLabel(
                            title: "Video",
                            symbol: "video.fill",
                            accent: app.appearance.accent.color,
                            enabled: store.capabilities.videoPost,
                            emphasized: true
                        )
                    }
                    .disabled(!store.capabilities.videoPost)
                },
                onTool: { tool in
                    handle(tool, store: store)
                }
            )
            .fontDesign(.default)
            .accessibilitySortPriority(40)
            .fullScreenCover(isPresented: $showsCamera) {
                ModulaCameraCaptureView(
                    onCapture: { data, mimeType in
                        showsCamera = false
                        Task { await store.attachCapturedPhoto(data, mimeType: mimeType) }
                    },
                    onClose: { showsCamera = false }
                )
            }
        }
    }

    private func authorRow(_ store: CreationStudioStore) -> some View {
        HStack(spacing: 12) {
            ModulaAvatar(
                initials: String((app.auth.account?.displayName ?? app.auth.account?.primaryHandle ?? "M").prefix(2)).uppercased(),
                size: 40,
                name: app.auth.account?.displayName
            )
            AudiencePicker(selection: Binding(
                get: { store.draft.audience },
                set: { store.setAudience($0) }
            ))
            .accessibilitySortPriority(90)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func editor(_ store: CreationStudioStore) -> some View {
        let accent = app.appearance.accent.color
        let stage = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return TextEditor(text: Binding(
            get: { store.draft.text },
            set: { store.handlePaste($0) }
        ))
        .font(.body)
        .fontDesign(app.appearance.fontDesign)
        // Settings → Keyboard.
        .autocorrectionDisabled(!ModulaPreferences.composerAutocorrect)
        .textInputAutocapitalization(ModulaPreferences.composerAutoCapitalise ? .sentences : .never)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 200)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .focused($editorFocused)
        .background {
            stage
                .fill(accent.opacity(editorFocused ? (colorScheme == .dark ? 0.12 : 0.06) : 0.04))
        }
        .modulaGlass(in: stage, interactive: false, tint: editorFocused ? accent.opacity(0.22) : nil, specular: true)
        .overlay {
            stage.strokeBorder(
                editorFocused ? accent.opacity(0.55) : Color.primary.opacity(0.08),
                lineWidth: editorFocused ? 1.4 : 0.8
            )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: editorFocused)
        .overlay(alignment: .topLeading) {
            if store.draft.text.isEmpty {
                Text(placeholder(store))
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.72))
                    .padding(.top, 20)
                    .padding(.leading, 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
        // Settings → Creator → "Show insights tip after publish".
        if ModulaPreferences.creatorShowsInsightsHint {
            app.navigation.flash("Posted. See how it does in Settings → Creator → Insights.", symbol: "chart.line.uptrend.xyaxis")
        }
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
