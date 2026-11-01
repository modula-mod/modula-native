import SwiftUI

struct DiscoverSearchEntry: View {
    var compact: Bool = false
    var action: () -> Void
    /// Nil when the current scope has no filters (Trending, Topics): the menu then only offers Refresh.
    var onCustomise: (() -> Void)?
    var onRefresh: () -> Void
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        HStack(spacing: 8) {
            Button {
                ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "search", key: "entry"), for: .search(.root(nil)))
                action()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    if !compact {
                        Text("Search people, posts, topics")
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, compact ? 0 : 14)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(width: compact ? 38 : nil, height: 38)
                .contentShape(Capsule())
                .modulaGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .modulaHeroSource("search", key: "entry")
            .accessibilityLabel("Search people, posts, topics, modules")
            .accessibilityIdentifier("discover.search-entry")
            .accessibilityHint("Opens Search")

            // Filter + options merged into one glass menu.
            Menu {
                if let onCustomise {
                    Button("Customise", systemImage: "slider.horizontal.3", action: onCustomise)
                        .accessibilityIdentifier("discover.customise")
                }
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .modulaGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Options")
            .accessibilityIdentifier("discover.options")
        }
    }
}

struct DiscoverTopicCard: View {
    let topic: DiscoverTopic
    var rank: Int?
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        Button {
            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "topic", key: topic.id), for: .search(.section(.topics, topic.query)))
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                DiscoverTopicArtwork(seed: topic.id)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    if let rank {
                        Text(String(format: "%02d", rank))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Text(topic.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let count = topic.postCountLabel {
                        Text(count)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(14)
            }
            .frame(width: 168, height: 132 * app.appearance.density.spacingScale)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .modulaHeroSource("topic", key: topic.id)
        }
        .buttonStyle(.modulaPressTilt)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("discover.topic.\(topic.id)")
    }

    private var accessibilityLabel: String {
        var parts = [topic.label]
        if let count = topic.postCountLabel { parts.append(count) }
        if let rank { parts.append("Rank \(rank)") }
        return parts.joined(separator: ", ")
    }
}

struct DiscoverTopicArtwork: View {
    let seed: String
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Stable per-topic hue shift so the grid isn't one colour.
    private var hueShift: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 997 }) / 997.0 * 0.18 - 0.09
    }

    /// Each topic gets its own hue (stable per seed) so trending cards aren't all one colour.
    private var seedHue: Double {
        Double(seed.unicodeScalars.reduce(7) { ($0 &* 131 &+ Int($1.value)) % 7919 }) / 7919.0
    }

    var body: some View {
        let accent = Color(hue: seedHue, saturation: 0.62, brightness: 0.92)
        let drift = !ModulaEffectGate.reduceMotion(systemReduceMotion)
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(hue: seedHue, saturation: 0.7, brightness: 0.28), .black], startPoint: .topTrailing, endPoint: .bottomLeading)
                Circle()
                    .fill(RadialGradient(colors: [accent.modulaAdjusted(hue: hueShift).opacity(0.62), accent.opacity(0.12)], center: .center, startRadius: 4, endRadius: proxy.size.width * 0.5))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 6)
                    .phaseAnimator(drift ? [false, true] : [false]) { view, phase in
                        view.offset(
                            x: proxy.size.width * (phase ? 0.18 : 0.3),
                            y: -proxy.size.height * (phase ? 0.18 : 0.32)
                        )
                    } animation: { _ in .easeInOut(duration: 5.5) }
                Circle()
                    .fill(accent.modulaAdjusted(hue: -hueShift, brightness: 1.15).opacity(0.22))
                    .frame(width: proxy.size.width * 0.5)
                    .blur(radius: 14)
                    .offset(x: -proxy.size.width * 0.3, y: proxy.size.height * 0.34)
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.55)
                    .offset(x: -proxy.size.width * 0.22, y: proxy.size.height * 0.28)
                Text("#")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.08))
                    .offset(x: -20, y: -8)
            }
        }
    }
}

