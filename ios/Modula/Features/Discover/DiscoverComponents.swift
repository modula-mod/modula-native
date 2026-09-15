import SwiftUI

struct DiscoverSearchEntry: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Search people, posts, topics, modules")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search people, posts, topics, modules")
        .accessibilityIdentifier("discover.search-entry")
        .accessibilityHint("Opens Search")
    }
}

struct DiscoverTopicCard: View {
    let topic: DiscoverTopic
    var rank: Int?
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
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

private struct DiscoverTopicArtwork: View {
    let seed: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                Circle()
                    .fill(app.appearance.accent.color.opacity(0.42))
                    .frame(width: proxy.size.width * 0.9)
                    .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.3)
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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
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
                                    .foregroundStyle(app.appearance.accent.color)
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(person.displayName), @\(person.handle)")

            Button(action: onFollow) {
                Text(person.followState.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .foregroundStyle(person.isFollowing ? Color.secondary : Color.white)
                    .background(
                        Capsule().fill(person.isFollowing ? Color.primary.opacity(0.08) : app.appearance.accent.color)
                    )
            }
            .buttonStyle(.plain)
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

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onOpen) {
                VStack(spacing: 8) {
                    ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 56)
                    Text(person.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("@\(person.handle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 118)
            }
            .buttonStyle(.plain)
            Button(action: onFollow) {
                Text(person.followState.title)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(app.appearance.accent.color)
            .disabled(followBusy)
            .accessibilityLabel(person.followState.title)
        }
        .padding(12)
        .frame(width: 142)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("discover.person-card.\(person.routeID)")
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
                    }
                }
            }
        }
    }
}

struct DiscoverPostCard: View {
    let post: DiscoverPost
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                if let author = post.author {
                    HStack(spacing: 10) {
                        ModulaAvatar(initials: author.initials, url: author.avatarURL, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(author.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("@\(author.handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let date = post.createdAt {
                            Text(ActivityRelativeTime.string(from: date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if let text = post.text {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let media = post.media {
                    DiscoverMediaPreview(media: media)
                }
                HStack(spacing: 16) {
                    if let likes = post.likeCount {
                        Label("\(likes)", systemImage: "heart")
                    }
                    if let replies = post.replyCount {
                        Label("\(replies)", systemImage: "bubble.right")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16 * app.appearance.density.spacingScale)
            .background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(post.text ?? "Post")
        .accessibilityIdentifier("discover.post.\(post.id)")
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
                DiscoverPostCard(post: post) { onOpen(post) }
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
