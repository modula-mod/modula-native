import SwiftUI
import AVFoundation

struct DiscoverDashboardView: View {
    let dashboard: DiscoverDashboard
    let previewPosts: [DiscoverPost]
    let featuredProducts: [CatalogueProduct]
    let installedIDs: Set<String>
    var followBusyID: String?
    var onTopic: (DiscoverTopic) -> Void
    var onPerson: (DiscoverPerson) -> Void
    var onFollow: (DiscoverPerson) -> Void
    var onSeePeople: () -> Void
    var onPost: (DiscoverPost) -> Void
    var onModule: (CatalogueProduct) -> Void
    var onSeeModules: () -> Void
    var onReel: ((Reel) -> Void)? = nil

    private var shelfPeople: [DiscoverPerson] {
        Array(dashboard.people.sorted { $0.usefulness > $1.usefulness }.prefix(10))
    }

    private var heroItems: [DiscoverHeroItem] {
        var items: [DiscoverHeroItem] = []
        for t in dashboard.topics.prefix(4) { items.append(.topic(t)) }
        for p in previewPosts.prefix(3) where p.media?.url != nil { items.append(.post(p)) }
        for m in featuredProducts.prefix(2) { items.append(.module(m)) }
        return Array(items.prefix(6))
    }

    /// Mixed media for the mosaic: muted reels (video) interleaved with image posts.
    private var mosaicTiles: [DiscoverMosaicTile] {
        var videos = dashboard.reels.filter { $0.media?.url != nil }.prefix(4).map(DiscoverMosaicTile.reel)
        var images = (previewPosts + dashboard.posts)
            .filter { $0.media?.url != nil }
            .reduce(into: [DiscoverPost]()) { acc, post in if !acc.contains(where: { $0.id == post.id }) { acc.append(post) } }
            .prefix(10)
            .map(DiscoverMosaicTile.post)
        var out: [DiscoverMosaicTile] = []
        while out.count < 12, !(videos.isEmpty && images.isEmpty) {
            // Video lands on the big slot of every other row.
            if out.count % 3 == 0, !videos.isEmpty { out.append(videos.removeFirst()) }
            else if !images.isEmpty { out.append(images.removeFirst()) }
            else { out.append(videos.removeFirst()) }
        }
        return out
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if !heroItems.isEmpty {
                DiscoverHeroCarousel(items: heroItems, onTopic: onTopic, onPost: onPost, onModule: onModule)
                    .modulaPageEntrance()
            }
            if !dashboard.topics.isEmpty {
                DiscoverBentoTopics(topics: Array(dashboard.topics.prefix(6)), onOpen: onTopic)
            }
            if !shelfPeople.isEmpty {
                DiscoverPeopleShelf(people: shelfPeople, followBusyID: followBusyID, onSeeAll: onSeePeople, onOpen: onPerson, onFollow: onFollow)
            }
            if !dashboard.reels.isEmpty, let onReel {
                DiscoverReelsShelf(reels: dashboard.reels, onOpen: onReel)
            }
            if mosaicTiles.count >= 3 {
                DiscoverMosaic(
                    tiles: mosaicTiles,
                    topics: Array(dashboard.topics.prefix(8)),
                    onPost: onPost,
                    onReel: { reel in onReel?(reel) },
                    onTopic: onTopic
                )
            }
            if !featuredProducts.isEmpty {
                DiscoverModuleSpotlight(products: Array(featuredProducts.prefix(4)), installedIDs: installedIDs, onSeeAll: onSeeModules, onOpen: onModule)
            }
            if !previewPosts.isEmpty {
                DiscoverPostShelf(posts: Array(previewPosts.prefix(3)), onOpen: onPost)
            } else if !dashboard.media.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Visuals").font(.title3.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(dashboard.media.prefix(6).enumerated()), id: \.offset) { item in
                                DiscoverMediaPreview(media: item.element).frame(width: 180).modulaCarouselReveal()
                            }
                        }
                    }
                }
            }
        }
    }
}

enum DiscoverHeroItem: Identifiable, Hashable {
    case topic(DiscoverTopic), post(DiscoverPost), module(CatalogueProduct)
    var id: String {
        switch self {
        case .topic(let t): "topic.\(t.id)"
        case .post(let p): "post.\(p.id)"
        case .module(let m): "module.\(m.id)"
        }
    }
}