struct DiscoverPersonRow: View {
    let person: DiscoverPerson
    var followBusy: Bool
    var onOpen: () -> Void
    var onFollow: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        HStack(spacing: 12) {
            Button {
                ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "person", key: person.routeID), for: .profile(person.routeID, .overview))
                onOpen()
            } label: {
                HStack(spacing: 12) {
                    ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(person.displayName)
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                            if person.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(app.appearance.liveAccent)
                                    .accessibilityLabel("Verified")
                            }
                        }
                        Text("@\(person.handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let bio = person.bio {
                            Text(bio)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .modulaHeroSource("person", key: person.routeID)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
            .accessibilityLabel("\(person.displayName), @\(person.handle)")

            Button(action: onFollow) {
                DiscoverFollowLabel(person: person, busy: followBusy)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(
                        Capsule().fill(person.isFollowing ? Color.primary.opacity(0.08) : app.appearance.liveAccent)
                    )
            }
            .buttonStyle(.modulaPress)
            .disabled(followBusy)
            .accessibilityLabel(person.followState.title)
            .accessibilityIdentifier("discover.follow.\(person.routeID)")
        }
        .padding(.vertical, 6 * app.appearance.density.spacingScale)
        .accessibilityIdentifier("discover.person.\(person.routeID)")
    }
}

struct DiscoverPersonCard: View {
    let person: DiscoverPerson
    var followBusy: Bool
    var onOpen: () -> Void
    var onFollow: () -> Void
    @Environment(AppEnvironment.self) private var app

    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        let accent = app.appearance.liveAccent
        VStack(spacing: 10) {
            Button {
                ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "person-card", key: person.routeID), for: .profile(person.routeID, .overview))
                onOpen()
            } label: {
                VStack(spacing: 8) {
                    ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 56)
                        .padding(3)
                        .background(
                            Circle().stroke(
                                AngularGradient(colors: [accent, accent.modulaAdjusted(hue: 0.08), accent.opacity(0.3), accent], center: .center),
                                lineWidth: 2
                            )
                        )
                        .shadow(color: accent.opacity(0.35), radius: 8, y: 2)
                    Text(person.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("@\(person.handle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 118)
                .contentShape(Rectangle())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.95))
            Button(action: onFollow) {
                DiscoverFollowLabel(person: person, busy: followBusy)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .disabled(followBusy)
            .accessibilityLabel(person.followState.title)
        }
        .padding(12)
        .frame(width: 142)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
        .modulaHeroSource("person-card", key: person.routeID)
        .modulaCarouselReveal()
        .accessibilityIdentifier("discover.person-card.\(person.routeID)")
    }
}

/// Follow/Following text that cross-fades and pops a glyph when the state flips.
struct DiscoverFollowLabel: View {
    let person: DiscoverPerson
    var busy: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: person.isFollowing ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: person.isFollowing)
            }
            Text(person.followState.title)
                .font(.caption.weight(.semibold))
                .contentTransition(.interpolate)
        }
        .foregroundStyle(person.isFollowing ? Color.secondary : Color.white)
        .animation(.snappy, value: person.isFollowing)
    }
}

struct DiscoverPeopleShelf: View {
    let people: [DiscoverPerson]
    var followBusyID: String?
    var onSeeAll: () -> Void
    var onOpen: (DiscoverPerson) -> Void
    var onFollow: (DiscoverPerson) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("People to discover").font(.title3.bold())
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("discover.people.see-all")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(people) { person in
                        DiscoverPersonCard(
                            person: person,
                            followBusy: followBusyID == person.id,
                            onOpen: { onOpen(person) },
                            onFollow: { onFollow(person) }
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct DiscoverTopicShelf: View {
    let topics: [DiscoverTopic]
    var onOpen: (DiscoverTopic) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending now").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(topics.enumerated()), id: \.element.id) { item in
                        DiscoverTopicCard(topic: item.element, rank: item.offset + 1) { onOpen(item.element) }
                            .modulaCarouselReveal()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct DiscoverMediaPreview: View {
    let media: DiscoverPostMedia

    var body: some View {
        Group {
            if let url = media.url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(media.altText ?? media.title ?? "Image")
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: media.colour ?? "#103B41"))
                    .frame(height: 120)
                    .overlay(alignment: .bottomLeading) {
                        if let title = media.title {
                            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white).padding(12)
                        }
                    }
                    .accessibilityLabel(media.altText ?? media.title ?? "Media")
            }
        }
    }
}

