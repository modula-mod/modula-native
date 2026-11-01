import SwiftUI
import UIKit

// Enhancements-50: shared micro-interaction / state primitives. Kept in their own file so
// feature streams only touch one-line call sites. Every primitive honours Reduce Motion
// (system + Modula's extra reduction) and Reduce Transparency, uses design tokens, and
// renders buttons through `modulaAccentCTA`.

// MARK: - Skeleton loader

/// Content-shaped placeholder rows with the shared shimmer. Static under Reduce Motion.
/// Replaces bare spinners so layout doesn't jump when real rows land (perceived performance).
struct ModulaSkeletonList: View {
    var title: String = "Loading…"
    var rows: Int = 4
    var showsMedia: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
            ForEach(0..<rows, id: \.self) { index in
                ModulaSkeletonRow(showsMedia: showsMedia && index % 2 == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ModulaSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct ModulaSkeletonRow: View {
    var showsMedia = false
    @ScaledMetric(relativeTo: .body) private var avatar: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var line: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            HStack(spacing: ModulaSpacing.sm) {
                Circle().frame(width: avatar, height: avatar)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().frame(width: 140, height: line)
                    Capsule().frame(width: 90, height: line * 0.8)
                }
            }
            Capsule().frame(maxWidth: .infinity).frame(height: line)
            Capsule().frame(maxWidth: 220).frame(height: line)
            if showsMedia {
                RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous)
                    .frame(maxWidth: .infinity).frame(height: 160)
            }
        }
        .foregroundStyle(Color.secondary.opacity(0.18))
        .modulaShimmer()
    }
}

extension View {
    /// Shows skeleton rows instead of `self` while `isLoading`.
    @ViewBuilder func modulaSkeleton(_ isLoading: Bool, rows: Int = 3, title: String = "Loading…") -> some View {
        if isLoading { ModulaSkeletonList(title: title, rows: rows) } else { self }
    }
}

// MARK: - Error / retry

/// Error state with an accent retry CTA, an in-flight spinner, offline-aware copy and an
/// automatic retry when connectivity returns. VoiceOver announces the failure once.
struct ModulaRetryState: View {
    var message: String
    var retry: (() -> Void)?
    @State private var net = Lab30Connectivity.shared
    @State private var retrying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ContentUnavailableView {
            Label(net.isOnline ? "Something went wrong" : "You're offline",
                  systemImage: net.isOnline ? "exclamationmark.triangle" : "wifi.slash")
                .symbolEffect(.bounce, options: .nonRepeating, isActive: !ModulaEffectGate.reduceMotion(reduceMotion))
        } description: {
            Text(net.isOnline ? message : "We'll retry automatically when you're back online.")
        } actions: {
            if let retry {
                Button {
                    HapticEngine.shared.play(.lightImpact)
                    retrying = true
                    retry()
                    Task { try? await Task.sleep(for: .seconds(1.2)); retrying = false }
                } label: {
                    HStack(spacing: ModulaSpacing.xs) {
                        if retrying { ProgressView().tint(.white) } else { Image(systemName: "arrow.clockwise") }
                        Text("Try Again")
                    }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, ModulaSpacing.lg)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .modulaAccentCTA()
                .disabled(retrying)
                .accessibilityHint("Reloads this content")
            }
        }
        .onAppear {
            HapticEngine.shared.play(.warning)
            UIAccessibility.post(notification: .announcement, argument: net.isOnline ? message : "You're offline")
        }
        .onChange(of: net.isOnline) { _, online in
            if online, let retry { retry() }
        }
    }
}

// MARK: - Tab reselect → scroll to top

enum ModulaTabReselect {
    static let notification = Notification.Name("modula.tab.reselected")
    /// Posts a "scroll to top" request for the given tab (keyboard ⌘↑ or tab re-tap).
    @MainActor static func post(_ tab: AppTab) {
        NotificationCenter.default.post(name: notification, object: tab.rawValue)
    }
}

/// Drop inside a ScrollView's content. Finds the enclosing UIScrollView and scrolls it to the
/// top when its tab is re-tapped while already at the root (status-bar style, Jakob's law).
private struct ScrollTopHook: UIViewRepresentable {
    var tab: AppTab
    var reduceMotion: Bool
    func makeUIView(context: Context) -> HookView { HookView() }
    func updateUIView(_ view: HookView, context: Context) {
        view.tab = tab
        view.animated = !reduceMotion
    }

