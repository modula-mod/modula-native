import SwiftUI

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
                let lead = topics.first
                let rest = Array(topics.dropFirst().prefix(5))
                VStack(spacing: 10) {
                    if let lead {
                        DiscoverTopicCard(topic: lead, rank: 1) { onOpen(lead) }
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { item in
                            DiscoverTopicCard(topic: item.element, rank: item.offset + 2) { onOpen(item.element) }
                                .frame(minHeight: 100)
                        }
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
