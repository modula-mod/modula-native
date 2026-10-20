import PDFKit
import SwiftUI
import UIKit

// MARK: - Inline PDF posts (LinkedIn-style document carousel)
//
// A PDF post renders inside the card as a horizontally swipeable carousel:
// slide 0 is a cover/title page, slides 1…n are the document pages. Each page
// paints a fast low-res thumbnail first, then a sharp render sized to the cell.
// Rendering happens off the main thread in `PDFPageRenderer`, results live in a
// cost-bounded `PDFPageImageCache`, and per-page work is tied to `.task` so it is
// cancelled as soon as a lazy cell scrolls offscreen.

enum PDFPageQuality: String, Sendable, CaseIterable {
    case thumbnail
    case sharp
}

/// Pure layout/progress maths, kept separate so it is unit-testable.
enum PDFCarouselMath {
    /// Low-res pass width in pixels. Small enough to decode in a few milliseconds.
    static let thumbnailPixelWidth: CGFloat = 180
    /// Upper bound for a sharp render, whatever the device scale.
    static let maxSharpPixelWidth: CGFloat = 1_600

    /// Slides = cover + pages.
    static func slideCount(pageCount: Int) -> Int { max(0, pageCount) + 1 }

    /// Slide index → PDF page index (nil for the cover).
    static func pageIndex(forSlide slide: Int) -> Int? { slide >= 1 ? slide - 1 : nil }

    /// 0…1 progress across the whole carousel (cover = 0, last page = 1).
    static func progress(slide: Int, pageCount: Int) -> Double {
        guard pageCount > 0 else { return 0 }
        let clamped = min(max(slide, 0), pageCount)
        return Double(clamped) / Double(pageCount)
    }

    /// Counter label for the glass capsule.
    static func counterText(slide: Int, pageCount: Int) -> String {
        guard let page = pageIndex(forSlide: slide), pageCount > 0 else {
            return pageCount > 0 ? "\(pageCount) pages" : "PDF"
        }
        return "\(min(page + 1, pageCount)) / \(pageCount)"
    }

    /// Pixel width to render for a cell of `pointWidth` points.
    static func pixelWidth(for quality: PDFPageQuality, pointWidth: CGFloat, scale: CGFloat) -> CGFloat {
        switch quality {
        case .thumbnail: return thumbnailPixelWidth
        case .sharp: return min(max(pointWidth * max(scale, 1), thumbnailPixelWidth), maxSharpPixelWidth)
        }
    }

    /// Bytes an RGBA bitmap of this size occupies (NSCache cost).
    static func cost(width: CGFloat, height: CGFloat) -> Int { Int(max(width, 0) * max(height, 0) * 4) }

    static func cacheKey(url: URL, page: Int, quality: PDFPageQuality, pixelWidth: CGFloat) -> String {
        "\(url.standardizedFileURL.path)#\(page)@\(quality.rawValue):\(Int(pixelWidth))"
    }

    /// Trailing/leading peek so the next (and previous) page is actually visible.
    /// `containerRelativeFrame(.horizontal)` ignores contentMargins, so pages must be
    /// narrower than the carousel or the side-page strip never paints.
    static let sidePeek: CGFloat = 44
    static let pageSpacing: CGFloat = 10

    static func pageWidth(containerWidth: CGFloat, peek: CGFloat = sidePeek) -> CGFloat {
        let available = containerWidth - (peek * 2)
        return min(max(available, min(containerWidth, 220)), containerWidth)
    }
}

/// Cost-bounded bitmap cache (thread-safe; NSCache also drops on memory warnings).
final class PDFPageImageCache: @unchecked Sendable {
    static let shared = PDFPageImageCache()
    static let defaultCostLimit = 48 * 1_024 * 1_024

    private let cache = NSCache<NSString, UIImage>()

    init(costLimit: Int = PDFPageImageCache.defaultCostLimit, countLimit: Int = 160) {
        cache.totalCostLimit = costLimit
        cache.countLimit = countLimit
        cache.name = "modula.pdf.pages"
    }

