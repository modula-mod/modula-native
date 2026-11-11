import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct StoryRing: View {
    let state: StoryRingState
    var size: CGFloat = 58
    var accent: Color
    /// `.own` shows a "+" only when there is nothing posted yet; an own ring with live
    /// stories is drawn as an active (gradient) ring instead.
    var showsAddBadge = true
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let emphasised = state == .unseen || (state == .own && !showsAddBadge)
        // Unseen: thick gradient ring (Von Restorff). Seen: hairline grey so it recedes.
        let line: CGFloat = emphasised ? 2.6 : 1.2
        let outer = size + 8
        ZStack {
            if emphasised {
                Circle().strokeBorder(Self.gradient(accent), lineWidth: line)
            } else if state == .own {
                Circle().strokeBorder(Color.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
            } else {
                Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: line)
            }
            if state == .own && showsAddBadge { plusBadge }
        }
        .frame(width: outer, height: outer)
        .accessibilityHidden(true)
    }

    /// Shared story gradient: accent → magenta → amber. Used by rings, cards and the hero.
    static func gradient(_ accent: Color) -> AngularGradient {
        AngularGradient(
            colors: [accent, Color(hex: "#FF2D87"), Color(hex: "#FFB020"), accent],
            center: .center,
            angle: .degrees(-90)
        )
    }

    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(accent, in: Circle())
            .overlay(Circle().stroke(ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas, lineWidth: 2.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .accessibilityHidden(true)
    }
}

struct StoryAvatar: View {
    let group: StoryGroup
    var size: CGFloat = 58
    var accent: Color

    var body: some View {
        ZStack {
            StoryRing(state: group.ring, size: size, accent: accent, showsAddBadge: group.isComposerPlaceholder)
            ModulaAvatar(initials: group.author.initials, url: group.author.avatarURL, size: size - 2)
        }
        .frame(width: size + 8, height: size + 8)
        .overlay(alignment: .topTrailing) {
            // "New" dot: something posted in the last hour that you haven't seen.
            if group.ring == .unseen, let latest = group.items.map(\.createdAt).max(), Date().timeIntervalSince(latest) < 3600 {
                Circle()
                    .fill(Color(hex: "#34C759"))
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: -3, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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

    /// Home uses a larger, image-led disc so "Your story" never truncates to "Your st…".
    /// ~58pt discs so ~6 fit across a phone (Fitts: still well above 44pt; Hick: more choices at a glance).
    private var avatarSize: CGFloat { compact ? 54 : 58 }
    private var labelWidth: CGFloat { compact ? 60 : 64 }

    private var ownHandle: String? { app.auth.account?.primaryHandle.lowercased() }

    private func isSelf(_ handle: String, id: String) -> Bool {
        if let own = ownHandle, !own.isEmpty, handle.lowercased() == own { return true }
        if let account = app.auth.account?.accountId, account == id { return true }
        return false
    }

    /// One entry per person: a single "you" group (first wins), no duplicate authors
    /// (the rail can repeat someone by id and by handle).
    private var displayGroups: [StoryGroup] {
        var seenIDs = Set<String>()
        var seenHandles = Set<String>()
        var hasOwn = false
        var result: [StoryGroup] = []
        for var group in groups {
            if !group.isOwn, isSelf(group.author.handle, id: group.author.id) { group.isOwn = true }
            if group.isOwn {
                guard !hasOwn else { continue }
                hasOwn = true
                result.insert(group, at: 0)
                continue
            }
            let handle = group.author.handle.lowercased()
            guard seenIDs.insert(group.author.id).inserted else { continue }
            if !handle.isEmpty, !seenHandles.insert(handle).inserted { continue }
            result.append(group)
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: compact ? 8 : 10) {
                if showsComposer {
                    Button(action: onCreate ?? {}) {
                        trayCell(
                            avatar: StoryAvatar(
                                group: StoryGroup(
                                    id: "own-create",
                                    author: ConversationParticipant(
                                        id: "me",
                                        handle: "",
                                        displayName: "You",
                                        avatarURL: app.profile.ownProfile?.avatarURL
                                    ),
                                    items: [],
                                    isOwn: true,
                                    reportedRing: .own
                                ),
                                size: avatarSize,
                                accent: app.appearance.liveAccent
                            ),
                            title: "Your story"
                        )
                    }
                    .buttonStyle(.modulaPress)
                    .modulaCarouselReveal()
                    .accessibilityLabel("Your story")
                    .accessibilityHint("Creates a new story")
                    .accessibilityValue("empty")
                    .accessibilityIdentifier("home.story.own")
                }
                ForEach(displayGroups) { group in
                    Button {
                        onSelect(group)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        trayCell(
                            avatar: StoryAvatar(group: group, size: avatarSize, accent: app.appearance.liveAccent)
                                .modulaHeroSource("story", key: group.id),
                            title: trayTitle(group)
                        )
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.93, haptic: nil))
                    .modulaCarouselReveal()
                    .overlay(alignment: .bottomTrailing) {
                        if group.isOwn, let onCreate {
                            Button {
                                onCreate()
                                HapticEngine.shared.play(.navigation)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(app.appearance.liveAccent, in: Circle())
                                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2.5))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: 12, y: -14)
                            .accessibilityLabel("Add to your story")
                            .accessibilityIdentifier("home.story.add")
                        }
                    }
                    .accessibilityValue(group.isOwn ? (group.isComposerPlaceholder ? "empty" : "active") : "")
                    .accessibilityIdentifier(group.isOwn ? "home.story.own" : "home.story.\(group.id)")
                }
                // Nobody you follow has a story up: show people from your feed as dashed
                // "suggested" rings (tap → profile) so the row isn't just "Your story".
                if !compact {
                    ForEach(suggestedAuthors) { author in
                        Button {
                            app.navigation.push(.profile(author.id, .overview))
                            HapticEngine.shared.play(.navigation)
                        } label: {
                            trayCell(
                                avatar: ModulaAvatar(initials: author.initials, url: author.avatarURL, size: avatarSize - 2, name: author.displayName)
                                    .padding(4)
                                    .overlay(
                                        Circle().strokeBorder(
                                            Color.primary.opacity(0.2),
                                            lineWidth: 2
                                        )
                                    )
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "person.badge.plus")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(app.appearance.liveAccent, in: Circle())
                                            .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                                    },
                                title: author.displayName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? author.displayName,
                                secondary: true
                            )
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.93, haptic: nil))
                        .accessibilityLabel("Suggested: \(author.displayName)")
                        .accessibilityIdentifier("home.story.suggested.\(author.id)")
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, compact ? 0 : 24)
        }
        // Soft trailing fade: the row reads as scrollable instead of a ring cut in half.
        .mask {
            if compact {
                Rectangle()
            } else {
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .frame(minHeight: compact ? 88 : 94)
        .frame(maxHeight: compact ? 96 : 104)
        .accessibilityIdentifier("home.story.tray")
    }

    private func trayCell<Avatar: View>(avatar: Avatar, title: String, secondary: Bool = false) -> some View {
        VStack(spacing: 5) {
            avatar
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondary ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: labelWidth)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func trayTitle(_ group: StoryGroup) -> String {
        if group.isOwn { return "Your story" }
        let name = group.author.displayName.trimmingCharacters(in: .whitespaces)
        return name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    /// People from your feeds shown after real stories while the row is short. Never you,
    /// never someone already in the row, never a test fixture, one entry per person.
    private var suggestedAuthors: [SocialAuthor] {
        let shown = displayGroups.filter { !$0.isOwn }
        let room = max(0, 6 - shown.count)
        guard room > 0 else { return [] }
        var seen = Set(shown.map(\.author.id))
        var seenKeys = Set(shown.map { $0.author.handle.lowercased() })
        var seenNames = Set(shown.map { $0.author.displayName.lowercased() })
        if let own = app.profile.ownProfile {
            seenNames.insert(own.displayName.lowercased())
            seenKeys.insert(own.handle.lowercased())
        }
        return HomeMode.allCases.flatMap { app.home.visiblePosts(for: $0) }
            .compactMap(\.author)
            .filter { author in
                guard !isSelf(author.handle, id: author.id) else { return false }
                guard !ModulaFixtureFilter.isFixture(name: author.displayName, handle: author.handle) else { return false }
                guard seen.insert(author.id).inserted else { return false }
                guard seenKeys.insert(author.handle.lowercased()).inserted else { return false }
                return seenNames.insert(author.displayName.lowercased()).inserted
            }
            .prefix(room)
            .map { $0 }
    }

    private var showsComposer: Bool {
        onCreate != nil && !displayGroups.contains(where: \.isOwn)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { app.appearance.liveAccent }
    private var others: [StoryGroup] { app.stories.trayGroups.filter { !$0.isOwn && $0.hasStories } }
    private var unseen: [StoryGroup] { others.filter { $0.ring == .unseen } }
    private var ownGroup: StoryGroup? { app.stories.trayGroups.first { $0.isOwn && $0.hasStories } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                StoryCenteredCarousel(groups: app.stories.trayGroups, onSelect: open, onCreate: create)
                    .padding(.top, 4)
                quickActions
                if !unseen.isEmpty {
                    section("New for you", count: unseen.count) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(unseen) { group in
                                    StoryCoverCard(group: group, accent: accent, width: 132) { open(group) }
                                }
                            }
                            .padding(.horizontal, ModulaLayout.contentInset)
                        }
                        .padding(.horizontal, -ModulaLayout.contentInset)
                    }
                }
                if !others.isEmpty {
                    section("Following", count: others.count) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(others) { group in
                                StoryCoverCard(group: group, accent: accent, width: nil) { open(group) }
                            }
                        }
                    }
                } else {
                    emptyFollowing
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 40)
        }
        .refreshable { await app.stories.refresh() }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle("Stories")
        .task { await app.stories.loadIfNeeded() }
    }

    private func open(_ group: StoryGroup) {
        HapticEngine.shared.play(.selection)
        if group.isComposerPlaceholder { create(); return }
        Task {
            if let route = await app.stories.destination(for: group) {
                app.navigation.push(route)
            }
        }
    }

    private func create() {
        HapticEngine.shared.play(.navigation)
        app.navigation.push(.stories(.create))
    }

    /// Three big, equal targets (Fitts + Hick): every entry point opens the real composer.
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create").font(.headline)
            HStack(spacing: 10) {
                quickTile("Camera", symbol: "camera.fill", tint: accent)
                quickTile("Text", symbol: "textformat", tint: Color(hex: "#FF2D87"))
                quickTile("Photo", symbol: "photo.on.rectangle.angled", tint: Color(hex: "#FFB020"))
            }
        }
    }

    private func quickTile(_ title: String, symbol: String, tint: Color) -> some View {
        Button(action: create) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint.gradient, in: Circle())
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
        }
        .buttonStyle(.modulaPress)
        .accessibilityLabel("Create \(title.lowercased()) story")
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.headline)
                Text("\(count)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            content()
        }
    }

    private var emptyFollowing: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed").font(.title2).foregroundStyle(accent)
            Text("No stories from people you follow yet").font(.subheadline.weight(.semibold))
            Text("Stories disappear after 24 hours. Share one to get things going.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: create) {
                Label("Create story", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.modulaPress)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
    }
}

/// Centred story carousel: your bubble enlarged in the middle with an "Add story" pill,
/// friends shrinking away on either side (reference: centred bubbles).
struct StoryCenteredCarousel: View {
    let groups: [StoryGroup]
    var onSelect: (StoryGroup) -> Void
    var onCreate: () -> Void
    @Environment(AppEnvironment.self) private var app

    private var others: [StoryGroup] { groups.filter { !$0.isOwn && $0.hasStories } }
    private var own: StoryGroup? { groups.first { $0.isOwn } }

    var body: some View {
        let left = Array(others.prefix(2))
        let right = Array(others.dropFirst(2).prefix(2))
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ForEach(Array(left.reversed().enumerated()), id: \.element.id) { idx, g in side(g, size: idx == 0 && left.count == 2 ? 44 : 56) }
                centre
                ForEach(Array(right.enumerated()), id: \.element.id) { idx, g in side(g, size: idx == 0 ? 56 : 44) }
            }
            .frame(maxWidth: .infinity)
            Button(action: onCreate) {
                HStack(spacing: 10) {
                    Text(own?.hasStories == true ? "Add to story" : "Add story")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(app.appearance.liveAccent, in: Circle())
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .frame(minHeight: 44)
                .modulaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.modulaPress)
            .offset(y: -18)
            .accessibilityIdentifier("stories.add")
        }
        .padding(.top, 8)
    }

    private var centre: some View {
        let profile = app.profile.ownProfile
        return Button {
            if let own, own.hasStories { onSelect(own) } else { onCreate() }
        } label: {
            ZStack {
                if own?.hasStories == true {
                    Circle().strokeBorder(StoryRing.gradient(app.appearance.liveAccent), lineWidth: 3)
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.5)
                }
                ModulaAvatar(initials: String((profile?.displayName ?? "You").prefix(2)).uppercased(), url: profile?.avatarURL, size: 104)
            }
            .frame(width: 114, height: 114)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
        .accessibilityLabel(own?.hasStories == true ? "Your story" : "Create your story")
    }

    private func side(_ g: StoryGroup, size: CGFloat) -> some View {
        Button { onSelect(g) } label: {
            VStack(spacing: 4) {
                StoryAvatar(group: g, size: size, accent: app.appearance.liveAccent)
                Text(g.author.displayName.split(separator: " ").first.map(String.init) ?? g.author.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: size + 10)
            }
        }
        .buttonStyle(ModulaPressStyle(scale: 0.93, haptic: nil))
        .opacity(size < 50 ? 0.7 : 1)
    }
}

