import Foundation
import PDFKit
import UniformTypeIdentifiers

struct NodusExtractedKnowledge: Sendable, Equatable {
    let title: String
    let sourceType: NodusKnowledgeSourceType
    let sourceName: String
    let text: String
    let locations: [Int: String]
}

struct NodusKnowledgeImporter: Sendable {
    let maximumBytes = 20_000_000

    func extract(from url: URL) throws -> NodusExtractedKnowledge {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maximumBytes { throw NodusKnowledgeImportError.fileTooLarge }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            return try textDocument(url: url, type: .markdown)
        case "txt":
            return try textDocument(url: url, type: .txt)
        case "json":
            return try textDocument(url: url, type: .json)
        case "pdf":
            return try pdfDocument(url: url)
        default:
            throw NodusKnowledgeImportError.unsupportedType
        }
    }

    private func textDocument(url: URL, type: NodusKnowledgeSourceType) throws -> NodusExtractedKnowledge {
        guard let data = try? Data(contentsOf: url), data.count <= maximumBytes,
              let text = String(data: data, encoding: .utf8) else {
            throw NodusKnowledgeImportError.unreadable
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NodusKnowledgeImportError.emptyText
        }
        return NodusExtractedKnowledge(
            title: url.deletingPathExtension().lastPathComponent,
            sourceType: type,
            sourceName: url.lastPathComponent,
            text: text,
            locations: [:]
        )
    }

    private func pdfDocument(url: URL) throws -> NodusExtractedKnowledge {
        guard let document = PDFDocument(url: url) else { throw NodusKnowledgeImportError.unreadable }
        var pages: [String] = []
        var locations: [Int: String] = [:]
        for pageIndex in 0 ..< document.pageCount {
            let text = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }
            locations[pages.count] = "p. \(pageIndex + 1)"
            pages.append(text)
        }
        guard !pages.isEmpty else { throw NodusKnowledgeImportError.noExtractableText }
        return NodusExtractedKnowledge(
            title: document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                ?? url.deletingPathExtension().lastPathComponent,
            sourceType: .pdf,
            sourceName: url.lastPathComponent,
            text: pages.joined(separator: "\n\n"),
            locations: locations
        )
    }
}