    var costLimit: Int { cache.totalCostLimit }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func insert(_ image: UIImage, for key: String) {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        cache.setObject(image, forKey: key as NSString, cost: PDFCarouselMath.cost(width: pixels.width, height: pixels.height))
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Serial background renderer. Keeps a handful of open documents (LRU) so swiping
/// doesn't reparse the file, and never touches the main thread.
actor PDFPageRenderer {
    static let shared = PDFPageRenderer()
    private static let maxOpenDocuments = 4

    private var documents: [URL: PDFDocument] = [:]
    private var order: [URL] = []
    /// Reading-time estimates are text extraction (slow on big files): computed once per file.
    var readingMinutesCache: [URL: Int] = [:]
    private let cache: PDFPageImageCache

    init(cache: PDFPageImageCache = .shared) { self.cache = cache }

    func document(for url: URL) -> PDFDocument? {
        if let open = documents[url] {
            order.removeAll { $0 == url }; order.append(url)
            return open
        }
        guard let document = PDFDocument(url: url) else { return nil }
        documents[url] = document
        order.append(url)
        while order.count > Self.maxOpenDocuments {
            let evicted = order.removeFirst()
            documents[evicted] = nil
        }
        return document
    }

    func pageCount(url: URL) -> Int { document(for: url)?.pageCount ?? 0 }

    /// Height / width of a page's crop box (defaults to A4 portrait).
    func aspectRatio(url: URL, page: Int) -> CGFloat {
        guard let bounds = document(for: url)?.page(at: page)?.bounds(for: .cropBox), bounds.width > 0 else { return 1.414 }
        return bounds.height / bounds.width
    }

    func render(url: URL, page index: Int, quality: PDFPageQuality, pixelWidth: CGFloat) throws -> UIImage? {
        let key = PDFCarouselMath.cacheKey(url: url, page: index, quality: quality, pixelWidth: pixelWidth)
        if let hit = cache.image(for: key) { return hit }
        try Task.checkCancellation()
        guard let page = document(for: url)?.page(at: index) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0 else { return nil }
        let size = CGSize(width: pixelWidth, height: pixelWidth * bounds.height / bounds.width)
        let image = page.thumbnail(of: size, for: .cropBox)
        try Task.checkCancellation()
        cache.insert(image, for: key)
        return image
    }

    func close(url: URL) {
        documents[url] = nil
        order.removeAll { $0 == url }
    }
}

// MARK: - Views

struct ModulaPDFInlineCarousel: View {
    let attachment: ModulaAttachment
    /// Local file once downloaded; nil while loading.
    let fileURL: URL?
    var failed = false
    var height: CGFloat = 420
    var onRetry: () -> Void = {}
    /// Bumped by the host when the reader closes so "Continue reading" refreshes.
    var readingVersion = 0
    var onOpen: (Int) -> Void

    @State private var pageCount = 0
    @State private var slide: Int? = 0
    @State private var coverImage: UIImage?
    /// Tiny render of page 1, upscaled as the cover backdrop: looks blurred without a live blur pass.
    @State private var coverBackdrop: UIImage?
    @State private var docKind: PDFDocKind = .document
    @State private var readingMinutes: Int?
    @State private var lastPage = 0
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var knownPages: Int { pageCount > 0 ? pageCount : (attachment.metadata.pageCount ?? 0) }
    private var currentSlide: Int { slide ?? 0 }
    private var accent: Color { app.appearance.accent.color }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                carousel
                controls
            }
            .frame(height: height)
            footer
        }
        .task(id: fileURL) {
            lastPage = PDFReadingStore.shared.lastPage(for: attachment.id)
            guard let fileURL else { return }
            let renderer = PDFPageRenderer.shared
            let count = await renderer.pageCount(url: fileURL)
            pageCount = count
            guard count > 0 else { return }
            let thumb = try? await renderer.render(url: fileURL, page: 0, quality: .thumbnail, pixelWidth: PDFCarouselMath.thumbnailPixelWidth)
            let backdrop = try? await renderer.render(url: fileURL, page: 0, quality: .thumbnail, pixelWidth: 18)
            guard !Task.isCancelled else { return }
            if let thumb {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { coverImage = thumb; coverBackdrop = backdrop }
            }
            docKind = PDFDocKind.classify(aspectRatio: await renderer.aspectRatio(url: fileURL, page: 0), pageCount: count)
            readingMinutes = await renderer.readingMinutes(url: fileURL)
        }
        .onAppear { lastPage = PDFReadingStore.shared.lastPage(for: attachment.id) }
        .onChange(of: readingVersion) { lastPage = PDFReadingStore.shared.lastPage(for: attachment.id) }
    }

    private var carousel: some View {
        GeometryReader { proxy in
            let pageWidth = PDFCarouselMath.pageWidth(containerWidth: proxy.size.width)
            ScrollView(.horizontal) {
                LazyHStack(spacing: PDFCarouselMath.pageSpacing) {
                    cover
                        .frame(width: pageWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .id(0)
                    if let fileURL {
                        ForEach(0..<pageCount, id: \.self) { index in
                            PDFInlinePageView(url: fileURL, page: index)
                                .frame(width: pageWidth)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.92)
                                        .rotation3DEffect(
                                            .degrees(reduceMotion ? 0 : phase.value * 8),
                                            axis: (x: 0, y: 1, z: 0),
                                            perspective: 0.7
                                        )
                                        .offset(x: reduceMotion ? 0 : phase.value * -14)
                                        .opacity(phase.isIdentity ? 1 : 0.82)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onOpen(index) }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Page \(index + 1) of \(pageCount)")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Opens the full-screen reader")
                                .accessibilityIdentifier("pdf.inline.page.\(index + 1)")
                                .id(index + 1)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $slide)
            .scrollIndicators(.hidden)
            .sensoryFeedback(.selection, trigger: currentSlide)
            .accessibilityIdentifier("pdf.inline.carousel")
        }
    }

    // MARK: Cover

    private var cover: some View {
        ZStack(alignment: .bottom) {
            if let coverBackdrop {
                Image(uiImage: coverBackdrop).resizable().interpolation(.medium).scaledToFill()
                    .opacity(0.55)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                colors: [accent.opacity(0.28), .black.opacity(0.18), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Spacer(minLength: 40)
                coverThumb
                coverMeta
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if fileURL != nil { onOpen(0) } }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pdf.inline.cover")
    }

    private var coverThumb: some View {
        Group {
            if let coverImage {
                Image(uiImage: coverImage).resizable().scaledToFit()
            } else {
                Color.white.opacity(0.9)
                    .overlay { Image(systemName: "doc.richtext.fill").font(.largeTitle).foregroundStyle(.secondary) }
                    .aspectRatio(0.72, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height - 148)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            // Static faux shadow (no offscreen shadow pass while the feed scrolls).
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.28))
                .padding(-3)
                .offset(y: 5)
        )
        .accessibilityHidden(true)
    }

    private var coverMeta: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(docKind.rawValue, systemImage: docKind.symbol)
                    .font(.caption.weight(.bold))
                Spacer(minLength: 0)
                if failed {
                    Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .modulaGlass(in: Capsule())
                } else if fileURL == nil {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Label("Swipe to read", systemImage: "hand.draw")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .modulaGlass(in: Capsule(), interactive: false)
                }
            }
            Text(attachment.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(coverDetail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coverDetail: String {
        var parts: [String] = []
        if knownPages > 0 { parts.append("\(knownPages) pages") }
        if let bytes = attachment.byteSize { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        if failed { parts.append("Preview unavailable") }
        return parts.isEmpty ? "PDF document" : parts.joined(separator: " · ")
    }

    // MARK: Controls

    private func jump(to target: Int) {
        withAnimation(reduceMotion ? nil : .snappy) { slide = min(max(target, 0), knownPages) }
    }

    private var controls: some View {
        VStack {
            HStack {
                Text(PDFCarouselMath.counterText(slide: currentSlide, pageCount: knownPages))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .accessibilityIdentifier("pdf.inline.counter")
                Spacer()
                if let fileURL {
                    ModulaGlassGroup(spacing: 6) {
                        HStack(spacing: 6) {
                            ShareLink(item: fileURL) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Circle(), specular: true)
                            .accessibilityLabel("Save or share PDF")
                            .accessibilityIdentifier("pdf.inline.save")
                            Button { onOpen(PDFCarouselMath.pageIndex(forSlide: currentSlide) ?? 0) } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Circle(), specular: true)
                            .accessibilityLabel("Open full screen")
                            .accessibilityIdentifier("pdf.inline.expand")
                        }
                    }
                }
            }
            Spacer()
            if knownPages > 0 { scrubber }
        }
        .padding(.horizontal, ModulaSpacing.sm + 14)
        .padding(.vertical, ModulaSpacing.sm)
    }

    @ViewBuilder private var scrubber: some View {
        let slides = PDFCarouselMath.slideCount(pageCount: knownPages)
        Group {
            if PDFReadingMath.usesDots(slideCount: slides) {
                HStack(spacing: 6) {
                    ForEach(0..<slides, id: \.self) { index in
                        Capsule()
                            .fill(index == currentSlide ? accent : Color.white.opacity(0.55))
                            .frame(width: index == currentSlide ? 18 : 6, height: 6)
                            .contentShape(Rectangle().inset(by: -6))
                            .onTapGesture { jump(to: index) }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .animation(reduceMotion ? nil : .snappy, value: currentSlide)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(accent)
                            .frame(width: max(6, proxy.size.width * PDFCarouselMath.progress(slide: currentSlide, pageCount: knownPages)))
                    }
                    .contentShape(Rectangle().inset(by: -10))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let fraction = value.location.x / max(proxy.size.width, 1)
                        let target = Int((min(max(fraction, 0), 1) * Double(knownPages)).rounded())
                        if target != currentSlide { slide = target }
                    })
                }
                .frame(height: 4)
                .padding(6)
                .animation(reduceMotion ? nil : .snappy, value: currentSlide)
            }
        }
        .modulaGlass(in: Capsule(), interactive: false)
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue(PDFCarouselMath.counterText(slide: currentSlide, pageCount: knownPages))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: jump(to: currentSlide + 1)
            case .decrement: jump(to: currentSlide - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("pdf.inline.progress")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Label(docKind == .document ? "PDF" : "PDF · \(docKind.rawValue)", systemImage: "doc.richtext.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(accent.opacity(0.14), in: Capsule())
                .accessibilityIdentifier("pdf.inline.badge")
            if let readingMinutes {
                Label(PDFReadingMath.readingLabel(minutes: readingMinutes), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdf.inline.readingTime")
            }
            Spacer(minLength: 0)
            if fileURL != nil, PDFReadingMath.shouldOfferContinue(lastPage: lastPage, pageCount: knownPages) {
                Button { onOpen(lastPage) } label: {
                    Label("Continue p. \(lastPage + 1)", systemImage: "book.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), tint: accent)
                .accessibilityLabel("Continue reading from page \(lastPage + 1)")
                .accessibilityIdentifier("pdf.inline.continue")
            }
        }
        .padding(.horizontal, ModulaSpacing.sm + 6)
        .padding(.vertical, 10)
    }
}

/// One page: low-res thumbnail first, then a sharp render. `.task` cancels both
/// when the lazy cell leaves the screen.
struct PDFInlinePageView: View {
    let url: URL
    let page: Int
    @State private var image: UIImage?
    @State private var isSharp = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(isSharp ? .high : .medium)
                        .scaledToFit()
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                        .padding(.vertical, 28)
                        .padding(.horizontal, 6)
                        .transition(.opacity)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .task(id: "\(page)-\(Int(proxy.size.width))") {
                await load(pointWidth: proxy.size.width)
            }
        }
    }

    private func load(pointWidth: CGFloat) async {
        let renderer = PDFPageRenderer.shared
        let sharpWidth = PDFCarouselMath.pixelWidth(for: .sharp, pointWidth: pointWidth, scale: displayScale)
        let sharpKey = PDFCarouselMath.cacheKey(url: url, page: page, quality: .sharp, pixelWidth: sharpWidth)
        if let cached = PDFPageImageCache.shared.image(for: sharpKey) {
            image = cached; isSharp = true
            return
        }
        if image == nil, let thumb = try? await renderer.render(url: url, page: page, quality: .thumbnail, pixelWidth: PDFCarouselMath.thumbnailPixelWidth) {
            image = thumb
        }
        // Small settle delay: fast flicks through pages never pay for sharp renders.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        if let sharp = try? await renderer.render(url: url, page: page, quality: .sharp, pixelWidth: sharpWidth), !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.15)) { image = sharp; isSharp = true }
        }
    }
}
