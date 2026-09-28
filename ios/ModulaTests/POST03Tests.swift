import AVFoundation
import PDFKit
import UIKit
import XCTest
@testable import Modula

final class POST03AttachmentTests: XCTestCase {
    func testMIMETypeIsAuthoritativeAndFilenameIsFallbackOnly() {
        XCTAssertEqual(AttachmentKind.resolve(mimeType: "application/pdf", filename: "photo.jpg"), .pdf)
        XCTAssertEqual(AttachmentKind.resolve(mimeType: "image/jpeg", filename: "document.pdf"), .image)
        XCTAssertEqual(AttachmentKind.resolve(mimeType: "application/x-unexpected", filename: "photo.jpg"), .unknown)
        XCTAssertEqual(AttachmentKind.resolve(mimeType: nil, filename: "notes.md"), .document)
        XCTAssertEqual(AttachmentKind.resolve(mimeType: nil, filename: "clip.MP4"), .video)
    }

    func testUnexpectedMetadataFailsGracefully() {
        let attachment = ModulaAttachment(id: "unexpected", kind: .unknown, remoteURL: nil, mimeType: "application/x-unknown", filename: String(repeating: "x", count: 400), byteSize: 0, dimensions: CGSize(width: -4, height: 0), duration: -1)
        XCTAssertNil(attachment.dimensions)
        XCTAssertNil(attachment.duration)
        XCTAssertFalse(attachment.isAvailable)
        XCTAssertEqual(AttachmentViewerRoute.resolve(attachment), .unsupported)
        XCTAssertEqual(attachment.displayName.count, 240)
    }

    func testViewerRoutesEverySupportedKind() {
        for (kind, route) in [(AttachmentKind.image, AttachmentViewerRoute.image), (.video, .video), (.pdf, .pdf), (.document, .document), (.audio, .audio)] {
            let attachment = ModulaAttachment(id: kind.rawValue, kind: kind, remoteURL: URL(string: "https://example.com/item"))
            XCTAssertEqual(AttachmentViewerRoute.resolve(attachment), route)
        }
    }

    func testAccessibilityLabelIncludesDocumentMetadata() {
        let value = ModulaAttachment(id: "pdf", kind: .pdf, remoteURL: URL(string: "https://example.com/file.pdf"), mimeType: "application/pdf", filename: "Modula Architecture.pdf", byteSize: 4_200_000, metadata: AttachmentMetadata(pageCount: 18))
        XCTAssertTrue(value.accessibilityLabel.contains("PDF document"))
        XCTAssertTrue(value.accessibilityLabel.contains("18 pages"))
        XCTAssertTrue(value.accessibilityLabel.contains("Modula Architecture.pdf"))
    }

