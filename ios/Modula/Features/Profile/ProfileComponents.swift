import SwiftUI
import UIKit

// MARK: - Cover

struct ProfileCover: View {
    let coverURL: URL?
    let coverColour: String?
    /// Hero tint (avatar colour / accent) for the aurora shader.
    var tint: Color? = nil
    var scrollProgress: CGFloat = 0
    var safeAreaTop: CGFloat = ProfileFullBleedMetrics.windowSafeAreaTop
    var pocketCenterX: CGFloat? = nil
    var pocketRadius: CGFloat? = nil
    var onTap: (() -> Void)? = nil
    var contextActions: [ModulaContextAction] = []
    var onContextAction: ((ModulaContextAction) -> Void)? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var retryID = 0

    private var coverHeight: CGFloat {
        ProfileFullBleedMetrics.coverHeight(
            sizeClass: sizeClass,
            safeAreaTop: safeAreaTop,
            accessibility: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var dissolve: CGFloat {
        ModulaScrollProgress.clamp(scrollProgress)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let stretch: CGFloat = {
                guard !reduceMotion, proxy.frame(in: .global).minY > 0 else { return 0 }
                return min(proxy.frame(in: .global).minY * 0.22, 36)
            }()
            ZStack(alignment: .bottom) {
                fallbackComposition
                    .opacity(coverURL == nil ? 1 : 0.001)
                if let coverURL {
                    ModulaRemoteImage(
                        url: coverURL,
                        cacheKey: "cover:\(coverURL.path)",
                        maximumPixelSize: max(width, coverHeight) * UIScreen.main.scale,
                        retryID: retryID
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: coverHeight + stretch)
                                .clipped()
                        case .failure:
                            fallbackComposition.overlay(alignment: .topTrailing) {
                                Button("Retry cover", systemImage: "arrow.clockwise") { retryID += 1 }
                                    .labelStyle(.iconOnly)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.38), in: Circle())
                                    .foregroundStyle(.white)
                                    .padding(.top, safeAreaTop + 8)
                                    .padding(.trailing, 12)
                            }
                        case .loading:
                            fallbackComposition
                                .overlay(ProgressView().tint(.white.opacity(0.7)))
                        }
                    }
                }

