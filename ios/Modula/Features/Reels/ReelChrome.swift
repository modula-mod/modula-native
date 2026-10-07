import SwiftUI

// MARK: - TikTok-style right rail

struct ReelTikTokRail: View {
    let reel: Reel
    let post: SocialPost
    var onComment: () -> Void
    var onShare: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var following = false
    @State private var followBusy = false
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            creator
            railButton(post.liked ? "heart.fill" : "heart", count: max(post.likeCount, post.reactionCount), active: post.liked, tint: .pink) {
                Task { await app.postActions.toggleLike(post) }
                HapticEngine.shared.play(.lightImpact)
            }
            railButton("bubble.right", count: post.replyCount, active: false) { onComment() }
            railButton(post.saved ? "bookmark.fill" : "bookmark", count: 0, active: post.saved, tint: .yellow) {
                Task { await app.postActions.toggleSave(post) }
            }
            railButton("square.and.arrow.up", count: 0, active: false) { onShare() }
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
            if !following {
                Button {
                    guard !followBusy else { return }
                    followBusy = true
                    Task {
                        let ok = await app.profile.follow(profileID: reel.creator.id, handle: reel.creator.handle)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { following = ok }
                        followBusy = false
                        if ok { HapticEngine.shared.play(.followComplete) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(app.appearance.accent.color))
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .offset(y: 10)
                .accessibilityLabel("Follow \(reel.creator.displayName)")
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
        .rotationEffect(.degrees(spin && !ModulaEffectGate.reduceMotion(reduceMotion) ? 360 : 0))
        .animation(ModulaEffectGate.reduceMotion(reduceMotion) ? nil : .linear(duration: 4).repeatForever(autoreverses: false), value: spin)
        .onAppear { spin = true }
        .accessibilityLabel(title)
    }

    private func railButton(_ symbol: String, count: Int, active: Bool, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(active ? tint : .white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                    .symbolEffect(.bounce, value: active)
                if count > 0 {
                    Text(ModulaCountFormat.compact(count) ?? "\(count)")
                        .font(.caption2.weight(.semibold))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
            .frame(width: 52)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.88, haptic: .selection))
    }
}

// MARK: - Caption + music marquee

struct ReelCaptionBlock: View {
    let reel: Reel
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
            if let caption = reel.caption, !caption.isEmpty {
                Button {
                    withAnimation(ModulaEffectGate.reduceMotion(reduceMotion) ? nil : .snappy) { expanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(expanded ? 12 : 2)
                            .multilineTextAlignment(.leading)
                        if caption.count > 80 {
                            Text(expanded ? "less" : "more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if !hashtags.isEmpty {
                Text(hashtags.prefix(6).joined(separator: " "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
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
            TimelineView(.animation(minimumInterval: 1/30, paused: ModulaEffectGate.reduceMotion(reduceMotion))) { context in
                let t = ModulaEffectGate.reduceMotion(reduceMotion) ? 0 : context.date.timeIntervalSinceReferenceDate
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .offset(x: -CGFloat(t.truncatingRemainder(dividingBy: 8) / 8) * 120)
            }
            .frame(maxWidth: 200, alignment: .leading)
            .clipped()
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
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Playback").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                Button {
                    onRate(Float(value)); onDismiss()
                } label: {
                    HStack {
                        Text(value == 1 ? "Normal" : String(format: "%.1g×", value))
                        Spacer()
                        if abs(Double(rate) - value) < 0.05 {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.vertical, 4)
            Button { onNotInterested(); onDismiss() } label: {
                Label("Not interested", systemImage: "eye.slash").padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
            Button { onSave(); onDismiss() } label: {
                Label("Save video", systemImage: "bookmark").padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
            Button { onToggleCaptions(); onDismiss() } label: {
                Label(captionsOn ? "Captions on" : "Captions off", systemImage: "captions.bubble").padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
            Button { onToggleClear(); onDismiss() } label: {
                Label(clearDisplay ? "Show UI" : "Clear display", systemImage: "eye").padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
        }
        .padding(.bottom, 10)
        .frame(width: 260)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

// MARK: - Following / For You tabs

struct ReelFeedTabs: View {
    @Binding var tab: ReelFeedTab
    var body: some View {
        HStack(spacing: 18) {
            ForEach(ReelFeedTab.allCases) { item in
                Button {
                    withAnimation(.snappy) { tab = item }
                    HapticEngine.shared.play(.selection)
                } label: {
                    VStack(spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(tab == item ? .bold : .semibold))
                            .foregroundStyle(.white.opacity(tab == item ? 1 : 0.55))
                        Capsule()
                            .fill(.white)
                            .frame(width: tab == item ? 28 : 0, height: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
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
