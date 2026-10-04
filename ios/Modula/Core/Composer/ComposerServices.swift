import ImageIO
import SwiftUI
import UIKit

// MARK: - GIFs (Greenfield proxy; the provider key never reaches the app)

struct ModulaGif: Identifiable, Hashable, Sendable {
    let id: String
    var title: String?
    var url: URL
    var previewURL: URL
    var width: Int?
    var height: Int?
}

enum ModulaGifError: Error, Equatable {
    case notConfigured
    case failed(String)
}

struct GreenfieldGifRepository: Sendable {
    var client: GreenfieldClient

    func trending(offset: Int = 0) async throws -> (items: [ModulaGif], nextOffset: Int?) {
        try await load(path: "/v1/gifs/trending?limit=24&offset=\(offset)")
    }

    func search(_ query: String, offset: Int = 0) async throws -> (items: [ModulaGif], nextOffset: Int?) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await load(path: "/v1/gifs/search?q=\(q)&limit=24&offset=\(offset)")
    }

    private func load(path: String) async throws -> (items: [ModulaGif], nextOffset: Int?) {
        do {
            let value = try await client.authenticatedJSON("GET", path: path)
            let items: [ModulaGif] = (value["items"]?.array ?? []).compactMap { item in
                guard let id = item["id"]?.string,
                      let url = item["url"]?.string.flatMap(URL.init(string:)) else { return nil }
                return ModulaGif(
                    id: id, title: item["title"]?.string, url: url,
                    previewURL: item["previewUrl"]?.string.flatMap(URL.init(string:)) ?? url,
                    width: item["width"]?.int, height: item["height"]?.int
                )
            }
            return (items, value["nextOffset"]?.int)
        } catch APIError.rejected(_, "CAPABILITY_DISABLED") {
            throw ModulaGifError.notConfigured
        } catch let error as APIError {
            throw ModulaGifError.failed(error.userFacingMessage)
        }
    }
}

// MARK: - Link previews (Greenfield unfurl, SSRF-guarded and cached server-side)

struct ModulaLinkPreviewData: Hashable, Sendable {
    var url: URL
    var canonicalURL: URL
    var domain: String
    var title: String?
    var description: String?
    var imageURL: URL?
    var siteName: String?
}

@MainActor
final class ModulaLinkPreviewStore {
    static let shared = ModulaLinkPreviewStore()
    private var cache: [URL: ModulaLinkPreviewData?] = [:]
    private var inflight: [URL: Task<ModulaLinkPreviewData?, Never>] = [:]

    func preview(for url: URL, client: GreenfieldClient) async -> ModulaLinkPreviewData? {
        if let cached = cache[url] { return cached }
        if let task = inflight[url] { return await task.value }
        let task = Task<ModulaLinkPreviewData?, Never> {
            let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            guard let value = try? await client.authenticatedJSON("GET", path: "/v1/link-previews?url=\(encoded)"),
                  let preview = value["preview"], preview["title"] != nil || preview["imageUrl"] != nil else { return nil }
            return ModulaLinkPreviewData(
                url: url,
                canonicalURL: preview["canonicalUrl"]?.string.flatMap(URL.init(string:)) ?? url,
                domain: preview["domain"]?.string ?? url.host ?? "",
                title: preview["title"]?.string,
                description: preview["description"]?.string,
                imageURL: preview["imageUrl"]?.string.flatMap(URL.init(string:)),
                siteName: preview["siteName"]?.string
            )
        }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        cache[url] = result
        return result
    }
}

enum ModulaLinkDetector {
    /// First web link in free text (posts and comments).
    static func firstWebURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        }
        return nil
    }
}

// MARK: - Animated remote image (GIFs animate; stills decode once)

@MainActor
final class ModulaAnimatedImageCache {
    static let shared = ModulaAnimatedImageCache()
    private let storage = NSCache<NSURL, UIImage>()
    private init() { storage.countLimit = 120 }

    func image(for url: URL) -> UIImage? { storage.object(forKey: url as NSURL) }

    func load(_ url: URL, client: GreenfieldClient?) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        let data: Data
        if let client, let fetched = try? await client.mediaData(from: url) {
            // Authenticated for Greenfield media (comment attachments); plain HTTPS elsewhere.
            data = fetched
        } else if let (fetched, _) = try? await URLSession.shared.data(from: url) {
            data = fetched
        } else {
            return nil
        }
        let image = await Task.detached(priority: .userInitiated) { Self.decode(data) }.value
        if let image { storage.setObject(image, forKey: url as NSURL) }
        return image
    }

    nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration: Double = 0
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 480, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        for index in 0..<min(count, 120) {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += max(delay, 0.02)
            frames.append(UIImage(cgImage: frame))
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

private struct ModulaAnimatedImageView: UIViewRepresentable {
    let image: UIImage?
    var animates: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if animates || image?.images == nil {
            view.image = image
        } else {
            view.image = image?.images?.first
        }
    }
}

/// Remote image that animates GIFs (paused under Reduce Motion).
struct ModulaAnimatedRemoteImage: View {
    let url: URL
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image {
                ModulaAnimatedImageView(image: image, animates: !reduceMotion)
            }
        }
        .task(id: url) {
            image = ModulaAnimatedImageCache.shared.image(for: url)
            if image == nil { image = await ModulaAnimatedImageCache.shared.load(url, client: app.client) }
        }
    }
}