    func testRealJPEGPNGPDFAudioAndQuickLookFixtures() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let png = try XCTUnwrap(image.pngData())
        XCTAssertNotNil(UIImage(data: jpeg))
        XCTAssertNotNil(UIImage(data: png))

        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            context.beginPage()
            NSString(string: "POST-03 real PDF fixture").draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 1)

        let wav = Self.makeSilentWAV(sampleCount: 800)
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")

        let store = DraftMediaStore()
        let account = "post03-fixtures-\(UUID().uuidString)"
        let fixtures = try [
            store.importData(jpeg, accountID: account, kind: .image, mimeType: "image/jpeg", originalFilename: "fixture.jpg", width: 24, height: 16),
            store.importData(png, accountID: account, kind: .image, mimeType: "image/png", originalFilename: "fixture.png", width: 24, height: 16),
            store.importData(pdf, accountID: account, kind: .pdf, mimeType: "application/pdf", originalFilename: "fixture.pdf", pageCount: 1),
            store.importData(wav, accountID: account, kind: .audio, mimeType: "audio/wav", originalFilename: "fixture.wav", duration: 0.1),
            store.importData(Data("Quick Look fixture".utf8), accountID: account, kind: .document, mimeType: "text/plain", originalFilename: "fixture.txt")
        ]
        defer { fixtures.forEach(store.remove) }

        XCTAssertEqual(fixtures.map(\.uploadState), Array(repeating: .readyToUpload, count: 5))
        XCTAssertTrue(fixtures.allSatisfy { store.fileURL($0).isFileURL && FileManager.default.fileExists(atPath: store.fileURL($0).path) })
        XCTAssertEqual(
            zip(fixtures, [AttachmentKind.image, .image, .pdf, .audio, .document]).map { media, kind in
                AttachmentViewerRoute.resolve(ModulaAttachment(
                    id: media.id, kind: kind, remoteURL: nil, localFileURL: store.fileURL(media),
                    mimeType: media.mimeType, filename: media.originalFilename, byteSize: Int64(media.byteCount ?? 0),
                    metadata: AttachmentMetadata(pageCount: media.pageCount)
                ))
            },
            [.image, .image, .pdf, .audio, .document]
        )
    }

    func testRealMP4FixtureIsPlayableAndRoutesToVideo() async throws {
        let videoURL = try await Self.makeMP4Fixture()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 0)

        let store = DraftMediaStore()
        let media = try store.importFile(
            at: videoURL, accountID: "post03-video-\(UUID().uuidString)", kind: .video,
            mimeType: "video/mp4", originalFilename: "fixture.mp4", width: 32, height: 32, duration: duration
        )
        defer { store.remove(media) }
        let attachment = ModulaAttachment(
            id: media.id, kind: .video, remoteURL: nil, localFileURL: store.fileURL(media),
            mimeType: media.mimeType, filename: media.originalFilename, byteSize: Int64(media.byteCount ?? 0), duration: duration
        )
        XCTAssertEqual(AttachmentViewerRoute.resolve(attachment), .video)
    }

    private static func makeSilentWAV(sampleCount: UInt32) -> Data {
        let dataSize = sampleCount * 2
        var output = Data()
        output.append(Data("RIFF".utf8))
        output.appendLittleEndian(36 + dataSize)
        output.append(Data("WAVEfmt ".utf8))
        output.appendLittleEndian(UInt32(16))
        output.appendLittleEndian(UInt16(1))
        output.appendLittleEndian(UInt16(1))
        output.appendLittleEndian(UInt32(8_000))
        output.appendLittleEndian(UInt32(16_000))
        output.appendLittleEndian(UInt16(2))
        output.appendLittleEndian(UInt16(16))
        output.append(Data("data".utf8))
        output.appendLittleEndian(dataSize)
        output.append(Data(repeating: 0, count: Int(dataSize)))
        return output
    }

    private static func makeMP4Fixture() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("post03-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32,
            AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 32,
            kCVPixelBufferHeightKey as String: 32
        ])
        guard writer.canAdd(input) else { throw FixtureError.videoWriterUnavailable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.videoWriterUnavailable }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard result == kCVReturnSuccess, let buffer else { throw FixtureError.videoWriterUnavailable }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0x66, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: 0, timescale: 30)) else {
            throw writer.error ?? FixtureError.videoWriterUnavailable
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: 3, timescale: 30)) else {
            throw writer.error ?? FixtureError.videoWriterUnavailable
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.videoWriterUnavailable }
        return url
    }

    private enum FixtureError: Error { case videoWriterUnavailable }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

final class POST03PostMappingTests: XCTestCase {
    func testImageAttachmentsMapToOneGalleryInStableOrder() {
        let source = fixture(media: (1...5).map { SocialPostMedia(id: "i\($0)", url: URL(string: "https://example.com/\($0).jpg"), altText: nil, kind: "image", aspectRatio: 1, mimeType: "image/jpeg") })
        let post = ModulaPostMapper.map(source)
        guard case .imageGallery(let gallery) = post.content.first else { return XCTFail("Expected gallery") }
        XCTAssertEqual(gallery.attachments.map(\.id), ["i1", "i2", "i3", "i4", "i5"])
        XCTAssertEqual(PostRendererKind.resolve(post.content[0]), .gallery)
    }