/// Tall 3:4 cover card for a story group: cover media when hydrated, else a gradient
/// with the author's avatar, plus a ring-state stripe and the author's name.
struct StoryCoverCard: View {
    let group: StoryGroup
    let accent: Color
    var width: CGFloat?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                cover
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.author.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    if let date = group.items.map(\.createdAt).max() {
                        Text(ActivityRelativeTime.string(from: date)).font(.caption2).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(10)
            }
            .overlay(alignment: .topLeading) {
                StoryAvatar(group: group, size: 34, accent: accent)
                    .padding(6)
            }
            .frame(width: width)
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(group.ring == .unseen ? AnyShapeStyle(StoryRing.gradient(accent)) : AnyShapeStyle(Color.primary.opacity(0.08)), lineWidth: group.ring == .unseen ? 2 : 1)
            )
        }
        .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
        .accessibilityLabel("\(group.author.displayName)’s story, \(group.ring == .unseen ? "unseen" : "seen")")
    }

    @ViewBuilder
    private var cover: some View {
        if let item = group.representative, let url = item.media?.posterURL ?? item.media?.url, item.kind != .text {
            ModulaRemoteImage(url: url, cacheKey: "story-cover:\(item.id)") { phase in
                switch phase {
                case .success(let image): Image(uiImage: image).resizable().scaledToFill()
                default: fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.85), Color(hex: "#FF2D87").opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ModulaAvatar(initials: group.author.initials, url: group.author.avatarURL, size: 56)
        }
    }
}

