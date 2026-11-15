import SwiftUI

enum ModulaMediaViewerSource: Hashable, Sendable {
    case remote(URL)
    case asset(String)
    case symbol(String)
}

struct ModulaMediaViewerItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let source: ModulaMediaViewerSource?
    let accessibilityDescription: String
    var allowsShare: Bool = true

    var url: URL? {
        if case .remote(let url) = source { return url }
        return nil
    }

    init(
        id: String? = nil,
        title: String,
        source: ModulaMediaViewerSource?,
        accessibilityDescription: String,
        allowsShare: Bool = true
    ) {
        self.id = id ?? "\(title)|\(String(describing: source))"
        self.title = title
        self.source = source
        self.accessibilityDescription = accessibilityDescription
        self.allowsShare = allowsShare
    }

    init(title: String, url: URL?, accessibilityDescription: String, allowsShare: Bool = true) {
        self.init(
            title: title,
            source: url.map(ModulaMediaViewerSource.remote),
            accessibilityDescription: accessibilityDescription,
            allowsShare: allowsShare
        )
    }
}

enum ModulaMediaViewerTransition: Sendable {
    case fade
    case sourceZoom
    case reducedMotion
}

struct ModulaMediaViewerControls: View {
    let title: String
    var index: Int
    var count: Int
    var shareURL: URL?
    var allowsShare: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: ModulaSpacing.sm) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close media")
                Spacer()
                VStack(spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if count > 1 {
                        Text("\(index + 1) of \(count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if allowsShare, let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Share \(title)")
                } else {
                    Color.clear.frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, ModulaSpacing.md)
            .padding(.top, ModulaSpacing.xs)
            Spacer()
            if count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { page in
                        Capsule()
                            .fill(page == index ? Color.white : Color.white.opacity(0.35))
                            .frame(width: page == index ? 18 : 6, height: 6)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: index)
                .padding(.bottom, ModulaSpacing.md)
                .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(true)
    }
}

/// Reusable full-screen image gallery. Paging stays disabled while a page is zoomed,
/// preventing horizontal page and image-pan gestures from competing.
struct ModulaMediaViewer: View {
    let items: [ModulaMediaViewerItem]
    var initialID: String?
    var transition: ModulaMediaViewerTransition = .sourceZoom
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: String
    @State private var zoomedPageID: String?
    @State private var controlsVisible = true
    /// 0…1 while the current page is pulled down to close (finger-following dismiss).
    @State private var pullProgress: CGFloat = 0

    init(
        items: [ModulaMediaViewerItem],
        initialID: String? = nil,
        transition: ModulaMediaViewerTransition = .sourceZoom,
        onDismiss: @escaping () -> Void
    ) {
        let safeItems = items.isEmpty
            ? [ModulaMediaViewerItem(title: "Media", source: nil, accessibilityDescription: "Unavailable media", allowsShare: false)]
            : items
        self.items = safeItems
        self.initialID = initialID
        self.transition = transition
        self.onDismiss = onDismiss
        self._selection = State(initialValue: initialID ?? safeItems[0].id)
    }

    init(
        title: String,
        url: URL?,
        accessibilityDescription: String,
        allowsShare: Bool = true,
        onDismiss: @escaping () -> Void
    ) {
        let item = ModulaMediaViewerItem(
            title: title,
            url: url,
            accessibilityDescription: accessibilityDescription,
            allowsShare: allowsShare
        )
        self.init(items: [item], initialID: item.id, onDismiss: onDismiss)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - pullProgress * 0.75).ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(items) { item in
                    ModulaMediaViewerPage(
                        item: item,
                        isSelected: selection == item.id,
                        onZoomChanged: { zoomed in zoomedPageID = zoomed ? item.id : nil },
                        onDismiss: dismiss,
                        onToggleControls: { controlsVisible.toggle() },
                        onPullChanged: { pullProgress = $0 }
                    )
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(zoomedPageID != nil)

            if controlsVisible, let currentItem {
                ModulaMediaViewerControls(
                    title: currentItem.title,
                    index: currentIndex,
                    count: items.count,
                    shareURL: currentItem.url,
                    allowsShare: currentItem.allowsShare,
                    onDismiss: dismiss
                )
                .opacity(1 - min(pullProgress * 3, 1))
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: controlsVisible)
        .onChange(of: selection) { _, _ in
            zoomedPageID = nil
            HapticEngine.shared.play(.selectionChanged)
        }
        .accessibilityIdentifier("media.viewer")
    }

    private var currentIndex: Int { items.firstIndex(where: { $0.id == selection }) ?? 0 }
    private var currentItem: ModulaMediaViewerItem? { items[safe: currentIndex] }

    private func dismiss() {
        HapticEngine.shared.play(.selectionChanged)
        onDismiss()
    }
}

