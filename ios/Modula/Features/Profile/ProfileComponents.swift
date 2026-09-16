import SwiftUI

// MARK: - Cover

struct ProfileCover: View {
    let coverURL: URL?
    let coverColour: String?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var coverHeight: CGFloat {
        sizeClass == .regular ? 300 : 240
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                placeholder
                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: coverHeight)
                                .clipped()
                        case .failure:
                            placeholder
                        case .empty:
                            placeholder
                                .overlay(ProgressView().tint(.white.opacity(0.7)))
                        @unknown default:
                            placeholder
                        }
                    }
                }
                LinearGradient(
                    colors: [.clear, canvas.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: coverHeight)
            .clipped()
        }
        .frame(height: coverHeight)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            fillColor
            Circle()
                .fill(app.appearance.accent.color.opacity(0.18))
                .frame(width: 220)
                .offset(x: 90, y: -40)
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 150)
                .offset(x: 90, y: -40)
        }
    }

    private var fillColor: Color {
        if let coverColour, !coverColour.isEmpty {
            return Color(hex: coverColour)
        }
        return canvas
    }

    private var canvas: Color {
        ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
    }
}

// MARK: - Avatar pocket

/// Circular carve under the cover so the avatar sits in a canvas-coloured pocket (Light + OLED).
private struct ProfileAvatarCarve: Shape {
    var avatarCenterX: CGFloat
    var avatarRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let center = CGPoint(x: avatarCenterX, y: rect.maxY)
        path.addEllipse(in: CGRect(
            x: center.x - avatarRadius,
            y: center.y - avatarRadius,
            width: avatarRadius * 2,
            height: avatarRadius * 2
        ))
        return path
    }
}

struct ProfileAvatarPocket: View {
    let profile: ModulaProfile
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var avatarSize: CGFloat {
        sizeClass == .regular ? 120 : 96
    }

    private var ring: CGFloat { 5 }
    private var carveRadius: CGFloat { (avatarSize / 2) + ring + 2 }

    var body: some View {
        let inset = ModulaLayout.contentInset
        ZStack(alignment: .bottomLeading) {
            canvas
                .frame(height: avatarSize * 0.42)
                .mask(
                    ProfileAvatarCarve(avatarCenterX: inset + avatarSize / 2, avatarRadius: carveRadius)
                        .fill(style: FillStyle(eoFill: true))
                )

            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: avatarSize)
                        .overlay(
                            Circle()
                                .strokeBorder(canvas, lineWidth: ring)
                        )
                        .accessibilityLabel("\(profile.displayName) avatar")

                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: avatarSize * 0.22, weight: .semibold))
                            .foregroundStyle(app.appearance.accent.color)
                            .background(Circle().fill(canvas).padding(-3))
                            .offset(x: 2, y: 2)
                            .accessibilityLabel("Verified")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
            .offset(y: avatarSize * 0.38)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, avatarSize * 0.38)
        .accessibilityElement(children: .contain)
    }

    private var canvas: Color {
        ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
    }
}

// MARK: - Identity

struct ProfileIdentityBlock: View {
    let profile: ModulaProfile
    @Environment(AppEnvironment.self) private var app
    @State private var bioExpanded = false

    private var bioIsLong: Bool { profile.bio.count > 160 || profile.bio.contains("\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ModulaText(text: profile.displayName, role: .title)
                    .lineLimit(2)
                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(app.appearance.accent.color)
                        .accessibilityLabel("Verified")
                }
            }

            HStack(spacing: 6) {
                Text("@\(profile.handle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let pronouns = profile.pronouns, !pronouns.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(pronouns)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(bioExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if bioIsLong {
                    Button(bioExpanded ? "Less" : "More") {
                        withAnimation(.easeOut(duration: 0.2)) { bioExpanded.toggle() }
                        HapticEngine.shared.play(.selection)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.appearance.accent.color)
                    .buttonStyle(.plain)
                    .accessibilityLabel(bioExpanded ? "Show less bio" : "Show more bio")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.identity")
    }
}

// MARK: - Actions / counts

struct ProfileActionsRow: View {
    let profile: ModulaProfile
    var selected: ProfileSection?
    var showsModules: Bool = true
    var onPosts: () -> Void
    var onFollowers: () -> Void
    var onFollowing: () -> Void
    var onModules: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            metric(
                value: profile.postCount,
                label: "Posts",
                selected: selected == .posts,
                accessibilityNoun: "posts",
                action: onPosts
            )
            metric(
                value: profile.followerCount,
                label: "Followers",
                selected: selected == .followers,
                accessibilityNoun: "followers",
                action: onFollowers
            )
            metric(
                value: profile.followingCount,
                label: "Following",
                selected: selected == .following,
                accessibilityNoun: "following",
                action: onFollowing
            )
            if showsModules, let onModules {
                metric(
                    value: profile.moduleCount,
                    label: "Modules",
                    selected: selected == .modules,
                    accessibilityNoun: "modules",
                    action: onModules
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.actions")
    }

    private func metric(
        value: Int,
        label: String,
        selected: Bool,
        accessibilityNoun: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(ProfileCountFormatter.compact(value))
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? app.appearance.accent.color : .primary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(selected ? app.appearance.accent.color : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ProfileCountFormatter.accessibility(value, noun: accessibilityNoun))
    }
}

// MARK: - About grid

struct ProfileAboutGrid: View {
    let profile: ModulaProfile
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var app

