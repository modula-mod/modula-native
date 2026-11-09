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


// MARK: - Link inspector (roadmap #14)

/// Routes every `openURL` inside the modified view through the inspector sheet. Applied on the
/// chat and again inside Chat info (a sheet can only present from its own level).
private struct MessageLinkInspectorModifier: ViewModifier {
    @State private var target: MessageLinkTarget?
    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                target = MessageLinkTarget(url: url)
                return .handled
            })
            .sheet(item: $target) { MessageLinkInspectorSheet(url: $0.url) }
    }
}

extension View {
    func messageLinkInspector() -> some View { modifier(MessageLinkInspectorModifier()) }
}

struct MessageLinkTarget: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Shows the actual destination of a link from a message before anything opens. Uses only the
/// URL in the message: no remote preview fetch, no reputation score, and no claim it is safe.
struct MessageLinkInspectorSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var host: String { url.host(percentEncoded: false) ?? url.absoluteString }
    private var scheme: String { (url.scheme ?? "").lowercased() }
    private var notes: [String] {
        var items: [String] = []
        if scheme == "http" { items.append("This address isn’t encrypted (http).") }
        if !["http", "https"].contains(scheme), !scheme.isEmpty { items.append("Opens with another app (\(scheme):).") }
        if host.lowercased().contains("xn--") { items.append("This domain uses international characters, written here in encoded form.") }
        if url.user != nil { items.append("This address contains text before an @ sign; the real site is \(host).") }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Goes to").font(.subheadline).foregroundStyle(.secondary)
                        Text(host)
                            .font(.title2.weight(.bold))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("messages.link.host")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full address").font(.subheadline).foregroundStyle(.secondary)
                        Text(url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
                            .accessibilityIdentifier("messages.link.address")
                    }
                    ForEach(notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        Button {
                            HapticEngine.shared.play(.navigation)
                            UIApplication.shared.open(url)
                            dismiss()
                        } label: {
                            Text("Open link").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
                        .modulaAccentCTA()
                        .accessibilityIdentifier("messages.link.open")

                        HStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.url = url
                                HapticEngine.shared.play(.selection)
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
                            .modulaGlass(in: Capsule(), interactive: true)
                            .accessibilityIdentifier("messages.link.copy")

                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: nil))
                            .modulaGlass(in: Capsule(), interactive: true)
                            .accessibilityIdentifier("messages.link.share")
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