struct ModulaMediaViewerPage: View {
    let item: ModulaMediaViewerItem
    var isSelected: Bool
    var onZoomChanged: (Bool) -> Void
    var onDismiss: () -> Void
    var onToggleControls: () -> Void
    /// Pull-down-to-close progress (0…1) so the viewer can fade its backdrop with the finger.
    var onPullChanged: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var settledOffset: CGSize = .zero
    @State private var retryID = 0
    /// Snaps back without bounce when a pull is released short of closing.
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.26, bounce: 0)))
    private var gestureOffset: CGSize = .zero

    private var pullProgress: CGFloat {
        guard scale <= 1.05 else { return 0 }
        return min(max(gestureOffset.height / 320, 0), 1)
    }

    var body: some View {
        mediaContent
            .scaleEffect(scale * (1 - pullProgress * 0.22))
            .offset(x: settledOffset.width + gestureOffset.width, y: settledOffset.height + gestureOffset.height)
            .contentShape(Rectangle())
            .gesture(magnifyGesture)
            .simultaneousGesture(panGesture)
            // Enhancements-50: double-tap registered first so it isn't swallowed by the single tap.
            .onTapGesture(count: 2, perform: toggleZoom)
            .onTapGesture { onToggleControls() }
            .onChange(of: isSelected) { _, selected in if !selected { reset() } }
            .onChange(of: pullProgress) { _, progress in onPullChanged(progress) }
            .accessibilityLabel(item.accessibilityDescription)
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: "Zoom in") { setZoom(2.2) }
            .accessibilityAction(named: "Reset zoom") { reset() }
            .accessibilityAction(named: "Dismiss") { onDismiss() }
    }

    @ViewBuilder private var mediaContent: some View {
        switch item.source {
        case .remote(let url):
            ModulaRemoteImage(url: url, cacheKey: "viewer:\(item.id)", maximumPixelSize: 4_096, retryID: retryID) { phase in
                switch phase {
                case .success(let image): Image(uiImage: image).resizable().scaledToFit()
                case .loading: ProgressView().tint(.white)
                case .failure: fallback.overlay(alignment: .bottom) {
                    Button {
                        HapticEngine.shared.play(.lightImpact)
                        retryID += 1
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, ModulaSpacing.lg).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .modulaAccentCTA()
                    .padding(.bottom, 44)
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .asset(let name):
            Image(name).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .symbol(let name):
            Image(systemName: name)
                .resizable().scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(70)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case nil:
            fallback
        }
    }

    private var fallback: some View {
        VStack(spacing: ModulaSpacing.sm) {
            Image(systemName: "photo").font(.largeTitle)
            Text(item.title).font(.headline)
        }
        .foregroundStyle(.white.opacity(0.78))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Enhancements-50: pinch is direct manipulation, not motion — it now works with
                // Reduce Motion on. A tick marks the 4× limit (feedback at the boundary).
                let raw = settledScale * value
                let next = min(max(raw, 1), 4)
                if next == 4, scale < 4 { HapticEngine.shared.play(.dragThreshold) }
                scale = next
                onZoomChanged(scale > 1.05)
            }
            .onEnded { _ in
                settledScale = scale
                if scale < 1.05 { reset() }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($gestureOffset) { value, state, _ in
                if scale > 1.05 {
                    state = value.translation
                } else if value.translation.height > 0, value.translation.height > abs(value.translation.width) {
                    // Unzoomed: only a downward pull follows the finger (sideways stays the pager's).
                    state = CGSize(width: value.translation.width * 0.35, height: value.translation.height)
                }
            }
            .onEnded { value in
                let vertical = abs(value.translation.width) < abs(value.translation.height)
                let flung = value.predictedEndTranslation.height > 420
                if scale <= 1.05, vertical, value.translation.height > 0, value.translation.height > 120 || flung {
                    onDismiss()
                } else if scale > 1.05 {
                    settledOffset = CGSize(
                        width: settledOffset.width + value.translation.width,
                        height: settledOffset.height + value.translation.height
                    )
                }
            }
    }

    private func toggleZoom() {
        setZoom(scale > 1.2 ? 1 : 2.2)
        HapticEngine.shared.play(.lightImpact)
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            scale = value
            settledScale = value
            if value == 1 { settledOffset = .zero }
        }
        onZoomChanged(value > 1.05)
    }

    private func reset() { setZoom(1) }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Pull down to close (full-screen covers without their own pager/scroll)

extension View {
    /// Finger-following pull-down that closes a full-screen cover (video / audio viewers).
    /// Only downward, vertical-dominant drags take part, so taps and player scrubbing keep working.
    func modulaPullDownToDismiss(_ onDismiss: @escaping () -> Void) -> some View {
        modifier(ModulaPullDownToDismiss(onDismiss: onDismiss))
    }
}

private struct ModulaPullDownToDismiss: ViewModifier {
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.26, bounce: 0)))
    private var pull: CGFloat = 0

    func body(content: Content) -> some View {
        let progress = min(pull / 360, 1)
        content
            .offset(y: reduceMotion ? 0 : pull)
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.12, anchor: .top)
            .opacity(reduceMotion ? 1 - progress * 0.5 : 1)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .updating($pull) { value, state, _ in
                        guard value.translation.height > 0,
                              value.translation.height > abs(value.translation.width) * 1.3 else { return }
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let vertical = value.translation.height > abs(value.translation.width) * 1.3
                        guard vertical, value.translation.height > 120 || value.predictedEndTranslation.height > 420 else { return }
                        HapticEngine.shared.play(.selectionChanged)
                        onDismiss()
                    }
            )
            .accessibilityAction(.escape) { onDismiss() }
    }
}
