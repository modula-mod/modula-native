import SwiftUI

enum ContentPostCatalogRoute: String, CaseIterable, Identifiable {
    case shell = "Post Shell"
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
    case actionRail = "Action Rail"
    case metadata = "Metadata Chips"
    case comments = "Comments"
    case states = "Attachment States"
    case fullInteraction = "Full Post Interaction"

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
        case .states: "arrow.triangle.2.circlepath"
        case .fullInteraction: "hand.tap"
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
    }

    private var note: String {
        switch route {
        case .fullInteraction: "Reference flow: content, reaction selection, comments, context, and expansion."
        case .states: "Loading, failed, offline, and unavailable states stay truthful."
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
            fixtureActions
        case .metadata:
            ViewThatFits {
                HStack { metadataChips }
                VStack(alignment: .leading) { metadataChips }
            }
        case .comments:
            Button("Open comments sheet", systemImage: "bubble.right") { commentsPresented = true }
                .buttonStyle(.borderedProminent).tint(app.appearance.accent.color)
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
        }
    }

    private var fixtureHeader: some View {
        HStack(spacing: ModulaSpacing.sm) {
            ModulaAvatar(initials: "AR", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) { Text("Alex Rivers").font(.subheadline.bold()); Image(systemName: "checkmark.seal.fill").foregroundStyle(ModulaColor.accent) }
                Text("Bali, Indonesia · 2h").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "ellipsis")
        }
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

private enum PostCatalogFixtures {
    static let image = attachment(id: "portrait", kind: .image, mime: "image/jpeg", name: "Portrait.jpg", dimensions: CGSize(width: 900, height: 1_300), alt: "Portrait travel photograph fixture")
    static let gallery = (1...5).map { attachment(id: "gallery-\($0)", kind: .image, mime: "image/jpeg", name: "Travel \($0).jpg", dimensions: CGSize(width: 1_200, height: $0.isMultiple(of: 2) ? 900 : 1_400), alt: "Gallery image \($0) of 5") }
    static let video = attachment(id: "video", kind: .video, mime: "video/mp4", name: "Sunset.mp4", duration: 42, alt: "Short sunset video fixture")
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

    private static func attachment(id: String, kind: AttachmentKind, mime: String, name: String, bytes: Int64? = nil, dimensions: CGSize? = nil, duration: TimeInterval? = nil, pages: Int? = nil, alt: String? = nil) -> ModulaAttachment {
        ModulaAttachment(id: id, kind: kind, remoteURL: nil, mimeType: mime, filename: name, byteSize: bytes, dimensions: dimensions, duration: duration, accessibilityDescription: alt, metadata: AttachmentMetadata(pageCount: pages))
    }
}