struct DiscoverPostShelf: View {
    let posts: [DiscoverPost]
    var onOpen: (DiscoverPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular today").font(.title3.bold())
            ForEach(posts) { post in
                SharedFeedPostCard(post: post.asSocialPost(), identifierPrefix: "discover")
                    .padding(.horizontal, -ModulaLayout.contentInset)
                    .padding(.horizontal, ModulaLayout.postBleedGutter)
            }
        }
    }
}

struct DiscoverModuleShelf: View {
    let products: [CatalogueProduct]
    var installedIDs: Set<String>
    var onSeeAll: () -> Void
    var onOpen: (CatalogueProduct) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Modules worth exploring").font(.title3.bold())
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("discover.modules.see-all")
            }
            ForEach(products) { product in
                ProductCard(product: product, installed: installedIDs.contains(product.id)) {
                    onOpen(product)
                }
            }
        }
    }
}

struct DiscoverSkeleton: View {
    var kind: Kind
    enum Kind { case topic, person, post, module }

    var body: some View {
        shape.modulaShimmer()
    }

    @ViewBuilder private var shape: some View {
        switch kind {
        case .topic:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 168, height: 132)
        case .person:
            HStack {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(width: 120, height: 12)
                    Capsule().fill(Color.primary.opacity(0.06)).frame(width: 80, height: 10)
                }
                Spacer()
            }
            .frame(minHeight: 44)
        case .post:
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 160)
        case .module:
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 96)
        }
    }
}


enum DiscoverSearchRecents {
    private static let key = "discover.search.recents.v1"
    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var items = load().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(items.prefix(12)), forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

struct DiscoverSearchIdle: View {
    var onPickRecent: (String) -> Void
    var onPickSuggestion: (String) -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var recentsVersion = 0
    private var recents: [String] { _ = recentsVersion; return DiscoverSearchRecents.load() }
    private var suggestions: [String] {
        let topics = app.discover.trending.dashboard?.topics.prefix(6).map(\.label) ?? []
        return topics.isEmpty ? ["Design", "Modules", "Reels", "Creators", "AI", "Stories"] : Array(topics)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !recents.isEmpty {
                HStack {
                    Text("Recent").font(.title3.bold()); Spacer()
                    Button("Clear") {
                        DiscoverSearchRecents.clear()
                        withAnimation(.snappy) { recentsVersion += 1 }
                        HapticEngine.shared.play(.selection)
                    }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(recents, id: \.self) { item in
                    Button { onPickRecent(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                .frame(width: 28, height: 28).modulaGlass(in: Circle(), interactive: false)
                            Text(item).font(.body).foregroundStyle(.primary); Spacer()
                            Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(ModulaPressStyle(scale: 0.98, haptic: .selection))
                }
            }
            Text("Suggested").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { item in
                        Button { onPickSuggestion(item); HapticEngine.shared.play(.selection) } label: {
                            Text(item).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.liveAccent.opacity(0.12))
                        }.buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                    }
                }
            }.scrollClipDisabled()
            ContentUnavailableView {
                Label("Search Modula", systemImage: "magnifyingglass")
            } description: { Text("People, posts, modules, and topics — one field.") }
            .frame(minHeight: 120)
        }
        .modulaPageEntrance()
        .accessibilityIdentifier("search.idle")
    }
}
