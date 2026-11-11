import LinkPresentation
import Photos
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
    @State private var editorFocused = false
    /// Shared with the comment composer: WYSIWYG markdown editor + formatting bar.
    @State private var rich = ModulaRichEditorController()
    @State private var linkSheet: ModulaLinkInsertSheet.Mode?
    @State private var mediaPanelActive = false
    @StateObject private var recorder = ModulaVoiceRecorder()
    @Namespace private var glassMorph
    @State private var store: CreationStudioStore?
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var mediaStage: ComposeMediaStage = .collapsed
    @State private var showFileImporter = false
    @State private var showMoreOptions = false
    @AppStorage(ModulaMascotSettings.key(for: .other)) private var mascotShown = ModulaMascotSettings.defaultShown(.other)
    @State private var barScrollWidth: CGFloat = 0
    @State private var localLinkURL = "https://"
    @State private var appeared = false
    @State private var publishTask: Task<Void, Never>?
    @State private var publishMorph = false
    @StateObject private var photoLibrary = ModulaPhotoLibraryModel(includeVideos: true)
    @State private var showsFullCamera = false
    @State private var cameraLibraryItems: [PhotosPickerItem] = []

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
        .toolbar(.hidden, for: .tabBar)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
                accent: app.appearance.liveAccent,
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
                    store.composerTip = "Type @ followed by a name."
                    editorFocused = true
                },
                onHashtagsTip: {
                    store.composerTip = "Type # to add a topic."
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
        let accent = app.appearance.liveAccent
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
                    .foregroundStyle(store.draft.isPublishing ? Color.red : Color.primary)
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
                DraftStatusView(saved: app.drafts.showSavedIndicator, publishing: store.draft.isPublishing, savedAt: app.drafts.lastSavedAt)
                    .accessibilitySortPriority(20)
            }

            Button {
                startPublishing(store)
            } label: {
                Text(store.draft.kind.publishLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(store.canPublish ? Color.white : Color.primary.opacity(0.78))
                    .padding(.horizontal, store.canPublish ? 20 : 16)
                    .padding(.vertical, 8)
                    .background {
                        // Disabled: a solid neutral fill keeps the label readable on any backdrop.
                        if !store.canPublish { Capsule().fill(Color(uiColor: .tertiarySystemFill)) }
                    }
                    .overlay {
                        Capsule().strokeBorder(Color.primary.opacity(store.canPublish ? 0 : 0.30), lineWidth: 1)
                    }
                    .scaleEffect(publishMorph ? 0.92 : 1)
                    .modulaGlass(
                        in: Capsule(),
                        interactive: store.canPublish,
                        tint: store.canPublish ? accent : nil,
                        prominent: store.canPublish,
                        specular: true
                    )
                    .shadow(color: accent.opacity(store.canPublish ? 0.35 : 0), radius: 10, y: 3)
                    .modulaGlassID("compose.publish", in: glassMorph)
            }
            .buttonStyle(.plain)
            .fontDesign(.default)
            .disabled(!store.canPublish)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: store.canPublish)
            .accessibilityHint(store.publishHint ?? "Publishes this post")
            .accessibilitySortPriority(10)
            .accessibilityIdentifier("compose.publish")
            .onChange(of: store.canPublish) { _, enabled in
                if enabled { HapticEngine.shared.play(.lightImpact) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func composer(_ store: CreationStudioStore) -> some View {
        let accent = app.appearance.liveAccent
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    threadRow(store)

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
                        mediaAttachStage(store, accent: accent)
                        .modulaGlassID("compose.media.stage", in: glassMorph)
                    }

                    if store.draft.link == nil, let url = ComposerLinkDetector.firstURL(in: store.draft.text) {
                        ComposerLinkPreviewCard(url: url)
                            .transition(.opacity)
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
                            footerNote: "Adds the link to your post."
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

            if false, ModulaPreferences.explainLimitedLibrary, mediaStage == .library {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    Text("Only the photos you pick are shared with Modula.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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

            if editorFocused && !recorder.isRecording && !store.kindUnavailable {
                ModulaRichFormattingBar(
                    controller: rich,
                    onLink: { linkSheet = .link },
                    onAbbr: { linkSheet = .abbr },
                    onTranslate: nil
                )
                .padding(.leading, mascotShown ? 62 : 10)
                .padding(.trailing, 10)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("compose.formatting")
            }
            if recorder.isRecording {
                HStack(spacing: 8) {
                    ModulaGlassIconButton(title: "Discard voice note", systemImage: "trash", size: ModulaLayout.minimumTouch, tint: .red) {
                        recorder.cancel()
                        HapticEngine.shared.play(.failure)
                    }
                    ModulaRecordingPill(recorder: recorder, cancelProgress: 0)
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
                    ModulaGlassSendButton(title: "Add voice note", systemImage: "checkmark", ready: true, busy: false, size: ModulaLayout.minimumTouch, tint: app.appearance.liveAccent) {
                        finishVoiceNote(store)
                    }
                    .accessibilityIdentifier("compose.voice.done")
                }
                .padding(.horizontal, 10)
                .transition(.opacity)
            }
            accessoryBar(store)
                .accessibilitySortPriority(40)
                .modulaComposerMascot(.other, busy: store.draft.isPublishing, text: store.draft.text, attachmentCount: store.draft.media.count, slotted: true)
            if mediaPanelActive {
                ModulaComposerMediaPanel(
                    client: app.client,
                    onEmoji: { insertText($0, store) },
                    onGif: { gif in
                        mediaPanelActive = false
                        Task { await attachGif(gif, store) }
                    },
                    onSticker: { sticker in
                        insertText(sticker.emoji, store)
                        mediaPanelActive = false
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("compose.media-panel")
            }
        }
        .animation(stageMotion, value: editorFocused)
        .animation(stageMotion, value: mediaPanelActive)
        .animation(stageMotion, value: recorder.isRecording)
        .sheet(item: Binding(get: { linkSheet.map { ComposerLinkSheetItem(mode: $0) } }, set: { linkSheet = $0?.mode })) { item in
            ModulaLinkInsertSheet(mode: item.mode, initialText: rich.selectedText) { label, value in
                switch item.mode {
                case .link: rich.insertLink(text: label, url: value)
                case .abbr: rich.insertAbbreviation(label, title: value)
                }
            }
        }
        .onChange(of: editorFocused) { _, focused in
            if focused { mediaPanelActive = false }
        }
        .fullScreenCover(isPresented: $showsFullCamera) {
            StoryCaptureStage(
                canVideo: store.capabilities.videoPost,
                libraryItems: $cameraLibraryItems,
                onPhoto: { image in
                    showsFullCamera = false
                    Task { await store.attachCameraImage(image) }
                },
                onVideo: { url in
                    showsFullCamera = false
                    Task { await store.attachCameraVideo(url) }
                },
                onText: {},
                onLayout: {},
                onClose: { showsFullCamera = false },
                allowedModes: store.capabilities.videoPost ? [.photo, .video] : [.photo]
            )
            .environment(app)
        }
        .onChange(of: cameraLibraryItems) { _, items in
            guard !items.isEmpty else { return }
            cameraLibraryItems = []
            showsFullCamera = false
            Task { await store.attachImages(items) }
        }
    }

    private func mediaAttachStage(_ store: CreationStudioStore, accent: Color) -> some View {
        let maxCount = store.capabilities.carouselPost ? (store.capabilities.maxMediaCount ?? 10) : 1
        let modes: [ModulaInlineCamera.Mode] = store.capabilities.videoPost ? [.photo, .video] : [.photo]
        return ComposeMediaAttachStage(
            stage: $mediaStage,
            accent: accent,
            idPrefix: "compose.media",
            height: 300,
            maxSelectionCount: store.capabilities.carouselPost
                ? (store.capabilities.maxMediaCount ?? 10) : 1,
            matching: .images,
            cameraModes: modes,
            onPhotosPicked: { items in
                Task { await store.attachImages(items) }
            },
            onCameraPhoto: { image in
                Task { await store.attachCameraImage(image) }
            },
            onCameraVideo: { url in
                Task { await store.attachCameraVideo(url) }
            },
            photoLibrary: photoLibrary,
            onAssetsPicked: { assets in
                Task {
                    for asset in assets {
                        if asset.mediaType == .video {
                            if let url = await photoLibrary.videoFile(asset) {
                                await store.attachCameraVideo(url)
                            }
                        } else if let image = await photoLibrary.fullImage(asset) {
                            await store.attachCameraImage(image)
                        }
                    }
                }
            },
            allowsVideo: store.capabilities.videoPost,
            onVideoBlocked: {
                app.navigation.flash("Video posts aren’t available yet — pick photos", symbol: "video.slash")
            },
            onOpenCamera: {
                editorFocused = false
                withAnimation(stageMotion) { mediaStage = .collapsed }
                showsFullCamera = true
            }
        )
    }

    private func insertText(_ value: String, _ store: CreationStudioStore) {
        store.handlePaste(store.draft.text + value)
        HapticEngine.shared.play(.selection)
    }

    /// GIFs come from the same GIPHY-backed panel as comments; posts attach them as image media.
    private func attachGif(_ gif: ModulaGif, _ store: CreationStudioStore) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: gif.url)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-\(gif.id).gif")
            try data.write(to: url, options: .atomic)
            await store.attachFiles([url])
            HapticEngine.shared.play(.success)
        } catch {
            store.publishError = "Couldn't add that GIF. Your draft is safe."
        }
    }

    private func toggleVoice(_ store: CreationStudioStore) {
        if recorder.isRecording {
            finishVoiceNote(store)
        } else {
            editorFocused = false
            mediaPanelActive = false
            Task { @MainActor in
                if await recorder.start() { HapticEngine.shared.play(.actionConfirmed) }
            }
        }
    }

    private func finishVoiceNote(_ store: CreationStudioStore) {
        guard let note = recorder.finish() else { return }
        HapticEngine.shared.play(.success)
        Task { await store.attachFiles([note.fileURL]) }
    }

    /// Thread-style row: avatar on the left, name + auto-growing text inline beside it.
    private func threadRow(_ store: CreationStudioStore) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ModulaAvatar(
                initials: String((app.auth.account?.displayName ?? app.auth.account?.primaryHandle ?? "M").prefix(2)).uppercased(),
                size: 40,
                name: app.auth.account?.displayName
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(app.auth.account?.displayName ?? app.auth.account?.primaryHandle ?? "You")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                writingCanvas(store)
            }
        }
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onTapGesture { editorFocused = true }
    }

    /// Compact Liquid Glass bar pinned above the keyboard.
    private func accessoryBar(_ store: CreationStudioStore) -> some View {
        let accent = app.appearance.liveAccent
        let caps = store.capabilities
        return ModulaGlassGroup(spacing: 6) {
            HStack(spacing: 4) {
                if mascotShown {
                    // Moliboo's own reserved slot — it lives here and never covers a control.
                    Color.clear
                        .frame(width: 44, height: 44)
                        .modulaMascotPerch()
                        .accessibilityHidden(true)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: barSpacing(caps)) {
                        if caps.toolEnabled(.photo) {
                            barIcon("photo.on.rectangle.angled", "Photo", id: "compose.tool.photo", active: mediaStage == .library, accent: accent) {
                                toggleStage(.library)
                            }
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                barIcon("camera", "Camera", id: "compose.tool.camera", active: showsFullCamera, accent: accent) {
                                    editorFocused = false
                                    withAnimation(stageMotion) { mediaStage = .collapsed }
                                    showsFullCamera = true
                                }
                            }
                        }
                        if caps.videoPost {
                            PhotosPicker(selection: $videoPickerItems, maxSelectionCount: 1, matching: .videos) {
                                ComposerBarIconLabel(symbol: "video", accent: accent, active: false)
                            }
                            .simultaneousGesture(TapGesture().onEnded { HapticEngine.shared.play(.selection) })
                            .accessibilityLabel("Video")
                            .accessibilityIdentifier("compose.tool.video")
                        }
                        barIcon("doc.richtext", "Attach file", id: "compose.tool.file", accent: accent) {
                            showFileImporter = true
                        }
                        if caps.pollPost {
                            barIcon("chart.bar.xaxis", "Poll", id: "compose.tool.poll", active: store.showsLocalPollEditor, accent: accent) {
                                store.showsLocalPollEditor.toggle()
                                store.showsLocalLinkEditor = false
                            }
                        }
                        barIcon(mediaPanelActive ? "keyboard" : "face.smiling", mediaPanelActive ? "Show keyboard" : "Emoji, stickers and GIFs", id: "compose.tool.media", active: mediaPanelActive, accent: accent) {
                            let opening = !mediaPanelActive
                            if opening {
                                editorFocused = false
                                withAnimation(stageMotion) { mediaStage = .collapsed }
                            }
                            mediaPanelActive = opening
                            if !opening { editorFocused = true }
                        }
                        barIcon(recorder.isRecording ? "stop.fill" : "mic", recorder.isRecording ? "Stop recording" : "Voice note", id: "compose.tool.voice", active: recorder.isRecording, accent: accent) {
                            toggleVoice(store)
                        }
                        barIcon("at", "Mention", id: "compose.tool.mention", accent: accent) {
                            store.handlePaste(store.draft.text + ((store.draft.text.last.map { $0.isWhitespace } ?? true) ? "@" : " @"))
                            editorFocused = true
                        }
                        barIcon("ellipsis", "More options", id: "compose.tool.more", accent: accent) {
                            editorFocused = false
                            mediaPanelActive = false
                            withAnimation(stageMotion) { mediaStage = .collapsed }
                            showMoreOptions = true
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barScrollWidth = $0 }
                // Keep icons inside the pill: clip to the capsule and feather both edges.
                .clipShape(Capsule())
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                }

                ComposerReadingChip(text: store.draft.text)
                if let limit = caps.characterLimit, limit > 0 {
                    CharacterRing(count: store.draft.text.count, limit: limit, accent: accent)
                }
                AudiencePicker(selection: Binding(
                    get: { store.draft.audience },
                    set: { store.setAudience($0) }
                ))
                .controlSize(.small)
                .accessibilitySortPriority(90)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .modulaGlass(in: Capsule(), interactive: false, specular: true)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: mediaStage)
    }

    private var stageMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.84)
    }

    private func toggleStage(_ target: ComposeMediaStage) {
        editorFocused = false
        mediaPanelActive = false
        withAnimation(stageMotion) { mediaStage = mediaStage == target ? .collapsed : target }
    }

    /// Even spacing: spread the icons across the visible scroll width; fall back to tight
    /// spacing (and scrolling) when they don't fit.
    private func barSpacing(_ caps: CreationCapabilities) -> CGFloat {
        var n = 5 // file, media, voice, mention, more
        if caps.toolEnabled(.photo) { n += UIImagePickerController.isSourceTypeAvailable(.camera) ? 2 : 1 }
        if caps.videoPost { n += 1 }
        if caps.pollPost { n += 1 }
        let free = barScrollWidth - 12 - CGFloat(n) * 44
        return n > 1 ? max(2, min(14, free / CGFloat(n - 1))) : 2
    }

    private func barIcon(_ symbol: String, _ label: String, id: String, active: Bool = false, accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            ComposerBarIconLabel(symbol: symbol, accent: accent, active: active)
        }
        .buttonStyle(ComposerBarButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func writingCanvas(_ store: CreationStudioStore) -> some View {
        let accent = app.appearance.liveAccent
        _ = accent
        return ModulaRichTextEditor(
            text: Binding(
                get: { store.draft.text },
                set: { store.handlePaste($0) }
            ),
            isFocused: $editorFocused,
            controller: rich,
            spellCheck: ModulaPreferences.composerAutocorrect,
            autocapitalize: ModulaPreferences.composerAutoCapitalise,
            maxLines: 40
        )
        .frame(minHeight: 66, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if store.draft.text.isEmpty {
                Text(placeholder(store))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 11)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ComposerBarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// X-style character ring; turns amber near the limit, red past it.
private struct CharacterRing: View {
    let count: Int
    let limit: Int
    let accent: Color

    var body: some View {
        let remaining = limit - count
        let progress = min(Double(count) / Double(limit), 1)
        let color: Color = remaining < 0 ? .red : (remaining <= 20 ? .orange : accent)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if remaining <= 20 {
                Text("\(remaining)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: remaining <= 20 ? 28 : 22, height: remaining <= 20 ? 28 : 22)
        .animation(.easeOut(duration: 0.15), value: progress)
        .accessibilityLabel("\(max(remaining, 0)) characters left")
        .opacity(count == 0 ? 0 : 1)
    }
}

private struct ComposerBarIconLabel: View {
    let symbol: String
    let accent: Color
    let active: Bool
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? accent : Color.primary.opacity(0.8))
            .frame(width: 44, height: 44)
            .background(Circle().fill(accent.opacity(active ? 0.16 : 0)).padding(2))
            .contentShape(Circle())
    }
}

private struct ComposerLinkSheetItem: Identifiable {
    let mode: ModulaLinkInsertSheet.Mode
    var id: String { mode == .link ? "link" : "abbr" }
}

// MARK: - Link preview card (LinkPresentation, on device)

enum ComposerLinkDetector {
    static func firstURL(in text: String) -> URL? {
        guard text.contains("."), let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let url = detector.firstMatch(in: text, options: [], range: range)?.url,
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

struct ComposerLinkPreviewCard: View {
    let url: URL
    @State private var metadata: LPLinkMetadata?
    @State private var failed = false

    var body: some View {
        Group {
            if let metadata {
                ComposerLinkView(metadata: metadata)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
            } else if !failed {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(url.host() ?? url.absoluteString).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .accessibilityLabel("Link preview for \(url.host() ?? url.absoluteString)")
        .task(id: url) {
            metadata = nil
            failed = false
            try? await Task.sleep(for: .milliseconds(450))   // debounce while typing
            guard !Task.isCancelled else { return }
            let provider = LPMetadataProvider()
            provider.timeout = 8
            do {
                let result = try await provider.startFetchingMetadata(for: url)
                guard !Task.isCancelled else { return }
                metadata = result
            } catch {
                failed = true
            }
        }
    }
}

private struct ComposerLinkView: UIViewRepresentable {
    let metadata: LPLinkMetadata
    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ uiView: LPLinkView, context: Context) { uiView.metadata = metadata }
}


/// Word count and reading time, shown once a draft is long enough for it to matter.
struct ComposerReadingChip: View {
    let text: String
    var body: some View {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if words >= 40 {
            let minutes = max(1, Int((Double(words) / 230).rounded()))
            Text("\(words) words · \(minutes) min")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .modulaGlass(in: Capsule(), interactive: false)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel("\(words) words, about \(minutes) minute read")
        }
    }
}