struct DiscoverHeroCarousel: View {
    let items: [DiscoverHeroItem]
    var onTopic: (DiscoverTopic) -> Void
    var onPost: (DiscoverPost) -> Void
    var onModule: (CatalogueProduct) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today on Modula").font(.title2.bold())
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    heroCard(item).tag(index).padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 210)
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? app.appearance.accent.color : Color.primary.opacity(0.18))
                        .frame(width: i == page ? 18 : 6, height: 6)
                        .animation(ModulaEffectGate.reduceMotion(reduceMotion) ? nil : .snappy, value: page)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }

    private func heroCard(_ item: DiscoverHeroItem) -> some View {
        let accent = app.appearance.accent.color
        return Button {
            switch item {
            case .topic(let t): onTopic(t)
            case .post(let p): onPost(p)
            case .module(let m): onModule(m)
            }
            HapticEngine.shared.play(.navigation)
        } label: {
            ZStack(alignment: .bottomLeading) {
                heroBackdrop(item)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow(item)).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .modulaGlass(in: Capsule(), interactive: false, tint: .white.opacity(0.12))
                    Text(title(item)).font(.title3.bold()).foregroundStyle(.white).lineLimit(2)
                    if let sub = subtitle(item) {
                        Text(sub).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
            .shadow(color: accent.opacity(0.25), radius: 16, y: 8)
        }
        .buttonStyle(.modulaPressTilt)
        .accessibilityLabel(title(item))
    }

    @ViewBuilder private func heroBackdrop(_ item: DiscoverHeroItem) -> some View {
        switch item {
        case .topic(let topic):
            DiscoverTopicArtwork(seed: topic.id)
        case .post(let post):
            if let url = post.media?.url {
                ModulaRemoteImage(url: url, cacheKey: "discover-hero:\(url.absoluteString)", maximumPixelSize: 1200) { phase in
                    switch phase {
                    case .success(let image): Image(uiImage: image).resizable().scaledToFill()
                    default: LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            } else {
                LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .module(let product):
            ProductBackdrop(product: product)
        }
    }

    private func eyebrow(_ item: DiscoverHeroItem) -> String {
        switch item { case .topic: "TRENDING"; case .post: "POPULAR"; case .module: "MODULE" }
    }
    private func title(_ item: DiscoverHeroItem) -> String {
        switch item {
        case .topic(let t): t.label
        case .post(let p): p.text.map { String($0.prefix(80)) } ?? "Post"
        case .module(let m): m.name
        }
    }
    private func subtitle(_ item: DiscoverHeroItem) -> String? {
        switch item {
        case .topic(let t): t.summary ?? t.postCountLabel
        case .post(let p): p.author.map { "@\($0.handle)" }
        case .module(let m): m.description
        }
    }
}

struct DiscoverBentoTopics: View {
    let topics: [DiscoverTopic]
    var onOpen: (DiscoverTopic) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending topics").font(.title3.bold())
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(Array(topics.enumerated()), id: \.element.id) { item in
                        DiscoverTopicCard(topic: item.element, rank: item.offset + 1) { onOpen(item.element) }
                    }
                }
            } else {
                // Even count only, so the 2-column grid never leaves a lone card.
                let shown = Array(topics.prefix(6))
                let grid = shown.count > 1 ? Array(shown.prefix(shown.count - shown.count % 2)) : shown
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(grid.enumerated()), id: \.element.id) { item in
                        DiscoverTopicCard(topic: item.element, rank: item.offset + 1) { onOpen(item.element) }
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
        }
    }
}

struct DiscoverModuleSpotlight: View {
    let products: [CatalogueProduct]
    let installedIDs: Set<String>
    var onSeeAll: () -> Void
    var onOpen: (CatalogueProduct) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Module spotlight").font(.title3.bold())
                Spacer()
                Button("See all", action: onSeeAll).font(.subheadline.weight(.semibold))
            }
            if let lead = products.first { ProductHero(product: lead) { onOpen(lead) } }
            ForEach(products.dropFirst()) { product in
                ProductCard(product: product, installed: installedIDs.contains(product.id)) { onOpen(product) }
            }
        }
    }
}


// MARK: - Mosaic

enum DiscoverMosaicTile: Identifiable, Hashable {
    case post(DiscoverPost)
    case reel(Reel)

    var id: String {
        switch self {
        case .post(let post): "post.\(post.id)"
        case .reel(let reel): "reel.\(reel.id)"
        }
    }

    var searchableText: String {
        switch self {
        case .post(let post): [post.text, post.media?.title, post.media?.altText].compactMap { $0 }.joined(separator: " ").lowercased()
        case .reel(let reel): (reel.caption ?? "").lowercased()
        }
    }
}