                // Liquid bottom fade — soft multi-stop dissolve into canvas (mockup cloud seam).
                liquidBottomFade
                    .frame(height: coverHeight * 0.58)
                    .opacity(0.92 + (0.08 * Double(dissolve)))
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: coverHeight + stretch, alignment: .top)
            // Parallax: the hero drifts at ~40% of the scroll speed while the page scrolls up.
            .visualEffect { [reduceMotion] content, proxy in
                let minY = proxy.frame(in: .scrollView).minY
                return content.offset(y: reduceMotion || minY >= 0 ? 0 : -minY * 0.4)
            }
            .offset(y: reduceMotion ? 0 : -CGFloat(dissolve) * 22)
            .opacity(1 - (0.32 * Double(dissolve)))
            .mask {
                if let pocketCenterX, let pocketRadius {
                    AvatarPocketShape(centerX: pocketCenterX, radius: pocketRadius)
                } else {
                    Rectangle()
                }
            }
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

    /// Soft, liquid-feeling seam from photography into the content canvas.
    private var liquidBottomFade: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: canvas.opacity(0.08 + 0.2 * Double(dissolve)), location: 0.28),
                    .init(color: canvas.opacity(0.35 + 0.25 * Double(dissolve)), location: 0.52),
                    .init(color: canvas.opacity(0.72 + 0.18 * Double(dissolve)), location: 0.78),
                    .init(color: canvas.opacity(0.96), location: 0.92),
                    .init(color: canvas, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Secondary soft bloom — reads more “liquid” than a single hard gradient.
            LinearGradient(
                colors: [
                    .clear,
                    canvas.opacity(scheme == .dark ? 0.18 : 0.28),
                    canvas.opacity(scheme == .dark ? 0.45 : 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blur(radius: reduceMotion ? 0 : 18)
            .opacity(0.65)
            .mask(
                LinearGradient(
                    colors: [.clear, .white, .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var fallbackComposition: some View {
        ZStack {
            ModulaAuroraBackground(
                tint: tint ?? fillColor,
                secondary: coverColour.flatMap { $0.isEmpty ? nil : Color(hex: $0) },
                intensity: 1
            )
            legacyGeometry
                .opacity(0.35)
        }
    }

    private var legacyGeometry: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .clear,
                    canvas.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft Modula geometry — intentional, not empty lavender disks.
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(app.appearance.accent.color.opacity(0.14))
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

enum ProfileIdentityMetrics {
    static func avatarSize(sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 112 : 104
    }

    static func carveRadius(avatarSize: CGFloat) -> CGFloat {
        (avatarSize / 2) + 8
    }

    static func overlap(avatarSize: CGFloat) -> CGFloat { avatarSize / 2 }
    static func contentHeight(avatarSize: CGFloat) -> CGFloat { avatarSize - overlap(avatarSize: avatarSize) }
}

/// Circular carve under the cover so the avatar sits in a canvas-coloured pocket (Light + OLED).
struct ProfileAvatarPocket: View {
    let profile: ModulaProfile
    var tint: Color? = nil
    var onTap: (() -> Void)? = nil
    var onStoryTap: (() -> Void)? = nil
    var storyRing: StoryRingState? = nil
    var contextActions: [ModulaContextAction] = []
    var onContextAction: ((ModulaContextAction) -> Void)? = nil

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var avatarSize: CGFloat {
        ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)
    }

    private var ring: CGFloat { 5 }
    private var carveRadius: CGFloat { ProfileIdentityMetrics.carveRadius(avatarSize: avatarSize) }
    /// How much of the avatar sits above the content surface (intersection geometry).
    private var intersection: CGFloat { ProfileIdentityMetrics.overlap(avatarSize: avatarSize) }

    var body: some View {
        let inset = ModulaLayout.contentInset
        Color.clear
            .frame(height: ProfileIdentityMetrics.contentHeight(avatarSize: avatarSize))
            .overlay(alignment: .topLeading) {
                avatarBadge
                    .frame(width: avatarSize, height: avatarSize + (isOwnProfile && overlayStore.badge != nil ? 18 : 0))
                    .offset(y: -intersection)
                    .padding(.leading, inset)
            }
            .onAppear { overlayStore.bind(accountID: app.auth.account?.accountId) }
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
                    decoratedAvatarContent
                        .overlay(
                            Circle()
                                .strokeBorder(canvas, lineWidth: ring)
                        )
                        .overlay {
                            if overlayStore.frameID == ProfileAvatarFrame.none.id {
                                ModulaGlowRing(
                                    tint: tint ?? app.appearance.accent.color,
                                    lineWidth: storyRing == nil ? 3 : 1.5,
                                    glow: storyRing == nil
                                )
                                .padding(-1.5)
                            }
                        }
                        .shadow(color: (tint ?? .black).opacity(0.25), radius: 12, y: 4)

                    if let storyRing {
                        StoryRing(state: storyRing, size: avatarSize, accent: app.appearance.accent.color)
                    }
                }
            }
            .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
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

    private var overlayStore: ProfileAvatarOverlayStore { ProfileAvatarOverlayStore.shared }

    private var isOwnProfile: Bool {
        profile.id == app.auth.account?.accountId
            || profile.handle.caseInsensitiveCompare(app.auth.account?.primaryHandle ?? "") == .orderedSame
    }

    @ViewBuilder
    private var decoratedAvatarContent: some View {
        if isOwnProfile {
            ModulaDecoratedAvatar(
                size: avatarSize - 8,
                frame: ProfileAvatarFrame.frame(id: overlayStore.frameID),
                presence: overlayStore.presence,
                badge: overlayStore.badge,
                customBadgeLabel: overlayStore.customBadgeLabel,
                customBadgeColor: Color(hex: overlayStore.customBadgeColorHex),
                showsBadgeChip: overlayStore.badge != nil
            ) {
                ProfileAvatarContent(profile: profile, size: avatarSize - 8)
            }
        } else {
            ProfileAvatarContent(profile: profile, size: avatarSize)
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
    @Environment(\.profileAccentColor) private var profileAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bioExpanded = false

    private var bioIsLong: Bool { profile.bio.count > 160 || profile.bio.contains("\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ModulaText(text: profile.displayName, role: .title)
                    .lineLimit(2)
                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(profileAccent ?? app.appearance.accent.color)
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

            Text("@\(profile.handle)" + (profile.pronouns.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(bioExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if bioIsLong {
                    Button(bioExpanded ? "Less" : "More") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { bioExpanded.toggle() }
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
        .accessibilityElement(children: .contain)
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

    @Environment(\.profileAccentColor) private var profileAccent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        metricRow
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.metrics")
    }

    private var metricRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : (showsModules ? 4 : 3)), spacing: 12) {
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
                ModulaCountUpText(value: value, format: ProfileCountFormatter.compact)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(selected ? app.appearance.accent.color : .primary)
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
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
        .accessibilityLabel(ProfileCountFormatter.accessibility(value, noun: accessibilityNoun))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Tool actions (Follow / Message — Edit lives in the top toolbar)

struct ProfileToolActions: View {
    let followTitle: String
    let isFollowing: Bool
    var followBusy: Bool = false
    var messageTitle: String? = nil
    var onPrimary: () -> Void
    var onMessage: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var opaque: Bool {
        reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    if followBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(followTitle)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(reduceMotion ? .opacity : .interpolate)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(primaryForeground)
                .background(primaryBackground, in: Capsule())
                .overlay(
                    Capsule().stroke(primaryStroke, lineWidth: isFollowing ? 1 : 0)
                )
            }
            .buttonStyle(.plain)
            .disabled(followBusy)
            .accessibilityLabel(followTitle)
            .accessibilityIdentifier("profile.follow.cta")

            if let messageTitle, let onMessage {
                Button(action: onMessage) {
                    Text(messageTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .foregroundStyle(.primary)
                        .background(Color.clear)
                        .modulaChrome(in: Capsule(), opaque: opaque)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(messageTitle)
                .accessibilityIdentifier("profile.message.cta")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.tools")
    }

    private var primaryForeground: Color {
        isFollowing ? .primary : .white
    }

    private var primaryBackground: some ShapeStyle {
        AnyShapeStyle(isFollowing ? Color.primary.opacity(0.08) : app.appearance.accent.color)
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
        if let location = profile.location?.label, !location.isEmpty, ProfileFieldPrivacy.isPublic(profile.location?.visibility) {
            items.append(("Location", location, nil))
        }
        if let website = profile.website, let url = website.url, ProfileFieldPrivacy.isPublic(website.visibility) {
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
        .modulaShimmer()
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
                        .opacity(followBusy ? 0 : 1)
                        .overlay {
                            if followBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(person.isFollowing ? Color.secondary : Color.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: ModulaLayout.minimumTouch)
                        .foregroundStyle(person.isFollowing ? Color.secondary : Color.white)
                        .background(
                            Capsule().fill(person.isFollowing ? Color.primary.opacity(0.08) : app.appearance.accent.color)
                        )
                }
                .buttonStyle(.plain)
                .disabled(followBusy)
                .accessibilityLabel("\(person.followState.title), \(person.displayName)")
                .accessibilityValue(followBusy ? "Updating" : "")
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

/// Compatibility alias — prefer `ModulaShareMoreCapsule` for new call sites.
typealias ProfileShareMoreCapsule = ModulaShareMoreCapsule

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
                .frame(width: 44, height: 44)
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
                .frame(width: 44, height: 44)
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


// MARK: - Mascot-aware avatar content

/// Shows the dressed mascot inside the avatar ring when the user opts in; otherwise the photo.
struct ProfileAvatarContent: View {
    let profile: ModulaProfile
    let size: CGFloat
    @AppStorage(MascotProfileSettings.useAsAvatarKey) private var useMascot = false
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue

    var body: some View {
        let selection = MascotSelection.resolve(raw: kindRaw)
        if useMascot, selection != .off {
            MascotAvatarView(size: size)
        } else {
            ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: size, name: profile.displayName)
        }
    }
}

// MARK: - Avatar overlays (frames, badges, presence)

// MARK: - Local overlay preferences (server has no fields yet)

/// Discord-style frames, LinkedIn-style status badges, and presence dots — stored locally
/// per account until the profile API grows matching fields.
@MainActor @Observable
final class ProfileAvatarOverlayStore {
    static let shared = ProfileAvatarOverlayStore()

    private(set) var frameID: String = ProfileAvatarFrame.none.id
    private(set) var badge: ProfileStatusBadge?
    private(set) var presence: ProfilePresenceStatus = .offline
    private(set) var customBadgeLabel: String = ""
    private(set) var customBadgeColorHex: String = "#3478F6"

    private var accountKey: String = "anon"

    func bind(accountID: String?) {
        accountKey = accountID ?? "anon"
        load()
    }

    func setFrame(_ id: String) {
        frameID = id
        persist()
    }

    func setBadge(_ badge: ProfileStatusBadge?) {
        self.badge = badge
        persist()
    }

    func setPresence(_ presence: ProfilePresenceStatus) {
        self.presence = presence
        persist()
    }

    func setCustomBadge(label: String, hex: String) {
        customBadgeLabel = String(label.prefix(28))
        customBadgeColorHex = hex
        badge = .custom
        persist()
    }

    private var defaultsKey: String { "profile.avatarOverlays.v1.\(accountKey)" }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            frameID = ProfileAvatarFrame.none.id
            badge = nil
            presence = .offline
            return
        }
        frameID = decoded.frameID
        badge = decoded.badge.flatMap(ProfileStatusBadge.init(rawValue:))
        presence = ProfilePresenceStatus(rawValue: decoded.presence) ?? .offline
        customBadgeLabel = decoded.customLabel
        customBadgeColorHex = decoded.customHex
    }

    private func persist() {
        let payload = Payload(
            frameID: frameID,
            badge: badge?.rawValue,
            presence: presence.rawValue,
            customLabel: customBadgeLabel,
            customHex: customBadgeColorHex
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private struct Payload: Codable {
        var frameID: String
        var badge: String?
        var presence: String
        var customLabel: String
        var customHex: String
    }
}

// MARK: - Catalog

struct ProfileAvatarFrame: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: Kind

    enum Kind: Hashable, Sendable {
        case none
        case softRing(Color)
        case dualRing(Color, Color)
        case dashed(Color)
        case gradient([Color])
        case pixels(Color)
        case laurels(Color)
        case hex(Color)
        case sparkle(Color)
        case neon(Color)
        case mascotPaw(Color)
    }

    static let none = ProfileAvatarFrame(id: "none", title: "None", kind: .none)

    static let catalog: [ProfileAvatarFrame] = [
        none,
        .init(id: "soft.accent", title: "Soft", kind: .softRing(Color(hex: "#3478F6"))),
        .init(id: "soft.violet", title: "Violet", kind: .softRing(Color(hex: "#7656D6"))),
        .init(id: "soft.coral", title: "Coral", kind: .softRing(Color(hex: "#D66056"))),
        .init(id: "dual.ocean", title: "Ocean Dual", kind: .dualRing(Color(hex: "#3478F6"), Color(hex: "#5AC8FA"))),
        .init(id: "dual.sunset", title: "Sunset", kind: .dualRing(Color(hex: "#FF6B6B"), Color(hex: "#FFD93D"))),
        .init(id: "dashed.mint", title: "Dashed Mint", kind: .dashed(Color(hex: "#34C759"))),
        .init(id: "grad.aurora", title: "Aurora", kind: .gradient([.purple, .pink, .orange, .yellow, .purple])),
        .init(id: "grad.ice", title: "Ice", kind: .gradient([.cyan, .blue, .indigo, .cyan])),
        .init(id: "pixels.lime", title: "Pixels", kind: .pixels(Color(hex: "#A8E10C"))),
        .init(id: "laurels.gold", title: "Laurels", kind: .laurels(Color(hex: "#C9A227"))),
        .init(id: "hex.teal", title: "Hex", kind: .hex(Color(hex: "#369CAA"))),
        .init(id: "sparkle.pink", title: "Sparkle", kind: .sparkle(Color(hex: "#FF2D55"))),
        .init(id: "neon.cyan", title: "Neon", kind: .neon(Color(hex: "#00F5FF"))),
        .init(id: "paw.purple", title: "Paw", kind: .mascotPaw(Color(hex: "#AF52DE"))),
    ]

    static func frame(id: String) -> ProfileAvatarFrame {
        catalog.first { $0.id == id } ?? .none
    }
}

enum ProfileStatusBadge: String, CaseIterable, Identifiable, Sendable {
    case openToWork
    case hiring
    case collaborating
    case learning
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openToWork: "Open to work"
        case .hiring: "Hiring"
        case .collaborating: "Collaborating"
        case .learning: "Learning"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .openToWork: "briefcase.fill"
        case .hiring: "person.badge.plus"
        case .collaborating: "person.2.fill"
        case .learning: "book.fill"
        case .custom: "tag.fill"
        }
    }

    var defaultColor: Color {
        switch self {
        case .openToWork: Color(hex: "#0A66C2") // LinkedIn-ish blue
        case .hiring: Color(hex: "#34C759")
        case .collaborating: Color(hex: "#7656D6")
        case .learning: Color(hex: "#FF9F0A")
        case .custom: Color(hex: "#3478F6")
        }
    }
}

enum ProfilePresenceStatus: String, CaseIterable, Identifiable, Sendable {
    case online, idle, dnd, offline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: "Online"
        case .idle: "Idle"
        case .dnd: "Do not disturb"
        case .offline: "Invisible"
        }
    }

    var color: Color {
        switch self {
        case .online: Color(hex: "#23A559")
        case .idle: Color(hex: "#F0B232")
        case .dnd: Color(hex: "#F23F43")
        case .offline: Color(hex: "#80848E")
        }
    }
}

// MARK: - Decorated avatar

/// Wraps avatar content with frame ring, presence pip, and optional status badge chip.
struct ModulaDecoratedAvatar<Content: View>: View {
    var size: CGFloat
    var frame: ProfileAvatarFrame
    var presence: ProfilePresenceStatus = .offline
    var badge: ProfileStatusBadge? = nil
    var customBadgeLabel: String = ""
    var customBadgeColor: Color = .accentColor
    var showsBadgeChip = true
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringPad: CGFloat {
        switch frame.kind {
        case .none: 0
        case .softRing, .dashed: 4
        case .dualRing, .gradient, .neon, .sparkle: 6
        case .pixels, .laurels, .hex, .mascotPaw: 8
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .bottomTrailing) {
                content()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .padding(ringPad)
                    .background { frameBackground }
                    .overlay { frameOverlay }

                if presence != .offline {
                    presencePip
                        .offset(x: -2, y: -2)
                }
            }

            if showsBadgeChip, let badge {
                statusChip(badge)
                    .offset(y: size * 0.42)
            }
        }
        .frame(width: size + ringPad * 2, height: size + ringPad * 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var frameBackground: some View {
        switch frame.kind {
        case .none:
            EmptyView()
        case .softRing(let color), .dashed(let color), .pixels(let color), .laurels(let color), .hex(let color), .mascotPaw(let color), .neon(let color), .sparkle(let color):
            Circle().strokeBorder(color.opacity(0.35), lineWidth: 3)
        case .dualRing(let a, let b):
            Circle().strokeBorder(
                AngularGradient(colors: [a, b, a], center: .center),
                lineWidth: 3.5
            )
        case .gradient(let colors):
            Circle().strokeBorder(
                AngularGradient(colors: colors, center: .center),
                lineWidth: 4
            )
        }
    }

    @ViewBuilder
    private var frameOverlay: some View {
        switch frame.kind {
        case .none:
            EmptyView()
        case .softRing(let color):
            Circle().strokeBorder(color.opacity(0.85), lineWidth: 2.5)
        case .dualRing(let a, let b):
            Circle()
                .strokeBorder(AngularGradient(colors: [a, b, a], center: .center), lineWidth: 3)
                .padding(2)
            Circle()
                .strokeBorder(b.opacity(0.5), lineWidth: 1)
                .padding(-1)
        case .dashed(let color):
            Circle()
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
        case .gradient(let colors):
            Circle()
                .strokeBorder(AngularGradient(colors: colors, center: .center), lineWidth: 3.5)
                .shadow(color: colors.first?.opacity(reduceMotion ? 0 : 0.45) ?? .clear, radius: 8)
        case .pixels(let color):
            Circle().strokeBorder(color, lineWidth: 2)
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: -(size / 2 + ringPad - 1))
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        case .laurels(let color):
            Circle().strokeBorder(color.opacity(0.7), lineWidth: 2)
            Image(systemName: "laurel.leading")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(color)
                .offset(x: -(size * 0.52), y: size * 0.08)
            Image(systemName: "laurel.trailing")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(color)
                .offset(x: size * 0.52, y: size * 0.08)
        case .hex(let color):
            Circle().strokeBorder(color.opacity(0.25), lineWidth: 1)
            Image(systemName: "hexagon")
                .font(.system(size: size + ringPad * 2, weight: .ultraLight))
                .foregroundStyle(color.opacity(0.9))
        case .sparkle(let color):
            Circle().strokeBorder(color.opacity(0.8), lineWidth: 2)
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .offset(y: -(size / 2 + ringPad))
                    .rotationEffect(.degrees(Double(i) * 72))
            }
        case .neon(let color):
            Circle()
                .strokeBorder(color, lineWidth: 2)
                .shadow(color: color.opacity(reduceMotion ? 0 : 0.9), radius: 10)
                .shadow(color: color.opacity(reduceMotion ? 0 : 0.5), radius: 18)
        case .mascotPaw(let color):
            Circle().strokeBorder(color.opacity(0.55), lineWidth: 2)
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(color)
                .offset(x: size * 0.38, y: -size * 0.38)
        }
    }

    private var presencePip: some View {
        Circle()
            .fill(presence.color)
            .frame(width: max(12, size * 0.22), height: max(12, size * 0.22))
            .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2.5))
            .accessibilityLabel(presence.title)
    }

    private func statusChip(_ badge: ProfileStatusBadge) -> some View {
        let label = badge == .custom ? (customBadgeLabel.isEmpty ? "Custom" : customBadgeLabel) : badge.title
        let color = badge == .custom ? customBadgeColor : badge.defaultColor
        return HStack(spacing: 4) {
            Image(systemName: badge.systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityLabel(label)
    }
}

// MARK: - Editor sheet

struct ProfileAvatarOverlayEditor: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    private var store: ProfileAvatarOverlayStore { ProfileAvatarOverlayStore.shared }
    @State private var customLabel: String = ""
    @State private var customHex: String = "#3478F6"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview

                    section("Frame") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                            ForEach(ProfileAvatarFrame.catalog) { item in
                                Button {
                                    store.setFrame(item.id)
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    VStack(spacing: 6) {
                                        ModulaDecoratedAvatar(
                                            size: 44,
                                            frame: item,
                                            presence: .offline,
                                            showsBadgeChip: false
                                        ) {
                                            Circle().fill(app.appearance.accent.color.opacity(0.35))
                                        }
                                        Text(item.title)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(store.frameID == item.id ? app.appearance.accent.color : .secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(store.frameID == item.id ? app.appearance.accent.color.opacity(0.12) : Color.primary.opacity(0.04))
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.title)
                                .accessibilityAddTraits(store.frameID == item.id ? .isSelected : [])
                            }
                        }
                    }

                    section("Status badge") {
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    badgeChip(nil, title: "None", color: .secondary)
                                    ForEach(ProfileStatusBadge.allCases.filter { $0 != .custom }) { badge in
                                        badgeChip(badge, title: badge.title, color: badge.defaultColor)
                                    }
                                    badgeChip(.custom, title: "Custom", color: Color(hex: customHex))
                                }
                            }
                            if store.badge == .custom {
                                TextField("Badge label", text: $customLabel)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .modulaGlass(in: Capsule(), interactive: true)
                                    .onChange(of: customLabel) { _, value in
                                        store.setCustomBadge(label: value, hex: customHex)
                                    }
                                HStack(spacing: 8) {
                                    ForEach(["#3478F6", "#0A66C2", "#34C759", "#FF9F0A", "#FF2D55", "#AF52DE"], id: \.self) { hex in
                                        Button {
                                            customHex = hex
                                            store.setCustomBadge(label: customLabel, hex: hex)
                                            HapticEngine.shared.play(.selection)
                                        } label: {
                                            Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                                .overlay(Circle().strokeBorder(customHex == hex ? Color.primary : .clear, lineWidth: 2))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    section("Presence") {
                        HStack(spacing: 8) {
                            ForEach(ProfilePresenceStatus.allCases) { status in
                                Button {
                                    store.setPresence(status)
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(status.color).frame(width: 10, height: 10)
                                        Text(status.title).font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(
                                        Capsule().fill(store.presence == status ? status.color.opacity(0.18) : Color.primary.opacity(0.05))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text("Frames, badges, and presence are saved on this device until the profile API supports them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .modulaCanvas()
            .navigationTitle("Avatar overlays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                store.bind(accountID: app.auth.account?.accountId)
                customLabel = store.customBadgeLabel
                customHex = store.customBadgeColorHex
            }
        }
    }

    private var preview: some View {
        let frame = ProfileAvatarFrame.frame(id: store.frameID)
        return HStack {
            Spacer()
            ModulaDecoratedAvatar(
                size: 96,
                frame: frame,
                presence: store.presence,
                badge: store.badge,
                customBadgeLabel: store.customBadgeLabel,
                customBadgeColor: Color(hex: store.customBadgeColorHex)
            ) {
                if let profile = app.profile.ownProfile {
                    ProfileAvatarContent(profile: profile, size: 96)
                } else {
                    Circle().fill(app.appearance.accent.color.opacity(0.35))
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func badgeChip(_ badge: ProfileStatusBadge?, title: String, color: Color) -> some View {
        Button {
            store.setBadge(badge)
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 6) {
                if let badge {
                    Image(systemName: badge.systemImage).font(.caption.weight(.bold))
                }
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(store.badge == badge ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(store.badge == badge ? color : Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
