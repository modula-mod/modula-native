import SwiftUI

enum ContentPostCatalogRoute: String, CaseIterable, Identifiable {
    case shell = "Immersive Post Shell"
    case header = "Post Header"
    case text = "Text Post"
    case image = "Image Post"
    case gallery = "Image Gallery"
    case video = "Video Post"
    case pdf = "PDF Post"
    case document = "Document Post"
    case audio = "Audio Post"
    case link = "Link Post"
    case mixed = "Mixed Content"
    case actionRail = "Media Action Rail"
    case metadata = "Metadata Chips"
    case comments = "Comments Morph"
    case postDetail = "Post Detail"
    case feedRhythm = "Feed Rhythm"
    case states = "Loading States"
    case errorStates = "Error States"
    case diagnostics = "Attachment Diagnostics"
    case fullInteraction = "Full Post Interaction"
    case richComposer = "Rich Composer"
    case uploadQueue = "Upload Queue"
    case imageDraft = "Image Draft"
    case videoDraft = "Video Draft"
    case pdfDraft = "PDF Draft"
    case documentDraft = "Document Draft"
    case audioDraft = "Audio Draft"
    case mixedDraft = "Mixed Draft"
    case uploadFailure = "Upload Failure"
    case retry = "Retry"
    case processing = "Processing"
    case publishState = "Publish State"
    case stressFeed = "60+ Mixed Feed"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .shell: "rectangle.stack"
        case .header: "person.text.rectangle"
        case .text: "text.alignleft"
        case .image: "photo"
        case .gallery: "photo.on.rectangle.angled"
        case .video: "video"
        case .pdf: "doc.richtext"
        case .document: "doc"
        case .audio: "waveform"
        case .link: "link"
        case .mixed: "square.stack.3d.up"
        case .actionRail: "ellipsis.rectangle"
        case .metadata: "tag"
        case .comments: "bubble.left.and.bubble.right"
        case .postDetail: "rectangle.expand.vertical"
        case .feedRhythm: "water.waves"
        case .states: "arrow.triangle.2.circlepath"
        case .errorStates: "exclamationmark.triangle"
        case .diagnostics: "stethoscope"
        case .fullInteraction: "hand.tap"
        case .richComposer: "square.and.pencil"
        case .uploadQueue: "arrow.up.circle"
        case .imageDraft: "photo.badge.plus"
        case .videoDraft: "video.badge.plus"
        case .pdfDraft: "doc.richtext.fill"
        case .documentDraft: "doc.badge.plus"
        case .audioDraft: "waveform.badge.plus"
        case .mixedDraft: "square.stack.3d.up.fill"
        case .uploadFailure: "exclamationmark.arrow.triangle.2.circlepath"
        case .retry: "arrow.clockwise"
        case .processing: "gearshape.2"
        case .publishState: "paperplane"
        case .stressFeed: "speedometer"
        }
    }
}

