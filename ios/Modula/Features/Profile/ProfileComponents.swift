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
            // Stretch is applied to the whole cover below (scale from the bottom edge).
            let stretch: CGFloat = 0
            ZStack(alignment: .bottom) {
                fallbackComposition
                    .opacity(coverURL == nil ? 1 : 0.001)
                if let coverURL {
                    ModulaRemoteImage(
                        url: coverURL,
                        cacheKey: "cover:\(coverURL.path)",
                        maximumPixelSize: max(width, coverHeight) * UIScreen.main.scale * 1.5,
                        retryID: retryID
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            // The whole banner stays readable: it's shown at full width below the
                            // status bar (aspect fit), over a blurred fill of itself, so baked-in
                            // text is never cropped off the sides or hidden behind the nav bar.
                            // Edge to edge, aspect-fill, sharp (no letterbox / blurred side fill).
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: coverHeight + stretch)
                                .clipped()
                            // Banner softens as the page scrolls (and a touch while stretching).
                            .blur(radius: coverBlur(stretch: stretch), opaque: true)
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

                // Animated banner overlay (v2) — aurora drift + spark particles.
                ProfileBannerFX(accent: tint ?? app.appearance.liveAccent)
                    .frame(width: width, height: coverHeight + stretch)
                    .opacity(0.55 + 0.25 * Double(1 - dissolve))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)

                // Light top fade only — keeps the status bar and nav buttons legible.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(scheme == .dark ? 0.34 : 0.2), Color.black.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: safeAreaTop + 70)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)

                // Liquid bottom fade — soft multi-stop dissolve into the page background.
                liquidBottomFade
                    .frame(height: coverHeight * (coverURL == nil ? 0.62 : 0.3))
                    .opacity(0.92 + (0.08 * Double(dissolve)))
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: coverHeight + stretch, alignment: .top)
            // Parallax: the hero drifts at ~40% of the scroll speed while the page scrolls up.
            .visualEffect { [reduceMotion] content, proxy in
                let minY = proxy.frame(in: .scrollView).minY
                return content.offset(y: reduceMotion || minY >= 0 ? 0 : -minY * 0.4)
            }
            .mask {
                if let pocketCenterX, let pocketRadius {
                    // Inverted pocket: a concave notch carved up into the banner's bottom edge.
                    ProfileCoverNotchShape(centerX: pocketCenterX, radius: pocketRadius)
                } else {
                    Rectangle()
                }
            }
            .clipped()
            .overlay {
                if let pocketCenterX, let pocketRadius {
                    ProfileCoverNotchRim(
                        centerX: pocketCenterX,
                        radius: pocketRadius,
                        tint: tint ?? app.appearance.liveAccent
                    )
                }
            }
        }
        .frame(height: coverHeight)
        // Stretchy header: on pull-down the cover scales from its bottom edge to fill the gap
        // (no blank strip). On scroll-up it stays sharp until it slides under the header bar,
        // then blurs progressively.
        .visualEffect { [reduceMotion, coverHeight, safeAreaTop] content, proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let pull = max(0, minY)
            let scale = coverHeight > 0 ? (coverHeight + pull) / coverHeight : 1
            let headerBottom = safeAreaTop + 44
            let under = max(0, -minY - (coverHeight - headerBottom - 40))
            let radius = reduceMotion ? 0 : min(under / 80 * 14, 14)
            return content
                .scaleEffect(x: scale, y: scale, anchor: .bottom)
                .blur(radius: radius, opaque: true)
        }
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

    private func coverBlur(stretch: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return 0
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
                .fill(app.appearance.liveAccent.opacity(0.14))
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

// MARK: - Cover notch (inverted avatar pocket)

/// Cover silhouette with a concave semicircular notch carved up into its bottom edge,
/// centred on the avatar. Points are sampled explicitly so the notch always bites
/// upward into the banner, independent of arc direction conventions.
struct ProfileCoverNotchShape: Shape {
    var centerX: CGFloat
    var radius: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let fillet = min(14, radius * 0.24)
        let lift = 0.32 // radians: where each fillet meets the circle
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: min(rect.maxX, centerX + radius + fillet), y: rect.maxY))
        path.addQuadCurve(
            to: Self.point(centerX, rect.maxY, radius, lift),
            control: CGPoint(x: centerX + radius, y: rect.maxY)
        )
        let steps = 40
        for index in 1...steps {
            let angle = lift + (Double.pi - 2 * lift) * Double(index) / Double(steps)
            path.addLine(to: Self.point(centerX, rect.maxY, radius, angle))
        }
        path.addQuadCurve(
            to: CGPoint(x: max(rect.minX, centerX - radius - fillet), y: rect.maxY),
            control: CGPoint(x: centerX - radius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    nonisolated static func point(_ cx: CGFloat, _ baseY: CGFloat, _ r: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: cx + r * CGFloat(cos(angle)), y: baseY - r * CGFloat(sin(angle)))
    }
}

/// Just the notch's curved edge (for strokes: rim + inner shadow).
struct ProfileCoverNotchArc: Shape {
    var centerX: CGFloat
    var radius: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        for index in 0...steps {
            let angle = Double.pi * Double(index) / Double(steps)
            let point = CGPoint(
                x: centerX + radius * CGFloat(cos(angle)),
                y: rect.maxY - radius * CGFloat(sin(angle))
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Soft inner shadow + glass rim along the notch so the avatar reads as nested in
/// a pocket pressed into the banner (Light, Dark and OLED).
struct ProfileCoverNotchRim: View {
    var centerX: CGFloat
    var radius: CGFloat
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let crown = UnitPoint(x: 0.5, y: max(0, (height - radius) / height))
            ZStack {
                // Inner shadow, kept on the banner side of the notch.
                ProfileCoverNotchArc(centerX: centerX, radius: radius)
                    .stroke(Color.black.opacity(scheme == .dark ? 0.5 : 0.2), lineWidth: 12)
                    .blur(radius: 7)
                    .mask(ProfileCoverNotchShape(centerX: centerX, radius: radius))
                // Faint tinted bloom just inside the rim.
                ProfileCoverNotchArc(centerX: centerX, radius: radius + 3)
                    .stroke(tint.opacity(0.3), lineWidth: 3)
                    .blur(radius: 3)
                    .mask(ProfileCoverNotchShape(centerX: centerX, radius: radius))
                // Glass rim: bright at the crown, dissolving toward the seam.
                ProfileCoverNotchArc(centerX: centerX, radius: radius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(scheme == .dark ? 0.42 : 0.8), Color.white.opacity(0.14), .clear],
                            startPoint: crown,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    .frame(width: avatarSize, height: avatarSize)
                    .offset(y: -intersection)
                    .padding(.leading, inset)
            }
            .onAppear {
                overlayStore.bind(accountID: app.auth.account?.accountId)
                if isOwnProfile { overlayStore.noteOwnAvatar(profile.avatarURL) }
            }
            .onChange(of: profile.avatarURL) { _, url in
                if isOwnProfile { overlayStore.noteOwnAvatar(url) }
            }
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
                    // Clean stack: the photo, one thin ring (or the chosen frame), a soft round
                    // shadow. The thick canvas stroke and the shimmer halo drew a black block and a
                    // jagged edge over the full-bleed cover.
                    decoratedAvatarContent
                        .overlay {
                            if overlayStore.frameID == ProfileAvatarFrame.none.id {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.9), lineWidth: storyRing == nil ? 2 : 1)
                            }
                        }
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 3)