struct StoryInsightsView: View {
    let item: StoryItem
    let position: Int
    let count: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        insightThumb
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Published")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: "#369CAA"))
                            Text(headline)
                                .font(.title3.bold())
                                .lineLimit(3)
                            Text(ConversationRow.relative(item.createdAt))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Story \(position) of \(count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let remaining = StoryInsightFacts.remaining(until: item.expiresAt) {
                                Label(remaining, systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else {
                                Text("Expiry isn’t included on this story.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Text("Your story at a glance")
                        .font(.title3.bold())
                    // Only metrics the API actually returns; unsupported ones are hidden, not faked.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        if let viewers = item.viewerCount {
                            insightCard("Views", value: viewers.formatted(), detail: "People who opened it")
                        }
                        insightCard("Position", value: "\(position) of \(count)", detail: "In your current story")
                        if let remaining = StoryInsightFacts.remaining(until: item.expiresAt) {
                            insightCard("Time left", value: remaining.replacingOccurrences(of: " remaining", with: ""), detail: "Before it expires")
                        }
                        insightCard("Type", value: item.kind == .video ? "Video" : item.kind == .text ? "Text" : "Photo", detail: ConversationRow.relative(item.createdAt))
                    }
                    HStack(spacing: 12) {
                        ShareLink(item: insightReport) {
                            Label("Share report", systemImage: "paperplane")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                                .modulaGlass(in: Capsule(), interactive: true)
                        }
                        .accessibilityIdentifier("story.insights.share")
                        Button { dismiss() } label: {
                            HStack(spacing: 6) {
                                Text("View your story")
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .modulaAccentCTA()
                        .accessibilityIdentifier("story.insights.view")
                    }
                    .padding(.top, 6)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Story Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("story.insights")
    }

    private var headline: String {
        let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Story" : text
    }

    private var insightReport: String {
        var lines = ["Story insights — \(headline)", "Story \(position) of \(count)"]
        if let v = item.viewerCount { lines.append("Views: \(v)") }
        if let r = StoryInsightFacts.remaining(until: item.expiresAt) { lines.append(r) }
        return lines.joined(separator: "\n")
    }

    private func insightCard(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var insightThumb: some View {
        if let url = item.media?.url {
            ModulaRemoteImage(url: url, cacheKey: "story-insight:\(item.id)") { phase in
                switch phase {
                case .success(let image):
                    Image(uiImage: image).resizable().scaledToFill()
                default:
                    Color(hex: "#369CAA")
                }
            }
            .frame(width: 84, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#369CAA"))
                .frame(width: 84, height: 112)
                .overlay { Image(systemName: "text.alignleft").foregroundStyle(.white) }
        }
    }

    private func insightStat(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title.bold())
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
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
    @AppStorage("settings.personalisation.storyAutoAdvance") private var storyAutoAdvance = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var replyFocused: Bool
    @State private var engine: StoryProgressEngine
    @State private var holding = false
    @State private var loadedItemID: StoryID?
    @State private var failedItemID: StoryID?
    @State private var retryID = 0
    @State private var videoCoordinator = FeedVideoCoordinator()
    @State private var expandedVideo: ModulaAttachment?
    @State private var replyDraft = ""
    @State private var reactedLocally = false
    @State private var burstEmoji: String?
    /// Brief "Sent" chip above the reply bar after a reply or reaction is delivered.
    @State private var sentReceipt: String?
    @State private var confirmMute = false
    @State private var confirmReport = false
    @State private var confirmDelete = false
    @State private var showsInsights = false

    private let teal = Color(hex: "#369CAA")

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
            // Edge taps / hold — primary navigation. Bottom Previous/Next text removed.
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goPrevious() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goNext() }
            }
            .padding(.bottom, 96)
            .allowsHitTesting(
                !replyFocused
                    && StoryViewerGate.allowsTapNavigation(item: item, loadedID: loadedItemID, failedID: failedItemID)
            )
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
        .confirmationDialog("Mute \(item?.author.displayName ?? "this person")?", isPresented: $confirmMute, titleVisibility: .visible) {
            Button("Mute", role: .destructive) {
                guard let item else { return }
                Task {
                    if await app.profile.mute(profileID: item.author.id) {
                        app.navigation.flash("Muted \(item.author.displayName)", symbol: "speaker.slash")
                    } else {
                        app.navigation.flash("Couldn’t mute right now", symbol: "exclamationmark.triangle")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this story?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let item = currentItem else { return }
                Task {
                    if await app.stories.delete(itemID: item.id) {
                        HapticEngine.shared.play(.actionConfirmed)
                        app.navigation.flash("Story deleted", symbol: "trash")
                        app.navigation.close()
                    } else {
                        app.navigation.flash("Couldn’t delete story", symbol: "exclamationmark.triangle")
                        engine.resume()
                    }
                }
            }
            Button("Cancel", role: .cancel) { engine.resume() }
        } message: {
            Text("It’s removed for everyone right away.")
        }
        .confirmationDialog("Report this story?", isPresented: $confirmReport, titleVisibility: .visible) {
            Button("Spam", role: .destructive) { reportCurrent(category: "spam") }
            Button("Harassment", role: .destructive) { reportCurrent(category: "harassment") }
            Button("Something else", role: .destructive) { reportCurrent(category: "other") }
            Button("Cancel", role: .cancel) {}
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.height > 80 {
                    app.navigation.close()
                } else if value.translation.height < -60, abs(value.translation.width) < 80 {
                    // Swipe up → reply (and quick reactions).
                    if let item = currentItem, !item.isOwn {
                        replyFocused = true
                        HapticEngine.shared.play(.selection)
                    }
                }
            }
        )
        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
            guard !replyFocused else { return }
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
        .onChange(of: engine.index) { _, _ in
            replyDraft = ""
            reactedLocally = false
            replyFocused = false
        }
        .onChange(of: replyFocused) { _, focused in
            if focused {
                engine.pause()
            } else if !holding, scenePhase == .active {
                engine.resume()
            }
        }
        .onAppear { engine.autoAdvance = storyAutoAdvance }
        .onChange(of: scenePhase) { _, phase in
            engine.isAppActive = phase == .active
            if phase != .active { engine.pause() } else if !holding, !replyFocused { engine.resume() }
        }
        .sheet(isPresented: $showsInsights) {
            if let item = currentItem, item.isOwn {
                StoryInsightsView(item: item, position: engine.index + 1, count: max(group.items.count, 1))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("story.viewer")
        .accessibilityActions {
            Button("Previous") { goPrevious() }
            Button("Next") { goNext() }
            Button(engine.isPaused ? "Resume" : "Pause") {
                if engine.isPaused { engine.resume() } else { engine.pause() }
            }
            Button("Close") { app.navigation.close() }
            if canReply, let item {
                Button("Reply") { reply(item) }
            }
            if let item {
                Button("Share") { share(item) }
            }
        }
    }

    /// Never consume a story while its protected media is still loading.
    /// Videos keep edge-tap navigation until playback finishes.
    private var progressActive: Bool {
        !engine.isPaused && engine.isAppActive && !engine.isHoldingAtEnd
            && !replyFocused
            && loadedItemID == currentItem?.id && currentItem?.kind != .video
    }

    private var canReply: Bool {
        app.stories.capabilities.reply && app.messaging.capabilities.send
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

    private func goPrevious() {
        _ = engine.previous()
        if !reduceMotion { HapticEngine.shared.play(.selection) }
    }

    private func goNext() {
        handle(engine.next())
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
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
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
        VStack(spacing: 0) {
            topChrome(item)
            Spacer(minLength: 0)
            bottomChrome(item)
        }
        // Hold to pause also clears the chrome so the story can be seen unobstructed.
        .opacity(holding && !replyFocused ? 0 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: holding)
        .animation(reduceMotion ? nil : .snappy, value: replyFocused)
        .overlay {
            if let burstEmoji {
                Text(burstEmoji)
                    .font(.system(size: 120))
                    .shadow(radius: 12)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func topChrome(_ item: StoryItem?) -> some View {
        VStack(spacing: 10) {
            StoryProgressBar(count: engine.segmentCount, index: engine.index, progress: engine.progress)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            HStack(spacing: 10) {
                if let item {
                    ZStack {
                        Circle().strokeBorder(StoryRing.gradient(teal), lineWidth: 2)
                        ModulaAvatar(initials: item.author.initials, url: item.author.avatarURL, size: 34)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.author.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if group.items.count > 1 {
                                Text("\(engine.index + 1) of \(group.items.count)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("·").foregroundStyle(.white.opacity(0.45))
                            }
                            Text(ConversationRow.relative(item.createdAt))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                            if item.isOwn, let viewers = item.viewerCount {
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(viewers == 1 ? "1 view" : "\(viewers) views")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(teal.opacity(0.95))
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                ModulaGlassGroup(spacing: 8) {
                    ModulaGlassIconButton(
                        title: "Close",
                        systemImage: "xmark",
                        size: 40,
                        tint: .white.opacity(0.18),
                        foreground: .white
                    ) {
                        app.navigation.close()
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func bottomChrome(_ item: StoryItem?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let caption = item?.text, item?.kind != .text, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.black.opacity(0.28))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                            }
                    }
                    .padding(.horizontal, 14)
                    .accessibilityIdentifier("story.caption")
            }

            if replyFocused, let item, !item.isOwn {
                quickReactions(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let sentReceipt {
                Label(sentReceipt, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .modulaGlass(in: Capsule(), tint: .white.opacity(0.14))
                    .transition(.opacity)
                    .accessibilityIdentifier("story.sent")
            }

            ModulaGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    replyField(item)
                    reactButton(item)
                    shareButton(item)
                    overflowMenu(item)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func replyField(_ item: StoryItem?) -> some View {
        let own = item?.isOwn == true
        let enabled = canReply && !own
        HStack(spacing: 8) {
            TextField(
                own ? "Your story" : (enabled ? "Send a reply…" : "Replies unavailable"),
                text: $replyDraft
            )
            .textFieldStyle(.plain)
            .focused($replyFocused)
            .submitLabel(.send)
            .onSubmit { if let item { sendReply(item) } }
            .disabled(!enabled)
            .foregroundStyle(.white)
            if enabled, !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    if let item { sendReply(item) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(teal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send reply")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .modulaGlass(in: Capsule(), tint: teal.opacity(enabled ? 0.35 : 0.12), specular: true)
        .opacity(enabled || own ? 1 : 0.55)
        .accessibilityIdentifier("story.reply")
    }

    private static let quickEmoji = ["😂", "😮", "😍", "😢", "👏", "🔥", "🎉", "💯"]

    /// Quick reactions: shown on the story locally and sent to the author as a reply when replies are available.
    private func quickReactions(_ item: StoryItem) -> some View {
        HStack(spacing: 4) {
            ForEach(Self.quickEmoji, id: \.self) { emoji in
                Button {
                    LocalEmojiReactionStore.shared.set(emoji, for: "story:\(item.id)")
                    reactedLocally = true
                    replyFocused = false
                    // Instagram-style: a quick reaction is delivered to the author as a story reply.
                    if canReply, !item.isOwn {
                        Task {
                            if await app.stories.reply(to: item.id, text: emoji) {
                                showSentReceipt("Sent \(emoji)")
                            }
                        }
                    }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6)) { burstEmoji = emoji }
                    HapticEngine.shared.play(.success)
                    Task {
                        try? await Task.sleep(for: .seconds(1.1))
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { burstEmoji = nil }
                    }
                } label: {
                    Text(emoji).font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.85, haptic: nil))
                .accessibilityLabel("React \(emoji)")
            }
        }
        .padding(.horizontal, 12)
    }

    private func reactButton(_ item: StoryItem?) -> some View {
        ModulaGlassIconButton(
            title: reactedLocally ? "Liked" : "React",
            systemImage: reactedLocally ? "heart.fill" : "heart",
            size: 44,
            tint: reactedLocally ? teal : .white.opacity(0.16),
            foreground: .white,
            enabled: item != nil
        ) {
            guard let item, item.isOwn == false else {
                app.navigation.flash("That’s your story", symbol: "heart")
                return
            }
            guard app.stories.capabilities.react else {
                app.navigation.flash("Reactions aren’t available yet", symbol: "heart")
                return
            }
            reactedLocally.toggle()
            if !reduceMotion { HapticEngine.shared.play(.selection) }
        }
        .accessibilityIdentifier("story.react")
    }

    private func shareButton(_ item: StoryItem?) -> some View {
        ModulaGlassIconButton(
            title: "Share",
            systemImage: "square.and.arrow.up",
            size: 44,
            tint: .white.opacity(0.16),
            foreground: .white,
            enabled: item != nil
        ) {
            if let item { share(item) }
        }
        .accessibilityIdentifier("story.share")
    }

    @ViewBuilder
    private func overflowMenu(_ item: StoryItem?) -> some View {
        Menu {
            if let item {
                if item.isOwn {
                    if let viewers = item.viewerCount {
                        Text(viewers == 1 ? "1 view" : "\(viewers) views")
                    } else if app.stories.capabilities.viewers {
                        Text("Views aren’t loaded yet")
                    }
                    Button("Story insights", systemImage: "chart.bar") { showsInsights = true }
                    Button("Share story", systemImage: "square.and.arrow.up") { share(item) }
                    Button("Copy link", systemImage: "link") { copyLink(item) }
                    if let media = item.media, media.url != nil, media.kind == .image || media.kind == .video {
                        Button("Save to Photos", systemImage: "arrow.down.to.line") { saveOwnStory(item) }
                    }
                    Button("Delete story", systemImage: "trash", role: .destructive) {
                        engine.pause()
                        confirmDelete = true
                    }
                } else {
                    if canReply {
                        Button("Reply in Messages", systemImage: "bubble.left") { reply(item) }
                    }
                    Button("Share", systemImage: "square.and.arrow.up") { share(item) }
                    Button("Copy link", systemImage: "link") { copyLink(item) }
                    Button("Mute", systemImage: "speaker.slash") { confirmMute = true }
                    Button("Report", systemImage: "flag", role: .destructive) { confirmReport = true }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .modulaGlass(in: Circle(), tint: .white.opacity(0.16), specular: true)
        }
        .accessibilityLabel("More options")
        .accessibilityIdentifier("story.more")
    }

    @MainActor private func handle(_ event: StoryProgressEvent) {
        if event == .finished { app.navigation.close() }
        if event == .advanced { HapticEngine.shared.play(.selection) }
    }

    private func reply(_ item: StoryItem) {
        guard canReply else {
            app.navigation.flash("Replies aren’t available yet", symbol: "bubble.left")
            return
        }
        app.navigation.open(.messages(.new))
        app.navigation.flash("Reply in Messages", symbol: "bubble.left")
    }

    private func sendReply(_ item: StoryItem) {
        let text = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard canReply else {
            app.navigation.flash("Replies aren’t available yet", symbol: "bubble.left")
            return
        }
        replyDraft = ""
        replyFocused = false
        HapticEngine.shared.play(.selection)
        Task {
            if await app.stories.reply(to: item.id, text: text) {
                showSentReceipt("Sent to \(item.author.displayName)")
            } else {
                replyDraft = text
                app.navigation.flash("Couldn’t send reply", symbol: "exclamationmark.triangle")
            }
        }
    }

    private func showSentReceipt(_ text: String) {
        HapticEngine.shared.play(.success)
        withAnimation(.easeOut(duration: 0.2)) { sentReceipt = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if sentReceipt == text { withAnimation(.easeOut(duration: 0.25)) { sentReceipt = nil } }
        }
    }

    /// Downloads your own story's original media and adds it to Photos (add-only access).
    private func saveOwnStory(_ item: StoryItem) {
        guard let media = item.media, let url = media.url else { return }
        let client = app.client
        let navigation = app.navigation
        navigation.flash("Saving…", symbol: "arrow.down.circle")
        Task { @MainActor in
            var saved = false
            if media.kind == .video {
                if let temp = try? await client.downloadMedia(from: url) {
                    let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    try? FileManager.default.copyItem(at: temp, to: destination)
                    saved = await StoryVideoExporter.saveToPhotos(destination)
                    try? FileManager.default.removeItem(at: destination)
                }
            } else if let data = try? await client.mediaData(from: url) {
                saved = await ModulaPhotoLibrarySaver.save(data)
            }
            navigation.flash(saved ? "Saved to Photos" : "Couldn’t save to Photos", symbol: saved ? "photo.badge.checkmark" : "exclamationmark.triangle")
            HapticEngine.shared.play(saved ? .saveComplete : .failure)
        }
    }

    private func copyLink(_ item: StoryItem) {
        UIPasteboard.general.url = ModulaShareLink.story(item.id)
        app.navigation.flash("Story link copied", symbol: "link")
        HapticEngine.shared.play(.confirmation)
    }

    private func share(_ item: StoryItem) {
        app.navigation.presented = .universalShare(
            .link(url: ModulaShareLink.story(item.id), title: "\(item.author.displayName)’s story")
        )
        if !reduceMotion { HapticEngine.shared.play(.selection) }
    }

    private func reportCurrent(category: String) {
        guard let item = currentItem else { return }
        Task {
            if await app.profile.report(
                profileID: item.author.id,
                category: category,
                details: "Story \(item.id)"
            ) {
                app.navigation.flash("Thanks, report sent", symbol: "flag")
            } else {
                app.navigation.flash("Couldn’t send report", symbol: "exclamationmark.triangle")
            }
        }
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
        HStack(spacing: count > 12 ? 2 : 3) {
            ForEach(0..<count, id: \.self) { idx in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.32))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * fill(for: idx))
                    }
                }
                .frame(height: 2.5)
            }
        }
        // Liquid Glass track instead of a shadow: the shadow re-rendered offscreen on every progress tick.
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .modulaGlass(in: Capsule())
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

// MARK: - Filters

struct StoryFilter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String

    static let catalog: [StoryFilter] = [
        .init(id: "none", title: "Original", systemImage: "circle"),
        .init(id: "vivid", title: "Vivid", systemImage: "sun.max.fill"),
        .init(id: "warm", title: "Warm", systemImage: "flame.fill"),
        .init(id: "cool", title: "Cool", systemImage: "snowflake"),
        .init(id: "mono", title: "Mono", systemImage: "circle.lefthalf.filled"),
        .init(id: "fade", title: "Fade", systemImage: "cloud.fill"),
        .init(id: "noir", title: "Noir", systemImage: "moon.fill"),
        .init(id: "chrome", title: "Chrome", systemImage: "sparkles"),
        .init(id: "dramatic", title: "Drama", systemImage: "theatermasks.fill"),
        .init(id: "sepia", title: "Sepia", systemImage: "camera.filters"),
        .init(id: "bloom", title: "Bloom", systemImage: "sun.haze.fill"),
        .init(id: "vignette", title: "Vignette", systemImage: "circle.dashed"),
        .init(id: "instant", title: "Instant", systemImage: "camera.fill"),
        .init(id: "process", title: "Process", systemImage: "drop.fill"),
        .init(id: "tonal", title: "Tonal", systemImage: "circle.righthalf.filled"),
        .init(id: "transfer", title: "Retro", systemImage: "film.fill"),
    ] + PhotoFilterDialLook.allCases.map(\.storyFilter)
}

enum StoryFilterEngine {
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])

    @MainActor
    static func apply(_ filter: StoryFilter, to image: UIImage, intensity: Double = 1) -> UIImage {
        guard filter.id != "none", intensity > 0.01, let cg = image.cgImage else { return image }
        let source = CIImage(cgImage: cg)
        var output = ciApply(filter.id, to: source).cropped(to: source.extent)
        if intensity < 0.99 {
            output = source.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: output,
                kCIInputTimeKey: intensity,
            ]).cropped(to: source.extent)
        }
        guard let rendered = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Pure Core Image chain, shared by still filters and the live camera.
    nonisolated static func ciApply(_ filterID: String, to ci: CIImage) -> CIImage {
        guard filterID != "none" else { return ci }
        let output: CIImage?
        switch filterID {
        case "vivid":
            let f = CIFilter.colorControls()
            f.inputImage = ci
            f.saturation = 1.45
            f.contrast = 1.12
            output = f.outputImage
        case "warm":
            let f = CIFilter.temperatureAndTint()
            f.inputImage = ci
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 4500, y: 0)
            output = f.outputImage
        case "cool":
            let f = CIFilter.temperatureAndTint()
            f.inputImage = ci
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 9000, y: 0)
            output = f.outputImage
        case "mono":
            let f = CIFilter.photoEffectMono()
            f.inputImage = ci
            output = f.outputImage
        case "fade":
            let f = CIFilter.photoEffectFade()
            f.inputImage = ci
            output = f.outputImage
        case "noir":
            let f = CIFilter.photoEffectNoir()
            f.inputImage = ci
            output = f.outputImage
        case "chrome":
            let f = CIFilter.photoEffectChrome()
            f.inputImage = ci
            output = f.outputImage
        case "dramatic":
            let f = CIFilter.colorControls()
            f.inputImage = ci
            f.contrast = 1.35
            f.saturation = 0.85
            f.brightness = -0.03
            output = f.outputImage
        case "sepia":
            let f = CIFilter.sepiaTone()
            f.inputImage = ci
            f.intensity = 0.85
            output = f.outputImage
        case "bloom":
            let f = CIFilter.bloom()
            f.inputImage = ci
            f.radius = 12
            f.intensity = 0.7
            output = f.outputImage?.cropped(to: ci.extent)
        case "vignette":
            let f = CIFilter.vignette()
            f.inputImage = ci
            f.intensity = 1.2
            f.radius = 1.6
            output = f.outputImage
        case "instant":
            let f = CIFilter.photoEffectInstant()
            f.inputImage = ci
            output = f.outputImage
        case "process":
            let f = CIFilter.photoEffectProcess()
            f.inputImage = ci
            output = f.outputImage
        case "tonal":
            let f = CIFilter.photoEffectTonal()
            f.inputImage = ci
            output = f.outputImage
        case "transfer":
            let f = CIFilter.photoEffectTransfer()
            f.inputImage = ci
            output = f.outputImage
        case "bw":
            let f = CIFilter.photoEffectMono()
            f.inputImage = ci
            output = f.outputImage
        case "dreamy":
            let bloom = CIFilter.bloom()
            bloom.inputImage = ci
            bloom.radius = 10
            bloom.intensity = 0.55
            let glowed = (bloom.outputImage ?? ci).cropped(to: ci.extent)
            let color = CIFilter.colorControls()
            color.inputImage = glowed
            color.saturation = 0.78
            color.contrast = 0.9
            color.brightness = 0.05
            output = color.outputImage?.cropped(to: ci.extent)
        case "soft-light":
            output = softLight(ci)
        case "dither":
            let dither = CIFilter(name: "CIDither")
            dither?.setValue(ci, forKey: kCIInputImageKey)
            dither?.setValue(0.82, forKey: kCIInputIntensityKey)
            output = dither?.outputImage?.cropped(to: ci.extent)
        default:
            output = ci
        }
        return output ?? ci
    }

    /// Soft-light blend of a slightly warmed copy over the original, then a gentle lift.
    private static func softLight(_ ci: CIImage) -> CIImage {
        let warm = CIFilter.temperatureAndTint()
        warm.inputImage = ci
        warm.neutral = CIVector(x: 6500, y: 0)
        warm.targetNeutral = CIVector(x: 5600, y: 0)
        let warmed = (warm.outputImage ?? ci).cropped(to: ci.extent)
        let blend = CIFilter(name: "CISoftLightBlendMode")
        blend?.setValue(warmed, forKey: kCIInputImageKey)
        blend?.setValue(ci, forKey: kCIInputBackgroundImageKey)
        let blended = (blend?.outputImage ?? warmed).cropped(to: ci.extent)
        let color = CIFilter.colorControls()
        color.inputImage = blended
        color.contrast = 0.94
        color.brightness = 0.02
        color.saturation = 1.02
        return (color.outputImage ?? blended).cropped(to: ci.extent)
    }
}

// MARK: - Create Story v2 — model

enum StoryTextStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, strong, typewriter, serif, neon, outline, script, marker, chalk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: "Classic"
        case .strong: "Strong"
        case .typewriter: "Type"
        case .serif: "Editor"
        case .neon: "Neon"
        case .outline: "Outline"
        case .script: "Script"
        case .marker: "Marker"
        case .chalk: "Chalk"
        }
    }
    /// Story-only display faces; app UI fonts are untouched.
    var font: Font {
        switch self {
        case .classic: .system(size: 30, weight: .bold, design: .rounded)
        case .strong: .system(size: 32, weight: .black, design: .default)
        case .typewriter: .system(size: 24, weight: .medium, design: .monospaced)
        case .serif: .system(size: 30, weight: .semibold, design: .serif)
        case .neon: .system(size: 30, weight: .heavy, design: .rounded)
        case .outline: .system(size: 32, weight: .black, design: .rounded)
        case .script: .custom("SnellRoundhand-Black", size: 36)
        case .marker: .custom("MarkerFelt-Wide", size: 30)
        case .chalk: .custom("ChalkboardSE-Bold", size: 28)
        }
    }
}

enum StoryTextBackground: String, CaseIterable, Sendable {
    case none, solid, soft, highlight, outline, neon
    var symbol: String {
        switch self {
        case .none: "character"
        case .solid: "character.textbox"
        case .soft: "square.fill.text.grid.1x2"
        case .highlight: "highlighter"
        case .outline: "square.dashed"
        case .neon: "lightbulb.max"
        }
    }
    var fillsWithColour: Bool { self == .solid || self == .highlight }
}

enum StoryTextAlign: String, CaseIterable, Sendable {
    case center, leading, trailing
    var text: TextAlignment {
        switch self {
        case .center: .center
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    var symbol: String {
        switch self {
        case .center: "text.aligncenter"
        case .leading: "text.alignleft"
        case .trailing: "text.alignright"
        }
    }
}

struct StoryTextSpec: Equatable, Sendable {
    var text: String = ""
    var style: StoryTextStyle = .classic
    var colorHex: String = "#FFFFFF"
    var background: StoryTextBackground = .none
    var alignment: StoryTextAlign = .center
    var animation: StoryTextAnimation = .none
}

struct StoryLayer: Identifiable, Equatable {
    enum Content: Equatable {
        case emoji(String)
        case animated(String)
        case mascot(String)
        case sprout(String)
        case gif(URL)
        case text(StoryTextSpec)
        case location(String)
        case mention(String)
        case poll(question: String, a: String, b: String)
        case question(String)
        case countdown(title: String, date: Date)
        case music(title: String, artist: String)
        case slider(prompt: String, emoji: String)
        case quiz(question: String, options: [String])
        case time(Date)
        case addYours(String)
        case reply(String)
        /// Visual link sticker (baked into the image; not tappable for viewers yet).
        case link(String)
        /// Subject lifted from a photo; the bitmap lives in the composer's image map (keyed by layer id).
        case cutout

        var isInteractive: Bool {
            switch self {
            case .location, .mention, .link, .poll, .question, .countdown, .music, .slider, .quiz, .addYours, .reply: true
            default: false
            }
        }
    }
    let id: String
    var content: Content
    var x: CGFloat = 0.5
    var y: CGFloat = 0.42
    var scale: CGFloat = 1
    var rotation: Double = 0
}

enum StoryBrush: String, CaseIterable, Identifiable, Sendable {
    case pen, marker, neon, eraser
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .neon: "wand.and.rays"
        case .eraser: "eraser"
        }
    }
}

struct StoryDrawStroke: Identifiable, Equatable, Sendable {
    let id: String
    var points: [CGPoint]
    var colorHex: String
    var width: CGFloat
    var brush: StoryBrush
}

struct StoryGradientBG: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let hexes: [String]
    var colors: [Color] { hexes.map { Color(hex: $0) } }
    static let catalog: [StoryGradientBG] = [
        .init(id: "sunset", title: "Sunset", hexes: ["#FF6B6B", "#FFD93D", "#FF8E53"]),
        .init(id: "ocean", title: "Ocean", hexes: ["#667EEA", "#764BA2"]),
        .init(id: "mint", title: "Mint", hexes: ["#11998E", "#38EF7D"]),
        .init(id: "candy", title: "Candy", hexes: ["#F093FB", "#F5576C"]),
        .init(id: "sky", title: "Sky", hexes: ["#4FACFE", "#00F2FE"]),
        .init(id: "aurora", title: "Aurora", hexes: ["#0F2027", "#2C5364", "#36D1DC"]),
        .init(id: "peach", title: "Peach", hexes: ["#FFECD2", "#FCB69F"]),
        .init(id: "noir", title: "Noir", hexes: ["#232526", "#414345"]),
        // Solid colours
        .init(id: "solid.black", title: "Black", hexes: ["#000000", "#000000"]),
        .init(id: "solid.white", title: "White", hexes: ["#F7F7F7", "#F7F7F7"]),
        .init(id: "solid.red", title: "Red", hexes: ["#FF3B30", "#FF3B30"]),
        .init(id: "solid.orange", title: "Orange", hexes: ["#FF9500", "#FF9500"]),
        .init(id: "solid.yellow", title: "Yellow", hexes: ["#FFD60A", "#FFD60A"]),
        .init(id: "solid.green", title: "Green", hexes: ["#34C759", "#34C759"]),
        .init(id: "solid.blue", title: "Blue", hexes: ["#0A84FF", "#0A84FF"]),
        .init(id: "solid.purple", title: "Purple", hexes: ["#7656D6", "#7656D6"]),
        .init(id: "solid.pink", title: "Pink", hexes: ["#FF2D55", "#FF2D55"]),
    ]
}

enum StoryCollageLayout: String, CaseIterable, Identifiable, Sendable {
    case twoRows, twoColumns, threeRows, grid
    var id: String { rawValue }
    var slots: Int {
        switch self {
        case .twoRows, .twoColumns: 2
        case .threeRows: 3
        case .grid: 4
        }
    }
    var symbol: String {
        switch self {
        case .twoRows: "rectangle.split.1x2"
        case .twoColumns: "rectangle.split.2x1"
        case .threeRows: "rectangle.split.3x1"
        case .grid: "rectangle.split.2x2"
        }
    }
    var title: String {
        switch self {
        case .twoRows: "Stack"
        case .twoColumns: "Side by side"
        case .threeRows: "Triptych"
        case .grid: "Grid"
        }
    }
    func rects(in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        switch self {
        case .twoRows: return [CGRect(x: 0, y: 0, width: w, height: h / 2), CGRect(x: 0, y: h / 2, width: w, height: h / 2)]
        case .twoColumns: return [CGRect(x: 0, y: 0, width: w / 2, height: h), CGRect(x: w / 2, y: 0, width: w / 2, height: h)]
        case .threeRows: return (0..<3).map { CGRect(x: 0, y: h * CGFloat($0) / 3, width: w, height: h / 3) }
        case .grid: return [
            CGRect(x: 0, y: 0, width: w / 2, height: h / 2), CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2),
            CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2), CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2),
        ]
        }
    }
}

enum StoryMusicCatalog {
    static let tracks: [(title: String, artist: String)] = [
        ("Midnight Drive", "Modula FM"), ("Soft Focus", "Studio Waves"), ("Neon Pulse", "City Lights"),
        ("Golden Hour", "Sunroom"), ("Low Battery", "Lo-Fi Lab"), ("Afterglow", "Night Bus"),
        ("Paper Planes", "Loft Tapes"), ("Slow Motion", "Velvet Room"),
    ]
}

/// Decodes GIF data into an animated UIImage (frames capped for memory).
enum StoryGIFDecoder {
    static func animatedImage(from data: Data, maxFrames: Int = 48, maxPixel: CGFloat = 360) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        var frames: [UIImage] = []
        var duration: Double = 0
        let step = max(1, count / maxFrames)
        for i in stride(from: 0, to: count, by: step) {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.08
            duration += max(delay, 0.02) * Double(step)
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

private struct StoryAnimatedImageView: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image !== image { uiView.image = image }
        if image.images != nil, !uiView.isAnimating { uiView.startAnimating() }
    }
}

// MARK: - Create Story v2 — shared render views (edit stage + baking)

struct StoryBackgroundView: View {
    var image: UIImage?
    var gradient: StoryGradientBG?
    var collage: StoryCollageLayout?
    var collageImages: [UIImage] = []
    var showsPlaceholders = true
    /// Pinch/pan crop of the photo background (offset is a fraction of the canvas).
    var imageScale: CGFloat = 1
    var imageOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            if let collage {
                // While editing, cells sit below the Retake / close bar so controls never overlap a frame.
                let inset: CGFloat = showsPlaceholders ? 64 : 0
                let area = CGSize(width: geo.size.width, height: max(geo.size.height - inset, 1))
                ZStack(alignment: .topLeading) {
                    Color.black
                    ForEach(Array(collage.rects(in: area).enumerated().map { ($0.offset, $0.element.offsetBy(dx: 0, dy: inset)) }), id: \.0) { index, rect in
                        Group {
                            if index < collageImages.count {
                                Image(uiImage: collageImages[index])
                                    .resizable()
                                    .scaledToFill()
                            } else if showsPlaceholders {
                                ZStack {
                                    Color(white: 0.14)
                                    Image(systemName: "plus")
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            } else {
                                Color(white: 0.1)
                            }
                        }
                        .frame(width: max(rect.width - 6, 1), height: max(rect.height - 6, 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .offset(x: rect.minX + 3, y: rect.minY + 3)
                    }
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(imageScale)
                    .offset(x: imageOffset.width * geo.size.width, y: imageOffset.height * geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Color.black)
                    .clipped()
            } else if let gradient {
                LinearGradient(colors: gradient.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color(white: 0.08)
            }
        }
    }
}

struct StoryDrawingCanvas: View {
    var strokes: [StoryDrawStroke]
    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                if stroke.points.count == 1 {
                    path.addLine(to: CGPoint(x: first.x * size.width + 0.1, y: first.y * size.height + 0.1))
                }
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                let colour = Color(hex: stroke.colorHex)
                switch stroke.brush {
                case .pen:
                    context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                case .marker:
                    context.stroke(path, with: .color(colour.opacity(0.5)), style: StrokeStyle(lineWidth: stroke.width * 2.6, lineCap: .square, lineJoin: .round))
                case .neon:
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: stroke.width * 1.4))
                        layer.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: stroke.width * 2.2, lineCap: .round, lineJoin: .round))
                    }
                    context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, stroke.width * 0.35), lineCap: .round, lineJoin: .round))
                case .eraser:
                    var eraser = context
                    eraser.blendMode = .clear
                    eraser.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: stroke.width * 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct StoryLayerView: View {
    let layer: StoryLayer
    var gif: UIImage?
    var isBaking = false
    var accent: Color = Color(hex: "#7656D6")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch layer.content {
        case .emoji(let emoji):
            Text(emoji).font(.system(size: 72))
        case .animated(let raw):
            if let style = ModulaAnimatedSticker.Style(rawValue: raw) {
                ModulaAnimatedSticker(style: style, size: 120)
            }
        case .mascot(let raw):
            if let kind = ModulaMascotKind(rawValue: raw) {
                ModulaMascotSticker(kind: kind, size: 130)
            }
        case .sprout(let raw):
            if let item = SproutStickerPack.sticker(id: raw) {
                SproutStickerImage(assetName: item.assetName, size: 140)
            }
        case .gif:
            Group {
                if let gif {
                    if isBaking {
                        Image(uiImage: gif.images?.first ?? gif).resizable().scaledToFit()
                    } else {
                        StoryAnimatedImageView(image: gif)
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 160, height: 160 * ((gif?.size.height ?? 160) / max(gif?.size.width ?? 160, 1)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .text(let spec):
            textView(spec)
                .modifier(StoryTextAnimationModifier(animation: spec.animation, enabled: !isBaking && !reduceMotion))
        case .location(let place):
            Label(place.uppercased(), systemImage: "mappin.and.ellipse")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "#7656D6"), Color(hex: "#FF2D55")], startPoint: .leading, endPoint: .trailing))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        case .mention(let handle):
            let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
            HStack(spacing: 7) {
                Image(systemName: "at")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(LinearGradient(colors: [Color(hex: "#FF9500"), Color(hex: "#FF2D55")], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                Text((clean.isEmpty ? "username" : clean).lowercased())
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "#FF9500"), Color(hex: "#FF2D55")], startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1)
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        case .link(let url):
            let host = URL(string: url.contains("://") ? url : "https://" + url)?.host() ?? url
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color(hex: "#0A84FF"), in: Circle())
                Text(host.isEmpty ? "Add link" : host.uppercased())
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "#0A84FF"))
                    .lineLimit(1)
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        case .poll(let question, let a, let b):
            VStack(spacing: 10) {
                Text(question)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                VStack(spacing: 6) {
                    pollOption(a)
                    pollOption(b)
                }
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(width: 230)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        case .question(let prompt):
            VStack(spacing: 0) {
                Text(prompt)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [accent, Color(hex: "#FF2D55")], startPoint: .leading, endPoint: .trailing))
                Text("Type something…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.94))
            }
            .frame(width: 230)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        case .countdown(let title, let date):
            VStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text(date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.black)
                Label("Countdown", systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(minWidth: 200)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        case .music(let title, let artist):
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [accent, Color(hex: "#FF2D55")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(artist).font(.system(size: 12, weight: .medium)).opacity(0.75).lineLimit(1)
                }
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach([10.0, 16, 8, 14], id: \.self) { h in
                        Capsule().frame(width: 3, height: h)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
        case .slider, .quiz, .time, .addYours, .reply, .cutout:
            extraStickers
        }
    }

