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
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(items) { item in
                    ModulaMediaViewerPage(
                        item: item,
                        isSelected: selection == item.id,
                        onZoomChanged: { zoomed in zoomedPageID = zoomed ? item.id : nil },
                        onDismiss: dismiss,
                        onToggleControls: { controlsVisible.toggle() }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var settledOffset: CGSize = .zero
    @State private var retryID = 0
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        mediaContent
            .scaleEffect(scale)
            .offset(x: settledOffset.width + gestureOffset.width, y: settledOffset.height + gestureOffset.height)
            .contentShape(Rectangle())
            .gesture(magnifyGesture)
            .simultaneousGesture(panGesture)
            .onTapGesture { onToggleControls() }
            .onTapGesture(count: 2, perform: toggleZoom)
            .onChange(of: isSelected) { _, selected in if !selected { reset() } }
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
                    Button("Retry", systemImage: "arrow.clockwise") { retryID += 1 }
                        .buttonStyle(.bordered).tint(.white).padding(.bottom, 44)
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
                guard !reduceMotion else { return }
                scale = min(max(settledScale * value, 1), 4)
                onZoomChanged(scale > 1.05)
            }
            .onEnded { _ in
                settledScale = scale
                if scale < 1.05 { reset() }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($gestureOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                if scale <= 1.05, value.translation.height > 120, abs(value.translation.width) < abs(value.translation.height) {
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
