@preconcurrency import LinkPresentation
import SwiftUI
import UIKit

/// The first web link in a chat message, classified for inline display.
/// Settings → Chats: "Preview media inline" shows image links as images and
/// "Link previews" fetches a rich preview (title/icon) for other links. With both
/// off — or with Data saver on for link previews — nothing is fetched.
enum MessageInlineContent: Equatable, Sendable {
    case image(URL)
    case link(URL)

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "avif"]

    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first { $0.scheme == "https" || $0.scheme == "http" }
    }

    static func classify(_ url: URL) -> MessageInlineContent {
        imageExtensions.contains(url.pathExtension.lowercased()) ? .image(url) : .link(url)
    }

    static func detect(
        in text: String,
        inlineMedia: Bool = ModulaPreferences.chatInlineMedia,
        linkPreviews: Bool = ModulaPreferences.chatLinkPreviews
    ) -> MessageInlineContent? {
        guard let url = firstURL(in: text) else { return nil }
        switch classify(url) {
        case .image(let image): return inlineMedia ? .image(image) : (linkPreviews ? .link(image) : nil)
        case .link(let link): return linkPreviews ? .link(link) : nil
        }
    }
}

struct MessageInlineContentView: View {
    let content: MessageInlineContent

    var body: some View {
        switch content {
        case .image(let url):
            ModulaRemoteImage(url: url, cacheKey: "message-inline:\(url.absoluteString)", maximumPixelSize: 900) { phase in
                switch phase {
                case .success(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 240, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Image from \(url.host() ?? "link")")
                default:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 180, height: 120)
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                        .accessibilityHidden(true)
                }
            }
        case .link(let url):
            MessageLinkPreview(url: url)
                .frame(maxWidth: 280)
        }
    }
}

/// Rich link card backed by LinkPresentation. Metadata is fetched once per URL and
/// cached for the session; failures fall back to a plain host row.
struct MessageLinkPreview: View {
    let url: URL
    @State private var metadata: LPLinkMetadata?
    @State private var failed = false

    var body: some View {
        Group {
            if let metadata {
                LinkPreviewRepresentable(metadata: metadata)
                    .frame(minHeight: 60)
            } else {
                Link(destination: url) {
                    Label(url.host() ?? url.absoluteString, systemImage: failed ? "link" : "globe")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
        .task(id: url) {
            if let cached = MessageLinkMetadataCache.shared.metadata(for: url) {
                metadata = cached
                return
            }
            let provider = LPMetadataProvider()
            provider.timeout = 8
            do {
                let fetched = try await provider.startFetchingMetadata(for: url)
                MessageLinkMetadataCache.shared.store(fetched, for: url)
                metadata = fetched
            } catch {
                failed = true
            }
        }
    }
}

@MainActor
final class MessageLinkMetadataCache {
    static let shared = MessageLinkMetadataCache()
    private var entries: [URL: LPLinkMetadata] = [:]
    func metadata(for url: URL) -> LPLinkMetadata? { entries[url] }
    func store(_ metadata: LPLinkMetadata, for url: URL) {
        if entries.count > 64 { entries.removeAll() }
        entries[url] = metadata
    }
}

private struct LinkPreviewRepresentable: UIViewRepresentable {
    let metadata: LPLinkMetadata
    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ uiView: LPLinkView, context: Context) {
        uiView.metadata = metadata
    }
}