struct ContentPostCatalogView: View {
    var body: some View {
        List {
            Section {
                Text("Development-only fixtures for the universal content layer. These screens never inject sample posts into production feeds.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Content & Posts") {
                ForEach(ContentPostCatalogRoute.allCases) { route in
                    NavigationLink {
                        ContentPostCatalogPage(route: route)
                    } label: {
                        Label(route.rawValue, systemImage: route.symbol)
                    }
                    .accessibilityIdentifier("catalog.posts.\(route.id.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
        }
        .navigationTitle("Content & Posts")
        .accessibilityIdentifier("catalog.posts")
    }
}

private struct ContentPostCatalogPage: View {
    let route: ContentPostCatalogRoute
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var selectedAttachment: ModulaAttachment?
    @State private var selectedReaction: SocialReaction?
    @State private var commentsPresented = false
    @State private var commentText = "A thoughtful reply"
    @State private var pickedDraft: ModulaAttachment?
    @State private var pickerMessage: String?
    @State private var railSaved = false
    @State private var railLiked = false
    @State private var railNotice = "Local interaction preview · no network mutations"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                CatalogLabSection(title: route.rawValue, note: note) {
                    demo
                }
                if route != .states {
                    CatalogLabSection(title: "Unavailable state", note: "Missing content remains explicit and never renders as an empty rectangle.") {
                        ModulaDocumentCard(attachment: PostCatalogFixtures.unavailable) {}
                    }
                }
            }
            .padding(ModulaSpacing.md)
        }
        .modulaCanvas()
        .navigationTitle(route.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedAttachment) { attachment in
            AttachmentViewerRouter(
                attachment: attachment,
                imageGallery: route == .gallery ? PostCatalogFixtures.gallery : []
            ) { selectedAttachment = nil }
        }
        .sheet(isPresented: $commentsPresented) {
            ModulaSheet(detents: [.compact, .medium, .large]) {
                VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                    Text("Comments").font(.title2.bold())
                    Text("The production post route supplies live comments. This lab verifies the shared sheet and composer without creating fake network state.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ModulaComposer(text: $commentText, prompt: "Add a comment…", onSend: {})
                }
                .padding(ModulaSpacing.md)
            }
        }
        .task(id: route.id) {
            guard route == .stressFeed || route == .feedRhythm else { return }
            for mode in HomeMode.allCases {
                await app.home.loadIfNeeded(mode, signedIn: app.auth.account != nil)
            }
        }
    }

    private var note: String {
        switch route {
        case .fullInteraction: "Reference flow: content, reaction selection, comments, context, and expansion."
        case .states: "Content-shaped loading states must resolve to ready or failed."
        case .errorStates: "Failures name the affected capability and expose a real retry action."
        case .diagnostics: "Development-only metadata exposes attachment state without credentials or signed URL values."
        case .feedRhythm: "A single post domain adapts its spacing and controls to the content it carries."
        case .postDetail: "Detail renders every canonical block in order with stronger content breathing room."
        case .richComposer, .uploadQueue, .imageDraft, .videoDraft, .pdfDraft, .documentDraft,
             .audioDraft, .mixedDraft, .uploadFailure, .retry, .processing, .publishState:
            "Interactive publishing fixtures use the same explicit draft and upload states as Creation Studio."
        case .stressFeed: "Sixty mixed renderer instances exercise lazy loading and feed rhythm without seeding production data."
        default: "Uses the same production component selected by the canonical content renderer."
        }
    }

    @ViewBuilder
    private var demo: some View {
        switch route {
        case .shell, .text:
            VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                fixtureHeader
                Text("A single post shell can present text, media, documents, audio, and links without duplicating identity or engagement logic.")
                    .font(.body)
                fixtureActions
            }
        case .header:
            fixtureHeader
        case .image:
            ModulaPostImage(attachment: PostCatalogFixtures.image) { selectedAttachment = PostCatalogFixtures.image }
        case .gallery:
            ModulaPostImageGallery(attachments: PostCatalogFixtures.gallery) { selectedAttachment = $0 }
        case .video:
            ModulaVideoSurface(attachment: PostCatalogFixtures.video) { selectedAttachment = PostCatalogFixtures.video }
        case .pdf:
            ModulaPDFSurface(attachment: PostCatalogFixtures.pdf) { selectedAttachment = PostCatalogFixtures.pdf }
        case .document:
            VStack(spacing: ModulaSpacing.sm) {
                ModulaDocumentCard(attachment: PostCatalogFixtures.document) { selectedAttachment = PostCatalogFixtures.document }
                ModulaDocumentCard(attachment: PostCatalogFixtures.spreadsheet) { selectedAttachment = PostCatalogFixtures.spreadsheet }
                ModulaDocumentCard(attachment: PostCatalogFixtures.presentation) { selectedAttachment = PostCatalogFixtures.presentation }
            }
        case .audio:
            ModulaAudioSurface(attachment: PostCatalogFixtures.audio) { selectedAttachment = PostCatalogFixtures.audio }
        case .link:
            ModulaLinkPreview(content: PostCatalogFixtures.link) { openURL($0) }
        case .mixed:
            ModulaPostContentRenderer(
                post: PostCatalogFixtures.mixedPost,
                presentation: .detail,
                onOpenAttachment: { selectedAttachment = $0 },
                onOpenLink: { openURL($0) },
                onOpenModule: { _ in }
            )
        case .actionRail:
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [app.appearance.accent.color.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content first").font(.title2.bold())
                    Text(railNotice).font(.footnote).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("A shared production rail. Tap More or drag down for context.").font(.subheadline)
                }
                .foregroundStyle(.white)
                .padding(20)
                .padding(.trailing, 64)
                PostActionRail(post: railPreviewPost,
                    onLike: { railLiked.toggle() }, onComment: { commentsPresented = true },
                    onSave: { railSaved.toggle() }, onShare: { railNotice = "Share selected · preview only" },
                    onReactLongPress: { railNotice = "Reaction selected · preview only" },
                    onContextAction: { railNotice = "\($0.title) selected · preview only" })
                    .padding(.trailing, 12)
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        case .metadata:
            ViewThatFits {
                HStack { metadataChips }
                VStack(alignment: .leading) { metadataChips }
            }
        case .comments:
            Button("Open comments sheet", systemImage: "bubble.right") { commentsPresented = true }
                .buttonStyle(.borderedProminent).tint(app.appearance.accent.color)
        case .postDetail:
            ModulaPostContentRenderer(
                post: PostCatalogFixtures.mixedPost,
                presentation: .detail,
                onOpenAttachment: { selectedAttachment = $0 },
                onOpenLink: { openURL($0) },
                onOpenModule: { _ in }
            )
        case .feedRhythm:
            VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                ForEach(Array(stressPosts.prefix(8))) { post in
                    VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                        Text(post.presentationStyle.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let body = post.body { Text(body) }
                        ModulaPostContentRenderer(
                            post: post,
                            presentation: .feed,
                            onOpenAttachment: { selectedAttachment = $0 },
                            onOpenLink: { openURL($0) },
                            onOpenModule: { _ in }
                        )
                    }
                    Divider().opacity(0.3)
                }
            }
        case .states:
            VStack(spacing: ModulaSpacing.sm) {
                ProgressView("Loading attachment…")
                Label("Download failed · Retry", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                Label("Unavailable offline", systemImage: "wifi.slash")
                ModulaDocumentCard(attachment: PostCatalogFixtures.unavailable) {}
                Divider()
                ModulaAttachmentPicker { pickedDraft = $0; pickerMessage = nil } onFailure: { pickerMessage = $0 }
                if let pickedDraft {
                    Label("Draft preview: \(pickedDraft.displayName)", systemImage: pickedDraft.kind.defaultSystemImage)
                        .font(.caption).foregroundStyle(.secondary)
                } else if let pickerMessage {
                    Text(pickerMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .errorStates:
            VStack(spacing: ModulaSpacing.sm) {
                CatalogAttachmentError(title: "Couldn’t load photo", symbol: "photo", retry: {})
                CatalogAttachmentError(title: "Document unavailable", symbol: "doc.richtext", retry: {})
                CatalogAttachmentError(title: "Video couldn’t be played", symbol: "video.slash", retry: {})
            }
        case .diagnostics:
            VStack(spacing: ModulaSpacing.sm) {
                AttachmentDiagnosticsCard(attachment: PostCatalogFixtures.image, lastRequestResult: "Not requested")
                AttachmentDiagnosticsCard(attachment: PostCatalogFixtures.pdf, lastRequestResult: "Not requested")
                AttachmentDiagnosticsCard(attachment: PostCatalogFixtures.processingVideo, lastRequestResult: "Processing")
            }
        case .fullInteraction:
            VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                fixtureHeader
                ModulaVideoSurface(attachment: PostCatalogFixtures.video) { selectedAttachment = PostCatalogFixtures.video }
                Text("Progressively reveal controls instead of crowding the resting state.")
                PostReactionPicker(current: selectedReaction, multiEnabled: true) { selectedReaction = $0 } onCancel: {}
                HStack {
                    Button("Comments", systemImage: "bubble.right") { commentsPresented = true }
                    Spacer()
                    Button("Expand", systemImage: "arrow.up.left.and.arrow.down.right") { selectedAttachment = PostCatalogFixtures.video }
                }
                .buttonStyle(.bordered)
            }
            .modulaContextMenu(actions: [
                .init(id: "copy", title: "Copy link", systemImage: "link"),
                .init(id: "save", title: "Save", systemImage: "bookmark")
            ]) { _ in }
        case .richComposer:
            VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                TextField("What's happening?", text: $commentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                AttachmentPipelineCatalogLab(initialState: .local, showsMixedQueue: true)
            }
        case .uploadQueue, .mixedDraft:
            AttachmentPipelineCatalogLab(initialState: .uploading, showsMixedQueue: true)
        case .imageDraft:
            DraftAttachmentCatalogCard(kind: .image, name: "Portrait.jpg", state: .readyToUpload, progress: 0)
        case .videoDraft:
            DraftAttachmentCatalogCard(kind: .video, name: "Sunset.mp4", state: .uploading, progress: 0.38)
        case .pdfDraft:
            DraftAttachmentCatalogCard(kind: .pdf, name: "Product Strategy.pdf", state: .readyToUpload, progress: 0)
        case .documentDraft:
            DraftAttachmentCatalogCard(kind: .document, name: "Product Brief.docx", state: .readyToUpload, progress: 0)
        case .audioDraft:
            DraftAttachmentCatalogCard(kind: .audio, name: "A Walk.m4a", state: .uploading, progress: 0.72)
        case .uploadFailure:
            AttachmentPipelineCatalogLab(initialState: .failed, showsMixedQueue: false)
        case .retry:
            AttachmentPipelineCatalogLab(initialState: .failed, showsMixedQueue: true)
        case .processing:
            AttachmentPipelineCatalogLab(initialState: .processing, showsMixedQueue: false)
        case .publishState:
            AttachmentPipelineCatalogLab(initialState: .ready, showsMixedQueue: true)
        case .stressFeed:
            LazyVStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                Text(liveStressSource.isEmpty ? "60 state fixtures · live feed unavailable" : "60 live-backed mixed posts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("catalog.posts.stress-count")
                ForEach(stressPosts) { post in
                    VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                        Text("Fixture \(post.id)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if let body = post.body { Text(body).font(.body) }
                        ModulaPostContentRenderer(
                            post: post,
                            presentation: .feed,
                            onOpenAttachment: { _ in },
                            onOpenLink: { _ in },
                            onOpenModule: { _ in }
                        )
                        Divider()
                    }
                }
            }
            .accessibilityIdentifier("catalog.posts.stress-feed")
        }
    }

    private var liveStressSource: [ModulaPost] {
        var seen = Set<String>()
        return HomeMode.allCases
            .flatMap { app.home.visiblePosts(for: $0) }
            .filter { seen.insert($0.id).inserted }
            .map(ModulaPostMapper.map)
    }

    private var stressPosts: [ModulaPost] {
        let live = liveStressSource
        guard !live.isEmpty else { return PostCatalogFixtures.stressPosts }
        return (0..<60).map { index in
            let source = live[index % live.count]
            return ModulaPost(
                id: "live-stress-\(index)-\(source.id)",
                author: source.author,
                createdAt: source.createdAt,
                editedAt: source.editedAt,
                body: source.body,
                content: source.content,
                context: source.context,
                engagement: source.engagement
            )
        }
    }

    private var fixtureHeader: some View {
        HStack(spacing: ModulaSpacing.sm) {
            ModulaAvatar(initials: "AR", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) { Text("Alex Rivers").font(.subheadline.bold()); Image(systemName: "checkmark.seal.fill").foregroundStyle(app.appearance.accent.color) }
                Text("Bali, Indonesia · 2h").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "ellipsis")
        }
    }

    private var railPreviewPost: SocialPost {
        SocialPost(id: "catalog-action-rail", author: nil, createdAt: Date(timeIntervalSince1970: 0),
            editedAt: nil, feed: nil, text: nil, kind: .media, visibility: .private, audience: nil,
            media: [], link: nil, module: nil, glowColour: nil,
            engagement: .init(liked: railLiked, saved: railSaved, reposted: false,
                viewerReaction: railLiked ? .like : nil, likeCount: railLiked ? 1 : 0,
                replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: railLiked ? 1 : 0))
    }

    private var fixtureActions: some View {
        HStack {
            Label("24.6K", systemImage: "heart")
            Spacer(); Label("368", systemImage: "bubble.right")
            Spacer(); Image(systemName: "bookmark")
            Spacer(); Image(systemName: "square.and.arrow.up")
        }
        .font(.subheadline).foregroundStyle(.secondary)
        .frame(minHeight: ModulaLayout.minimumTouch)
    }

    @ViewBuilder private var metadataChips: some View {
        ModulaPostMetadataChip(systemImage: "music.note", title: "Tycho · A Walk")
        ModulaPostMetadataChip(systemImage: "location", title: "Bali, Indonesia")
        ModulaPostMetadataChip(systemImage: "number", title: "travel")
    }
}

private struct CatalogAttachmentError: View {
    let title: String
    let symbol: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 34)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button("Retry", systemImage: "arrow.clockwise", action: retry).labelStyle(.iconOnly)
        }
        .padding(ModulaSpacing.sm)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
    }
}

