import SwiftUI

// MARK: - TikTok-style right rail

struct ReelTikTokRail: View {
    let reel: Reel
    let post: SocialPost
    var isPlaying: Bool = true
    var onComment: () -> Void
    var onShare: () -> Void
    /// Long-press on Like: opens the shared reaction strip next to it (global frame of the heart).
    var onReactionsRequested: ((CGRect) -> Void)? = nil
    @Environment(AppEnvironment.self) private var app
    @State private var heartFrame: CGRect = .zero
    @State private var suppressLikeTap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var following = false
    @State private var followBusy = false
    /// Brief "followed" confirmation: the + morphs into a checkmark, then the badge leaves.
    @State private var justFollowed = false

    var body: some View {
        // One white SF Symbol family, same size/weight/shadow, count under each (TikTok spacing).
        // Only the like heart takes colour when active; Save fills white (no yellow).
        VStack(spacing: 14) {
            creator
            railButton("heart.fill", count: max(post.likeCount, post.reactionCount), active: post.liked, tint: .red, label: post.liked ? "Unlike" : "Like") {
                // The release after a long-press (strip opened) must not also toggle the like.
                if suppressLikeTap { suppressLikeTap = false; return }
                Task { await app.postActions.toggleLike(post) }
                HapticEngine.shared.play(.lightImpact)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { heartFrame = $0 }
            // Quick taps finish long before 0.4 s, so this never delays a normal like.
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard let onReactionsRequested else { return }
                suppressLikeTap = true
                HapticEngine.shared.play(.contextOpen)
                onReactionsRequested(heartFrame)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    suppressLikeTap = false
                }
            })
            .accessibilityAction(named: "React") { onReactionsRequested?(heartFrame) }
            railButton("bubble.right.fill", count: post.replyCount, active: false, label: "Comments", id: "ellipsis.bubble.fill") { onComment() }
            railButton(post.saved ? "bookmark.fill" : "bookmark", count: 0, active: post.saved, label: post.saved ? "Unsave" : "Save", id: "bookmark.fill") {
                Task { await app.postActions.toggleSave(post) }
            }
            railButton("paperplane.fill", count: 0, active: false, label: "Share", id: "arrowshape.turn.up.right.fill") { onShare() }
            soundDisc
        }
        .foregroundStyle(.white)
        .padding(.trailing, 10)
        .padding(.bottom, 24)
    }

    private var creator: some View {
        ZStack(alignment: .bottom) {
            Button {
                app.navigation.push(.profile(reel.creator.routeID, .overview))
                HapticEngine.shared.play(.navigation)
            } label: {
                ModulaAvatar(initials: reel.creator.initials, url: reel.creator.avatarURL, size: 48, name: reel.creator.displayName)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reels.avatar")
            if !following {
                Button {
                    guard !followBusy else { return }
                    followBusy = true
                    Task {
                        let ok = await app.profile.follow(profileID: reel.creator.id, handle: reel.creator.handle)
                        followBusy = false
                        guard ok else { return }
                        HapticEngine.shared.play(.followComplete)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { justFollowed = true }
                        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 850))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { following = true }
                    }
                } label: {
                    // White badge, black glyph (never accent/coral). Hit area padded to 44 pt.
                    Image(systemName: justFollowed ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white))
                        .scaleEffect(justFollowed && !reduceMotion ? 1.12 : 1)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(y: 21)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .disabled(justFollowed)
                .accessibilityLabel(justFollowed ? "Following \(reel.creator.displayName)" : "Follow \(reel.creator.displayName)")
                .accessibilityIdentifier("reels.follow")
            }
        }
        .padding(.bottom, 8)
    }

    private var soundDisc: some View {
        let title = reel.audio?.title ?? "Original audio"
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .semibold))
            ModulaAvatar(initials: reel.creator.initials, url: reel.creator.avatarURL, size: 18)
                .clipShape(Circle())
        }
        // Spins only while the video is actually playing; static under Reduce Motion.
        .modifier(DiscSpin(active: isPlaying && !ModulaEffectGate.reduceMotion(reduceMotion)))
        .accessibilityLabel(title)
    }

    private func railButton(_ symbol: String, count: Int, active: Bool, tint: Color = .white, label: String, id: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(active ? tint : .white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                    .symbolEffect(.bounce, value: active)
                    .frame(width: 44, height: 40)
                // Always reserve the count line so rail spacing stays even.
                Text(count > 0 ? (ModulaCountFormat.compact(count) ?? "\(count)") : " ")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .contentTransition(.numericText())
            }
            .frame(width: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.88, haptic: .selection))
        .accessibilityLabel(label)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityIdentifier("reels.rail.\(id ?? symbol)")
    }
}

