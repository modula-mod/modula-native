import SwiftUI

struct StoryRing: View {
    let state: StoryRingState
    var size: CGFloat = 64
    var accent: Color

    var body: some View {
        let line = state == .unseen ? max(2.5, size * 0.045) : max(1.5, size * 0.03)
        Circle()
            .strokeBorder(style: StrokeStyle(lineWidth: line, dash: state == .seen ? [4, 3] : []))
            .foregroundStyle(ringColor)
            .frame(width: size + line * 2, height: size + line * 2)
            .overlay(alignment: .bottomTrailing) {
                if state == .own {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.34, height: size * 0.34)
                        .background(accent, in: Circle())
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
    }

    private var ringColor: Color {
        switch state {
        case .unseen: accent
        case .seen: Color.primary.opacity(0.28)
        case .own: accent.opacity(0.85)
        }
    }
}

struct StoryAvatar: View {
    let group: StoryGroup
    var size: CGFloat = 64
    var accent: Color

    var body: some View {
        ZStack {
            StoryRing(state: group.ring, size: size, accent: accent)
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
        case .own: availability = "Your story"
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
                if let onCreate, app.stories.capabilities.create {
                    Button(action: onCreate) {
                        VStack(spacing: compact ? 4 : 6) {
                            StoryAvatar(
                                group: StoryGroup(id: "own-create", author: ConversationParticipant(id: "me", handle: "", displayName: "You", avatarURL: nil), items: [], isOwn: true),
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
                }
            }
            .padding(.vertical, compact ? 2 : 4)
        }
        .frame(minHeight: compact ? 78 : 88)
        .frame(maxHeight: compact ? 86 : 120)
        .accessibilityIdentifier("home.story.tray")
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
                    if let id = group.representative?.id {
                        app.navigation.replaceTop(with: .stories(.story(id)))
                    }
                }
                .padding(ModulaLayout.contentInset)
            }
        }
        .modulaCanvas()
        .navigationTitle("Stories")
        .task { await app.stories.loadIfNeeded() }
    }
}

struct StoryViewerHost: View {
    let storyID: StoryID
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let group = app.stories.group(containing: storyID) {
            StoryViewer(group: group, initialID: storyID)
        } else {
            ModulaEmptyState(title: "Story isn’t available.", message: "This story may have expired or isn’t shared with you.", symbol: "circle.dashed")
                .modulaCanvas()
                .navigationTitle("Story")
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
            chrome(item)
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            let event = engine.tick(0.05)
            if event == .advanced { HapticEngine.shared.play(.selection) }
            if event == .finished { app.navigation.close() }
        }
        .onChange(of: scenePhase) { _, phase in
            engine.isAppActive = phase == .active
            if phase != .active { engine.pause() } else if !holding { engine.resume() }
        }
        .onAppear {
            app.stories.markSeen(storyID: item?.id ?? initialID)
        }
        .onChange(of: engine.index) { _, _ in
            if let item = currentItem {
                app.stories.markSeen(storyID: item.id)
            }
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

    private var currentItem: StoryItem? {
        group.items.indices.contains(engine.index) ? group.items[engine.index] : nil
    }

    @ViewBuilder
    private func content(_ item: StoryItem?) -> some View {
        if let item {
            switch item.kind {
            case .image:
                if let url = item.media?.url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        default: textCard(item)
                        }
                    }
                } else {
                    textCard(item)
                }
            case .video:
                if let media = item.media, media.canPlayVideo {
                    textCard(item)
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
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(28)
        }
        .ignoresSafeArea()
    }

    private func chrome(_ item: StoryItem?) -> some View {
        VStack(spacing: 12) {
            StoryProgressBar(count: engine.segmentCount, index: engine.index, progress: engine.progress)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            HStack {
                if let item {
                    VStack(alignment: .leading) {
                        Text(item.author.displayName).font(.headline).foregroundStyle(.white)
                        Text(ConversationRow.relative(item.createdAt)).font(.caption).foregroundStyle(.white.opacity(0.7))
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
            .opacity(0.9)
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

    var body: some View {
        Group {
            // Creation Studio arrives in N4F; keep create capability-honest here.
            ModulaEmptyState(
                title: "Create story",
                message: app.stories.capabilities.create
                    ? "Story publishing opens from Creation Studio in a later phase."
                    : "Publishing stories isn’t available yet.",
                symbol: "plus.circle"
            )
        }
        .modulaCanvas()
        .navigationTitle("Create story")
        .accessibilityIdentifier("story.create")
        .accessibilityValue(RouteSerializer.serialize(.stories(.create)))
    }
}

#if DEBUG
#Preview("Story rings") {
    HStack {
        StoryRing(state: .unseen, accent: .teal)
        StoryRing(state: .seen, accent: .teal)
        StoryRing(state: .own, accent: .teal)
    }
    .padding()
}
#endif