private struct AttachmentDiagnosticsCard: View {
    let attachment: ModulaAttachment
    let lastRequestResult: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            diagnostic("ID", attachment.id)
            diagnostic("Kind", attachment.kind.rawValue)
            diagnostic("MIME", attachment.mimeType ?? "unknown")
            diagnostic("Remote state", String(describing: attachment.resolvedRemoteState))
            diagnostic("Access URL", attachment.remoteURL == nil ? "absent" : "present")
            diagnostic("Preview URL", attachment.previewURL == nil ? "absent" : "present")
            diagnostic("Thumbnail URL", attachment.thumbnailURL == nil ? "absent" : "present")
            diagnostic("Cache key", attachment.cacheIdentity)
            diagnostic("Last request", lastRequestResult)
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ModulaSpacing.sm)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attachment diagnostics for \(attachment.id), state \(String(describing: attachment.resolvedRemoteState))")
    }

    @ViewBuilder
    private func diagnostic(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

private struct AttachmentPipelineCatalogLab: View {
    @State private var state: DraftAttachmentState
    @State private var progress: Double
    let showsMixedQueue: Bool

    init(initialState: DraftAttachmentState, showsMixedQueue: Bool) {
        _state = State(initialValue: initialState)
        _progress = State(initialValue: initialState == .uploading ? 0.38 : (initialState == .ready ? 1 : 0))
        self.showsMixedQueue = showsMixedQueue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            if showsMixedQueue {
                DraftAttachmentCatalogCard(kind: .image, name: "Photo.png", state: .ready, progress: 1)
                DraftAttachmentCatalogCard(kind: .video, name: "Walkthrough.mp4", state: state, progress: progress)
                DraftAttachmentCatalogCard(kind: .pdf, name: "Architecture.pdf", state: .readyToUpload, progress: 0)
            } else {
                DraftAttachmentCatalogCard(kind: .video, name: "Walkthrough.mp4", state: state, progress: progress)
            }
            Picker("State", selection: $state) {
                ForEach([DraftAttachmentState.local, .readyToUpload, .uploading, .processing, .ready, .failed, .cancelled], id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .pickerStyle(.menu)
            if state == .uploading { Slider(value: $progress, in: 0...1).accessibilityLabel("Upload progress") }
            HStack {
                Button("Retry", systemImage: "arrow.clockwise") { state = .uploading; progress = 0.15 }
                Button("Cancel", role: .destructive) { state = .cancelled }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct DraftAttachmentCatalogCard: View {
    let kind: CreationMedia.Kind
    let name: String
    let state: DraftAttachmentState
    let progress: Double
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: symbol).frame(width: 36, height: 36).background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: ModulaRadius.small))
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(state == .failed ? .red : .secondary)
                if state == .uploading { ProgressView(value: progress) }
            }
            Spacer(minLength: 0)
            if state == .ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(app.appearance.accent.color) }
        }
        .padding(ModulaSpacing.sm)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: ModulaRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.rawValue) attachment, \(name), \(status)")
    }

    private var status: String {
        switch state {
        case .uploading: "Uploading \(Int(progress * 100))%"
        case .readyToUpload: "Ready to upload"
        case .failed: "Upload failed"
        default: state.rawValue.capitalized
        }
    }

    private var symbol: String {
        switch kind {
        case .image: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .document, .unknown: "doc"
        }
    }
}

