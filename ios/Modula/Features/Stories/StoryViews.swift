import PhotosUI
import SwiftUI
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct StoryRing: View {
    let state: StoryRingState
    var size: CGFloat = 64
    var accent: Color
    /// `.own` shows a "+" only when there is nothing posted yet; an own ring with live
    /// stories is drawn as an active (thick) ring instead.
    var showsAddBadge = true
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let emphasised = state == .unseen || (state == .own && !showsAddBadge)
        let line = emphasised ? max(2.5, size * 0.045) : max(1.5, size * 0.03)
        Circle()
            .strokeBorder(style: StrokeStyle(lineWidth: line, dash: state == .seen ? [4, 3] : []))
            .foregroundStyle(ringColor)
            .frame(width: size + line * 2, height: size + line * 2)
            .overlay(alignment: .bottomTrailing) {
                if state == .own && showsAddBadge {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.34, height: size * 0.34)
                        .background(accent, in: Circle())
                        // Cut-out stroke matches the actual canvas (Dim/OLED aware).
                        .overlay(Circle().stroke(ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas, lineWidth: 2))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
    }

    private var ringColor: Color {
        switch state {
        case .unseen: accent
        case .seen: Color.primary.opacity(0.28)
        case .own: showsAddBadge ? accent.opacity(0.85) : accent
        }
    }
}

struct StoryAvatar: View {
    let group: StoryGroup
    var size: CGFloat = 64
    var accent: Color

    var body: some View {
        ZStack {
            StoryRing(state: group.ring, size: size, accent: accent, showsAddBadge: group.isComposerPlaceholder)
            ModulaAvatar(initials: group.author.initials, url: group.author.avatarURL, size: size)
        }
        .frame(width: size + 10, height: size + 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let availability: String
        switch group.ring {
        case .unseen: availability = "Unseen story"
        case .seen: availability = "Seen story"
        case .own: availability = group.isComposerPlaceholder ? "Add to your story" : "Your story"
        }
        return "\(group.author.displayName), \(availability)"
    }
}

struct StoryTray: View {
    let groups: [StoryGroup]
    var compact = false
    var onSelect: (StoryGroup) -> Void
    var onCreate: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app

    private var avatarSize: CGFloat { compact ? 52 : 64 }
    private var labelWidth: CGFloat { compact ? 58 : 72 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 10 : 14) {
                if showsComposer {
                    Button(action: onCreate ?? {}) {
                        VStack(spacing: compact ? 4 : 6) {
                            StoryAvatar(
                                group: StoryGroup(
                                    id: "own-create",
                                    author: ConversationParticipant(id: "me", handle: "", displayName: "You", avatarURL: app.profile.ownProfile?.avatarURL),
                                    items: [],
                                    isOwn: true,
                                    reportedRing: .own
                                ),
                                size: avatarSize,
                                accent: app.appearance.accent.color
                            )
                            Text("Your story")
                                .font(compact ? .caption2 : .caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your story")
                    .accessibilityValue("empty")
                    .accessibilityIdentifier("home.story.own")
                }
                ForEach(groups) { group in
                    Button {
                        onSelect(group)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        VStack(spacing: compact ? 4 : 6) {
                            StoryAvatar(group: group, size: avatarSize, accent: app.appearance.accent.color)
                            Text(group.isOwn ? "Your story" : group.author.displayName)
                                .font(compact ? .caption2 : .caption)
                                .lineLimit(1)
                                .frame(width: labelWidth)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(group.isOwn ? (group.isComposerPlaceholder ? "empty" : "active") : "")
                    .accessibilityIdentifier(group.isOwn ? "home.story.own" : "home.story.\(group.id)")
                }
            }
            .padding(.vertical, compact ? 2 : 4)
        }
        .frame(minHeight: compact ? 78 : 88)
        .frame(maxHeight: compact ? 86 : 120)
        .accessibilityIdentifier("home.story.tray")
    }

    private var showsComposer: Bool {
        onCreate != nil
            && app.stories.capabilities.create
            && !groups.contains(where: \.isOwn)
    }
}

struct StoriesRouteView: View {
    let route: StoriesRoute

    var body: some View {
        switch route {
        case .root:
            StoryRootPlaceholder()
        case .create:
            StoryCreateView()
        case .story(let id):
            StoryViewerHost(storyID: id)
        }
    }
}

struct StoryRootPlaceholder: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if app.stories.trayGroups.isEmpty {
                ModulaEmptyState(
                    title: "Stories",
                    message: "Stories will appear here when they’re available.",
                    symbol: "circle.dashed"
                )
            } else {
                StoryTray(groups: app.stories.trayGroups) { group in
                    Task {
                        if let route = await app.stories.destination(for: group) {
                            app.navigation.replaceTop(with: route)
                        }
                    }
                } onCreate: {
                    app.navigation.replaceTop(with: .stories(.create))
                }
                .padding(ModulaLayout.contentInset)
            }
        }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Stories")
        .task { await app.stories.loadIfNeeded() }
    }
}

struct StoryViewerHost: View {
    let storyID: StoryID
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let group = app.stories.group(containing: storyID), !group.items.isEmpty {
            StoryViewer(group: group, initialID: storyID)
        } else {
            ModulaEmptyState(title: "Story isn’t available.", message: "This story may have expired or isn’t shared with you.", symbol: "circle.dashed")
                .modulaCanvas()
                .modulaSoftScrollEdge()
                .navigationTitle("Story")
                .task {
                    _ = await app.stories.hydrate(groupID: storyID)
                }
        }
    }
}