/// Mixed-size grid (one big tile + two small per row, alternating sides, then a row of three).
/// Video tiles autoplay muted only while mostly on screen. Tag chips filter the mosaic in place;
/// the chosen chip morphs into the header of the filtered feed.
struct DiscoverMosaic: View {
    let tiles: [DiscoverMosaicTile]
    let topics: [DiscoverTopic]
    var onPost: (DiscoverPost) -> Void
    var onReel: (Reel) -> Void
    var onTopic: (DiscoverTopic) -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selected: DiscoverTopic?
    @Namespace private var tagSpace
    private let gap: CGFloat = 6
    private let unit: CGFloat = 118

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }

    private var visible: [DiscoverMosaicTile] {
        guard let selected else { return tiles }
        let key = selected.label.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return tiles.filter { $0.searchableText.contains(key) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !topics.isEmpty, selected == nil { tagRow }
            let items = visible
            if items.isEmpty, let selected {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing in the mosaic for #\(selected.label) yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        onTopic(selected)
                    } label: {
                        Label("Open #\(selected.label) feed", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.accent.color.opacity(0.2))
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: .navigation))
                }
                .transition(.opacity)
            } else {
                grid(items)
            }
        }
        .animation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.82), value: selected)
        .accessibilityIdentifier("discover.mosaic")
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            if let selected {
                Button {
                    self.selected = nil
                    HapticEngine.shared.play(.selection)
                } label: {
                    HStack(spacing: 6) {
                        Text("#\(selected.label)").font(.title3.bold())
                        Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.accent.color.opacity(0.22))
                    .matchedGeometryEffect(id: "tag.\(selected.id)", in: tagSpace)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filtered by \(selected.label). Clear filter")
                Spacer()
                Button("See all") { onTopic(selected) }
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Mosaic").font(.title3.bold())
                Spacer()
            }
        }
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics) { topic in
                    Button {
                        selected = topic
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Text("#\(topic.label)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .modulaGlass(in: Capsule(), interactive: true)
                            .matchedGeometryEffect(id: "tag.\(topic.id)", in: tagSpace)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                }
            }
            .padding(.vertical, 2)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func grid(_ items: [DiscoverMosaicTile]) -> some View {
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                mosaicRow(row, style: index % 3)
            }
        }
    }

    @ViewBuilder
    private func mosaicRow(_ row: [DiscoverMosaicTile], style: Int) -> some View {
        if row.count == 3 && style != 2 {
            GeometryReader { geo in
                let big = (geo.size.width - gap) * 2 / 3
                let small = geo.size.width - gap - big
                HStack(spacing: gap) {
                    if style == 1 {
                        smallColumn(Array(row.dropFirst()), width: small)
                    }
                    tile(row[0], size: CGSize(width: big, height: unit * 2 + gap))
                    if style == 0 {
                        smallColumn(Array(row.dropFirst()), width: small)
                    }
                }
            }
            .frame(height: unit * 2 + gap)
        } else {
            GeometryReader { geo in
                let count = CGFloat(max(row.count, 1))
                let w = (geo.size.width - gap * (count - 1)) / count
                HStack(spacing: gap) {
                    ForEach(row) { item in tile(item, size: CGSize(width: w, height: unit * 1.2)) }
                }
            }
            .frame(height: unit * 1.2)
        }
    }

    private func smallColumn(_ items: [DiscoverMosaicTile], width: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(items) { item in tile(item, size: CGSize(width: width, height: unit)) }
        }
    }

    private func tile(_ item: DiscoverMosaicTile, size: CGSize) -> some View {
        Button {
            switch item {
            case .post(let post): onPost(post)
            case .reel(let reel):
                ModulaHeroMorph.disarm()
                onReel(reel)
            }
        } label: {
            DiscoverMosaicTileView(item: item)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.6))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: .navigation))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct DiscoverMosaicTileView: View {
    let item: DiscoverMosaicTile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch item {
            case .post(let post):
                Rectangle().fill(Color(hex: post.media?.colour ?? "#1F2933"))
                if let url = post.media?.url {
                    ModulaRemoteImage(url: url, cacheKey: "mosaic:\(post.id)", maximumPixelSize: 600) { phase in
                        if case .success(let image) = phase {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                }
            case .reel(let reel):
                Rectangle().fill(Color(hex: reel.posterColor ?? "#222222"))
                if let poster = reel.media?.posterURL {
                    ModulaRemoteImage(url: poster, cacheKey: "reel-poster:\(reel.id)", maximumPixelSize: 600) { phase in
                        if case .success(let image) = phase {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                }
                if let url = reel.media?.url, onScreen,
                   ModulaPreferences.allowsVideoAutoplay(systemReduceMotion: reduceMotion) {
                    MosaicLoopingVideo(url: url)
                        .transition(.opacity)
                }
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .contentShape(Rectangle())
        .onScrollVisibilityChange(threshold: 0.7) { visible in
            withAnimation(.easeOut(duration: 0.25)) { onScreen = visible }
        }
        .accessibilityLabel(label)
    }

    private var label: String {
        switch item {
        case .post(let post): post.media?.altText ?? post.text ?? "Post"
        case .reel(let reel): "Reel by \(reel.creator.displayName)"
        }
    }
}

/// Muted, looping, layer-backed player. Created only while its tile is visible and torn
/// down when it scrolls away, so at most the on-screen tiles hold a decoder.
private struct MosaicLoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> MosaicPlayerView {
        let view = MosaicPlayerView()
        view.start(url: url)
        return view
    }

    func updateUIView(_ view: MosaicPlayerView, context: Context) {}

    static func dismantleUIView(_ view: MosaicPlayerView, coordinator: ()) {
        view.stop()
    }
}

private final class MosaicPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?

    func start(url: URL) {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        if let layer = layer as? AVPlayerLayer {
            layer.player = queue
            layer.videoGravity = .resizeAspectFill
        }
        isUserInteractionEnabled = false
        queue.play()
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        (layer as? AVPlayerLayer)?.player = nil
        player = nil
    }
}
