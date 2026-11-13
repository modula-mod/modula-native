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
    @State private var viewing: MessageLinkTarget?

    var body: some View {
        switch content {
        case .image(let url):
            ModulaRemoteImage(url: url, cacheKey: "message-inline:\(url.absoluteString)", maximumPixelSize: 900) { phase in
                switch phase {
                case .success(let image):
                    // Roadmap #05: tap opens the full-screen viewer (pinch / double-tap zoom).
                    Button {
                        HapticEngine.shared.play(.navigation)
                        viewing = MessageLinkTarget(url: url)
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 240, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Image from \(url.host() ?? "link")")
                    .accessibilityHint("Opens full screen")
                    .accessibilityIdentifier("messages.inlineImage")
                    .fullScreenCover(item: $viewing) { target in
                        MessageImageViewer(url: target.url, preview: image)
                    }
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
                // A compact card in the app's own style (title + domain) instead of LPLinkView,
                // which truncated long addresses mid-host ("https://www.kl-cc.co…").
                Link(destination: url) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "safari")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metadata.title?.isEmpty == false ? metadata.title! : MessagePreviewText.displayHost(url))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(MessagePreviewText.displayHost(url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Link: \(metadata.title ?? MessagePreviewText.displayHost(url))")
                .accessibilityIdentifier("messages.linkCard")
            } else {
                Link(destination: url) {
                    Label(MessagePreviewText.displayHost(url), systemImage: failed ? "link" : "globe")
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


// MARK: - Full-screen image viewer (roadmap #05)

/// Edge-to-edge viewer for an image already shown in the chat: pinch to zoom, double-tap to
/// zoom in/out, drag to pan when zoomed, swipe down or Close to return to the same place.
/// Viewing only: nothing is saved or uploaded.
struct MessageImageViewer: View {
    let url: URL
    let preview: UIImage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0

    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dismissDrag) / 400, 0.6))
                .ignoresSafeArea()
            ModulaRemoteImage(url: url, cacheKey: "message-full:\(url.absoluteString)", maximumPixelSize: 2600) { phase in
                if case .success(let full) = phase {
                    zoomable(full)
                } else {
                    zoomable(preview)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close image")
            .accessibilityIdentifier("messages.imageViewer.close")
        }
        .statusBarHidden()
        .accessibilityIdentifier("messages.imageViewer")
    }

    private func zoomable(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height + dismissDrag)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1), maxScale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.01 { reset(animated: true) }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1 {
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        } else {
                            dismissDrag = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if scale > 1 {
                            lastOffset = offset
                        } else if abs(value.translation.height) > 120 {
                            dismiss()
                        } else {
                            withAnimation(reduceMotion ? nil : .snappy) { dismissDrag = 0 }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                if scale > 1 {
                    reset(animated: true)
                } else {
                    withAnimation(reduceMotion ? nil : .snappy) { scale = 2.5; lastScale = 2.5 }
                }
            }
            .accessibilityLabel("Image from \(url.host() ?? "link")")
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: scale > 1 ? "Zoom out" : "Zoom in") {
                if scale > 1 { reset(animated: false) } else { scale = 2.5; lastScale = 2.5 }
            }
    }

    private func reset(animated: Bool) {
        withAnimation(animated && !reduceMotion ? .snappy : nil) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero; dismissDrag = 0
        }
    }
}


// MARK: - Quote / sticker / link text (no raw tokens on screen)

/// Messages sent while the server had no reply field carry the quote as leading "> " lines.
/// Split them off so bubbles show a quote block instead of raw markdown.
enum MessageQuoteText {
    static func split(_ text: String) -> (quote: String?, body: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var quoted: [String] = []
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            var line = lines[index].trimmingCharacters(in: .whitespaces)
            line.removeFirst()
            if line.hasPrefix(" ") { line.removeFirst() }
            quoted.append(line)
            index += 1
        }
        guard index > 0 else { return (nil, text) }
        let body = lines[index...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = quoted.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (quote, body)
    }
}

/// One-line, human text for anywhere a message is summarised: inbox rows, Starred, search,
/// notifications, reply quotes. Never shows `{{sticker:…}}` tokens, `>` quote markers or a raw URL.
enum MessagePreviewText {
    static func plain(_ raw: String) -> String {
        let split = MessageQuoteText.split(raw)
        let parsed = ModulaLocalSticker.extract(split.body)
        var text = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, let first = parsed.stickers.first {
            return "Sticker · \(first.label)"
        }
        if text.isEmpty, let quote = split.quote, !quote.isEmpty {
            return "Reply: " + plain(quote)
        }
        if text.isEmpty { return split.quote != nil ? "Reply" : "" }
        if let url = MessageInlineContent.firstURL(in: text) {
            let urlText = url.absoluteString
            let stripped = text.replacingOccurrences(of: urlText, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty || text == urlText || text.hasPrefix(urlText) && stripped.count < 2 {
                return "🔗 " + displayHost(url)
            }
            text = text.replacingOccurrences(of: urlText, with: displayHost(url))
        }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    /// "https://www.kl-cc.co.uk/x" → "kl-cc.co.uk".
    static func displayHost(_ url: URL) -> String {
        var host = url.host(percentEncoded: false) ?? url.absoluteString
        if host.lowercased().hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Short visible form of a link inside a bubble: domain plus a trimmed path.
    static func displayLink(_ url: URL) -> String {
        let host = displayHost(url)
        var path = url.path(percentEncoded: false)
        if path == "/" { path = "" }
        let full = host + path
        return full.count <= 34 ? full : String(full.prefix(32)) + "…"
    }
}