struct StoryViewer: View {
    let group: StoryGroup
    let initialID: StoryID
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine: StoryProgressEngine
    @State private var holding = false
    @State private var loadedItemID: StoryID?
    @State private var failedItemID: StoryID?
    @State private var retryID = 0
    @State private var videoCoordinator = FeedVideoCoordinator()
    @State private var expandedVideo: ModulaAttachment?

    init(group: StoryGroup, initialID: StoryID) {
        self.group = group
        self.initialID = initialID
        let start = group.items.firstIndex(where: { $0.id == initialID }) ?? 0
        let engine = StoryProgressEngine(count: max(group.items.count, 1))
        engine.reset(to: start)
        _engine = State(initialValue: engine)
    }

    var body: some View {
        let item = group.items.indices.contains(engine.index) ? group.items[engine.index] : group.items.first
        ZStack {
            Color.black.ignoresSafeArea()
            content(item)
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { _ = engine.previous(); if !reduceMotion { HapticEngine.shared.play(.selection) } }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { handle(engine.next()); if !reduceMotion { HapticEngine.shared.play(.selection) } }
            }
            .allowsHitTesting(StoryViewerGate.allowsTapNavigation(item: item, loadedID: loadedItemID, failedID: failedItemID))
            if let item, failedItemID == item.id {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).accessibilityHidden(true)
                    Text("Couldn’t load this story")
                    Button("Retry") { failedItemID = nil; retryID += 1 }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("story.failed")
            }
            chrome(item)
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $expandedVideo) { attachment in
            AttachmentViewerRouter(attachment: attachment, onDismiss: { expandedVideo = nil })
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.height > 80 {
                    app.navigation.close()
                }
            }
        )
        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
            holding = pressing
            if pressing { engine.pause() } else { engine.resume() }
        }, perform: {})
        .background {
            // Display-linked progress instead of a free-running 20 Hz Timer:
            // the timeline is paused (no wakeups) while held, backgrounded,
            // loading, or showing video.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !progressActive)) { context in
                Color.clear
                    .onChange(of: context.date) { previous, now in
                        advanceProgress(by: now.timeIntervalSince(previous))
                    }
            }
            .accessibilityHidden(true)
        }
        .onChange(of: group.items.map(\.id)) { _, ids in
            // Hydration can grow the group after the viewer opened; keep the bar in sync
            // and stay on the item being watched.
            let current = currentItem?.id ?? initialID
            engine.resize(count: ids.count, keepingIndex: ids.firstIndex(of: current))
        }
        .onChange(of: scenePhase) { _, phase in
            engine.isAppActive = phase == .active
            if phase != .active { engine.pause() } else if !holding { engine.resume() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("story.viewer")
        .accessibilityActions {
            Button("Previous") { _ = engine.previous() }
            Button("Next") { handle(engine.next()) }
            Button(engine.isPaused ? "Resume" : "Pause") {
                if engine.isPaused { engine.resume() } else { engine.pause() }
            }
            Button("Close") { app.navigation.close() }
            if app.stories.capabilities.reply, let item {
                Button("Reply") { reply(item) }
            }
        }
    }

    /// Never consume a story while its protected media is still loading.
    /// Videos keep explicit Previous/Next navigation until playback finishes.
    private var progressActive: Bool {
        !engine.isPaused && engine.isAppActive && loadedItemID == currentItem?.id && currentItem?.kind != .video
    }

    private func advanceProgress(by delta: TimeInterval) {
        guard progressActive else { return }
        // Clamp so a long frame gap (e.g. after unpausing) never skips a story.
        let event = engine.tick(min(max(delta, 0), 0.1))
        if event == .advanced { HapticEngine.shared.play(.selection) }
        if event == .finished { app.navigation.close() }
    }

    private var currentItem: StoryItem? {
        group.items.indices.contains(engine.index) ? group.items[engine.index] : nil
    }

    @ViewBuilder
    private func content(_ item: StoryItem?) -> some View {
        if let item {
            switch item.kind {
            case .image:
                if let url = item.media?.url {
                    ModulaRemoteImage(url: url, cacheKey: "story:\(item.id)", retryID: retryID) { phase in
                        switch phase {
                        case .success(let image):
                            Image(uiImage: image).resizable().scaledToFit()
                                .onAppear { didDisplay(item) }
                        case .loading:
                            ProgressView("Loading story…").tint(.white).foregroundStyle(.white)
                        case .failure:
                            // The message + Retry are drawn above the tap zones (see body).
                            Color.clear.onAppear { failedItemID = item.id }
                        }
                    }
                } else {
                    textCard(item)
                }
            case .video:
                if let media = item.media, media.canPlayVideo {
                    let attachment = ModulaAttachment(id: media.id, kind: .video, remoteURL: media.url, thumbnailURL: media.posterURL, duration: media.duration)
                    if expandedVideo == nil {
                        ModulaVideoSurface(attachment: attachment, coordinator: videoCoordinator, onExpand: { expandedVideo = attachment })
                            .onAppear { didDisplay(item) }
                    }
                } else {
                    textCard(item)
                }
            case .text, .unknown:
                textCard(item)
            }
        }
    }

    private func textCard(_ item: StoryItem) -> some View {
        ZStack {
            Color(hex: item.background ?? "#111111")
            Text(item.text ?? item.author.displayName)
                .font(.title.weight(.semibold))
                .foregroundStyle(StoryTextContrast.prefersDarkText(hex: item.background ?? "#111111") ? Color.black : Color.white)
                .multilineTextAlignment(.center)
                .padding(28)
        }
        .ignoresSafeArea()
        .onAppear { didDisplay(item) }
    }

    private func didDisplay(_ item: StoryItem) {
        loadedItemID = item.id
        app.stories.markSeen(storyID: item.id)
    }

    private func chrome(_ item: StoryItem?) -> some View {
        VStack(spacing: 12) {
            // (Scrims below keep white chrome legible over light media.)
            StoryProgressBar(count: engine.segmentCount, index: engine.index, progress: engine.progress)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            HStack {
                if let item {
                    ModulaAvatar(initials: item.author.initials, url: item.author.avatarURL, size: 36)
                    VStack(alignment: .leading) {
                        Text(item.author.displayName).font(.headline).foregroundStyle(.white)
                        Text(ConversationRow.relative(item.createdAt)).font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Button {
                    app.navigation.close()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            Spacer()
            if let caption = item?.text, item?.kind != .text, !caption.isEmpty {
                Text(caption)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.35))
            }
            HStack {
                Button("Previous") { _ = engine.previous() }
                Spacer()
                if app.stories.capabilities.reply {
                    Button("Reply") { if let item { reply(item) } }
                }
                Spacer()
                Button("Next") { handle(engine.next()) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(16)
            .frame(minHeight: ModulaLayout.minimumTouch)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    @MainActor private func handle(_ event: StoryProgressEvent) {
        if event == .finished { app.navigation.close() }
        if event == .advanced { HapticEngine.shared.play(.selection) }
    }

    private func reply(_ item: StoryItem) {
        guard app.stories.capabilities.reply, app.messaging.capabilities.send else { return }
        app.navigation.open(.messages(.new))
    }
}

enum StoryViewerGate {
    /// Tap zones are live once the item rendered, and also when its media failed:
    /// a broken image must not trap the viewer (previously only the small Previous/Next
    /// buttons worked). Videos keep explicit navigation until playback finishes.
    static func allowsTapNavigation(item: StoryItem?, loadedID: StoryID?, failedID: StoryID?) -> Bool {
        guard let item, item.kind != .video else { return false }
        return loadedID == item.id || failedID == item.id
    }
}

struct StoryProgressBar: View {
    let count: Int
    let index: Int
    let progress: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { idx in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.28))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * fill(for: idx))
                    }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Story \(index + 1) of \(count)")
        .accessibilityIdentifier("story.progress")
    }

    private func fill(for idx: Int) -> CGFloat {
        if idx < index { return 1 }
        if idx > index { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }
}

struct StoryCreateView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var prepared: PreparedImage?
    @State private var caption = ""
    @State private var busy = false
    @State private var draftMedia: CreationMedia?
    @State private var visibility = "public"
    @State private var published = false
    @State private var restored = false
    private let draftID = "story-primary"

    var body: some View {
        Group {
            if app.stories.capabilities.create {
                ScrollView {
                    VStack(spacing: 18) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 360)
                                if let preview {
                                    Image(uiImage: preview)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 360)
                                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                } else {
                                    VStack(spacing: 10) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 36, weight: .semibold))
                                        Text("Add a photo")
                                            .font(.headline)
                                    }
                                    .foregroundStyle(app.appearance.accent.color)
                                }
                            }
                        }
                        .accessibilityLabel("Add a photo")
                        .accessibilityValue(photoAccessibilityValue)
                        .accessibilityIdentifier("story.create.photo")
                        .disabled(busy)

                        HStack {
                            Label("Available for 24 hours", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Picker("Audience", selection: $visibility) {
                                Text("Everyone").tag("public")
                                Text("Followers").tag("followers")
                            }
                            .pickerStyle(.menu)
                            .tint(app.appearance.accent.color)
                            .disabled(busy)
                        }

                        TextField("Add a caption", text: $caption, axis: .vertical)
                            .disabled(busy)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))

                        Button {
                            Task { await publish() }
                        } label: {
                            if busy {
                                ProgressView().frame(maxWidth: .infinity).frame(minHeight: 48)
                            } else {
                                Text("Share")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 48)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(app.appearance.accent.color)
                        .disabled(prepared == nil || busy)
                        .accessibilityIdentifier("story.create.share")
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            } else {
                ModulaEmptyState(
                    title: "Create story",
                    message: "Publishing stories isn’t available yet.",
                    symbol: "plus.circle"
                )
            }
        }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Create story")
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: pickerItem) { _, item in
            Task { await load(item) }
        }
        .task {
            await restoreDraft()
            #if DEBUG
            await injectUITestPhotoIfRequested()
            #endif
        }
        .onChange(of: caption) { _, _ in saveDraft() }
        .onChange(of: visibility) { _, _ in saveDraft() }
        .onDisappear { if !published { saveDraft(); app.drafts.flush() } }
        .overlay(alignment: .bottom) {
            if let message = app.stories.actionError ?? app.drafts.saveError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .accessibilityIdentifier("story.create")
        .accessibilityValue(RouteSerializer.serialize(.stories(.create)))
    }

    private var photoAccessibilityValue: String {
        guard let prepared else { return "No photo selected" }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-story-large-photo") {
            return "Photo selected, \(prepared.data.count) bytes"
        }
        #endif
        return "Photo selected"
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await load(data: data)
    }

    private func load(data: Data) async {
        app.stories.setActionError(nil)
        do {
            let image = try await MediaPreparation.jpegStrippingMetadata(
                data, maxPixel: StoryUploadBudget.targetLongEdge, quality: StoryUploadBudget.preferredQuality
            )
            guard let accountID = app.auth.account?.accountId else { return }
            let media = try app.draftMedia.importJPEG(image.data, accountID: accountID, width: image.width, height: image.height)
            prepared = image
            preview = UIImage(data: image.data)
            draftMedia = media
            saveDraft()
        } catch {
            app.stories.setActionError("Couldn’t prepare that photo.")
        }
    }

    private func publish() async {
        guard let prepared else { return }
        busy = true
        defer { busy = false }
        if await app.stories.publish(image: prepared, caption: caption, visibility: visibility) {
            published = true
            app.drafts.discardStory(id: draftID)
            app.navigation.close()
            HapticEngine.shared.play(.success)
        }
    }

    #if DEBUG
    /// UI-test hook: `--uitest-story-large-photo` feeds a generated, detail-heavy photo
    /// (well over 1 MB once prepared) through the same path as the Photos picker.
    /// Only honoured against the isolated N1 fixture host, never production.
    private func injectUITestPhotoIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-story-large-photo"), prepared == nil else { return }
        guard GreenfieldEnvironmentLabel.isIsolatedFixture(host: await app.client.apiOriginHost) else { return }
        let data = await Task.detached(priority: .userInitiated) { StoryUITestPhoto.detailedJPEG() }.value
        guard let data else { return }
        await load(data: data)
    }
    #endif

    private func saveDraft() {
        guard restored, !published else { return }
        app.drafts.upsertStory(StoryDraft(id: draftID, mediaAssetIDs: draftMedia.map { [$0.id] } ?? [],
            caption: caption, lastEdited: Date(), media: draftMedia, visibility: visibility), debounce: false)
    }

    private func restoreDraft() async {
        guard !restored else { return }
        defer { restored = true }
        guard let saved = app.drafts.stories.first(where: { $0.id == draftID }) else { return }
        caption = saved.caption
        visibility = saved.visibility == "followers" ? "followers" : "public"
        draftMedia = saved.media
        guard let media = saved.media else { return }
        do {
            let data = try Data(contentsOf: app.draftMedia.fileURL(media))
            let image = try await MediaPreparation.jpegStrippingMetadata(
                data, maxPixel: StoryUploadBudget.targetLongEdge, quality: StoryUploadBudget.preferredQuality
            )
            prepared = image
            preview = UIImage(data: image.data)
        } catch {
            app.stories.setActionError("The draft photo couldn’t be restored. Choose it again to continue.")
        }
    }
}

