#if DEBUG
import SwiftUI
import UIKit
import PDFKit

/// DEBUG-only lab for inline PDF posts. Launch with `--debug-pdf-lab` to render a
/// small feed of PDF posts backed by a locally generated sample document (no
/// network, no session). Used by `PDFInlinePostUITests` and for screenshots.
enum PDFInlineLab {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--debug-pdf-lab") }

    /// Writes (once) a multi-page sample PDF into the caches directory.
    static func sampleURL(pages: Int = 8) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("modula-pdf-lab-v2-\(pages).pdf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let colors: [UIColor] = [UIColor(red: 0.21, green: 0.61, blue: 0.67, alpha: 1), .systemIndigo, .systemOrange, .systemPink, .systemGreen, .systemPurple]
        let data = renderer.pdfData { context in
            for index in 0..<pages {
                context.beginPage()
                let color = colors[index % colors.count]
                color.withAlphaComponent(0.12).setFill()
                UIRectFill(bounds)
                color.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: bounds.width, height: 220))
                let title = index == 0 ? "Modula Design System" : "Chapter \(index)"
                (title as NSString).draw(at: CGPoint(x: 48, y: 90), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40), .foregroundColor: UIColor.white])
                ("Page \(index + 1) of \(pages)" as NSString).draw(at: CGPoint(x: 48, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.white.withAlphaComponent(0.85)])
                let body = String(repeating: "Liquid Glass surfaces, image-led hierarchy and calm motion. ", count: 14)
                (body as NSString).draw(in: CGRect(x: 48, y: 260, width: bounds.width - 96, height: 460), withAttributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.darkGray])
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(x: 48, y: 600, width: bounds.width - 96, height: 140), cornerRadius: 18).fill()
            }
        }
        // Add an outline (table of contents) so the reader's Contents sheet has entries.
        if let document = PDFDocument(data: data) {
            let root = PDFOutline()
            for index in 0..<pages {
                guard let page = document.page(at: index) else { continue }
                let item = PDFOutline()
                item.label = index == 0 ? "Cover" : "Chapter \(index)"
                item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
                root.insertChild(item, at: root.numberOfChildren)
            }
            document.outlineRoot = root
            if document.write(to: url) { return url }
        }
        try? data.write(to: url, options: .atomic)
        return url
    }

    static func attachment(id: String, name: String, pages: Int) -> ModulaAttachment {
        let url = sampleURL(pages: pages)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        return ModulaAttachment(id: id, kind: .pdf, remoteURL: nil, localFileURL: url, mimeType: "application/pdf", filename: name, byteSize: bytes, metadata: AttachmentMetadata(pageCount: pages))
    }
}

struct PDFInlineLabView: View {
    @State private var opened: ModulaAttachment?
    private let posts: [(String, ModulaAttachment)] = [
        ("Our new design system is live. Swipe through the highlights.", PDFInlineLab.attachment(id: "lab-pdf-1", name: "Modula Design System.pdf", pages: 8)),
        ("Q3 roadmap, short version.", PDFInlineLab.attachment(id: "lab-pdf-2", name: "Roadmap Q3.pdf", pages: 5))
    ]

    init() {
        // Each lab launch starts with no saved reading position.
        ["lab-pdf-1", "lab-pdf-2"].forEach { PDFReadingStore.shared.reset($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                    ForEach(posts, id: \.1.id) { post in
                        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                            HStack(spacing: ModulaSpacing.sm) {
                                Circle().fill(Color.accentColor.opacity(0.4)).frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Alex Rivers").font(.subheadline.weight(.semibold))
                                    Text("2h · Public").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(post.0).font(.body)
                            ModulaPDFSurface(attachment: post.1) { opened = post.1 }
                        }
                        .padding(.horizontal, ModulaSpacing.md)
                    }
                }
                .padding(.vertical, ModulaSpacing.md)
            }
            .navigationTitle("PDF Posts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $opened) { attachment in
            ModulaPDFViewer(attachment: attachment) { opened = nil }
        }
    }
}
#endif
