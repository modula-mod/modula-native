import Foundation
import PDFKit

// MARK: - Reading position, bookmarks, and document heuristics (local only)

struct PDFReadingState: Codable, Equatable, Sendable {
    var lastPage: Int = 0
    var bookmarks: [Int] = []
    var updatedAt: Date = .distantPast
}

/// Last-read page and bookmarks per document, saved locally in UserDefaults.
final class PDFReadingStore: @unchecked Sendable {
    static let shared = PDFReadingStore()
    private let defaults: UserDefaults
    private let prefix = "modula.pdf.reading."
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func state(for key: String) -> PDFReadingState {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: prefix + key),
              let state = try? JSONDecoder().decode(PDFReadingState.self, from: data) else { return PDFReadingState() }
        return state
    }

    private func write(_ state: PDFReadingState, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: prefix + key) }
    }

    func lastPage(for key: String) -> Int { state(for: key).lastPage }

    func setLastPage(_ page: Int, for key: String, now: Date = Date()) {
        var value = state(for: key)
        guard value.lastPage != max(0, page) else { return }
        value.lastPage = max(0, page); value.updatedAt = now
        write(value, for: key)
    }

    func bookmarks(for key: String) -> [Int] { state(for: key).bookmarks }

    @discardableResult
    func toggleBookmark(_ page: Int, for key: String) -> Bool {
        var value = state(for: key)
        let added: Bool
        if let index = value.bookmarks.firstIndex(of: page) { value.bookmarks.remove(at: index); added = false }
        else { value.bookmarks.append(page); value.bookmarks.sort(); added = true }
        write(value, for: key)
        return added
    }

    func reset(_ key: String) { defaults.removeObject(forKey: prefix + key) }
}

enum PDFDocKind: String, Sendable {
    case document = "Document"
    case slides = "Slides"
    case brochure = "Brochure"

    static func classify(aspectRatio: CGFloat, pageCount: Int) -> PDFDocKind {
        if aspectRatio < 0.9 { return .slides }          // landscape pages → deck
        if pageCount > 0 && pageCount <= 4 && abs(aspectRatio - 1) < 0.15 { return .brochure }
        return .document
    }

    var symbol: String {
        switch self {
        case .document: "doc.text.fill"
        case .slides: "rectangle.on.rectangle.angled.fill"
        case .brochure: "book.pages.fill"
        }
    }
}

enum PDFReadingMath {
    static let wordsPerMinute = 230.0
    /// Minutes for a document from a sampled words-per-page average (min 1).
    static func readingMinutes(sampledWords: Int, sampledPages: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 1 }
        let perPage = sampledPages > 0 ? Double(sampledWords) / Double(sampledPages) : 0
        // Visual pages (few words) still take ~12s to look at.
        let seconds = Double(pageCount) * max(perPage / wordsPerMinute * 60, 12)
        return max(1, Int((seconds / 60).rounded()))
    }

    static func readingLabel(minutes: Int) -> String { minutes < 60 ? "\(minutes) min read" : "\(minutes / 60) h \(minutes % 60) min read" }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Page under a scrubber position (0…1).
    static func page(forFraction fraction: Double, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return min(pageCount - 1, Int((clamped * Double(pageCount)).rounded(.down)))
    }

    static func fraction(forPage page: Int, pageCount: Int) -> Double {
        guard pageCount > 1 else { return 0 }
        return Double(min(max(page, 0), pageCount - 1)) / Double(pageCount - 1)
    }

    /// Landscape two-page spreads: cover alone, then (1,2), (3,4)…
    static func spread(containing page: Int, pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let p = min(max(page, 0), pageCount - 1)
        if p == 0 { return [0] }
        let left = p.isMultiple(of: 2) ? p - 1 : p
        return [left, left + 1].filter { $0 < pageCount }
    }

    /// Dots for small docs, a continuous bar for long ones.
    static func usesDots(slideCount: Int) -> Bool { slideCount <= 12 }

    /// Should the inline card offer "Continue reading"?
    static func shouldOfferContinue(lastPage: Int, pageCount: Int) -> Bool { lastPage > 0 && (pageCount == 0 || lastPage < pageCount) }
}

struct PDFOutlineEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let page: Int
    let depth: Int

    static func flatten(_ root: PDFOutline?, in document: PDFDocument, maxEntries: Int = 500) -> [PDFOutlineEntry] {
        var result: [PDFOutlineEntry] = []
        func walk(_ item: PDFOutline, depth: Int) {
            for index in 0..<item.numberOfChildren {
                guard result.count < maxEntries, let child = item.child(at: index) else { return }
                if let page = child.destination?.page ?? (child.action as? PDFActionGoTo)?.destination.page {
                    result.append(PDFOutlineEntry(id: result.count, title: child.label ?? "Untitled", page: document.index(for: page), depth: depth))
                }
                walk(child, depth: depth + 1)
            }
        }
        if let root { walk(root, depth: 0) }
        return result
    }
}

extension PDFPageRenderer {
    /// Samples up to 6 pages of text for a reading-time estimate.
    func readingMinutes(url: URL) -> Int {
        guard let document = PDFDocument(url: url) else { return 1 }
        let count = document.pageCount
        let sample = Array(Set((0..<min(count, 6)).map { $0 * max(1, count / 6) })).filter { $0 < count }
        let words = sample.reduce(0) { $0 + PDFReadingMath.wordCount(document.page(at: $1)?.string ?? "") }
        return PDFReadingMath.readingMinutes(sampledWords: words, sampledPages: sample.count, pageCount: count)
    }
}