#if DEBUG
enum StoryUITestPhoto {
    /// Gradient plus deterministic grain: compresses like a real high-detail photo,
    /// so the prepared 3072px q0.9 JPEG lands above the story byte budget and must be fitted.
    nonisolated static func detailedJPEG(width: Int = 2304, height: Int = 3072) -> Data? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        var seed: UInt32 = 0x9E37_79B9
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let grain = Int(seed >> 24) - 128
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8(clamping: 54 + x * 120 / width + grain / 2)
                pixels[offset + 1] = UInt8(clamping: 156 - y * 90 / height + grain / 2)
                pixels[offset + 2] = UInt8(clamping: 170 + (x + y) * 60 / (width + height) + grain / 2)
            }
        }
        let output = NSMutableData()
        let made: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ), let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                return false
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
            return CGImageDestinationFinalize(destination)
        }
        return made ? output as Data : nil
    }
}

#Preview("Story rings") {
    HStack {
        StoryRing(state: .unseen, accent: .teal)
        StoryRing(state: .seen, accent: .teal)
        StoryRing(state: .own, accent: .teal)
    }
    .padding()
}
#endif

/// Picks dark or light text for a story background colour (WCAG relative luminance).
enum StoryTextContrast {
    static func prefersDarkText(hex: String) -> Bool {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count >= 6, let rgb = UInt64(value.prefix(6), radix: 16) else { return false }
        func channel(_ shift: UInt64) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        // Contrast vs white = 1.05 / (L + 0.05); vs black = (L + 0.05) / 0.05.
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }
}
