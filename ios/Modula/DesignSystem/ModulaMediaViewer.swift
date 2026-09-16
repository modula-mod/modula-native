import SwiftUI

/// Full-screen image viewer for avatar, cover, and (later) post media.
struct ModulaMediaViewer: View {
    let title: String
    let url: URL?
    let accessibilityDescription: String
    var allowsShare: Bool = true
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            mediaContent
                .scaleEffect(scale)
                .offset(x: offset.width + dragTranslation.width, y: offset.height + dragTranslation.height)
                .gesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2, perform: toggleZoom)
                .accessibilityLabel(accessibilityDescription)
                .accessibilityAddTraits(.isImage)
                .accessibilityHint("Pinch or double tap to zoom. Swipe down to dismiss.")

            VStack {
                HStack {
                    Button("Close", action: dismiss)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Close media")
                    Spacer()
                    if allowsShare, let url {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Share \(title)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .statusBarHidden(true)
        .accessibilityIdentifier("media.viewer")
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    fallback
                case .empty:
                    ProgressView()
                        .tint(.white)
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !reduceMotion else { return }
                scale = min(max(lastScale * value, 1), 4)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.05 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale <= 1.05 {
                    dragTranslation = value.translation
                } else {
                    offset = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if scale <= 1.05, value.translation.height > 120 {
                    dismiss()
                } else if scale <= 1.05 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragTranslation = .zero
                    }
                }
            }
    }

    private func toggleZoom() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            if scale > 1.2 {
                scale = 1
                lastScale = 1
                offset = .zero
            } else {
                scale = 2.2
                lastScale = 2.2
            }
        }
        HapticEngine.shared.play(.lightImpact)
    }

    private func dismiss() {
        HapticEngine.shared.play(.selection)
        onDismiss()
    }
}

struct ModulaMediaViewerItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL?
    let accessibilityDescription: String
    var allowsShare: Bool = true

    init(title: String, url: URL?, accessibilityDescription: String, allowsShare: Bool = true) {
        self.id = "\(title)|\(url?.absoluteString ?? "none")"
        self.title = title
        self.url = url
        self.accessibilityDescription = accessibilityDescription
        self.allowsShare = allowsShare
    }
}