    @ViewBuilder
    private var extraStickers: some View {
        switch layer.content {
        case .cutout:
            if let gif {
                Image(uiImage: gif).resizable().scaledToFit()
                    .frame(width: 220, height: 220 * gif.size.height / max(gif.size.width, 1))
                    .shadow(color: .white, radius: 0, x: 2, y: 0)
                    .shadow(color: .white, radius: 0, x: -2, y: 0)
                    .shadow(color: .white, radius: 0, x: 0, y: 2)
                    .shadow(color: .white, radius: 0, x: 0, y: -2)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else {
                ProgressView().tint(.white)
            }
        case .slider(let prompt, let emoji):
            VStack(spacing: 12) {
                Text(prompt.isEmpty ? "How much?" : prompt)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.9)).frame(height: 8)
                    Capsule().fill(LinearGradient(colors: [accent, Color(hex: "#FF2D55")], startPoint: .leading, endPoint: .trailing)).frame(width: 90, height: 8)
                    Text(emoji).font(.system(size: 34)).offset(x: 72)
                }
                .frame(height: 40)
            }
            .padding(16)
            .frame(width: 240)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        case .quiz(let question, let options):
            VStack(spacing: 0) {
                Text(question.isEmpty ? "Quiz" : question)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [Color(hex: "#0A84FF"), accent], startPoint: .leading, endPoint: .trailing))
                VStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                        HStack(spacing: 10) {
                            Text(["A", "B", "C", "D"][min(i, 3)])
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color(white: 0.55), in: Circle())
                            Text(option).font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(10)
            }
            .frame(width: 240)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        case .time(let date):
            VStack(spacing: 0) {
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        case .addYours(let prompt):
            VStack(spacing: 6) {
                Label("ADD YOURS", systemImage: "camera.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text(prompt.isEmpty ? "Show me yours" : prompt)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                Text("Tap to join in")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(minWidth: 210)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        case .reply(let prompt):
            Label(prompt.isEmpty ? "Reply to my story" : prompt, systemImage: "arrowshape.turn.up.left.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        default:
            EmptyView()
        }
    }

    private func pollOption(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func textView(_ spec: StoryTextSpec) -> some View {
        let colour = Color(hex: spec.colorHex)
        let darkOnColour = StoryTextContrast.prefersDarkText(hex: spec.colorHex)
        let foreground: Color = spec.background.fillsWithColour ? (darkOnColour ? .black : .white) : colour
        let display = spec.text.isEmpty ? "Tap to type" : (spec.style == .strong ? spec.text.uppercased() : spec.text)
        return Text(display)
            .font(spec.style.font)
            .multilineTextAlignment(spec.alignment.text)
            .foregroundStyle(foreground)
            .shadow(color: spec.style == .neon ? colour.opacity(0.95) : .clear, radius: 10)
            .shadow(color: spec.style == .neon ? colour.opacity(0.6) : .clear, radius: 22)
            .shadow(color: spec.style == .outline ? .black : .clear, radius: 0, x: 1.5, y: 1.5)
            .shadow(color: spec.style == .outline ? .black : .clear, radius: 0, x: -1.5, y: -1.5)
            .shadow(color: spec.background == .none && spec.style != .neon && spec.style != .outline ? .black.opacity(0.35) : .clear, radius: 4, y: 1)
            .padding(.horizontal, spec.background == .none ? 4 : 12)
            .padding(.vertical, spec.background == .none ? 2 : 6)
            .background {
                switch spec.background {
                case .none: Color.clear
                case .solid: RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colour)
                case .soft: RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.45))
                case .highlight:
                    // Marker-style swipe: tighter, slightly tilted, translucent.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colour.opacity(0.88))
                        .rotationEffect(.degrees(-1.2))
                        .padding(.vertical, 3)
                case .outline:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(colour, lineWidth: 2.5)
                case .neon:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colour, lineWidth: 2))
                        .shadow(color: colour.opacity(0.9), radius: 8)
                        .shadow(color: colour.opacity(0.5), radius: 18)
                }
            }
            .frame(maxWidth: 300)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(spec.text.isEmpty ? 0.7 : 1)
    }
}