    func testMixedAttachmentsKeepBackendOrdering() {
        let source = fixture(media: [
            SocialPostMedia(id: "photo", url: URL(string: "https://example.com/a.jpg"), altText: nil, kind: "image", aspectRatio: 1, mimeType: "image/jpeg"),
            SocialPostMedia(id: "pdf", url: URL(string: "https://example.com/a.pdf"), altText: nil, kind: "document", aspectRatio: nil, mimeType: "application/pdf"),
            SocialPostMedia(id: "video", url: URL(string: "https://example.com/a.mp4"), altText: nil, kind: "video", aspectRatio: 1.7, mimeType: "video/mp4")
        ])
        let post = ModulaPostMapper.map(source)
        XCTAssertEqual(post.content.map(PostRendererKind.resolve), [.image, .pdf, .video])
        XCTAssertEqual(post.content.compactMap(\.attachment).map(\.id), ["photo", "pdf", "video"])
    }

    func testPDFMetadataSurvivesBackendMapping() {
        let source = fixture(media: [SocialPostMedia(id: "pdf", url: URL(string: "https://example.com/a.pdf"), altText: nil, kind: "document", aspectRatio: nil, mimeType: "application/pdf", filename: "Plan.pdf", byteSize: 8_000, pageCount: 40)])
        guard case .pdf(let pdf) = ModulaPostMapper.map(source).content.first else { return XCTFail("Expected PDF") }
        XCTAssertEqual(pdf.attachment.metadata.pageCount, 40)
        XCTAssertEqual(pdf.attachment.filename, "Plan.pdf")
        XCTAssertEqual(pdf.attachment.metadata.documentID, "pdf")
    }

    func testCarouselStateClampsDynamicPageChanges() {
        var state = PostCarouselState(count: 5, page: 20)
        XCTAssertEqual(state.page, 4)
        state.select(-2)
        XCTAssertEqual(state.page, 0)
        state.select(3)
        XCTAssertEqual(state.page, 3)
    }

    private func fixture(media: [SocialPostMedia]) -> SocialPost {
        SocialPost(id: "post", author: nil, createdAt: Date(), editedAt: nil, feed: "For You", text: "Fixture", kind: .media, visibility: .public, audience: nil, media: media, link: nil, module: nil, glowColour: nil, engagement: PostEngagement(liked: false, saved: false, reposted: false, viewerReaction: nil, likeCount: 0, replyCount: 0, repostCount: 0, quoteCount: 0, reactionCount: 0))
    }
}

@MainActor final class POST03VideoCoordinatorTests: XCTestCase {
    func testOnlyMostVisibleEligibleVideoIsActive() {
        let coordinator = FeedVideoCoordinator(activationThreshold: 0.55)
        coordinator.updateVisibility(id: "a", fraction: 0.7)
        XCTAssertEqual(coordinator.activeVideoID, "a")
        coordinator.updateVisibility(id: "b", fraction: 0.9)
        XCTAssertEqual(coordinator.activeVideoID, "b")
        coordinator.updateVisibility(id: "b", fraction: 0.2)
        XCTAssertEqual(coordinator.activeVideoID, "a")
        coordinator.remove(id: "a")
        XCTAssertNil(coordinator.activeVideoID)
    }
}

final class POST03DownloadTests: XCTestCase {
    func testConcurrentDownloadsAreDeduplicated() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("document".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let downloader = CountingDownloader(source: source)
        let manager = AttachmentDownloadManager(downloader: downloader)
        let attachment = ModulaAttachment(id: "test-\(UUID().uuidString)", kind: .document, remoteURL: URL(string: "https://example.com/document.txt"), mimeType: "text/plain", filename: "document.txt")
        async let first = manager.download(attachment)
        async let second = manager.download(attachment)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b)
        let calls = await downloader.calls()
        let active = await manager.activeDownloadCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(active, 0)
        try await manager.remove(attachment)
    }
}

private actor CountingDownloader: AttachmentRemoteDownloading {
    let source: URL
    private var count = 0
    init(source: URL) { self.source = source }
    func download(from url: URL) async throws -> URL {
        count += 1
        try await Task.sleep(for: .milliseconds(30))
        return source
    }
    func calls() -> Int { count }
}