                    if let storyRing {
                        StoryRing(state: storyRing, size: avatarSize, accent: app.appearance.liveAccent, showsAddBadge: false)
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
            // Verified lives next to the name; nothing sits on the avatar's edge any more,
            // so the banner seam stays clean.
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
    /// Others' profiles: small "Follows you" tag beside the name when the API says so.
    var showsFollowsYou: Bool = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.profileAccentColor) private var profileAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bioExpanded = false
    @State private var premiumStore = PremiumEntitlementStore.shared

    private var bioIsLong: Bool { profile.bio.count > 160 || profile.bio.contains("\n") }
    private var accent: Color { profileAccent ?? app.appearance.liveAccent }

    /// Own profile only. Other profiles have no membership field we are allowed to read.
    private var showsOwnPremiumBadge: Bool {
        guard premiumStore.showsOwnBadge else { return false }
        if profile.id == app.auth.account?.accountId { return true }
        let handle = app.auth.account?.primaryHandle ?? ""
        return !handle.isEmpty && profile.handle.caseInsensitiveCompare(handle) == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ModulaText(text: profile.displayName, role: .title)
                    .lineLimit(2)
                if showsOwnPremiumBadge {
                    PremiumProfileBadge(plan: premiumStore.plan)
                }
                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityLabel("Verified account")
                }
                if showsFollowsYou && profile.followsViewer {
                    Text("Follows you")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityIdentifier("profile.followsYou")
                }
            }

            // Handle + pronouns on their own line: nothing overlays it any more.
            HStack(spacing: 6) {
                Text("@\(profile.handle)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let pronouns = profile.pronouns, !pronouns.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(pronouns)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Copy @\(profile.handle)", systemImage: "at") {
                    UIPasteboard.general.string = "@\(profile.handle)"
                    HapticEngine.shared.play(.confirmation)
                    ModulaToastCenter.shared.show("Handle copied", symbol: "at", tone: .info)
                }
                Button("Copy profile link", systemImage: "link") {
                    UIPasteboard.general.string = profile.shareURL.absoluteString
                    HapticEngine.shared.play(.confirmation)
                    ModulaToastCenter.shared.show("Link copied", symbol: "link", tone: .info)
                }
            }
            .accessibilityIdentifier("profile.handle")

            if let headline = profile.headline, !headline.isEmpty {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityIdentifier("profile.headline")
            }

            if !profile.bio.isEmpty {
                // Links, #hashtags and @mentions in the bio are live.
                Text(PostTextLinks.attributed(profile.bio))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .tint(accent)
                    .lineLimit(bioExpanded ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .environment(\.openURL, OpenURLAction { url in
                        if let route = PostTextLinks.route(for: url) {
                            app.navigation.push(route)
                            HapticEngine.shared.play(.navigation)
                            return .handled
                        }
                        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                            return .discarded
                        }
                        return .systemAction
                    })
                    .accessibilityIdentifier("profile.bio")

                if bioIsLong {
                    Button(bioExpanded ? "Less" : "More") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { bioExpanded.toggle() }
                        HapticEngine.shared.play(.selection)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
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
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
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
                    .foregroundStyle(selected ? app.appearance.liveAccent : .primary)
                Text(label)
                    .font(.caption2.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? app.appearance.liveAccent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(app.appearance.liveAccent)
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
        AnyShapeStyle(isFollowing ? Color.primary.opacity(0.08) : app.appearance.liveAccent)
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
                                .foregroundStyle(app.appearance.liveAccent)
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

// MARK: - Info chips (location / website / joined…)

/// Replaces the old "Joined / Visibility / Sharing publicly" grid with compact glass chips.
struct ProfileInfoChips: View {
    let profile: ModulaProfile
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var app
    @Environment(\.profileAccentColor) private var profileAccent

    private struct Chip: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let action: (() -> Void)?
    }

    private var accent: Color { profileAccent ?? app.appearance.liveAccent }

    private var chips: [Chip] {
        var items: [Chip] = []
        // One accurate status: a focus/status message that talks about visibility
        // ("Sharing publicly") is replaced by the profile's real visibility below.
        if let focus = profile.focusStatus {
            let text = focus.message ?? focus.label
            let lower = text.lowercased()
            let talksPrivacy = lower.contains("public") || lower.contains("private") || lower.contains("sharing")
            if !talksPrivacy {
                items.append(Chip(id: "focus", symbol: "circle.fill", title: text, action: nil))
            }
        }
        if let location = profile.location?.label, !location.isEmpty, ProfileFieldPrivacy.isPublic(profile.location?.visibility) {
            items.append(Chip(id: "location", symbol: "mappin.and.ellipse", title: location, action: nil))
        }
        if let website = profile.website, let url = website.url, ProfileFieldPrivacy.isPublic(website.visibility) {
            let open = openURL
            items.append(Chip(id: "website", symbol: "link", title: website.domain ?? website.label, action: {
                ProfileAboutGrid.openSafely(url, openURL: open)
            }))
        }
        if let joined = profile.joinedAt {
            items.append(Chip(id: "joined", symbol: "calendar", title: "Joined \(joined.formatted(.dateTime.month(.abbreviated).year()))", action: nil))
        }
        if !profile.languages.isEmpty {
            items.append(Chip(id: "languages", symbol: "globe", title: profile.languages.prefix(3).joined(separator: ", "), action: nil))
        }
        if let visibility = profile.visibility, visibility != .public {
            items.append(Chip(id: "visibility", symbol: "lock.fill", title: visibility == .followers ? "Followers only" : visibility.displayTitle, action: nil))
        }
        return items
    }

    var body: some View {
        let items = chips
        if !items.isEmpty {
            ProfileChipFlowLayout(spacing: 8) {
                ForEach(items) { chip in
                    chipView(chip)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile.about")
        }
    }

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        let tappable = chip.action != nil
        let label = HStack(spacing: 5) {
            Image(systemName: chip.symbol)
                .font(.caption.weight(.semibold))
                .imageScale(chip.id == "focus" ? .small : .medium)
                .foregroundStyle(chip.id == "focus" ? Color.green : (tappable ? accent : Color.secondary))
                // Fixed icon box so Joined / Private / etc. share one baseline.
                .frame(width: 16, height: 16)
            Text(chip.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tappable ? accent : Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 30)
        if let action = chip.action {
            Button {
                action()
                HapticEngine.shared.play(.selection)
            } label: {
                label.contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
            .modulaGlass(in: Capsule(), interactive: true)
            .accessibilityLabel("Website, \(chip.title)")
            .accessibilityIdentifier("profile.chip.\(chip.id)")
        } else {
            // Plain metadata (Joined, Private…) reads as one clean line, not a pile of pills.
            label
                .padding(.horizontal, -11)
                .padding(.trailing, 6)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile.chip.\(chip.id)")
        }
    }
}

/// Wrapping row for chips.
struct ProfileChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if width > 0, width + spacing + size.width > maxWidth {
                height += rowHeight + spacing
                width = 0
                rowHeight = 0
            }
            width += (width == 0 ? 0 : spacing) + min(size.width, maxWidth)
            widest = max(widest, width)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Hero actions (Edit / Share · Follow / Message / Notify / More)

/// Primary profile buttons in Modula Liquid Glass. Own profile: Edit profile, Share
/// profile, QR. Others: Follow (morphs to Following), Message, notifications bell, more.
struct ProfileHeroActions: View {
    var isOwn: Bool
    var tint: Color
    var followTitle: String = "Follow"
    var isFollowing: Bool = false
    var followBusy: Bool = false
    var messageTitle: String? = nil
    var moreActions: [ModulaContextAction] = []
    var onEdit: () -> Void = {}
    var onShare: () -> Void = {}
    var onCode: () -> Void = {}
    var onFollow: () -> Void = {}
    var onMessage: () -> Void = {}
    var onNotify: () -> Void = {}
    var onMore: (ModulaContextAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Namespace private var glass

    var body: some View {
        ModulaGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                if isOwn {
                    pill("Edit profile", symbol: "pencil", prominent: true, id: "edit", action: onEdit)
                        .accessibilityIdentifier("profile.edit.cta")
                    pill("Share profile", symbol: "square.and.arrow.up", prominent: false, id: "share", action: onShare)
                        .accessibilityIdentifier("profile.share")
                    icon("Profile QR code", symbol: "qrcode", id: "qr", action: onCode)
                        .accessibilityIdentifier("profile.qr")
                } else {
                    followPill
                        .accessibilityIdentifier("profile.follow.cta")
                    if let messageTitle {
                        pill(messageTitle, symbol: "bubble.left.and.bubble.right", prominent: false, id: "message", action: onMessage)
                            .accessibilityIdentifier("profile.message.cta")
                    }
                    // Notifications bell removed: it only flashed "coming soon".
                    if !moreActions.isEmpty {
                        moreMenu
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.tools")
    }

    private func pill(_ title: String, symbol: String, prominent: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.lightImpact)
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
        .modifier(ProfilePillSurface(prominent: prominent, tint: tint))
        .modulaGlassID(id, in: glass)
        .accessibilityLabel(title)
    }

    private var followPill: some View {
        Button {
            onFollow()
        } label: {
            HStack(spacing: 6) {
                if followBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(isFollowing ? Color.primary : Color.white)
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.subheadline.weight(.bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(followTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(isFollowing ? Color.primary : Color.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
        .disabled(followBusy)
        .modulaGlass(in: Capsule(), interactive: true, tint: isFollowing ? nil : tint, prominent: !isFollowing, specular: true)
        .modulaGlassID("follow", in: glass)
        .animation(ModulaEffectGate.reduceMotion(systemReduceMotion) ? nil : .spring(response: 0.34, dampingFraction: 0.78), value: isFollowing)
        .accessibilityLabel(followTitle)
    }

    private func icon(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
        // Non-interactive glass: interactive glass swallowed most taps (QR needed ~5 taps).
        .modulaGlass(in: Circle(), interactive: false, specular: true)
        .contentShape(Circle())
        .modulaGlassID(id, in: glass)
        .accessibilityLabel(title)
    }

    /// Glass sits behind a plain native Menu, so the menu presents like the tab-bar
    /// accessory's Options menu (above all chrome) instead of morphing out of glass.
    private var moreMenu: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
                .modulaGlass(in: Circle(), interactive: false, specular: true)
                .modulaGlassID("more", in: glass)
                .accessibilityHidden(true)
            Menu {
                ForEach(moreActions) { action in
                    Button(role: action.role == .destructive ? .destructive : nil) {
                        onMore(action)
                    } label: {
                        if let systemImage = action.systemImage {
                            Label(action.title, systemImage: systemImage)
                        } else {
                            Text(action.title)
                        }
                    }
                    .disabled(action.role == .disabled)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("More")
            .accessibilityIdentifier("profile.more.inline")
        }
    }
}

// MARK: - Highlights

struct ProfileHighlightItem: Identifiable {
    let id: String
    let title: String
    var symbol: String? = nil
    var imageURL: URL? = nil
    var initials: String = ""
    var action: () -> Void
}

/// Story highlights row. Active stories are real; saved highlight albums are a stub
/// until the stories API stores them.
struct ProfileHighlightsRow: View {
    let items: [ProfileHighlightItem]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        Button {
                            HapticEngine.shared.play(.selection)
                            item.action()
                        } label: {
                            VStack(spacing: 6) {
                                bubble(item)
                                Text(item.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 72)
                            }
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                        .accessibilityLabel(item.title)
                        .accessibilityIdentifier("profile.highlight.\(item.id)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.highlights")
    }

    @ViewBuilder
    private func bubble(_ item: ProfileHighlightItem) -> some View {
        let live = item.imageURL != nil
        Group {
            if let url = item.imageURL {
                ModulaAvatar(initials: item.initials, url: url, size: 58)
                    .environment(\.modulaSuppressOwnFrame, true)
            } else {
                Circle()
                    .fill(tint.opacity(0.1))
                    .frame(width: 58, height: 58)
                    .overlay(
                        Image(systemName: item.symbol ?? "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(tint)
                    )
            }
        }
        .padding(4)
        .overlay(
            Circle().strokeBorder(
                tint.opacity(live ? 0.95 : 0.4),
                style: StrokeStyle(lineWidth: live ? 2.5 : 1.5, dash: live ? [] : [4, 3])
            )
        )
    }
}

// MARK: - Featured modules

struct ProfileFeaturedModulesRow: View {
    let products: [CatalogueProduct]
    var installedIDs: Set<String>
    var onOpen: (String) -> Void
    var onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfilePreviewHeader(title: "Featured modules", showsSeeAll: products.count > 3, onSeeAll: onSeeAll)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(products) { product in
                        Button {
                            HapticEngine.shared.play(.navigation)
                            onOpen(product.moduleId)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ProductArtwork(product: product, size: 48)
                                Text(product.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(installedIDs.contains(product.id) ? "Installed" : product.status.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 124, alignment: .leading)
                            .padding(12)
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
                        .accessibilityIdentifier("profile.featured.\(product.moduleId)")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.featuredModules")
    }
}

// MARK: - Mutual followers

/// "Followed by @a, @b and 3 others you follow" — computed from real follower /
/// following pages (first page of each).
struct ProfileMutualFollowersLine: View {
    let people: [ModulaProfile]
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(people.prefix(3)) { person in
                        ModulaAvatar(initials: person.initials, url: person.avatarURL, size: 22)
                            .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.5))
                    }
                }
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("profile.mutuals")
    }

    private var summary: String {
        let names = people.prefix(2).map { "@\($0.handle)" }
        let rest = people.count - names.count
        if names.count == 1 { return "Followed by \(names[0])" }
        if rest <= 0 { return "Followed by \(names[0]) and \(names[1])" }
        return "Followed by \(names[0]), \(names[1]) and \(rest) \(rest == 1 ? "other" : "others") you follow"
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
                                    .foregroundStyle(app.appearance.liveAccent)
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
                            Capsule().fill(person.isFollowing ? Color.primary.opacity(0.08) : app.appearance.liveAccent)
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
                Capsule().fill(prominent ? app.appearance.liveAccent : Color.primary.opacity(0.08))
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
        // The real photo wins wherever one exists, so the profile matches posts/Settings.
        if useMascot, selection != .off, profile.avatarURL == nil {
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
    /// Who the "open to" frame is meant for. On-device only until the profile API
    /// stores frames, so today it governs where *you* see it outside your profile.
    private(set) var badgeVisibility: ProfileFrameVisibility = .everyone
    /// The signed-in user's avatar URL, remembered so `ModulaAvatar` can spot "my photo"
    /// anywhere without observing ProfileStore.
    private(set) var ownAvatarURL: URL?
    /// "Currently building …" status line with a live dot (on-device until the API has it).
    private(set) var buildingStatus: String = ""

    private var accountKey: String = "anon"
    private var boundKey: String?

    /// Cheap to call from every avatar: only reloads when the signed-in account changes.
    func bind(accountID: String?) {
        let key = accountID ?? "anon"
        guard key != boundKey else { return }
        boundKey = key
        accountKey = key
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

    func noteOwnAvatar(_ url: URL?) {
        guard url != ownAvatarURL else { return }
        ownAvatarURL = url
        persist()
    }

    func setBadgeVisibility(_ visibility: ProfileFrameVisibility) {
        badgeVisibility = visibility
        persist()
    }

    func setBuildingStatus(_ text: String) {
        buildingStatus = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        persist()
    }

    /// Frames picker "Apply": commits every choice at once.
    func apply(
        frameID: String,
        badge: ProfileStatusBadge?,
        customLabel: String,
        customHex: String,
        presence: ProfilePresenceStatus,
        visibility: ProfileFrameVisibility
    ) {
        self.frameID = frameID
        self.badge = badge
        self.customBadgeLabel = String(customLabel.prefix(28))
        self.customBadgeColorHex = customHex
        self.presence = presence
        self.badgeVisibility = visibility
        persist()
    }

    private var defaultsKey: String { "profile.avatarOverlays.v1.\(accountKey)" }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            frameID = ProfileAvatarFrame.none.id
            badge = nil
            presence = .offline
            badgeVisibility = .everyone
            ownAvatarURL = nil
            buildingStatus = ""
            return
        }
        frameID = decoded.frameID
        badge = decoded.badge.flatMap(ProfileStatusBadge.init(rawValue:))
        presence = ProfilePresenceStatus(rawValue: decoded.presence) ?? .offline
        customBadgeLabel = decoded.customLabel
        customBadgeColorHex = decoded.customHex
        badgeVisibility = decoded.visibility.flatMap(ProfileFrameVisibility.init(rawValue:)) ?? .everyone
        ownAvatarURL = decoded.ownAvatar.flatMap(URL.init(string:))
        buildingStatus = decoded.building ?? ""
    }

    private func persist() {
        let payload = Payload(
            frameID: frameID,
            badge: badge?.rawValue,
            presence: presence.rawValue,
            customLabel: customBadgeLabel,
            customHex: customBadgeColorHex,
            visibility: badgeVisibility.rawValue,
            ownAvatar: ownAvatarURL?.absoluteString,
            building: buildingStatus.isEmpty ? nil : buildingStatus
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
        /// Added with arc frames; optional so v1 payloads still decode.
        var visibility: String?
        var ownAvatar: String?
        var building: String?
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
        case shimmer(Color)
        case auroraPulse
        case flame
        case orbit(Color)
        case neonPulse(Color)
        case seasonal(String) // spring/summer/autumn/winter
    }

    enum Rarity: String, Hashable, Sendable {
        case common, uncommon, rare, epic, legendary
        var title: String { rawValue.capitalized }
        var tint: Color {
            switch self {
            case .common: .secondary
            case .uncommon: Color(hex: "#34C759")
            case .rare: Color(hex: "#3478F6")
            case .epic: Color(hex: "#AF52DE")
            case .legendary: Color(hex: "#FF9F0A")
            }
        }
    }

    var rarity: Rarity {
        switch kind {
        case .none, .softRing, .dashed: .common
        case .dualRing, .pixels, .hex, .mascotPaw: .uncommon
        case .gradient, .sparkle, .laurels, .neon, .shimmer: .rare
        case .orbit, .neonPulse, .seasonal: .epic
        case .auroraPulse, .flame: .legendary
        }
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
        .init(id: "anim.shimmer", title: "Shimmer", kind: .shimmer(Color(hex: "#E8D5FF"))),
        .init(id: "anim.aurora", title: "Aurora Live", kind: .auroraPulse),
        .init(id: "anim.flame", title: "Flame", kind: .flame),
        .init(id: "anim.orbit", title: "Orbit", kind: .orbit(Color(hex: "#5AC8FA"))),
        .init(id: "anim.neonpulse", title: "Neon Pulse", kind: .neonPulse(Color(hex: "#00F5FF"))),
        .init(id: "anim.spring", title: "Spring", kind: .seasonal("spring")),
        .init(id: "anim.winter", title: "Winter", kind: .seasonal("winter")),
    ]

    static func frame(id: String) -> ProfileAvatarFrame {
        catalog.first { $0.id == id } ?? .none
    }
}

/// LinkedIn-style "open to" frames. Rendered as a curved arc banner drawn on the avatar
/// ring (`ProfileArcBanner`), never as a separate pill. Raw values are persisted.
enum ProfileStatusBadge: String, CaseIterable, Identifiable, Sendable {
    case openToWork
    case hiring
    case collaborating
    case freelance
    case building
    case mentoring
    case learning
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openToWork: "Open to work"
        case .hiring: "Hiring"
        case .collaborating: "Open to collab"
        case .freelance: "Freelance"
        case .building: "Building"
        case .mentoring: "Mentoring"
        case .learning: "Learning"
        case .custom: "Custom"
        }
    }

    /// Text set along the arc (#OPENTOWORK style).
    func arcLabel(custom: String = "") -> String {
        switch self {
        case .openToWork: return "#OPENTOWORK"
        case .hiring: return "#HIRING"
        case .collaborating: return "#OPENTOCOLLAB"
        case .freelance: return "#FREELANCE"
        case .building: return "#BUILDING"
        case .mentoring: return "#MENTORING"
        case .learning: return "#LEARNING"
        case .custom:
            let trimmed = custom
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
            if trimmed.isEmpty { return "#CUSTOM" }
            return trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
        }
    }

    var detail: String {
        switch self {
        case .openToWork: "Let people know you're looking for your next role."
        case .hiring: "Show you're hiring so candidates reach out."
        case .collaborating: "Invite others to build, write or create with you."
        case .freelance: "Signal you're taking on client work."
        case .building: "Share that you're heads-down shipping something new."
        case .mentoring: "Offer to mentor people earlier in their journey."
        case .learning: "Tell people what you're picking up right now."
        case .custom: "Write your own banner and pick its colour."
        }
    }

    var systemImage: String {
        switch self {
        case .openToWork: "briefcase.fill"
        case .hiring: "person.badge.plus"
        case .collaborating: "person.2.fill"
        case .freelance: "laptopcomputer"
        case .building: "hammer.fill"
        case .mentoring: "graduationcap.fill"
        case .learning: "book.fill"
        case .custom: "tag.fill"
        }
    }

    var defaultColor: Color {
        switch self {
        case .openToWork: Color(hex: "#2E8B3E") // LinkedIn #OPENTOWORK green
        case .hiring: Color(hex: "#7A3FE0") // LinkedIn #HIRING purple
        case .collaborating: Color(hex: "#0A66C2")
        case .freelance: Color(hex: "#0E9A94")
        case .building: Color(hex: "#E8641B")
        case .mentoring: Color(hex: "#D23C86")
        case .learning: Color(hex: "#D99A00")
        case .custom: Color(hex: "#3478F6")
        }
    }

    func resolvedColor(customHex: String) -> Color {
        self == .custom ? Color(hex: customHex) : defaultColor
    }
}

/// Audience for the "open to" frame.
enum ProfileFrameVisibility: String, CaseIterable, Identifiable, Sendable {
    case everyone, followers, onlyMe
    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .followers: "Followers"
        case .onlyMe: "Only me"
        }
    }

    var systemImage: String {
        switch self {
        case .everyone: "globe"
        case .followers: "person.2"
        case .onlyMe: "lock"
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
        case .dualRing, .gradient, .neon, .sparkle, .shimmer, .neonPulse: 6
        case .pixels, .laurels, .hex, .mascotPaw, .orbit, .auroraPulse, .flame, .seasonal: 8
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content()
                // The content may itself be a ModulaAvatar of the signed-in user; the arc
                // is drawn here, so don't let it draw a second one.
                .environment(\.modulaSuppressOwnFrame, true)
                .frame(width: size, height: size)
                .clipShape(Circle())
                // "Open to" frame: curved banner ON the avatar edge (lower-left), under the
                // decorative ring so animated frames stack on top of it.
                .overlay {
                    if showsBadgeChip, let badge {
                        ProfileArcBanner(
                            size: size,
                            label: badge.arcLabel(custom: customBadgeLabel),
                            color: badge == .custom ? customBadgeColor : badge.defaultColor
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(ringPad)
                .background { frameBackground }
                .overlay { frameOverlay }
                .overlay { animatedFrameLayer }

            if presence != .offline {
                // Sit the pip on the circle's 45° edge (inside the frame) so the cover
                // notch / parent clip can never cut it in half.
                presencePip
                    // Centre the pip exactly on the outer ring at 45°: (D/2)(1 - cos45°) from the corner.
                    .offset(x: -((size + ringPad * 2) * 0.1464 - pipSize / 2), y: -((size + ringPad * 2) * 0.1464 - pipSize / 2))
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
        case .shimmer(let color), .neonPulse(let color), .orbit(let color):
            Circle().strokeBorder(color.opacity(0.3), lineWidth: 3)
        case .auroraPulse:
            Circle().strokeBorder(AngularGradient(colors: [.purple, .pink, .cyan, .purple], center: .center), lineWidth: 4)
        case .flame:
            Circle().strokeBorder(Color.orange.opacity(0.4), lineWidth: 3)
        case .seasonal:
            Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 2)
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
                // Smooth dots instead of square pixels (read as a jagged halo at hero size).
                Circle()
                    .fill(color)
                    .frame(width: max(4, size * 0.035), height: max(4, size * 0.035))
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
        case .shimmer, .auroraPulse, .flame, .orbit, .neonPulse, .seasonal:
            EmptyView() // driven by animatedFrameLayer
        }
    }


    @ViewBuilder
    private var animatedFrameLayer: some View {
        let still = ModulaEffectGate.reduceMotion(reduceMotion)
        switch frame.kind {
        case .shimmer(let color):
            TimelineView(.animation(minimumInterval: 1/24, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [color.opacity(0.15), color, color.opacity(0.15)], center: .center, angle: .degrees(t * 80)),
                        lineWidth: 3
                    )
            }
        case .auroraPulse:
            TimelineView(.animation(minimumInterval: 1/24, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [.purple, .pink, .cyan, .mint, .purple], center: .center, angle: .degrees(t * 45)),
                        lineWidth: 4
                    )
                    .shadow(color: .purple.opacity(still ? 0 : 0.35 + 0.25 * sin(t * 2)), radius: 10)
            }
        case .flame:
            TimelineView(.animation(minimumInterval: 1/24, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().strokeBorder(Color.orange.opacity(0.7), lineWidth: 2.5)
                    ForEach(0..<6, id: \.self) { i in
                        Capsule()
                            .fill(LinearGradient(colors: [.yellow, .orange, .red.opacity(0.01)], startPoint: .bottom, endPoint: .top))
                            .frame(width: 5, height: 12 + CGFloat(sin(t * 6 + Double(i))) * 4)
                            .offset(y: -(size / 2 + ringPad + 2))
                            .rotationEffect(.degrees(Double(i) * 60 + (still ? 0 : sin(t * 3 + Double(i)) * 8)))
                    }
                }
            }
        case .orbit(let color):
            TimelineView(.animation(minimumInterval: 1/30, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().strokeBorder(color.opacity(0.35), lineWidth: 1.5)
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .offset(x: (size / 2 + ringPad - 2) * cos(t * (1.2 + Double(i) * 0.25) + Double(i) * 2))
                            .offset(y: (size / 2 + ringPad - 2) * sin(t * (1.2 + Double(i) * 0.25) + Double(i) * 2))
                            .shadow(color: color.opacity(0.8), radius: 4)
                    }
                }
            }
        case .neonPulse(let color):
            TimelineView(.animation(minimumInterval: 1/24, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                let pulse = still ? 0.6 : 0.45 + 0.45 * (0.5 + 0.5 * sin(t * 3))
                Circle()
                    .strokeBorder(color, lineWidth: 2.5)
                    .shadow(color: color.opacity(pulse), radius: 8 + pulse * 10)
                    .shadow(color: color.opacity(pulse * 0.5), radius: 18)
            }
        case .seasonal(let season):
            TimelineView(.animation(minimumInterval: 1/24, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                let symbol = season == "winter" ? "snowflake" : "leaf.fill"
                let tint: Color = season == "winter" ? .cyan : Color(hex: "#34C759")
                ZStack {
                    Circle().strokeBorder(tint.opacity(0.55), lineWidth: 2)
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: symbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(tint)
                            .offset(y: -(size / 2 + ringPad))
                            .rotationEffect(.degrees(Double(i) * 72 + (still ? 0 : t * 20)))
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private var pipSize: CGFloat { max(12, min(size * 0.2, 26)) }

    private var presencePip: some View {
        Circle()
            .fill(presence.color)
            .frame(width: pipSize, height: pipSize)
            .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2.5))
            .accessibilityLabel(presence.title)
    }

}

// MARK: - Editor sheet

/// Frames picker: big live preview, "Open to" arc frames with your real avatar in every
/// thumbnail, custom text + colour, audience, decorative rings, presence, then Apply.
struct ProfileAvatarOverlayEditor: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var store: ProfileAvatarOverlayStore { ProfileAvatarOverlayStore.shared }

    @State private var frameID: String = ProfileAvatarFrame.none.id
    @State private var badge: ProfileStatusBadge?
    @State private var customLabel: String = ""
    @State private var customHex: String = "#3478F6"
    @State private var presence: ProfilePresenceStatus = .offline
    @State private var visibility: ProfileFrameVisibility = .everyone
    @State private var building: String = ""
    @State private var loaded = false
    @Namespace private var selection

    private static let swatches = ["#2E8B3E", "#7A3FE0", "#0A66C2", "#0E9A94", "#E8641B", "#D23C86", "#D99A00", "#1C1C1E"]

    private var reduce: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }
    private var accent: Color { app.appearance.liveAccent }
    private var selectionSpring: Animation? { reduce ? nil : .spring(response: 0.38, dampingFraction: 0.78) }

    private var hasChanges: Bool {
        frameID != store.frameID
            || badge != store.badge
            || presence != store.presence
            || visibility != store.badgeVisibility
            || building.trimmingCharacters(in: .whitespacesAndNewlines) != store.buildingStatus
            || (badge == .custom && (customLabel != store.customBadgeLabel || customHex != store.customBadgeColorHex))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    preview
                    statusSection
                    if badge == .custom {
                        customSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    visibilitySection
                    buildingSection
                    ringSection
                    presenceSection
                    Text("Your frame shows wherever your photo appears in Modula.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { applyBar }
            .modulaCanvas()
            .navigationTitle("Frames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.primary)
                        .foregroundStyle(.primary)
                }
            }
            .onAppear(perform: loadDraft)
        }
        .accessibilityIdentifier("profile.frames")
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 16) {
            ModulaDecoratedAvatar(
                size: 168,
                frame: ProfileAvatarFrame.frame(id: frameID),
                presence: presence,
                badge: badge,
                customBadgeLabel: customLabel,
                customBadgeColor: Color(hex: customHex)
            ) {
                avatarContent(size: 168)
            }
            .animation(selectionSpring, value: badge)
            .animation(selectionSpring, value: frameID)

            VStack(spacing: 4) {
                Text(previewTitle)
                    .font(.title3.weight(.semibold))
                Text(badge?.detail ?? (selectedRing.id == ProfileAvatarFrame.none.id ? "Pick a frame to let people know what you’re up to." : "Ring frame"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(selectionSpring, value: badge)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false, specular: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview, \(previewTitle)")
    }

    private var selectedRing: ProfileAvatarFrame { ProfileAvatarFrame.frame(id: frameID) }

    /// Header mirrors whatever is selected below: banner, ring, or both.
    private var previewTitle: String {
        let ring = selectedRing.id == ProfileAvatarFrame.none.id ? nil : selectedRing.title
        switch (badge?.title, ring) {
        case let (b?, r?): return "\(b) · \(r)"
        case let (b?, nil): return b
        case let (nil, r?): return r
        default: return "No frame"
        }
    }

    @ViewBuilder
    private func avatarContent(size: CGFloat) -> some View {
        if let profile = app.profile.ownProfile {
            ProfileAvatarContent(profile: profile, size: size)
        } else {
            Circle().fill(accent.opacity(0.35))
        }
    }

    // MARK: Open-to frames

    private var statusSection: some View {
        section("Open to", subtitle: "A curved banner on your photo, like #OPENTOWORK.") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    statusThumb(nil)
                    ForEach(ProfileStatusBadge.allCases) { item in
                        statusThumb(item)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func statusThumb(_ item: ProfileStatusBadge?) -> some View {
        let selected = badge == item
        return Button {
            withAnimation(selectionSpring) { badge = item }
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 6) {
                ModulaDecoratedAvatar(
                    size: 64,
                    frame: ProfileAvatarFrame.none,
                    presence: .offline,
                    badge: item,
                    customBadgeLabel: customLabel,
                    customBadgeColor: Color(hex: customHex)
                ) {
                    avatarContent(size: 64)
                }
                .padding(5)
                .background {
                    if selected {
                        Circle()
                            .strokeBorder(accent, lineWidth: 2.5)
                            .matchedGeometryEffect(id: "status.selection", in: selection)
                    }
                }
                Text(item?.title ?? "None")
                    .font(.caption.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 80, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
        .accessibilityLabel(item?.title ?? "No frame")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("profile.frames.status.\(item?.rawValue ?? "none")")
    }

    private var customSection: some View {
        section("Custom banner", subtitle: "Up to 28 characters. Spaces are removed on the arc.") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("e.g. Open to speak", text: $customLabel)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .onChange(of: customLabel) { _, value in
                        if value.count > 28 { customLabel = String(value.prefix(28)) }
                    }
                    .accessibilityIdentifier("profile.frames.customText")
                HStack(spacing: 10) {
                    ForEach(Self.swatches, id: \.self) { hex in
                        Button {
                            customHex = hex
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: customHex == hex ? 2 : 0))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(customHex == hex ? 0.5 : 0), lineWidth: 1).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(hex)")
                        .accessibilityAddTraits(customHex == hex ? .isSelected : [])
                    }
                    ColorPicker(
                        "Custom colour",
                        selection: Binding(
                            get: { Color(hex: customHex) },
                            set: { customHex = Self.hexString($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: Audience

    private var visibilitySection: some View {
        section("Who sees your frame", subtitle: visibility == .onlyMe ? "Shown only on your own profile page." : nil) {
            HStack(spacing: 4) {
                ForEach(ProfileFrameVisibility.allCases) { option in
                    let selected = option == visibility
                    Button {
                        withAnimation(selectionSpring) { visibility = option }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label(option.title, systemImage: option.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(accent)
                                        .shadow(color: accent.opacity(0.3), radius: 6, y: 2)
                                        .matchedGeometryEffect(id: "visibility.pill", in: selection)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .modulaGlass(in: Capsule(), interactive: false)
            .disabled(badge == nil)
            .opacity(badge == nil ? 0.5 : 1)
        }
    }

    // MARK: Rings

    private var ringSection: some View {
        section("Ring", subtitle: "Animated rings stack with your banner.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                ForEach(ProfileAvatarFrame.catalog) { item in
                    let selected = frameID == item.id
                    Button {
                        withAnimation(selectionSpring) { frameID = item.id }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        VStack(spacing: 6) {
                            ModulaDecoratedAvatar(
                                size: 46,
                                frame: item,
                                presence: .offline,
                                showsBadgeChip: false
                            ) {
                                avatarContent(size: 46)
                            }
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(selected ? accent : Color.secondary)
                                .lineLimit(1)
                            Text(item.rarity.title)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(item.rarity.tint)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selected ? accent.opacity(0.14) : Color.primary.opacity(0.04))
                        }
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(accent.opacity(0.6), lineWidth: 1.5)
                                    .matchedGeometryEffect(id: "ring.selection", in: selection)
                            }
                        }
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Presence

    private var presenceSection: some View {
        section("Presence", subtitle: nil) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ProfilePresenceStatus.allCases) { status in
                        Button {
                            presence = status
                            HapticEngine.shared.play(.selection)
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(status.color).frame(width: 10, height: 10)
                                Text(status.title).font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                Capsule().fill(presence == status ? status.color.opacity(0.18) : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(presence == status ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Apply

    private var applyBar: some View {
        Button(action: apply) {
            Text(hasChanges ? "Apply" : "Done")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
        .background(accent, in: Capsule())
        .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom)
                .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
        }
        .accessibilityIdentifier("profile.frames.apply")
    }

    private func apply() {
        if hasChanges {
            store.apply(
                frameID: frameID,
                badge: badge,
                customLabel: customLabel,
                customHex: customHex,
                presence: presence,
                visibility: visibility
            )
            store.setBuildingStatus(building)
            HapticEngine.shared.play(.success)
            app.navigation.flash(badge == nil ? "Frame removed" : "Frame applied", symbol: "person.crop.circle.badge.checkmark")
        }
        dismiss()
    }

    private func loadDraft() {
        store.bind(accountID: app.auth.account?.accountId)
        guard !loaded else { return }
        loaded = true
        frameID = store.frameID
        badge = store.badge
        customLabel = store.customBadgeLabel
        customHex = store.customBadgeColorHex
        presence = store.presence
        visibility = store.badgeVisibility
        building = store.buildingStatus
    }

    private var buildingSection: some View {
        section("Currently building", subtitle: "A status line with a live dot under your name. Leave empty to hide it.") {
            HStack(spacing: 10) {
                ProfileLiveDot(color: .green)
                TextField("e.g. a habit tracker module", text: $building)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onChange(of: building) { _, value in
                        if value.count > 60 { building = String(value.prefix(60)) }
                    }
                if !building.isEmpty {
                    Button {
                        building = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear status")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .modulaGlass(in: Capsule(), interactive: true)
            .accessibilityIdentifier("profile.frames.building")
        }
    }

    private func section<Content: View>(_ title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private static func hexString(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}


/// Animated particles / aurora wash for profile cover headers. Frozen under Reduce Motion.
struct ProfileBannerFX: View {
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let still = ModulaEffectGate.reduceMotion(reduceMotion)
        TimelineView(.animation(minimumInterval: 1/24, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.35), .clear, Color.pink.opacity(0.2)],
                    startPoint: UnitPoint(x: 0.2 + 0.1 * sin(t * 0.4), y: 0),
                    endPoint: UnitPoint(x: 0.8, y: 1)
                )
                ForEach(0..<10, id: \.self) { i in
                    Circle()
                        .fill(i.isMultiple(of: 2) ? accent.opacity(0.55) : Color.white.opacity(0.45))
                        .frame(width: CGFloat(3 + i % 3), height: CGFloat(3 + i % 3))
                        .offset(
                            x: CGFloat(sin(t * 0.7 + Double(i)) * 140),
                            y: CGFloat(cos(t * 0.5 + Double(i) * 0.7) * 40) - 20
                        )
                        .blur(radius: still ? 0 : 0.5)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Arc frames ("open to" banner on the avatar ring)

/// LinkedIn-style curved banner drawn ON the avatar: a colour band hugging the lower-left
/// of the circle that fades out at both ends, with the label set along the arc.
/// Never a separate pill, so it can't collide with the name or handle.
struct ProfileArcBanner: View {
    var size: CGFloat
    var label: String
    var color: Color
    /// Text is only legible from ~56pt up; smaller avatars show the band alone.
    var showsText: Bool = true

    /// Screen-space degrees (0° = right, 90° = bottom): bottom-right round to upper-left.
    static let startDegrees: Double = 28
    static let endDegrees: Double = 222

    var body: some View {
        let band = max(3.5, size * 0.19)
        let radius = size / 2 - band / 2
        ZStack {
            ProfileArcBandShape(startDegrees: Self.startDegrees, endDegrees: Self.endDegrees, inset: band / 2)
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: color.opacity(0), location: 0),
                            .init(color: color, location: 0.22),
                            .init(color: color, location: 0.84),
                            .init(color: color.opacity(0), location: 1)
                        ],
                        center: .center,
                        startAngle: .degrees(Self.startDegrees),
                        endAngle: .degrees(Self.endDegrees)
                    ),
                    style: StrokeStyle(lineWidth: band, lineCap: .butt)
                )
            if showsText && size >= 56 {
                ProfileArcText(text: label, radius: radius, size: size, fontSize: band * 0.62)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.replacingOccurrences(of: "#", with: ""))
    }
}

/// Open arc along the circle (sampled points, so direction is unambiguous).
struct ProfileArcBandShape: Shape {
    var startDegrees: Double
    var endDegrees: Double
    var inset: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - inset
        let steps = 56
        for index in 0...steps {
            let t = Double(index) / Double(steps)
            let angle = (startDegrees + (endDegrees - startDegrees) * t) * Double.pi / 180
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Upright glyphs laid along the band, reading from the left side down round the bottom.
struct ProfileArcText: View {
    var text: String
    var radius: CGFloat
    var size: CGFloat
    var fontSize: CGFloat
    /// Middle of the label on the circle (lower-left).
    var centerDegrees: Double = 132

    private struct Glyph: Identifiable {
        let id: Int
        let character: String
        let degrees: Double
    }

    var body: some View {
        let layout = glyphLayout()
        ZStack {
            ForEach(layout.glyphs) { glyph in
                let radians = glyph.degrees * Double.pi / 180
                Text(glyph.character)
                    .font(.system(size: layout.font, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 0.6, y: 0.4)
                    .fixedSize()
                    .rotationEffect(.degrees(glyph.degrees - 90))
                    .position(
                        x: size / 2 + radius * CGFloat(cos(radians)),
                        y: size / 2 + radius * CGFloat(sin(radians))
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func glyphLayout() -> (glyphs: [Glyph], font: CGFloat) {
        let characters = Array(text).map(String.init)
        guard !characters.isEmpty, radius > 0 else { return ([], fontSize) }
        let tracking: CGFloat = 0.06
        func advance(_ character: String) -> CGFloat {
            switch character {
            case "I", "1", "!", ".", ",", "'": return 0.34
            case "M", "W": return 0.9
            case "#": return 0.72
            default: return 0.7
            }
        }
        var font = fontSize
        var widths = characters.map { advance($0) * font }
        var total = widths.reduce(0, +) + CGFloat(characters.count - 1) * font * tracking
        // Keep the label inside the visible part of the band (~150° of arc).
        let maxSpan = radius * CGFloat(150 * Double.pi / 180)
        if total > maxSpan {
            let scale = maxSpan / total
            font *= scale
            widths = widths.map { $0 * scale }
            total = maxSpan
        }
        // Reading direction runs from higher angles (left side) toward lower angles (bottom).
        var cursor: CGFloat = 0
        let startDegrees = centerDegrees + Double(total / radius) * 180 / Double.pi / 2
        var glyphs: [Glyph] = []
        for (index, character) in characters.enumerated() {
            let middle = cursor + widths[index] / 2
            let degrees = startDegrees - Double(middle / radius) * 180 / Double.pi
            glyphs.append(Glyph(id: index, character: character, degrees: degrees))
            cursor += widths[index] + font * tracking
        }
        return (glyphs, font)
    }
}

// MARK: - Own-avatar decoration everywhere

private struct ModulaSuppressOwnFrameKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set inside views that already draw the signed-in user's frame (the profile pocket,
    /// the Frames picker) so `ModulaAvatar` doesn't add a second arc.
    var modulaSuppressOwnFrame: Bool {
        get { self[ModulaSuppressOwnFrameKey.self] }
        set { self[ModulaSuppressOwnFrameKey.self] = newValue }
    }
}

/// Drawn by `ModulaAvatar` over the signed-in user's own photo (posts, comments, stories
/// ring, composer…) so the "open to" arc is consistent everywhere. On-device only:
/// other people see it once the profile API stores frames.
struct ProfileOwnAvatarArcOverlay: View {
    var size: CGFloat
    @Environment(AppEnvironment.self) private var app

    private var store: ProfileAvatarOverlayStore { ProfileAvatarOverlayStore.shared }

    var body: some View {
        Color.clear
            .overlay {
                if let badge = store.badge, store.badgeVisibility != .onlyMe {
                    ProfileArcBanner(
                        size: size,
                        label: badge.arcLabel(custom: store.customBadgeLabel),
                        color: badge.resolvedColor(customHex: store.customBadgeColorHex),
                        showsText: size >= 56
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { store.bind(accountID: app.auth.account?.accountId) }
    }
}


// MARK: - Profile glow + building status

/// Slow light sweep around an avatar wearing an active frame. Static glow with Reduce Motion.
struct ProfileFrameShimmer: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var spin = false

    var body: some View {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [.clear, .clear, color.opacity(0.5), .white.opacity(0.9), color.opacity(0.8), .clear, .clear],
                    center: .center
                ),
                lineWidth: 3
            )
            .rotationEffect(.degrees(spin ? 360 : 0))
            .blur(radius: 1)
            .shadow(color: color.opacity(0.5), radius: 8)
            .opacity(calm ? 0.4 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !calm else { return }
                withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

/// Pulsing "live" dot.
struct ProfileLiveDot: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var pulse = false

    var body: some View {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 16, height: 16)
                .scaleEffect(pulse ? 1.25 : 0.6)
                .opacity(pulse ? 0 : 0.9)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 3)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        .onAppear {
            guard !calm else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// "Building …" line under the profile identity (own profile; on-device for now).
struct ProfileBuildingStatusLine: View {
    let text: String
    var onEdit: (() -> Void)? = nil

    var body: some View {
        Button {
            onEdit?()
        } label: {
            HStack(spacing: 8) {
                ProfileLiveDot(color: .green)
                (Text("Building ").foregroundStyle(.secondary) + Text(text).fontWeight(.semibold))
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .modulaGlass(in: Capsule(), interactive: onEdit != nil)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: .selection))
        .disabled(onEdit == nil)
        .accessibilityLabel("Currently building \(text)")
        .accessibilityIdentifier("profile.building")
    }
}


/// Primary profile CTA (Edit profile) is a solid, clearly-enabled fill — glass over a pale
/// avatar tint read as disabled. Secondary pills stay Liquid Glass.
private struct ProfilePillSurface: ViewModifier {
    var prominent: Bool
    var tint: Color

    func body(content: Content) -> some View {
        if prominent {
            // Same filled accent CTA as the rest of the app (was a darkened cover tint).
            content.modulaAccentCTA()
        } else {
            content.modulaGlass(in: Capsule(), interactive: true, specular: true)
        }
    }
}
