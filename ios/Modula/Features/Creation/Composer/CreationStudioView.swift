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
    @Namespace private var glassMorph
    @State private var store: CreationStudioStore?
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var mediaStage: ComposeMediaStage = .collapsed
    @State private var showFileImporter = false
    @State private var showMoreOptions = false
    @State private var localLinkURL = "https://"
    @State private var appeared = false
    @State private var publishTask: Task<Void, Never>?
    @State private var publishMorph = false

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
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.97))
        .accessibilityIdentifier("compose.studio")
        .navigationBarBackButtonHidden(true)
        .modulaSoftScrollEdge()
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.86)) {
                appeared = true
            }
        }
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
        .sheet(isPresented: $showMoreOptions) {
            CreationMoreOptionsSheet(
                capabilities: store.capabilities,
                accent: app.appearance.accent.color,
                onFiles: { showFileImporter = true },
                onLink: {
                    localLinkURL = "https://"
                    store.showsLocalLinkEditor = true
                    store.showsLocalPollEditor = false
                },
                onPoll: {
                    store.showsLocalPollEditor = true
                    store.showsLocalLinkEditor = false
                },
                onMentionsTip: {
                    store.composerTip = "Type @ followed by a name — suggestions come from Greenfield search."
                    editorFocused = true
                },
                onHashtagsTip: {
                    store.composerTip = "Type # for topic suggestions from Greenfield."
                    editorFocused = true
                }
            )
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
                    .scaleEffect(publishMorph ? 0.92 : 1)
                    .modulaGlass(
                        in: Capsule(),
                        interactive: store.canPublish,
                        tint: accent,
                        prominent: store.canPublish,
                        specular: true
                    )
                    .modulaGlassID("compose.publish", in: glassMorph)
            }
            .buttonStyle(.plain)
            .fontDesign(.default)
            .disabled(!store.canPublish)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: store.canPublish)
            .accessibilityHint(store.publishHint ?? "Publishes this post")
            .accessibilitySortPriority(10)
            .accessibilityIdentifier("compose.publish")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func composer(_ store: CreationStudioStore) -> some View {
        let accent = app.appearance.accent.color
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identityStage(store)

                    writingCanvas(store)

                    if !store.mentionSuggestions.isEmpty || !store.hashtagSuggestions.isEmpty {
                        CreationSuggestionRail(
                            mentions: store.mentionSuggestions,
                            hashtags: store.hashtagSuggestions,
                            accent: accent,
                            onMention: store.applyMention,
                            onHashtag: store.applyHashtag
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }

                    if mediaStage.isExpanded {
                        ComposeMediaAttachStage(
                            stage: $mediaStage,
                            accent: accent,
                            idPrefix: "compose.media",
                            height: 300,
                            maxSelectionCount: store.capabilities.carouselPost
                                ? (store.capabilities.maxMediaCount ?? 10) : 1,
                            matching: .images,
                            cameraModes: store.capabilities.videoPost ? [.photo, .video] : [.photo],
                            onPhotosPicked: { items in
                                Task { await store.attachImages(items) }
                            },
                            onCameraPhoto: { image in
                                Task { await store.attachCameraImage(image) }
                            },
                            onCameraVideo: { url in
                                Task { await store.attachCameraVideo(url) }
                            }
                        )
                        .modulaGlassID("compose.media.stage", in: glassMorph)
                    }

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
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                    }

                    if store.showsLocalLinkEditor {
                        LinkPreviewEditor(
                            urlString: localLinkURL,
                            preview: nil,
                            editableMetadata: false,
                            onChange: { localLinkURL = $0 },
                            footerNote: "Adds the URL into your post as text. Structured link cards wait on Greenfield."
                        )
                        HStack {
                            Button("Cancel") {
                                store.showsLocalLinkEditor = false
                            }
                            Spacer()
                            Button("Insert link") {
                                store.insertLinkAsText(localLinkURL)
                            }
                            .fontWeight(.semibold)
                            .disabled(localLinkURL.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                        }
                        .fontDesign(.default)
                        .padding(.horizontal, 4)
                    }

                    if store.showsLocalPollEditor {
                        CreationTextPollEditor(
                            maxOptions: store.capabilities.maxPollOptions ?? 4,
                            accent: accent,
                            onInsert: store.insertPollAsText,
                            onCancel: { store.showsLocalPollEditor = false }
                        )
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

                    if let tip = store.composerTip {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(accent)
                            Text(tip)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button {
                                store.composerTip = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.opacity)
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
                .padding(.bottom, 28)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.86), value: mediaStage)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.84), value: store.draft.media.count)
            }
            .modulaSoftScrollEdge()
            .simultaneousGesture(TapGesture().onEnded {
                if mediaStage.isExpanded {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.84)) {
                        mediaStage = .collapsed
                    }
                }
            })

            if ModulaPreferences.explainLimitedLibrary, store.draft.media.isEmpty,
               store.capabilities.toolEnabled(.photo), !mediaStage.isExpanded {
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

            CreationComposerRail(
                accent: accent,
                mediaStage: $mediaStage,
                videoEnabled: store.capabilities.videoPost,
                glassNamespace: glassMorph,
                videoPicker: {
                    PhotosPicker(selection: $videoPickerItems, maxSelectionCount: 1, matching: .videos) {
                        CreationToolChipLabel(
                            title: "Video",
                            symbol: "video.fill",
                            accent: accent,
                            enabled: true,
                            emphasized: true
                        )
                    }
                },
                onMore: {
                    editorFocused = false
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)) {
                        mediaStage = .collapsed
                    }
                    showMoreOptions = true
                }
            )
            .fontDesign(.default)
            .accessibilitySortPriority(40)
        }
    }

    private func identityStage(_ store: CreationStudioStore) -> some View {
        HStack(spacing: 12) {
            ModulaAvatar(
                initials: String((app.auth.account?.displayName ?? app.auth.account?.primaryHandle ?? "M").prefix(2)).uppercased(),
                size: 44,
                name: app.auth.account?.displayName
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(app.auth.account?.displayName ?? app.auth.account?.primaryHandle ?? "You")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                AudiencePicker(selection: Binding(
                    get: { store.draft.audience },
                    set: { store.setAudience($0) }
                ))
                .accessibilitySortPriority(90)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func writingCanvas(_ store: CreationStudioStore) -> some View {
        let accent = app.appearance.accent.color
        let stage = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return TextEditor(text: Binding(
            get: { store.draft.text },
            set: { store.handlePaste($0) }
        ))
        .font(.body)
        .fontDesign(app.appearance.fontDesign)
        .autocorrectionDisabled(!ModulaPreferences.composerAutocorrect)
        .textInputAutocapitalization(ModulaPreferences.composerAutoCapitalise ? .sentences : .never)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 220)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .focused($editorFocused)
        .background {
            stage.fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        }
        .overlay {
            stage.strokeBorder(
                editorFocused ? accent.opacity(0.45) : Color.primary.opacity(0.08),
                lineWidth: editorFocused ? 1.2 : 0.7
            )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: editorFocused)
        .overlay(alignment: .topLeading) {
            if store.draft.text.isEmpty {
                Text(placeholder(store))
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.secondary.opacity(0.55))
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
        .onChange(of: editorFocused) { _, focused in
            if focused, mediaStage.isExpanded {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)) {
                    mediaStage = .collapsed
                }
            }
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
            capabilities: app.creationCapabilities,
            client: app.client
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
        if !reduceMotion {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { publishMorph = true }
        }
        app.postActions.ingest(post)
        app.home.ingestPublished(post)
        app.profile.ingestPublished(post)
        close()
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