/// Everything that is flattened into the published JPEG (WYSIWYG with the edit canvas).
struct StoryBakeView: View {
    let size: CGSize
    var image: UIImage?
    var gradient: StoryGradientBG?
    var collage: StoryCollageLayout?
    var collageImages: [UIImage]
    var strokes: [StoryDrawStroke]
    var layers: [StoryLayer]
    var gifs: [String: UIImage]
    var accent: Color
    var imageScale: CGFloat = 1
    var imageOffset: CGSize = .zero

    var body: some View {
        ZStack {
            StoryBackgroundView(image: image, gradient: gradient, collage: collage, collageImages: collageImages, showsPlaceholders: false, imageScale: imageScale, imageOffset: imageOffset)
            StoryDrawingCanvas(strokes: strokes)
            ForEach(layers) { layer in
                StoryLayerView(layer: layer, gif: gifs[layer.id], isBaking: true, accent: accent)
                    .scaleEffect(layer.scale)
                    .rotationEffect(.degrees(layer.rotation))
                    .position(x: layer.x * size.width, y: layer.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: - Create Story v2 — composer

@MainActor
struct StoryCreateView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var collagePickerItems: [PhotosPickerItem] = []
    @State private var showsCamera = true
    @State private var sourceImage: UIImage?
    @State private var filteredPreview: UIImage?
    @State private var filterThumbs: [String: UIImage] = [:]
    @State private var prepared: PreparedImage?
    @State private var caption = ""
    @State private var busy = false
    @State private var draftMedia: CreationMedia?
    @State private var visibility = "public"
    @State private var published = false
    @State private var restored = false
    @State private var draftID = "story-primary"
    @State private var filter = StoryFilter.catalog[0]
    @State private var videoURL: URL?
    @State private var toast: String?

    // v2 canvas state
    @State private var canvasSize = CGSize(width: 390, height: 693)
    @State private var gradientBG: StoryGradientBG?
    @State private var collageLayout: StoryCollageLayout?
    @State private var collageImages: [UIImage] = []
    @State private var layers: [StoryLayer] = []
    @State private var gifImages: [String: UIImage] = [:]
    @State private var strokes: [StoryDrawStroke] = []
    @State private var activeStroke: StoryDrawStroke?
    @State private var brush: StoryBrush = .pen
    @State private var drawColorHex = "#FFFFFF"
    @State private var drawWidth: CGFloat = 6
    @State private var tool: Tool?
    @State private var sheet: StorySheet?
    @State private var editingTextID: String?
    @State private var textSpec = StoryTextSpec()
    @FocusState private var textFocused: Bool
    @State private var draggingID: String?
    @State private var overTrash = false
    @State private var snapX = false
    @State private var snapY = false
    @State private var history: [StoryEditSnapshot] = []
    @State private var future: [StoryEditSnapshot] = []
    @State private var committed = StoryEditSnapshot()
    @State private var restoringHistory = false
    @State private var filterIntensity: Double = 1
    @State private var showsDrafts = false
    @State private var dragBase: [String: CGPoint] = [:]
    @State private var scaleBase: [String: CGFloat] = [:]
    @State private var rotationBase: [String: Double] = [:]
    @State private var bakeTask: Task<Void, Never>?
    @State private var interactiveNoticeShown = false
    @State private var bgScale: CGFloat = 1
    @State private var bgOffset: CGSize = .zero
    @State private var bgScaleBase: CGFloat?
    @State private var bgOffsetBase: CGSize?
    @State private var cutoutItems: [PhotosPickerItem] = []
    @State private var videoTime: Double = 0
    @State private var captions: [StoryCaption] = []
    @State private var captioning = false
    @State private var exporting = false

    // sticker sheet + forms
    @State private var stickerTab: StickerTab = .emoji
    @State private var gifQuery = ""
    @State private var gifs: [ModulaGif] = []
    @State private var gifStatus: String?
    @State private var formA = ""
    @State private var formB = ""
    @State private var formC = ""
    @State private var formDate = Date().addingTimeInterval(86_400)

    private static let canvasSpace = "story.canvas"
    private static let palette = ["#FFFFFF", "#000000", "#FF2D55", "#FF9500", "#FFD60A", "#30D158", "#64D2FF", "#0A84FF", "#BF5AF2", "#FF6FB5"]
    private static let emoji = ["😀", "😍", "🥹", "😂", "🔥", "✨", "🎉", "💜", "🦋", "🌟", "👑", "🐾", "😎", "🫶", "💫", "🎵", "🌈", "⚡", "🍓", "☕️", "🌙", "🌸", "🍕", "🏝️"]

    private enum Tool: String, CaseIterable, Identifiable {
        case draw, music, filters, layout
        var id: String { rawValue }
    }

    private enum StickerTab: String, CaseIterable, Identifiable {
        case emoji = "Emoji", animated = "Animated", mascot = "Mascots", gif = "GIFs"
        var id: String { rawValue }
    }

    private enum StorySheet: String, Identifiable {
        case stickers, location, mention, link, poll, question, countdown, slider, quiz, addYours, reply
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stickers: "Stickers"
            case .location: "Location"
            case .mention: "Mention"
            case .link: "Link"
            case .poll: "Poll"
            case .question: "Question"
            case .countdown: "Countdown"
            case .slider: "Emoji slider"
            case .quiz: "Quiz"
            case .addYours: "Add Yours"
            case .reply: "Reply sticker"
            }
        }
    }

    private var canPublishVideo: Bool { app.stories.capabilities.video }
    private var hasMedia: Bool { sourceImage != nil || videoURL != nil || gradientBG != nil || collageLayout != nil }
    private var canShare: Bool {
        if collageLayout != nil && collageImages.isEmpty { return false }
        return prepared != nil
    }
    private var accent: Color { app.appearance.liveAccent }
    private var spring: Animation { reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.84) }

    var body: some View {
        Group {
            if app.stories.capabilities.create {
                composer
            } else {
                ModulaEmptyState(
                    title: "Create story",
                    message: "Publishing stories isn’t available yet.",
                    symbol: "plus.circle"
                )
            }
        }
        .modulaCanvas()
        .navigationTitle("Create story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        // The system back chevron was still drawn under our own close (X) — one control only.
        .navigationBarBackButtonHidden(true)
        .onChange(of: cutoutItems) { _, items in
            Task { await loadCutout(items) }
        }
        .onChange(of: pickerItems) { _, items in
            Task { await loadPicker(items) }
        }
        .onChange(of: collagePickerItems) { _, items in
            Task { await loadCollage(items) }
        }
        .task {
            await restoreDraft()
            #if DEBUG
            await injectUITestPhotoIfRequested()
            #endif
        }
        .onChange(of: caption) { _, _ in saveDraft() }
        .onChange(of: visibility) { _, _ in saveDraft() }
        .onChange(of: filter) { _, _ in filterIntensity = 1; refilter() }
        .onChange(of: filterIntensity) { _, _ in refilter() }
        .sheet(isPresented: $showsDrafts) {
            StoryDraftsGallery(currentID: draftID) { id in
                showsDrafts = false
                openDraft(id)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            bakeTask?.cancel()
            if !published { saveDraft(); app.drafts.flush() }
        }
        .overlay(alignment: .bottom) {
            if let message = toast ?? app.stories.actionError ?? app.drafts.saveError {
                ModulaErrorBanner(message: message, identifier: "story.create.error") {
                    toast = nil
                    app.stories.setActionError(nil)
                }
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
                .presentationDetents(item == .stickers ? [.medium, .large] : [.height(item == .poll || item == .countdown ? 340 : 240)])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.resizes)
                .presentationBackground(.ultraThinMaterial)
        }
        .accessibilityIdentifier("story.create")
        .accessibilityValue(RouteSerializer.serialize(.stories(.create)))
    }

    private var composer: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if showsCamera || !hasMedia {
                captureStage
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
            } else {
                editStage
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.02).combined(with: .opacity))
            }

            if editingTextID == nil {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if hasMedia && !showsCamera, let tool {
                        toolChrome(tool)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    bottomBar
                }
                .opacity(draggingID == nil ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: draggingID == nil)
            }

            if editingTextID != nil {
                textEditorOverlay
                    .transition(.opacity)
            }
        }
        .animation(spring, value: showsCamera)
        .animation(spring, value: hasMedia)
        .animation(spring, value: tool)
        .animation(spring, value: editingTextID)
    }

    // MARK: Capture

    private var captureStage: some View {
        StoryCaptureStage(
            // Recording is always local; publishing video still depends on the backend capability.
            canVideo: true,
            libraryItems: $pickerItems,
            onPhoto: { image in Task { await accept(image: image) } },
            onVideo: { url in
                do {
                    videoURL = url
                    captions = []
                    sourceImage = nil
                    filteredPreview = nil
                    prepared = nil
                    gradientBG = nil
                    collageLayout = nil
                    showsCamera = false
                    HapticEngine.shared.play(.success)
                    if !canPublishVideo {
                        app.navigation.flash("Video sharing is coming soon — you can still edit and save it to Photos", symbol: "video")
                    }
                }
            },
            onText: { startTextStory() },
            onLayout: {
                withAnimation(spring) {
                    clearMedia()
                    collageLayout = .grid
                    showsCamera = false
                    tool = .layout
                }
                HapticEngine.shared.play(.selection)
            },
            onClose: {
                if hasMedia {
                    withAnimation(spring) { showsCamera = false }
                } else {
                    app.navigation.close()
                }
            }
        )
        .disabled(busy)
    }

    private func captureChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, ModulaSpacing.md)
            .frame(height: ModulaLayout.minimumTouch)
            .modulaGlass(in: Capsule(), interactive: false)
    }

    // MARK: Edit stage

    private var editStage: some View {
        GeometryReader { geo in
            ZStack {
                if let videoURL {
                    StoryLoopingVideo(url: videoURL) { videoTime = $0 }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay {
                            if let line = captions.first(where: { videoTime >= $0.start && videoTime <= $0.end }) {
                                StoryCaptionPill(text: line.text)
                                    .position(x: geo.size.width / 2, y: geo.size.height * 0.8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            if exporting || captioning {
                                ProgressView(captioning ? "Captioning…" : "Exporting…")
                                    .tint(.white).foregroundStyle(.white)
                                    .padding(18)
                                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                } else {
                    StoryBackgroundView(
                        image: filteredPreview ?? sourceImage,
                        gradient: gradientBG,
                        collage: collageLayout,
                        collageImages: collageImages,
                        imageScale: bgScale,
                        imageOffset: bgOffset
                    )
                    .gesture(backgroundCropGesture(in: geo.size), including: sourceImage != nil && collageLayout == nil && tool != .draw ? .all : .none)
                    .onTapGesture {
                        if gradientBG != nil, collageLayout == nil, tool != .draw { beginText() }
                    }
                }

                StoryDrawingCanvas(strokes: strokes + (activeStroke.map { [$0] } ?? []))

                ForEach(layers) { layer in
                    StoryLayerView(layer: layer, gif: gifImages[layer.id], accent: accent)
                        .scaleEffect(layer.scale * (draggingID == layer.id && overTrash ? 0.45 : 1))
                        .rotationEffect(.degrees(layer.rotation))
                        .opacity(editingTextID == layer.id ? 0 : (draggingID == layer.id && overTrash ? 0.6 : 1))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if case .text(let spec) = layer.content {
                                editingTextID = layer.id
                                textSpec = spec
                                HapticEngine.shared.play(.selection)
                            }
                        }
                        .contextMenu {
                            Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { moveLayer(layer.id, .front) }
                            Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") { moveLayer(layer.id, .forward) }
                            Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") { moveLayer(layer.id, .backward) }
                            Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { moveLayer(layer.id, .back) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(spring) { layers.removeAll { $0.id == layer.id }; gifImages[layer.id] = nil }
                                scheduleBake()
                            }
                        }
                        .gesture(layerGesture(layer.id))
                        .position(x: layer.x * geo.size.width, y: layer.y * geo.size.height)
                        .allowsHitTesting(tool != .draw && editingTextID == nil)
                        .animation(.snappy(duration: 0.18), value: overTrash)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }

                if draggingID != nil {
                    StorySnapGuides(vertical: snapX, horizontal: snapY)
                        .allowsHitTesting(false)
                }

                if tool == .draw {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawGesture(in: geo.size))
                }

                if draggingID != nil {
                    trashZone
                        .position(x: geo.size.width / 2, y: geo.size.height - 110)
                        .transition(.scale.combined(with: .opacity))
                }

                if editingTextID == nil && draggingID == nil {
                    // Soft scrims keep chrome legible over bright photos.
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                    LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 170)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .allowsHitTesting(false)
                    editTopBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    toolRail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 64)
                        .padding(.trailing, 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: Self.canvasSpace)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, size in canvasSize = size }
        }
        .animation(spring, value: layers.count)
        .animation(.snappy(duration: 0.2), value: draggingID)
    }

    private var trashZone: some View {
        Image(systemName: "trash")
            .font(.system(size: overTrash ? 24 : 20, weight: .semibold))
            .foregroundStyle(overTrash ? Color.white : Color.white.opacity(0.9))
            .frame(width: overTrash ? 70 : 56, height: overTrash ? 70 : 56)
            .background(overTrash ? Color.red.opacity(0.9) : Color.black.opacity(0.45), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
            .animation(.snappy(duration: 0.18), value: overTrash)
            .accessibilityLabel("Drop here to delete")
    }

    private var editTopBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(spring) {
                    clearMedia()
                    showsCamera = true
                }
                HapticEngine.shared.play(.selection)
            } label: {
                Label("Retake", systemImage: "chevron.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .modulaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story.create.retake")
            Menu {
                Button("New story", systemImage: "plus") { startNewDraft() }
                Button("Drafts (\(app.drafts.stories.count))", systemImage: "square.stack") { showsDrafts = true }
            } label: {
                Image(systemName: "square.stack")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .modulaGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Drafts")
            if bgScale != 1 || bgOffset != .zero {
                Button {
                    withAnimation(spring) { bgScale = 1; bgOffset = .zero }
                    scheduleBake()
                    HapticEngine.shared.play(.selection)
                } label: {
                    Label("Reset crop", systemImage: "crop")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .modulaGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            ModulaGlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    Button { undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .modulaGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(history.isEmpty)
                    .opacity(history.isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Undo")
                    Button { redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .modulaGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(future.isEmpty)
                    .opacity(future.isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Redo")
                }
            }
            Button {
                app.navigation.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .modulaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var toolRail: some View {
        VStack(alignment: .trailing, spacing: 8) {
            railButton("textformat", label: "Text", active: false) { beginText() }
            railButton("face.smiling", label: "Stickers", active: false) {
                sheet = .stickers
            }
            railButton("scribble.variable", label: "Draw", active: tool == .draw) { toggle(.draw) }
            railButton("music.note", label: "Music", active: tool == .music) { toggle(.music) }
            railButton("camera.filters", label: "Effects", active: tool == .filters) { toggle(.filters) }
            railButton("list.bullet", label: "Poll", active: sheet == .poll) {
                noticeInteractive()
                sheet = .poll
            }
            railButton("questionmark", label: "Question", active: sheet == .question) {
                noticeInteractive()
                sheet = .question
            }
            railButton("rectangle.split.2x2", label: "Layout", active: tool == .layout) {
                if collageLayout == nil {
                    withAnimation(spring) {
                        if let image = sourceImage { collageImages = [image] }
                        collageLayout = .twoRows
                        gradientBG = nil
                    }
                    scheduleBake()
                }
                toggle(.layout)
            }
            if videoURL != nil {
                railButton("captions.bubble", label: captions.isEmpty ? "Captions" : "Captions on", active: !captions.isEmpty) {
                    if captions.isEmpty { Task { await makeCaptions() } } else { withAnimation(spring) { captions = [] } }
                }
            }
            railButton("arrow.down.to.line", label: "Save", active: false) {
                Task { await saveToPhotos() }
            }
        }
    }

    private func railButton(_ symbol: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(active ? Color.black : Color.white)
                    .frame(width: 42, height: 42)
                    .background { if active { Circle().fill(.white) } }
                    .modulaGlass(in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func backgroundCropGesture(in size: CGSize) -> some Gesture {
        let pinch = MagnifyGesture()
            .onChanged { value in
                if bgScaleBase == nil { bgScaleBase = bgScale }
                bgScale = min(max((bgScaleBase ?? 1) * value.magnification, 1), 4)
            }
            .onEnded { _ in bgScaleBase = nil; scheduleBake() }
        let pan = DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard bgScale > 1.01 else { return }
                if bgOffsetBase == nil { bgOffsetBase = bgOffset }
                let base = bgOffsetBase ?? .zero
                let limit = (bgScale - 1) / 2
                bgOffset = CGSize(
                    width: min(max(base.width + value.translation.width / max(size.width, 1), -limit), limit),
                    height: min(max(base.height + value.translation.height / max(size.height, 1), -limit), limit)
                )
            }
            .onEnded { _ in bgOffsetBase = nil; scheduleBake() }
        return pinch.simultaneously(with: pan)
    }

    private func toggle(_ next: Tool) {
        withAnimation(spring) { tool = tool == next ? nil : next }
    }

    // MARK: Gestures

    private func layerGesture(_ id: String) -> some Gesture {
        let drag = DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
                if dragBase[id] == nil {
                    dragBase[id] = CGPoint(x: layers[i].x, y: layers[i].y)
                    draggingID = id
                    HapticEngine.shared.play(.lightImpact)
                }
                let base = dragBase[id] ?? .zero
                let w = max(canvasSize.width, 1), h = max(canvasSize.height, 1)
                var nx = min(max(base.x + value.translation.width / w, 0.02), 0.98)
                var ny = min(max(base.y + value.translation.height / h, 0.02), 0.98)
                // Snap to the centre lines (≈10pt magnet) with a tick on entry.
                let sx = abs(nx - 0.5) * w < 10, sy = abs(ny - 0.5) * h < 10
                if sx { nx = 0.5 }
                if sy { ny = 0.5 }
                if sx != snapX || sy != snapY {
                    if (sx && !snapX) || (sy && !snapY) { HapticEngine.shared.play(.selection) }
                    snapX = sx; snapY = sy
                }
                layers[i].x = nx
                layers[i].y = ny
                let over = isOverTrash(value.location)
                if over != overTrash {
                    overTrash = over
                    HapticEngine.shared.play(.dragThreshold)
                }
            }
            .onEnded { value in
                dragBase[id] = nil
                if isOverTrash(value.location) {
                    withAnimation(spring) {
                        layers.removeAll { $0.id == id }
                        gifImages[id] = nil
                    }
                    HapticEngine.shared.play(.drop)
                }
                draggingID = nil
                overTrash = false
                snapX = false; snapY = false
                scheduleBake()
            }
        let pinch = MagnifyGesture()
            .onChanged { value in
                guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
                if scaleBase[id] == nil { scaleBase[id] = layers[i].scale }
                layers[i].scale = min(max((scaleBase[id] ?? 1) * value.magnification, 0.3), 4)
            }
            .onEnded { _ in scaleBase[id] = nil; scheduleBake() }
        let rotate = RotateGesture()
            .onChanged { value in
                guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
                if rotationBase[id] == nil { rotationBase[id] = layers[i].rotation }
                layers[i].rotation = (rotationBase[id] ?? 0) + value.rotation.degrees
            }
            .onEnded { _ in rotationBase[id] = nil; scheduleBake() }
        return drag.simultaneously(with: pinch.simultaneously(with: rotate))
    }

    private func isOverTrash(_ location: CGPoint) -> Bool {
        let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 110)
        return hypot(location.x - centre.x, location.y - centre.y) < 64
    }

    private func drawGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(
                    x: min(max(value.location.x / max(size.width, 1), 0), 1),
                    y: min(max(value.location.y / max(size.height, 1), 0), 1)
                )
                if activeStroke == nil {
                    activeStroke = StoryDrawStroke(id: UUID().uuidString, points: [point], colorHex: drawColorHex, width: drawWidth, brush: brush)
                } else if let last = activeStroke?.points.last,
                          hypot((point.x - last.x) * size.width, (point.y - last.y) * size.height) > 1.5 {
                    activeStroke?.points.append(point)
                }
            }
            .onEnded { _ in
                if let stroke = activeStroke {
                    strokes.append(stroke)
                    scheduleBake()
                }
                activeStroke = nil
            }
    }

    // MARK: Text editor

    private var textEditorOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { commitText() }

            VStack(spacing: 14) {
                HStack {
                    Button {
                        textSpec.alignment = next(textSpec.alignment)
                        HapticEngine.shared.play(.selection)
                    } label: { editorIcon(textSpec.alignment.symbol) }
                    .accessibilityLabel("Alignment")
                    Button {
                        textSpec.background = next(textSpec.background)
                        HapticEngine.shared.play(.selection)
                    } label: { editorIcon(textSpec.background.symbol) }
                    .accessibilityLabel("Text background")
                    Button {
                        textSpec.animation = next(textSpec.animation)
                        HapticEngine.shared.play(.selection)
                    } label: { editorIcon(textSpec.animation.symbol) }
                    .accessibilityLabel("Text animation: \(textSpec.animation.title)")
                    if textSpec.animation != .none {
                        Text(textSpec.animation.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Done") { commitText() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .modulaAccentCTA()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                TextField("Start typing…", text: $textSpec.text, axis: .vertical)
                    .font(textSpec.style.font)
                    .multilineTextAlignment(textSpec.alignment.text)
                    .foregroundStyle(textSpec.background == .solid ? (StoryTextContrast.prefersDarkText(hex: textSpec.colorHex) ? Color.black : .white) : Color(hex: textSpec.colorHex))
                    .tint(Color(hex: textSpec.colorHex))
                    .lineLimit(1...6)
                    .focused($textFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if textSpec.background == .solid {
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: textSpec.colorHex))
                        }
                    }
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StoryTextStyle.allCases) { style in
                            Button {
                                textSpec.style = style
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Text(style.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(textSpec.style == style ? Color.black : Color.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(textSpec.style == style ? Color.white : Color.white.opacity(0.16), in: Capsule())
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                colourRow(selection: textSpec.colorHex) { textSpec.colorHex = $0 }
            }
            .padding(.vertical, 14)
        }
        .onAppear { textFocused = true }
    }

    private func editorIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.16), in: Circle())
            .contentTransition(.symbolEffect(.replace))
    }

    private func next<T: CaseIterable & Equatable>(_ value: T) -> T {
        let all = Array(T.allCases)
        let i = all.firstIndex(of: value) ?? 0
        return all[(i + 1) % all.count]
    }

    private func colourRow(selection: String, onPick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // System colour picker includes an eyedropper to sample colours from the image.
                ColorPicker("Pick colour", selection: Binding(
                    get: { Color(hex: selection) },
                    set: { onPick(storyHexString($0)) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30, height: 30)
                .accessibilityLabel("Custom colour or eyedropper")
                ForEach(Self.palette, id: \.self) { hex in
                    Button {
                        onPick(hex)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white, lineWidth: selection == hex ? 3 : 1.2))
                            .scaleEffect(selection == hex ? 1.12 : 1)
                            .animation(.snappy(duration: 0.18), value: selection)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(hex)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func beginText() {
        let layer = StoryLayer(id: UUID().uuidString, content: .text(StoryTextSpec(colorHex: textSpec.colorHex)), x: 0.5, y: 0.4)
        textSpec = StoryTextSpec(style: textSpec.style, colorHex: textSpec.colorHex, background: textSpec.background, alignment: textSpec.alignment, animation: textSpec.animation)
        withAnimation(spring) {
            layers.append(layer)
            editingTextID = layer.id
        }
    }

    private func commitText() {
        guard let id = editingTextID else { return }
        let trimmed = textSpec.text.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(spring) {
            if let i = layers.firstIndex(where: { $0.id == id }) {
                if trimmed.isEmpty {
                    layers.remove(at: i)
                } else {
                    var spec = textSpec
                    spec.text = trimmed
                    layers[i].content = .text(spec)
                }
            }
            editingTextID = nil
        }
        textFocused = false
        scheduleBake()
    }

    private func startTextStory() {
        withAnimation(spring) {
            clearMedia()
            gradientBG = StoryGradientBG.catalog.randomElement() ?? StoryGradientBG.catalog[0]
            showsCamera = false
            tool = .filters
        }
        HapticEngine.shared.play(.selection)
        beginText()
    }

    // MARK: Tool chrome

    @ViewBuilder
    private func toolChrome(_ tool: Tool) -> some View {
        VStack(spacing: 10) {
            switch tool {
            case .draw: drawChrome
            case .music: musicChrome
            case .filters: filtersChrome
            case .layout: layoutChrome
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.94))
    }

    private var drawChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(StoryBrush.allCases) { item in
                    Button {
                        brush = item
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(brush == item ? Color.black : Color.white)
                            .frame(width: 44, height: 44)
                            .background(brush == item ? Color.white : Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                    .accessibilityLabel(item.title)
                }
                Slider(value: $drawWidth, in: 2...22)
                    .tint(.white)
                Button {
                    if !strokes.isEmpty { strokes.removeLast(); scheduleBake() }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                .disabled(strokes.isEmpty)
                .opacity(strokes.isEmpty ? 0.4 : 1)
                .accessibilityLabel("Undo stroke")
            }
            .padding(.horizontal, 16)
            if brush != .eraser {
                colourRow(selection: drawColorHex) { drawColorHex = $0 }
            }
        }
    }

    private var musicChrome: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StoryMusicCatalog.tracks, id: \.title) { track in
                    Button {
                        addLayer(.music(title: track.title, artist: track.artist), y: 0.78)
                        app.navigation.flash("Music playback in stories is coming soon — sticker added", symbol: "music.note")
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.caption.weight(.bold)).lineLimit(1)
                                Text(track.artist).font(.caption2).opacity(0.75).lineLimit(1)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: 160, alignment: .leading)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var filtersChrome: some View {
        if sourceImage != nil && collageLayout == nil {
            if filter.id != "none" {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.white.opacity(0.8))
                    Slider(value: $filterIntensity, in: 0...1)
                        .tint(.white)
                        .accessibilityLabel("Filter intensity")
                    Text("\(Int(filterIntensity * 100))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
            }
            PhotoFilterDial(selection: $filter, accent: accent, reduceMotion: reduceMotion)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StoryFilter.catalog.filter { !PhotoFilterDialLook.ids.contains($0.id) }) { item in
                        Button {
                            filter = item
                            HapticEngine.shared.play(.selection)
                        } label: {
                            VStack(spacing: 6) {
                                Group {
                                    if let thumb = filterThumbs[item.id] {
                                        Image(uiImage: thumb).resizable().scaledToFill()
                                    } else {
                                        Color.white.opacity(0.2)
                                    }
                                }
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())
                                .overlay {
                                    Circle().strokeBorder(filter.id == item.id ? Color.white : Color.white.opacity(0.25), lineWidth: filter.id == item.id ? 2.5 : 1)
                                }
                                .scaleEffect(filter.id == item.id ? 1.06 : 1)
                                Text(item.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(filter.id == item.id ? Color.white : Color.white.opacity(0.7))
                            }
                            .animation(.snappy(duration: 0.18), value: filter)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(filter.id == item.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StoryGradientBG.catalog) { item in
                        Button {
                            withAnimation(spring) {
                                gradientBG = item
                                collageLayout = nil
                            }
                            scheduleBake()
                            HapticEngine.shared.play(.selection)
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 54, height: 54)
                                    .overlay {
                                        Circle().strokeBorder(gradientBG?.id == item.id ? Color.white : Color.white.opacity(0.25), lineWidth: gradientBG?.id == item.id ? 2.5 : 1)
                                    }
                                Text(item.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(gradientBG?.id == item.id ? Color.white : Color.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title) background")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var layoutChrome: some View {
        HStack(spacing: 10) {
            ForEach(StoryCollageLayout.allCases) { item in
                Button {
                    withAnimation(spring) {
                        collageLayout = item
                        gradientBG = nil
                        if collageImages.count > item.slots { collageImages = Array(collageImages.prefix(item.slots)) }
                    }
                    scheduleBake()
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(collageLayout == item ? Color.black : Color.white)
                        .frame(width: 44, height: 44)
                        .background(collageLayout == item ? Color.white : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                .accessibilityLabel(item.title)
            }
            Spacer(minLength: 0)
            PhotosPicker(selection: $collagePickerItems, maxSelectionCount: (collageLayout ?? .grid).slots, matching: .images) {
                Label("Photos", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story.create.layout.photos")
        }
        .padding(.horizontal, 16)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ item: StorySheet) -> some View {
        switch item {
        case .stickers: stickerSheet
        case .location:
            formSheet(item, fields: { glassField("Where are you?", text: $formA) }) {
                addLayer(.location(formA))
            }
        case .mention:
            formSheet(item, fields: { glassField("@username", text: $formA) }) {
                addLayer(.mention(formA))
            }
        case .link:
            formSheet(item, fields: { glassField("https://", text: $formA) }) {
                addLayer(.link(formA.trimmingCharacters(in: .whitespaces)))
            }
        case .poll:
            formSheet(item, fields: {
                glassField("Ask a question…", text: $formA)
                glassField("Option 1 (Yes)", text: $formB)
                glassField("Option 2 (No)", text: $formC)
            }) {
                addLayer(.poll(question: formA, a: formB.isEmpty ? "Yes" : formB, b: formC.isEmpty ? "No" : formC))
            }
        case .question:
            formSheet(item, fields: { glassField("Ask me a question", text: $formA) }) {
                addLayer(.question(formA.isEmpty ? "Ask me a question" : formA))
            }
        case .slider:
            formSheet(item, fields: {
                glassField("Ask something…", text: $formA)
                glassField("Emoji (😍)", text: $formB)
            }) {
                addLayer(.slider(prompt: formA, emoji: formB.isEmpty ? "😍" : String(formB.prefix(2))))
            }
        case .quiz:
            formSheet(item, fields: {
                glassField("Quiz question", text: $formA)
                glassField("Answer A (correct)", text: $formB)
                glassField("Answer B", text: $formC)
            }) {
                addLayer(.quiz(question: formA, options: [formB.isEmpty ? "Yes" : formB, formC.isEmpty ? "No" : formC]))
            }
        case .addYours:
            formSheet(item, fields: { glassField("Prompt, e.g. Show your desk setup", text: $formA) }) {
                addLayer(.addYours(formA))
            }
        case .reply:
            formSheet(item, fields: { glassField("Reply to my story", text: $formA) }) {
                addLayer(.reply(formA))
            }
        case .countdown:
            formSheet(item, fields: {
                glassField("Countdown name", text: $formA)
                DatePicker("Ends", selection: $formDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .padding(.horizontal, 4)
            }) {
                addLayer(.countdown(title: formA.isEmpty ? "Countdown" : formA, date: formDate))
            }
        }
    }

    private func glassField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .modulaGlass(in: Capsule(), interactive: true)
    }

    private func formSheet<Fields: View>(_ item: StorySheet, @ViewBuilder fields: () -> Fields, onAdd: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title).font(.headline)
            fields()
            Button {
                onAdd()
                sheet = nil
                noticeInteractive()
            } label: {
                Text("Add to story").font(.headline).frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.plain)
            .modulaAccentCTA()
            .disabled(![.question, .countdown, .poll, .slider, .quiz, .addYours, .reply].contains(item) && formA.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
        .onAppear {
            formA = ""; formB = ""; formC = ""
        }
    }

    private var stickerSheet: some View {
        VStack(spacing: 10) {
            // Interactive stickers: compact, scrollable tile row with icon previews.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    interactiveChip("Location", symbol: "mappin.and.ellipse") { sheet = .location }
                    interactiveChip("Mention", symbol: "at") { sheet = .mention }
                    interactiveChip("Link", symbol: "link") { sheet = .link }
                    interactiveChip("Poll", symbol: "chart.bar.xaxis") { sheet = .poll }
                    interactiveChip("Question", symbol: "questionmark.bubble") { sheet = .question }
                    interactiveChip("Countdown", symbol: "timer") { sheet = .countdown }
                    interactiveChip("Slider", symbol: "slider.horizontal.below.rectangle") { sheet = .slider }
                    interactiveChip("Quiz", symbol: "checklist") { sheet = .quiz }
                    interactiveChip("Add Yours", symbol: "camera.on.rectangle") { sheet = .addYours }
                    interactiveChip("Reply", symbol: "arrowshape.turn.up.left") { sheet = .reply }
                    interactiveChip("Time", symbol: "clock") {
                        addLayer(.time(Date()), y: 0.3)
                        sheet = nil
                    }
                    PhotosPicker(selection: $cutoutItems, maxSelectionCount: 1, matching: .images) {
                        StickerToolTile(title: "Cutout", symbol: "person.crop.rectangle.badge.plus", accent: accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sticker from photo")
                    interactiveChip("Music", symbol: "music.note") {
                        sheet = nil
                        withAnimation(spring) { tool = .music }
                    }
                
                }
                .padding(.vertical, 2)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .modulaHorizontalEdgeFade()
            .padding(.top, 14)

            // Shared emoji / Faces / Stickers / GIF panel (same as comments + composer).
            ModulaComposerMediaPanel(
                client: app.client,
                initialTab: .stickers,
                contentHeight: 420,
                onEmoji: { emoji in
                    addLayer(.emoji(emoji)); sheet = nil
                },
                onGif: { gif in
                    sheet = nil
                    Task { await addGif(gif) }
                },
                onSticker: { sticker in
                    addLayer(Self.storyContent(for: sticker)); sheet = nil
                }
            )
        }
    }

    /// Local sticker tokens become real mascot / animated layers instead of a
    /// placeholder 🐾 emoji (the "greyed paw").
    private static func storyContent(for sticker: ModulaSticker) -> StoryLayer.Content {
        if let local = ModulaLocalSticker.extract(sticker.id).stickers.first {
            switch local.kind {
            case .mascot: return .mascot(local.value)
            case .anim: return .animated(local.value)
            case .emoji: return .emoji(local.value)
            case .sprout: return .sprout(local.value)
            }
        }
        return .emoji(sticker.emoji)
    }

    private func interactiveChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.selection)
        } label: {
            StickerToolTile(title: title, symbol: symbol, accent: accent)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
        .accessibilityLabel(title)
    }

    private var gifSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search GIFs", text: $gifQuery)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .modulaGlass(in: Capsule(), interactive: true)
                .onSubmit { Task { await loadGifs() } }
            if let gifStatus {
                Text(gifStatus).font(.footnote).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(gifs) { gif in
                    Button {
                        Task { await addGif(gif) }
                        sheet = nil
                    } label: {
                        AsyncImage(url: gif.previewURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                ModulaShimmerBlock()
                            }
                        }
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                    .accessibilityLabel(gif.title ?? "GIF")
                }
            }
        }
        .task { if gifs.isEmpty { await loadGifs() } }
    }

    private func loadGifs() async {
        let repo = GreenfieldGifRepository(client: app.client)
        do {
            let query = gifQuery.trimmingCharacters(in: .whitespaces)
            let result = query.isEmpty ? try await repo.trending() : try await repo.search(query)
            gifs = result.items
            gifStatus = result.items.isEmpty ? "No GIFs found." : nil
        } catch ModulaGifError.notConfigured {
            gifStatus = "GIF stickers are coming soon."
        } catch {
            gifStatus = "Couldn’t load GIFs."
        }
    }

    private func addGif(_ gif: ModulaGif) async {
        let id = UUID().uuidString
        withAnimation(spring) {
            layers.append(StoryLayer(id: id, content: .gif(gif.url), x: 0.5, y: 0.45))
        }
        HapticEngine.shared.play(.selection)
        let data: Data?
        if let d = try? await app.client.mediaData(from: gif.url, maximumBytes: 12_000_000) {
            data = d
        } else {
            data = try? await URLSession.shared.data(from: gif.url).0
        }
        guard let data else {
            layers.removeAll { $0.id == id }
            toast = "Couldn’t load that GIF."
            return
        }
        let image = await Task.detached(priority: .userInitiated) { StoryGIFDecoder.animatedImage(from: data) }.value
        if let image {
            gifImages[id] = image
            scheduleBake()
        } else {
            layers.removeAll { $0.id == id }
        }
    }

    private func loadCutout(_ items: [PhotosPickerItem]) async {
        guard let item = items.first else { return }
        cutoutItems = []
        sheet = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            toast = "Couldn’t open that photo."
            return
        }
        let id = UUID().uuidString
        withAnimation(spring) {
            layers.append(StoryLayer(id: id, content: .cutout, x: 0.5, y: 0.5))
        }
        if let lifted = await StorySubjectLifter.lift(image) {
            gifImages[id] = lifted
            HapticEngine.shared.play(.success)
            scheduleBake()
        } else {
            layers.removeAll { $0.id == id }
            toast = "Couldn’t find a subject in that photo."
            HapticEngine.shared.play(.failure)
        }
    }

    private func addLayer(_ content: StoryLayer.Content, y: CGFloat = 0.42) {
        let jitter = CGFloat.random(in: -0.04...0.04)
        withAnimation(spring) {
            layers.append(StoryLayer(id: UUID().uuidString, content: content, x: 0.5 + jitter, y: y + jitter, rotation: content.isInteractive ? 0 : Double.random(in: -8...8)))
        }
        HapticEngine.shared.play(.selection)
        scheduleBake()
    }

    private func noticeInteractive() {
        guard !interactiveNoticeShown else { return }
        interactiveNoticeShown = true
        app.navigation.flash("Live polls, questions, mentions and countdowns are coming soon — they post as part of the image", symbol: "sparkles")
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if hasMedia && !showsCamera {
                HStack(spacing: 10) {
                    TextField("Add a story…", text: $caption, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .modulaGlass(in: Capsule(), interactive: true)
                        .disabled(busy)

                    Menu {
                        Button { visibility = "public" } label: { Label("Everyone", systemImage: "globe") }
                        Button { visibility = "followers" } label: { Label("Followers", systemImage: "person.2") }
                        if app.stories.capabilities.privacy {
                            Button { visibility = "close_friends" } label: { Label("Close Friends", systemImage: "star.circle.fill") }
                        }
                    } label: {
                        Label(audienceTitle, systemImage: audienceSymbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .modulaGlass(in: Capsule(), interactive: true, tint: visibility == "close_friends" ? Color.green : nil)
                    }
                    .disabled(busy)
                    .accessibilityLabel("Audience")
                }
            }

            HStack(spacing: 12) {
                if !showsCamera {
                    Button {
                        withAnimation(spring) { showsCamera = true }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .modulaGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                    .accessibilityLabel("Open camera")

                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 1, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            // PhotosPicker's label is nonisolated; modulaGlass is main-actor, so use material here.
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo library")
                }

                Spacer(minLength: 0)

                // Hidden while the camera is up so it never collides with the mode picker
                // (e.g. "Boomerang"); it appears once there is something to share.
                if !showsCamera {
                Button {
                    Task { await publish() }
                } label: {
                    Group {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Label("Share", systemImage: "arrow.up.circle.fill")
                                .font(.headline)
                        }
                    }
                    .frame(minWidth: 120)
                    .frame(height: 48)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                .modulaAccentCTA()
                .disabled(!canShare || busy || showsCamera)
                .opacity(!canShare || showsCamera ? 0.45 : 1)
                .accessibilityIdentifier("story.create.share")
                .transition(.opacity.combined(with: .scale(0.9)))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var audienceTitle: String {
        switch visibility {
        case "followers": "Followers"
        case "close_friends": "Close Friends"
        default: "Everyone"
        }
    }

    private var audienceSymbol: String {
        switch visibility {
        case "followers": "person.2"
        case "close_friends": "star.circle.fill"
        default: "globe"
        }
    }

    // MARK: Media + baking

    private func clearMedia() {
        bakeTask?.cancel()
        sourceImage = nil
        filteredPreview = nil
        filterThumbs = [:]
        prepared = nil
        draftMedia = nil
        videoURL = nil
        gradientBG = nil
        collageLayout = nil
        collageImages = []
        layers = []
        gifImages = [:]
        strokes = []
        history = []
        future = []
        committed = StoryEditSnapshot()
        filterIntensity = 1
        activeStroke = nil
        editingTextID = nil
        tool = nil
        filter = StoryFilter.catalog[0]
        bgScale = 1
        bgOffset = .zero
        captions = []
        videoTime = 0
    }

    private func refilter() {
        guard let sourceImage else { return }
        filteredPreview = StoryFilterEngine.apply(filter, to: sourceImage, intensity: filterIntensity)
        scheduleBake(delay: 0)
    }

    /// Downsamples off the main thread so filters and baking stay instant.
    private func downsampled(_ image: UIImage, maxPixel: CGFloat = 2160) async -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxPixel else { return image }
        let ratio = maxPixel / longest
        let target = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        return await image.byPreparingThumbnail(ofSize: target) ?? image
    }

    private func accept(image: UIImage) async {
        let base = await downsampled(image)
        sourceImage = base
        videoURL = nil
        gradientBG = nil
        collageLayout = nil
        collageImages = []
        filteredPreview = StoryFilterEngine.apply(filter, to: base, intensity: filterIntensity)
        withAnimation(spring) { showsCamera = false }
        HapticEngine.shared.play(.success)
        scheduleBake(delay: 0)
        if let thumb = await base.byPreparingThumbnail(ofSize: CGSize(width: 140, height: 140)) {
            var thumbs: [String: UIImage] = [:]
            for item in StoryFilter.catalog { thumbs[item.id] = StoryFilterEngine.apply(item, to: thumb) }
            filterThumbs = thumbs
        }
    }

    private func loadCollage(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        collagePickerItems = []
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(await downsampled(image, maxPixel: 1440))
            }
        }
        let slots = (collageLayout ?? .grid).slots
        withAnimation(spring) {
            if collageLayout == nil { collageLayout = images.count >= 4 ? .grid : (images.count == 3 ? .threeRows : .twoRows) }
            collageImages = Array((collageImages + images).suffix(slots))
        }
        HapticEngine.shared.play(.success)
        scheduleBake(delay: 0)
    }

    private var currentSnapshot: StoryEditSnapshot { StoryEditSnapshot(layers: layers, strokes: strokes) }

    /// Every finished edit funnels through scheduleBake, so that is where history checkpoints.
    private func commitHistory() {
        if restoringHistory { restoringHistory = false; committed = currentSnapshot; return }
        let now = currentSnapshot
        guard now != committed else { return }
        history.append(committed)
        if history.count > 50 { history.removeFirst() }
        future.removeAll()
        committed = now
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        future.append(currentSnapshot)
        apply(previous)
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        history.append(currentSnapshot)
        apply(next)
    }

    private func apply(_ snapshot: StoryEditSnapshot) {
        restoringHistory = true
        withAnimation(spring) {
            layers = snapshot.layers
            strokes = snapshot.strokes
        }
        HapticEngine.shared.play(.selection)
        scheduleBake()
    }

    private func moveLayer(_ id: String, _ move: StoryLayerMove) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(spring) {
            let layer = layers.remove(at: i)
            let target: Int
            switch move {
            case .front: target = layers.count
            case .forward: target = min(i + 1, layers.count)
            case .backward: target = max(i - 1, 0)
            case .back: target = 0
            }
            layers.insert(layer, at: target)
        }
        HapticEngine.shared.play(.selection)
        scheduleBake()
    }

    private func scheduleBake(delay: Double = 0.35) {
        commitHistory()
        bakeTask?.cancel()
        bakeTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await bakePrepared()
        }
    }

    private func renderComposite() -> UIImage? {
        guard videoURL == nil else { return nil }
        let base = filteredPreview ?? sourceImage
        guard base != nil || gradientBG != nil || (collageLayout != nil && !collageImages.isEmpty) else { return nil }
        let size = CGSize(width: max(canvasSize.width, 1), height: max(canvasSize.height, 1))
        let view = StoryBakeView(
            size: size,
            image: base,
            gradient: gradientBG,
            collage: collageLayout,
            collageImages: collageImages,
            strokes: strokes,
            layers: layers,
            gifs: gifImages,
            accent: accent,
            imageScale: bgScale,
            imageOffset: bgOffset
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1080 / size.width
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func bakePrepared() async {
        guard let composited = renderComposite(),
              let data = composited.jpegData(compressionQuality: 0.92) else { return }
        do {
            let image = try await MediaPreparation.jpegStrippingMetadata(
                data, maxPixel: StoryUploadBudget.targetLongEdge, quality: StoryUploadBudget.preferredQuality
            )
            guard !Task.isCancelled else { return }
            prepared = image
            if let accountID = app.auth.account?.accountId {
                draftMedia = try app.draftMedia.importJPEG(image.data, accountID: accountID, width: image.width, height: image.height)
            }
            saveDraft()
        } catch {
            app.stories.setActionError("Couldn’t prepare that photo.")
        }
    }

    private func makeCaptions() async {
        guard let videoURL, !captioning else { return }
        captioning = true
        defer { captioning = false }
        switch await StoryCaptioner.transcribe(videoURL) {
        case .success(let lines) where !lines.isEmpty:
            withAnimation(spring) { captions = lines }
            HapticEngine.shared.play(.success)
        case .success:
            toast = StoryCaptionError.noSpeech.message
        case .failure(let error):
            toast = error.message
            HapticEngine.shared.play(.failure)
        }
    }

    private func renderOverlay<V: View>(_ view: V, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1080 / max(size.width, 1)
        renderer.isOpaque = false
        return renderer.cgImage
    }

    private func overlayView(_ subset: [StoryLayer], strokes: [StoryDrawStroke], size: CGSize) -> some View {
        ZStack {
            StoryDrawingCanvas(strokes: strokes)
            ForEach(subset) { layer in
                StoryLayerView(layer: layer, gif: gifImages[layer.id], isBaking: true, accent: accent)
                    .scaleEffect(layer.scale)
                    .rotationEffect(.degrees(layer.rotation))
                    .position(x: layer.x * size.width, y: layer.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Burns layers, drawings, animated text and captions into the video (on device).
    private func exportVideo() async -> URL? {
        guard let videoURL else { return nil }
        let size = canvasSize
        func animation(_ layer: StoryLayer) -> StoryTextAnimation {
            if case .text(let spec) = layer.content { return spec.animation }
            return .none
        }
        let still = layers.filter { animation($0) == .none }
        let moving = layers.filter { animation($0) != .none }
        let staticImage = (still.isEmpty && strokes.isEmpty) ? nil : renderOverlay(overlayView(still, strokes: strokes, size: size), size: size)
        let animated: [StoryAnimatedOverlay] = moving.compactMap { layer in
            renderOverlay(overlayView([layer], strokes: [], size: size), size: size).map {
                StoryAnimatedOverlay(image: $0, animation: animation(layer), center: CGPoint(x: layer.x * size.width, y: layer.y * size.height))
            }
        }
        let captionImages: [StoryCaptionOverlay] = captions.compactMap { line in
            renderOverlay(StoryCaptionPill(text: line.text).position(x: size.width / 2, y: size.height * 0.8), size: size).map {
                StoryCaptionOverlay(image: $0, start: line.start, end: line.end)
            }
        }
        exporting = true
        defer { exporting = false }
        if staticImage == nil, animated.isEmpty, captionImages.isEmpty { return videoURL }
        return try? await StoryVideoExporter.export(video: videoURL, canvas: size, staticOverlay: staticImage, animated: animated, captions: captionImages, captionCenterY: 0.8)
    }

    private func saveToPhotos() async {
        if videoURL != nil {
            guard let url = await exportVideo() else {
                app.navigation.flash("Couldn’t export that video", symbol: "exclamationmark.triangle")
                HapticEngine.shared.play(.failure)
                return
            }
            let saved = await StoryVideoExporter.saveToPhotos(url)
            app.navigation.flash(saved ? "Video saved to Photos" : "Couldn’t save to Photos", symbol: saved ? "photo.badge.checkmark" : "exclamationmark.triangle")
            HapticEngine.shared.play(saved ? .saveComplete : .failure)
            return
        }
        bakeTask?.cancel()
        await bakePrepared()
        guard let prepared else {
            app.navigation.flash("Nothing to save yet", symbol: "exclamationmark.triangle")
            return
        }
        let saved = await ModulaPhotoLibrarySaver.save(prepared.data)
        app.navigation.flash(saved ? "Saved to Photos" : "Couldn’t save to Photos", symbol: saved ? "photo.badge.checkmark" : "exclamationmark.triangle")
        HapticEngine.shared.play(saved ? .saveComplete : .failure)
    }

    private func loadPicker(_ items: [PhotosPickerItem]) async {
        guard let item = items.first else { return }
        pickerItems = []
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await accept(image: image)
            return
        }
        if !canPublishVideo {
            app.navigation.flash("Video stories are coming soon — pick a photo", symbol: "video.slash")
            return
        }
        app.stories.setActionError("Couldn’t open that item. Try a photo.")
    }

    private func publish() async {
        if videoURL != nil, !canPublishVideo {
            toast = "Video stories aren’t available yet — share a photo instead."
            HapticEngine.shared.play(.failure)
            return
        }
        busy = true
        defer { busy = false }
        bakeTask?.cancel()
        await bakePrepared()
        guard let prepared else { return }
        let audience = visibility == "close_friends" && !app.stories.capabilities.privacy ? "followers" : visibility
        if await app.stories.publish(image: prepared, caption: caption, visibility: audience) {
            published = true
            ModulaMascotEvent.post(.published)
            CelebrationCenter.shared.reach(.firstStory)
            app.drafts.discardStory(id: draftID)
            app.navigation.close()
            HapticEngine.shared.play(.success)
            if ModulaPreferences.offerToSaveStories {
                let data = prepared.data
                let navigation = app.navigation
                Task {
                    let saved = await ModulaPhotoLibrarySaver.save(data)
                    navigation.flash(saved ? "Story saved to Photos" : "Couldn’t save to Photos", symbol: saved ? "photo.badge.checkmark" : "exclamationmark.triangle")
                }
            }
        }
    }

    #if DEBUG
    private func injectUITestPhotoIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-story-large-photo"), prepared == nil else { return }
        guard GreenfieldEnvironmentLabel.isIsolatedFixture(host: await app.client.apiOriginHost) else { return }
        let data = await Task.detached(priority: .userInitiated) { StoryUITestPhoto.detailedJPEG() }.value
        guard let data, let image = UIImage(data: data) else { return }
        await accept(image: image)
    }
    #endif

    /// Switch to another saved story draft (current work is saved first).
    private func openDraft(_ id: String) {
        guard id != draftID else { return }
        saveDraft()
        app.drafts.flush()
        clearMedia()
        caption = ""
        restored = false
        app.drafts.pendingResumeID = id
        Task { await restoreDraft() }
    }

    /// Start a fresh story without overwriting the current draft.
    private func startNewDraft() {
        saveDraft()
        app.drafts.flush()
        clearMedia()
        caption = ""
        draftID = "story-\(UUID().uuidString.prefix(8))"
        withAnimation(spring) { showsCamera = true }
    }

    private func saveDraft() {
        guard restored, !published else { return }
        app.drafts.upsertStory(StoryDraft(id: draftID, mediaAssetIDs: draftMedia.map { [$0.id] } ?? [],
            caption: caption, lastEdited: Date(), media: draftMedia, visibility: visibility), debounce: false)
    }

    private func restoreDraft() async {
        guard !restored else { return }
        defer { restored = true }
        if let resume = app.drafts.pendingResumeID, app.drafts.stories.contains(where: { $0.id == resume }) {
            draftID = resume
            app.drafts.pendingResumeID = nil
        }
        guard let saved = app.drafts.stories.first(where: { $0.id == draftID }) else {
            showsCamera = true
            return
        }
        caption = saved.caption
        visibility = ["followers", "close_friends"].contains(saved.visibility ?? "") ? (saved.visibility ?? "public") : "public"
        draftMedia = saved.media
        guard let media = saved.media else {
            showsCamera = true
            return
        }
        do {
            let data = try Data(contentsOf: app.draftMedia.fileURL(media))
            if let image = UIImage(data: data) {
                sourceImage = image
                filteredPreview = image
                showsCamera = false
                let preparedImage = try await MediaPreparation.jpegStrippingMetadata(
                    data, maxPixel: StoryUploadBudget.targetLongEdge, quality: StoryUploadBudget.preferredQuality
                )
                prepared = preparedImage
            }
        } catch {
            app.stories.setActionError("The draft photo couldn’t be restored. Choose it again to continue.")
            showsCamera = true
        }
    }
}

// MARK: - Shared press + shimmer primitives

/// Skeleton placeholder with a soft travelling highlight (static under Reduce Motion).
struct ModulaShimmerBlock: View {
    var cornerRadius: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        let still = ModulaEffectGate.reduceMotion(systemReduceMotion)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay {
                if !still {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .onAppear {
                guard !still else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityHidden(true)
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


/// Compact visual tile for an interactive story sticker (icon preview + label).
private struct StickerToolTile: View {
    let title: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 64)
        .contentShape(Rectangle())
    }
}


struct StoryEditSnapshot: Equatable {
    var layers: [StoryLayer] = []
    var strokes: [StoryDrawStroke] = []
}

enum StoryLayerMove { case front, forward, backward, back }

/// Centre alignment guides shown while a layer is magnetised to them.
private struct StorySnapGuides: View {
    let vertical: Bool
    let horizontal: Bool
    var body: some View {
        ZStack {
            if vertical {
                Rectangle().fill(Color.yellow.opacity(0.9)).frame(width: 1).frame(maxHeight: .infinity)
            }
            if horizontal {
                Rectangle().fill(Color.yellow.opacity(0.9)).frame(height: 1).frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: vertical)
        .animation(.easeOut(duration: 0.12), value: horizontal)
        .accessibilityHidden(true)
    }
}

/// On-device grid of saved story drafts.
private struct StoryDraftsGallery: View {
    let currentID: String
    let onOpen: (String) -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.drafts.stories.isEmpty {
                    ModulaEmptyState(title: "No drafts", message: "Stories you leave unfinished show up here.", symbol: "square.stack")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                            ForEach(app.drafts.stories.sorted { $0.lastEdited > $1.lastEdited }, id: \.id) { draft in
                                Button { onOpen(draft.id) } label: { tile(draft) }
                                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                                    .contextMenu {
                                        Button("Delete draft", systemImage: "trash", role: .destructive) {
                                            app.drafts.discardStory(id: draft.id)
                                        }
                                        .disabled(draft.id == currentID)
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Story drafts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tile(_ draft: StoryDraft) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let media = draft.media,
                   let image = UIImage(contentsOfFile: app.draftMedia.fileURL(media).path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: "#667EEA"), Color(hex: "#764BA2")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "textformat").font(.title2).foregroundStyle(.white.opacity(0.8)))
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(9 / 16, contentMode: .fill)
            .clipped()
            Text(draft.lastEdited, format: .relative(presentation: .named))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(6)
                .shadow(radius: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if draft.id == currentID {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white, lineWidth: 2)
            }
        }
        .accessibilityLabel("Draft, \(draft.preview)")
    }
}