    final class HookView: UIView {
        var tab: AppTab = .home
        var animated = true
        private var token: NSObjectProtocol?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if window != nil, token == nil {
                token = NotificationCenter.default.addObserver(forName: ModulaTabReselect.notification, object: nil, queue: .main) { [weak self] note in
                    let raw = note.object as? String
                    MainActor.assumeIsolated { self?.handle(raw) }
                }
            } else if window == nil, let token {
                NotificationCenter.default.removeObserver(token)
                self.token = nil
            }
        }
        private func handle(_ raw: String?) {
            guard raw == tab.rawValue, let window else { return }
            var node: UIView? = superview
            while let current = node, !(current is UIScrollView) { node = current.superview }
            guard let scroll = node as? UIScrollView else { return }
            let frame = scroll.convert(scroll.bounds, to: window)
            guard frame.intersects(window.bounds), !scroll.isHidden else { return }
            let top = CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top)
            guard scroll.contentOffset.y > top.y + 1 else { return }
            scroll.setContentOffset(top, animated: animated)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

private struct ScrollTopModifier: ViewModifier {
    var tab: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.background(
            ScrollTopHook(tab: tab, reduceMotion: ModulaEffectGate.reduceMotion(reduceMotion))
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}

extension View {
    /// Apply to the content *inside* a tab-root ScrollView.
    func modulaScrollsToTopOnReselect(_ tab: AppTab) -> some View { modifier(ScrollTopModifier(tab: tab)) }
}

// MARK: - Draft autosave indicator

/// "Saving…" → "Saved · 12s ago" pill. The relative time ticks (Zeigarnik: visible progress
/// on unfinished work reassures without nagging). Static text under Reduce Motion.
struct ModulaAutosaveIndicator: View {
    var savedAt: Date?
    var saving: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if saving {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
            } else if let savedAt {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Label(Self.copy(savedAt, now: context.date), systemImage: "checkmark.icloud")
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .contentTransition(ModulaEffectGate.reduceMotion(reduceMotion) ? .identity : .numericText())
        .accessibilityElement(children: .combine)
    }

    static func copy(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "Saved" }
        if seconds < 60 { return "Saved · \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Saved · \(minutes)m ago" }
        return "Saved · \(date.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Accent chip

/// Filter chip that uses the live accent when selected, Dynamic-Type aware height.
struct ModulaAccentChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 34

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .padding(.horizontal, ModulaSpacing.md)
                .frame(minHeight: height)
        }
        .buttonStyle(ModulaPressStyle(haptic: nil))
        .modifier(ChipFill(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private struct ChipFill: ViewModifier {
        var selected: Bool
        func body(content: Content) -> some View {
            if selected {
                content.modulaAccentCTA()
            } else {
                content.foregroundStyle(.primary).modulaGlass(in: Capsule(), interactive: true)
            }
        }
    }
}

// MARK: - Downsampled thumbnail

/// Thumbnail that decodes at display size (ImageIO downsampling + shared memory cache)
/// instead of `AsyncImage`'s full-resolution decode. Cuts memory and scroll hitches.
struct ModulaDownsampledImage: View {
    var url: URL?
    /// Longest side in points; decoded at points × screen scale.
    var pointSize: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixels = max(64, pointSize * displayScale)
        ModulaRemoteImage(url: url, cacheKey: "thumb:\(Int(pixels)):\(url?.absoluteString ?? "-")", maximumPixelSize: pixels) { phase in
            switch phase {
            case .success(let image):
                Image(uiImage: image).resizable().scaledToFill()
            case .loading:
                Rectangle().fill(Color.primary.opacity(0.08)).modulaShimmer()
            case .failure:
                Rectangle().fill(Color.primary.opacity(0.08))
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
    }
}

// MARK: - Person context menu + follow CTA

private struct PersonContextMenu: ViewModifier {
    var name: String
    var handle: String
    var isFollowing: Bool
    var onOpen: () -> Void
    var onFollow: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("View Profile", systemImage: "person.crop.circle", action: onOpen)
            Button(isFollowing ? "Unfollow" : "Follow", systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus", action: onFollow)
            Button("Copy Handle", systemImage: "at") {
                UIPasteboard.general.string = "@\(handle)"
                HapticEngine.shared.play(.success)
                ModulaToastCenter.shared.show("Copied @\(handle)", symbol: "doc.on.doc")
            }
        }
        .accessibilityAction(named: "Copy handle") {
            UIPasteboard.general.string = "@\(handle)"
            ModulaToastCenter.shared.show("Copied @\(handle)", symbol: "doc.on.doc")
        }
    }
}

private struct FollowCTA: ViewModifier {
    var isFollowing: Bool
    func body(content: Content) -> some View {
        if isFollowing {
            content.foregroundStyle(.primary).modulaGlass(in: Capsule(), interactive: true)
        } else {
            content.modulaAccentCTA()
        }
    }
}

extension View {
    /// Long-press menu for a person cell: View Profile, Follow/Unfollow, Copy Handle.
    func modulaPersonContextMenu(name: String, handle: String, isFollowing: Bool, onOpen: @escaping () -> Void, onFollow: @escaping () -> Void) -> some View {
        modifier(PersonContextMenu(name: name, handle: handle, isFollowing: isFollowing, onOpen: onOpen, onFollow: onFollow))
    }
    /// Follow buttons: accent CTA when it is the primary action, quiet glass once following.
    func modulaFollowCTA(isFollowing: Bool) -> some View { modifier(FollowCTA(isFollowing: isFollowing)) }
}

// MARK: - Refresh with feedback

extension View {
    /// `refreshable` plus closure: a soft success haptic and a VoiceOver "Updated"
    /// announcement when the pull finishes (goal-gradient: the gesture visibly completes).
    func modulaRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        refreshable {
            await action()
            await MainActor.run {
                HapticEngine.shared.play(.drop)
                UIAccessibility.post(notification: .announcement, argument: "Updated")
            }
        }
    }
}