private enum PostCatalogFixtures {
    static let image = attachment(id: "portrait", kind: .image, mime: "image/jpeg", name: "Portrait.jpg", dimensions: CGSize(width: 900, height: 1_300), alt: "Portrait travel photograph fixture")
    static let gallery = (1...5).map { attachment(id: "gallery-\($0)", kind: .image, mime: "image/jpeg", name: "Travel \($0).jpg", dimensions: CGSize(width: 1_200, height: $0.isMultiple(of: 2) ? 900 : 1_400), alt: "Gallery image \($0) of 5") }
    static let video = attachment(id: "video", kind: .video, mime: "video/mp4", name: "Sunset.mp4", duration: 42, alt: "Short sunset video fixture")
    static let processingVideo = ModulaAttachment(id: "processing-video", kind: .video, remoteURL: nil, mimeType: "video/mp4", filename: "Processing.mp4", remoteState: .processing)
    static let pdf = attachment(id: "pdf", kind: .pdf, mime: "application/pdf", name: "Modula Design System.pdf", bytes: 7_800_000, pages: 42)
    static let document = attachment(id: "docx", kind: .document, mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", name: "Product Brief.docx", bytes: 420_000)
    static let spreadsheet = attachment(id: "xlsx", kind: .document, mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", name: "Roadmap.xlsx", bytes: 910_000)
    static let presentation = attachment(id: "pptx", kind: .document, mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation", name: "Launch Review.pptx", bytes: 3_400_000)
    static let audio = ModulaAttachment(id: "audio", kind: .audio, remoteURL: nil, mimeType: "audio/mpeg", filename: "A Walk.mp3", duration: 278, accessibilityDescription: "Audio track", metadata: AttachmentMetadata(title: "A Walk", creator: "Tycho"))
    static let unavailable = attachment(id: "unavailable", kind: .unknown, mime: "application/x-unknown", name: "Unavailable attachment", bytes: 0)
    static let link = LinkContent(destination: URL(string: "https://modula.digital"), title: "Modula — native intelligence and modular software", description: "A compact rich link preview using destination metadata.", domain: "modula.digital", imageURL: nil, faviconURL: nil)

    static let mixedPost = ModulaPost(
        id: "catalog-mixed",
        author: PostAuthor(id: "alex", handle: "alex", displayName: "Alex Rivers", avatarURL: nil, isVerified: true),
        createdAt: Date(), editedAt: nil,
        body: "A photo, source PDF, and external reference in one canonical post.",
        content: [.image(.init(attachment: image)), .pdf(.init(attachment: pdf)), .link(link)],
        context: PostContext(feed: "Product", location: "London", audience: "Public", visibility: .public, audioTitle: nil, collection: "Design", topic: "systems", module: nil),
        engagement: PostEngagement(liked: false, saved: false, reposted: false, viewerReaction: nil, likeCount: 24, replyCount: 3, repostCount: 2, quoteCount: 0, reactionCount: 24)
    )

    static let stressPosts: [ModulaPost] = (0..<60).map { index in
        let content: [PostContentBlock]
        switch index {
        case 0..<10: content = []
        case 10..<20: content = [.image(.init(attachment: image))]
        case 20..<25: content = [.imageGallery(.init(attachments: gallery))]
        case 25..<33: content = [.video(.init(attachment: video))]
        case 33..<38: content = [.pdf(.init(attachment: pdf))]
        case 38..<43: content = [.document(.init(attachment: document))]
        case 43..<47: content = [.audio(.init(attachment: audio))]
        case 47..<51: content = [.link(link)]
        default: content = mixedPost.content
        }
        return ModulaPost(
            id: "stress-\(index)",
            author: mixedPost.author,
            createdAt: Date(timeIntervalSinceNow: TimeInterval(-index * 60)),
            editedAt: nil,
            body: "Mixed feed performance fixture \(index + 1).",
            content: content,
            context: mixedPost.context,
            engagement: mixedPost.engagement
        )
    }

    private static func attachment(id: String, kind: AttachmentKind, mime: String, name: String, bytes: Int64? = nil, dimensions: CGSize? = nil, duration: TimeInterval? = nil, pages: Int? = nil, alt: String? = nil) -> ModulaAttachment {
        ModulaAttachment(id: id, kind: kind, remoteURL: nil, mimeType: mime, filename: name, byteSize: bytes, dimensions: dimensions, duration: duration, accessibilityDescription: alt, metadata: AttachmentMetadata(pageCount: pages))
    }
}