// MARK: - Caption + music marquee

struct ReelCaptionBlock: View {
    let reel: Reel
    var showsCaption = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var hashtags: [String] {
        guard let text = reel.caption else { return [] }
        return text.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
            let t = String(token)
            return t.hasPrefix("#") && t.count > 1 ? t : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                appOpenProfile()
            } label: {
                Text("@\(reel.creator.handle)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            if showsCaption, let caption = reel.caption, !caption.isEmpty {
                Button {
                    withAnimation(ModulaEffectGate.reduceMotion(reduceMotion) ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { expanded.toggle() }
                    HapticEngine.shared.play(.selection)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        // Expanded: scrolls inside a capped height instead of pushing the rail off.
                        if expanded {
                            ScrollView(.vertical) {
                                Text(caption)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight: 220)
                        } else {
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        if caption.count > 80 {
                            Text(expanded ? "less" : "more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .contentTransition(.opacity)
                        }
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                    .padding(expanded ? 10 : 0)
                    .background {
                        // Legibility backing only while expanded (cheap: a flat colour, no blur).
                        if expanded {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.38))
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Collapses the caption" : "Shows the full caption")
                .transition(.opacity)
            }
            if showsCaption, !hashtags.isEmpty {
                // Tappable hashtags → Search (was static text).
                HStack(spacing: 6) {
                    ForEach(Array(hashtags.prefix(4)), id: \.self) { tag in
                        Button {
                            app.navigation.push(.search(.root(tag)))
                            HapticEngine.shared.play(.navigation)
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search \(tag)")
                    }
                }
            }
            musicMarquee
        }
        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }

    @Environment(AppEnvironment.self) private var app
    private func appOpenProfile() {
        app.navigation.push(.profile(reel.creator.routeID, .overview))
        HapticEngine.shared.play(.navigation)
    }

    private var musicMarquee: some View {
        let title = reel.audio.map { a in a.artist.map { "\($0) · \(a.title)" } ?? a.title } ?? "Original audio · \(reel.creator.displayName)"
        return HStack(spacing: 6) {
            Image(systemName: "music.note").font(.caption.weight(.bold))
            ReelMarqueeText(text: title, reduceMotion: ModulaEffectGate.reduceMotion(reduceMotion))
                .frame(width: 180, alignment: .leading)
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

// MARK: - Long-press quick menu

struct ReelQuickMenu: View {
    var rate: Float
    var captionsOn: Bool
    var clearDisplay: Bool
    var onRate: (Float) -> Void
    var onNotInterested: () -> Void
    var onSave: () -> Void
    var onToggleCaptions: () -> Void
    var onToggleClear: () -> Void
    var autoScroll = false
    var onToggleAutoScroll: () -> Void = {}
    var onCopyLink: (() -> Void)? = nil
    /// Keep watching in the floating dock / system Picture in Picture (nil hides the row).
    var onMiniPlayer: (() -> Void)? = nil
    var onPictureInPicture: (() -> Void)? = nil
    var onCopyCaption: (() -> Void)? = nil
    /// Remix / Duet: shown, but gated until the server can create derived reels.
    var onRemix: (() -> Void)? = nil
    var onSleepTimer: ((Int) -> Void)? = nil
    var sleepMinutesLeft: Int? = nil
    var onDismiss: () -> Void

    private static let rates: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        // Compact Notes-style menu: a row of three icon actions, then a short list with normal
        // row heights. Speed is a picker in the first tile instead of four separate rows.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Playback speed", selection: Binding(
                        get: { Self.rates.min(by: { abs($0 - Double(rate)) < abs($1 - Double(rate)) }) ?? 1 },
                        set: { onRate(Float($0)); onDismiss() }
                    )) {
                        ForEach(Self.rates, id: \.self) { value in
                            Text(value == 1 ? "Normal" : String(format: "%g×", value)).tag(value)
                        }
                    }
                } label: {
                    tile(abs(rate - 1) < 0.01 ? "Speed" : String(format: "%g×", Double(rate)), symbol: "gauge.with.needle")
                }
                .accessibilityLabel("Playback speed")
                .accessibilityValue(String(format: "%g times", Double(rate)))
                .accessibilityIdentifier("reels.menu.speed")
                Button { onSave(); onDismiss() } label: { tile("Save", symbol: "bookmark") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reels.menu.save")
                if let onCopyLink {
                    Button { onCopyLink(); onDismiss() } label: { tile("Copy link", symbol: "link") }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reels.menu.copylink")
                }
            }
            .padding(8)

            Divider().padding(.horizontal, 12)

            VStack(spacing: 0) {
                if let onMiniPlayer {
                    row("Mini player", symbol: "rectangle.inset.bottomright.filled", id: "reels.menu.miniplayer", action: onMiniPlayer)
                }
                if let onPictureInPicture {
                    row("Picture in Picture", symbol: "pip.enter", id: "reels.menu.pip", action: onPictureInPicture)
                }
                row("Captions", symbol: "captions.bubble", checked: captionsOn, id: "reels.menu.captions", action: onToggleCaptions)
                row(clearDisplay ? "Show controls" : "Clear display", symbol: "eye", id: "reels.menu.clear", action: onToggleClear)
                row("Auto-scroll", symbol: "arrow.down.to.line.circle", checked: autoScroll, id: "reels.menu.autoscroll", action: onToggleAutoScroll)
                    .accessibilityHint("Moves to the next reel when a video ends")
                if let onSleepTimer {
                    Menu {
                        ForEach([15, 30, 45, 60], id: \.self) { m in
                            Button("\(m) minutes") { onSleepTimer(m); onDismiss() }
                        }
                        if sleepMinutesLeft != nil {
                            Button("Turn Off", systemImage: "xmark", role: .destructive) { onSleepTimer(0); onDismiss() }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(sleepMinutesLeft.map { "Sleep timer · \($0) min" } ?? "Sleep timer").font(.body).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 8)
                            Image(systemName: "moon.zzz").font(.body).frame(width: 22)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("reels.menu.sleep")
                }
                if let onCopyCaption {
                    row("Copy caption", symbol: "text.quote", id: "reels.menu.copycaption", action: onCopyCaption)
                }
                if let onRemix {
                    row("Remix or Duet", symbol: "rectangle.split.2x1", id: "reels.menu.remix", action: onRemix)
                        .opacity(0.55)
                        .accessibilityHint("Not available yet")
                }
            }
            .padding(.vertical, 4)

            Divider().padding(.horizontal, 12)

            row("Not interested", symbol: "eye.slash", id: "reels.menu.notinterested", action: onNotInterested)
                .padding(.vertical, 4)
        }
        .frame(width: 270)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
    }

    private func tile(_ title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, symbol: String, checked: Bool? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button { action(); onDismiss() } label: {
            HStack(spacing: 12) {
                Text(title).font(.body).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if checked == true {
                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold))
                }
                Image(systemName: symbol).font(.body).frame(width: 22)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked == true ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - Following / For You tabs

struct ReelFeedTabs: View {
    @Binding var tab: ReelFeedTab
    var body: some View {
        // Shared segmented control, forced dark so it reads over video.
        ModulaSegmentedControl("Reels feed", selection: $tab, options: ReelFeedTab.allCases, compact: true,
                               identifier: { "reels.tab.\($0.rawValue)" }) { $0.title }
            .fixedSize()
            .environment(\.colorScheme, .dark)
    }
}

enum ReelFeedTab: String, CaseIterable, Identifiable {
    case following, forYou
    var id: Self { self }
    var title: String { self == .following ? "Following" : "For You" }
}

// MARK: - Loading shimmer

struct ReelLoadingShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Color.black
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Capsule().fill(.white.opacity(0.15)).frame(width: 120, height: 14)
                        Capsule().fill(.white.opacity(0.1)).frame(width: 200, height: 12)
                        Capsule().fill(.white.opacity(0.1)).frame(width: 160, height: 12)
                    }
                    Spacer()
                    VStack(spacing: 16) {
                        Circle().fill(.white.opacity(0.15)).frame(width: 48, height: 48)
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule().fill(.white.opacity(0.12)).frame(width: 36, height: 36)
                        }
                    }
                }
                .padding(24)
            }
        }
        .ignoresSafeArea()
        .modulaShimmer(!ModulaEffectGate.reduceMotion(reduceMotion))
        .accessibilityLabel("Loading reels")
    }
}

/// Continuous rotation that pauses in place when playback pauses.
private struct DiscSpin: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let angle = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5)) / 5 * 360
            content.rotationEffect(.degrees(active ? angle : 0))
        }
    }
}

/// Seamless looping marquee: scrolls only when the text is wider than the box.
struct ReelMarqueeText: View {
    let text: String
    var reduceMotion: Bool
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    private let gap: CGFloat = 36
    private let speed: Double = 28

    var body: some View {
        let overflow = textWidth > boxWidth && boxWidth > 0 && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !overflow)) { context in
            let cycle = Double(textWidth + gap)
            let offset = overflow ? (context.date.timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: max(cycle, 1)) : 0
            HStack(spacing: gap) {
                label
                if overflow { label }
            }
            .offset(x: -offset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }
}
