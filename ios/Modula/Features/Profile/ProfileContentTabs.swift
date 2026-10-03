import SwiftUI

// MARK: - Profile content tabs (Posts / Modules / Links)

enum ProfileContentTab: String, CaseIterable, Identifiable, Hashable {
    case posts, modules, links
    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: "Posts"
        case .modules: "Modules"
        case .links: "Links"
        }
    }

    var symbol: String {
        switch self {
        case .posts: "square.grid.2x2"
        case .modules: "shippingbox"
        case .links: "link"
        }
    }
}

enum ProfilePostLayout: String, CaseIterable, Identifiable, Hashable {
    case grid, list
    var id: String { rawValue }
    var symbol: String { self == .grid ? "square.grid.3x3" : "list.bullet.below.rectangle" }
    var title: String { self == .grid ? "Grid" : "List" }
}

/// Grid / list switch for the posts tab.
struct ProfilePostLayoutToggle: View {
    @Binding var layout: ProfilePostLayout
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Namespace private var pill

    var body: some View {
        let reduce = ModulaEffectGate.reduceMotion(systemReduceMotion)
        HStack(spacing: 2) {
            ForEach(ProfilePostLayout.allCases) { option in
                let selected = option == layout
                Button {
                    withAnimation(reduce ? nil : .spring(response: 0.32, dampingFraction: 0.8)) { layout = option }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: option.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selected ? tint : .secondary)
                        .symbolEffect(.bounce, value: selected && !reduce)
                        .frame(width: 38, height: 30)
                        .background {
                            if selected {
                                Capsule().fill(tint.opacity(0.16))
                                    .matchedGeometryEffect(id: "layout.pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post layout")
        .accessibilityIdentifier("profile.posts.layout")
    }
}

/// Three-column grid of real posts: media thumbnails, or tinted text cards.
struct ProfilePostGrid: View {
    let posts: [SocialPost]
    var tint: Color
    var onOpen: (SocialPost) -> Void
    var onReachEnd: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
            ForEach(posts) { post in
                Button { onOpen(post) } label: {
                    ProfilePostTile(post: post, tint: tint)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.95))
                .modulaScrollReveal()
                .onAppear {
                    if post.id == posts.last?.id { onReachEnd?() }
                }
                .accessibilityIdentifier("profile.grid.\(post.id)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ProfilePostTile: View {
    let post: SocialPost
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    private var media: SocialPostMedia? { post.primaryMedia }
    private var mediaURL: URL? { media.flatMap { $0.thumbnailURL ?? $0.previewURL ?? (isVisual($0) ? $0.url : nil) } }
    private var isVideo: Bool { media?.kind.lowercased().contains("video") == true }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let mediaURL {
                    ModulaRemoteImage(url: mediaURL, cacheKey: "tile:\(mediaURL.path)", maximumPixelSize: 420) { phase in
                        switch phase {
                        case .success(let image):
                            Image(uiImage: image).resizable().scaledToFill()
                        case .loading:
                            Rectangle().fill(Color.primary.opacity(0.06)).modulaShimmer()
                        case .failure:
                            textTile
                        }
                    }
                } else {
                    textTile
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if isVideo || post.media.count > 1 {
                    Image(systemName: isVideo ? "play.fill" : "square.on.square")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .padding(7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if post.likeCount > 0 {
                    Label("\(post.likeCount)", systemImage: post.liked ? "heart.fill" : "heart")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.32), in: Capsule())
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var textTile: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [tint.opacity(scheme == .dark ? 0.42 : 0.28), tint.modulaAdjusted(hue: 0.1).opacity(scheme == .dark ? 0.16 : 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 4) {
                if let module = post.module {
                    Label(module.name ?? "Module", systemImage: "shippingbox.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Text(post.text?.isEmpty == false ? post.text! : (post.link?.title ?? "Post"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
            .padding(9)
        }
        .modulaScrollSpecular(strength: 0.7)
    }

    private func isVisual(_ media: SocialPostMedia) -> Bool {
        let kind = media.kind.lowercased()
        return kind.contains("image") || kind.contains("photo") || kind.contains("gif")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if isVideo { parts.append("Video post") } else if media != nil { parts.append("Photo post") } else { parts.append("Post") }
        if let text = post.text, !text.isEmpty { parts.append(text) }
        if post.likeCount > 0 { parts.append("\(post.likeCount) likes") }
        return parts.joined(separator: ", ")
    }
}

/// Shimmering placeholder grid shown while real posts load.
struct ProfilePostGridSkeleton: View {
    var rows: Int = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
            ForEach(0..<(rows * 3), id: \.self) { _ in
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .modulaShimmer()
        .accessibilityLabel("Loading posts")
        .accessibilityIdentifier("profile.posts.loading")
    }
}
