import SwiftUI

// MARK: - Cover

struct ProfileCover: View {
    let coverURL: URL?
    let coverColour: String?
    var scrollProgress: CGFloat = 0
    var onTap: (() -> Void)? = nil
    var contextActions: [ModulaContextAction] = []
    var onContextAction: ((ModulaContextAction) -> Void)? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var coverHeight: CGFloat {
        let base: CGFloat = sizeClass == .regular ? 280 : 250
        if dynamicTypeSize.isAccessibilitySize { return max(220, base - 20) }
        return base
    }

    private var dissolve: CGFloat {
        ModulaScrollProgress.clamp(scrollProgress)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let stretch: CGFloat = {
                guard !reduceMotion, proxy.frame(in: .global).minY > 0 else { return 0 }
                return min(proxy.frame(in: .global).minY * 0.18, 28)
            }()
            ZStack {
                fallbackComposition
                    .opacity(coverURL == nil ? 1 : 0.001)
                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: coverHeight + stretch)
                                .clipped()
                        case .failure:
                            fallbackComposition
                        case .empty:
                            fallbackComposition
                                .overlay(ProgressView().tint(.white.opacity(0.7)))
                        @unknown default:
                            fallbackComposition
                        }
                    }
                }
                LinearGradient(
                    colors: [
                        .clear,
                        canvas.opacity(0.25 + (0.55 * Double(dissolve))),
                        canvas.opacity(0.75 + (0.2 * Double(dissolve)))
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .opacity(0.85 + (0.15 * Double(dissolve)))
            }
            .frame(width: width, height: coverHeight + stretch)
            .offset(y: reduceMotion ? 0 : -CGFloat(dissolve) * 18)
            .opacity(1 - (0.35 * Double(dissolve)))
            .clipped()
        }
        .frame(height: coverHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
            HapticEngine.shared.play(.lightImpact)
        }
        .contextMenu {
            ForEach(contextActions) { action in
                Button(role: action.role == .destructive ? .destructive : nil) {
                    HapticEngine.shared.play(.contextOpen)
                    onContextAction?(action)
                } label: {
                    if let systemImage = action.systemImage {
                        Label(action.title, systemImage: systemImage)
                    } else {
                        Text(action.title)
                    }
                }
                .disabled(action.role == .disabled)
                .accessibilityLabel(action.resolvedAccessibilityLabel)
            }
        }
        .accessibilityHidden(coverURL == nil)
        .accessibilityElement(children: coverURL == nil ? .ignore : .contain)
        .accessibilityLabel("Profile cover photo")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens cover photo")
        .accessibilityIdentifier("profile.cover")
    }

    private var fallbackComposition: some View {
        ZStack {
            LinearGradient(
                colors: [
                    fillColor.opacity(scheme == .dark ? 0.9 : 1),
                    app.appearance.accent.color.opacity(scheme == .dark ? 0.22 : 0.16),
                    canvas
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft Modula geometry — intentional, not empty lavender disks.
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(app.appearance.accent.color.opacity(0.12))
                .frame(width: 220, height: 120)
                .rotationEffect(.degrees(-18))
                .offset(x: 70, y: -28)
            Circle()
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.18), lineWidth: 1)
                .frame(width: 160, height: 160)
                .offset(x: -90, y: 36)
            Capsule()
                .fill(Color.white.opacity(scheme == .dark ? 0.05 : 0.2))
                .frame(width: 90, height: 10)
                .offset(x: -40, y: -50)
        }
    }

    private var fillColor: Color {
        if let coverColour, !coverColour.isEmpty {
            return Color(hex: coverColour)
        }
        return ModulaPalette.resolve(app.appearance, scheme: scheme).surface
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
    var onTap: (() -> Void)? = nil
    var onStoryTap: (() -> Void)? = nil
    var storyRing: StoryRingState? = nil
    var contextActions: [ModulaContextAction] = []
    var onContextAction: ((ModulaContextAction) -> Void)? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var avatarSize: CGFloat {
        sizeClass == .regular ? 112 : 104
    }

    private var ring: CGFloat { 5 }
    private var carveRadius: CGFloat { (avatarSize / 2) + ring + 2 }
    /// How much of the avatar sits above the content surface (intersection geometry).
    private var intersection: CGFloat { avatarSize * 0.42 }

    var body: some View {
        let inset = ModulaLayout.contentInset
        ZStack(alignment: .bottomLeading) {
            canvas
                .frame(height: intersection)
                .mask(
                    ProfileAvatarCarve(avatarCenterX: inset + avatarSize / 2, avatarRadius: carveRadius)
                        .fill(style: FillStyle(eoFill: true))
                )

            avatarBadge
                .padding(.leading, inset)
                // Align avatar center with carve center on the content edge.
                .alignmentGuide(.bottom) { dims in dims.height - intersection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: avatarSize - intersection + intersection)
        .padding(.bottom, avatarSize - intersection)
        .accessibilityElement(children: .contain)
    }

    private var avatarBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                if storyRing != nil, let onStoryTap {
                    onStoryTap()
                } else {
                    onTap?()
                }
                HapticEngine.shared.play(.lightImpact)
            } label: {
                ZStack {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: avatarSize)
                        .overlay(
                            Circle()
                                .strokeBorder(canvas, lineWidth: ring)
                        )
                    if let storyRing {
                        StoryRing(state: storyRing, size: avatarSize, accent: app.appearance.accent.color)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(contextActions) { action in
                    Button(role: action.role == .destructive ? .destructive : nil) {
                        HapticEngine.shared.play(.contextOpen)
                        onContextAction?(action)
                    } label: {
                        if let systemImage = action.systemImage {
                            Label(action.title, systemImage: systemImage)
                        } else {
                            Text(action.title)
                        }
                    }
                    .disabled(action.role == .disabled)
                    .accessibilityLabel(action.resolvedAccessibilityLabel)
                }
            }
            .accessibilityLabel("\(profile.displayName)'s profile photo")
            .accessibilityHint(storyRing == nil ? "Open profile photo" : "Opens story. Use Open profile photo or long press for the image.")
            .accessibilityAction(named: "Open profile photo") { onTap?() }
            .accessibilityAction(named: "Open story") { onStoryTap?() }
            .accessibilityIdentifier("profile.avatar")

            if profile.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: avatarSize * 0.2, weight: .semibold))
                    .foregroundStyle(app.appearance.accent.color)
                    .background(Circle().fill(canvas).padding(-3))
                    .offset(x: 2, y: 2)
                    .accessibilityLabel("Verified account")
            }
        }
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
                        .accessibilityLabel("Verified account")
                }
            }

            if let headline = profile.headline, !headline.isEmpty {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.headline")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    metricRow
                }
            } else {
                metricRow
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(app.appearance.contrastTransparency == .higherContrast ? 0.16 : 0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.metrics")
    }

    private var metricRow: some View {
        HStack(spacing: 0) {
            metric(
                value: profile.postCount,
                label: "Posts",
                selected: selected == .posts,
                accessibilityNoun: "posts",
                action: onPosts
            )
            separator
            metric(
                value: profile.followerCount,
                label: "Followers",
                selected: selected == .followers,
                accessibilityNoun: "followers",
                action: onFollowers
            )
            separator
            metric(
                value: profile.followingCount,
                label: "Following",
                selected: selected == .following,
                accessibilityNoun: "following",
                action: onFollowing
            )
            if showsModules, let onModules {
                separator
                metric(
                    value: profile.moduleCount,
                    label: "Modules",
                    selected: selected == .modules,
                    accessibilityNoun: "featured modules",
                    action: onModules
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }

    private func metric(
        value: Int,
        label: String,
        selected: Bool,
        accessibilityNoun: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            VStack(spacing: 2) {
                Text(ProfileCountFormatter.compact(value))
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? app.appearance.accent.color : .primary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption2.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? app.appearance.accent.color : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(app.appearance.accent.color)
                        .frame(width: 18, height: 3)
                        .offset(y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ProfileCountFormatter.accessibility(value, noun: accessibilityNoun))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Tool actions (Edit / Follow + Share + More)

struct ProfileToolActions: View {
    let isOwn: Bool
    let followTitle: String
    let isFollowing: Bool
    var followBusy: Bool = false
    var messageTitle: String? = nil
    var onPrimary: () -> Void
    var onShare: () -> Void
    var onMessage: (() -> Void)? = nil
    var moreActions: [ModulaContextAction]
    var onMore: (ModulaContextAction) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    if followBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isOwn ? "Edit Profile" : followTitle)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(reduceMotion ? .opacity : .interpolate)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(primaryForeground)
                .background(primaryBackground, in: Capsule())
                .overlay(
                    Capsule().stroke(primaryStroke, lineWidth: isOwn || isFollowing ? 1 : 0)
                )
            }
            .buttonStyle(.plain)
            .disabled(followBusy)
            .accessibilityLabel(isOwn ? "Edit Profile" : followTitle)
            .accessibilityIdentifier(isOwn ? "profile.edit.cta" : "profile.follow.cta")

            if let messageTitle, let onMessage, !isOwn {
                Button(action: onMessage) {
                    Text(messageTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .foregroundStyle(.primary)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(messageTitle)
                .accessibilityIdentifier("profile.message.cta")
            }

            Button(action: onShare) {
                Image(systemName: ModulaIconRegistry.symbol(.share, style: app.appearance.iconStyle))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share Profile")
            .accessibilityIdentifier("profile.share.cta")

            ModulaContextMenu(actions: moreActions, onSelect: onMore) {
                Image(systemName: ModulaIconRegistry.symbol(.more, style: app.appearance.iconStyle))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("profile.more.cta")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.tools")
    }

    private var primaryForeground: Color {
        if isOwn { return .primary }
        return isFollowing ? .primary : .white
    }

    private var primaryBackground: some ShapeStyle {
        if isOwn { return AnyShapeStyle(Color.primary.opacity(0.08)) }
        return AnyShapeStyle(isFollowing ? Color.primary.opacity(0.08) : app.appearance.accent.color)
    }

    private var primaryStroke: Color {
        Color.primary.opacity(0.12)
    }
}

// MARK: - About grid

struct ProfileAboutGrid: View {
    let profile: ModulaProfile
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        if !profile.languages.isEmpty {
            items.append(("Languages", profile.languages.joined(separator: ", "), nil))
        }
        if let visibility = profile.visibility {
            items.append(("Visibility", visibility.displayTitle, nil))
        }
        return items
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        if !rows.isEmpty {
            LazyVGrid(columns: columns, spacing: 14) {
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
    var busy: Bool = false
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? app.appearance.accent.color : Color.primary.opacity(0.08))
            )
            .overlay(
                Capsule().stroke(Color.primary.opacity(prominent ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
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