    private var rows: [(String, String, (() -> Void)?)] {
        var items: [(String, String, (() -> Void)?)] = []
        if let joined = profile.joinedAt {
            items.append(("Joined", Self.joinedFormatter.string(from: joined), nil))
        }
        if let location = profile.location?.label, !location.isEmpty {
            items.append(("Location", location, nil))
        }
        if let website = profile.website, let url = website.url {
            let label = website.domain ?? website.label
            items.append(("Website", label, { Self.openSafely(url, openURL: openURL) }))
        }
        if let visibility = profile.visibility {
            items.append(("Visibility", visibility.displayTitle, nil))
        }
        return items
    }

    var body: some View {
        if !rows.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let action = row.2 {
                            Button(row.1, action: action)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(app.appearance.accent.color)
                                .buttonStyle(.plain)
                                .lineLimit(2)
                        } else {
                            Text(row.1)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.0), \(row.1)")
                }
            }
            .accessibilityIdentifier("profile.about")
        }
    }

    private static let joinedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func openSafely(_ url: URL, openURL: OpenURLAction) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        openURL(url)
    }
}

// MARK: - Skeleton

struct ProfileSkeleton: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.primary.opacity(0.06))
                .frame(height: sizeClass == .regular ? 300 : 240)

            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 96, height: 96)
                .overlay(Circle().stroke(canvas, lineWidth: 5))
                .padding(.leading, ModulaLayout.contentInset)
                .offset(y: -36)
                .padding(.bottom, -36)

            VStack(alignment: .leading, spacing: 10) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(width: 160, height: 22)
                Capsule().fill(Color.primary.opacity(0.07)).frame(width: 110, height: 14)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 48)
                HStack(spacing: 24) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 6) {
                            Capsule().fill(Color.primary.opacity(0.1)).frame(width: 36, height: 16)
                            Capsule().fill(Color.primary.opacity(0.06)).frame(width: 48, height: 10)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 52)
        }
        .redacted(reason: .placeholder)
        .accessibilityIdentifier("profile.loading")
    }

    private var canvas: Color {
        ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
    }
}

// MARK: - People row

struct ProfilePeopleRow: View {
    let person: ModulaProfile
    var followBusy: Bool = false
    var showsFollow: Bool = true
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
                        if !person.bio.isEmpty {
                            Text(person.bio)
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

            if showsFollow {
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
                .accessibilityIdentifier("profile.follow.\(person.routeID)")
            }
        }
        .padding(.vertical, 6 * app.appearance.density.spacingScale)
        .accessibilityIdentifier("profile.person.\(person.routeID)")
    }
}

// MARK: - Module grid

struct ProfileModuleGrid: View {
    let products: [CatalogueProduct]
    var installedIDs: Set<String>
    var onOpen: (String) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(products) { product in
                Button {
                    onOpen(product.moduleId)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        ProductArtwork(product: product, size: 56)
                        Text(product.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(installedIDs.contains(product.id) ? "Installed" : product.status.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.module.\(product.moduleId)")
            }
        }
        .accessibilityIdentifier("profile.modules")
    }
}

// MARK: - Floating glass icon button

struct ProfileGlassIconButton: View {
    let title: String
    let symbol: String
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    private var opaque: Bool {
        app.appearance.contrastTransparency == .reduceTransparency
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaChrome(in: Circle(), opaque: opaque)
        .accessibilityLabel(title)
    }
}

struct ProfileGlassIconMenu<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    @Environment(AppEnvironment.self) private var app

    private var opaque: Bool {
        app.appearance.contrastTransparency == .reduceTransparency
    }

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .modulaChrome(in: Circle(), opaque: opaque)
        .accessibilityLabel(title)
    }
}

// MARK: - Primary CTA

struct ProfilePrimaryCTA: View {
    let title: String
    var prominent: Bool
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(
                    Capsule().fill(prominent ? app.appearance.accent.color : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Section chrome

struct ProfilePreviewHeader: View {
    let title: String
    var showsSeeAll: Bool
    var onSeeAll: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if showsSeeAll {
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
