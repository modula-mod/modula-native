import PDFKit
import SwiftUI
import UIKit

// MARK: - Immersive full-screen PDF reader
//
// Dark canvas, Liquid Glass chrome that hides on a single tap, thumbnail strip +
// grid overview, scrubber with preview bubble, double-tap smart zoom, text search
// with highlights, outline, landscape two-page spreads, bookmarks and last-read
// position (local), share page image / copy text / share document.

@MainActor
@Observable
final class PDFReaderModel {
    let url: URL
    let key: String
    let title: String
    private let store: PDFReadingStore

    private(set) var document: PDFDocument?
    private(set) var pageCount = 0
    var currentPage = 0 { didSet { if currentPage != oldValue { pageTick &+= 1; store.setLastPage(currentPage, for: key) } } }
    var chromeVisible = true
    private(set) var bookmarks: [Int] = []
    private(set) var outline: [PDFOutlineEntry] = []

    var searchQuery = ""
    private(set) var searchResults: [PDFSelection] = []
    private(set) var searchIndex = 0
    private(set) var searching = false

    /// Haptic triggers.
    private(set) var pageTick = 0
    private(set) var zoomTick = 0
    private(set) var bookmarkTick = 0

    @ObservationIgnored weak var pdfView: PDFView?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        url: URL,
        key: String,
        title: String,
        startPage: Int?,
        store: PDFReadingStore = .shared,
        document suppliedDocument: PDFDocument? = nil
    ) {
        self.url = url
        self.key = key
        self.title = title
        self.store = store
        let document = suppliedDocument ?? PDFDocument(url: url)
        self.document = document
        self.pageCount = document?.pageCount ?? 0
        self.bookmarks = store.bookmarks(for: key)
        let initial = startPage ?? store.lastPage(for: key)
        self.currentPage = min(max(initial, 0), max(pageCount - 1, 0))
        if let document { outline = PDFOutlineEntry.flatten(document.outlineRoot, in: document) }
    }

    var isBookmarked: Bool { bookmarks.contains(currentPage) }
    var counterText: String { pageCount > 0 ? "\(currentPage + 1) / \(pageCount)" : "" }
    var currentPageText: String { document?.page(at: currentPage)?.string ?? "" }

    func attach(_ view: PDFView) {
        pdfView = view
        go(to: currentPage, animated: false)
    }

    func go(to page: Int, animated: Bool = true) {
        guard pageCount > 0 else { return }
        let target = min(max(page, 0), pageCount - 1)
        currentPage = target
        guard let view = pdfView, let pdfPage = document?.page(at: target), view.currentPage !== pdfPage else { return }
        view.go(to: pdfPage)
    }

    /// Set when the reader is closing so PDFView teardown can't overwrite the position.
    @ObservationIgnored private(set) var isClosing = false

    func pageChanged(to page: Int) {
        guard !isClosing, page != currentPage else { return }
        currentPage = page
    }

    func close() {
        store.setLastPage(currentPage, for: key)
        isClosing = true
    }

    func toggleChrome() { chromeVisible.toggle() }

    func toggleBookmark() {
        store.toggleBookmark(currentPage, for: key)
        bookmarks = store.bookmarks(for: key)
        bookmarkTick &+= 1
    }

    func didZoom() { zoomTick &+= 1 }

    // Search (debounced; PDFKit find on the main actor, results highlighted in place).
    func updateSearch(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.runSearch()
        }
    }

    private func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let document, query.count >= 2 else { clearSearch(keepQuery: true); return }
        searching = true
        let found = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchResults = Array(found.prefix(500))
        searchResults.forEach { $0.color = UIColor.systemYellow.withAlphaComponent(0.55) }
        searchIndex = 0
        searching = false
        pdfView?.highlightedSelections = searchResults
        focusResult()
    }

    func nextResult(_ step: Int = 1) {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + step + searchResults.count) % searchResults.count
        focusResult()
    }

    private func focusResult() {
        guard searchResults.indices.contains(searchIndex) else { return }
        let selection = searchResults[searchIndex]
        if let page = selection.pages.first, let index = document?.index(for: page) { currentPage = index }
        pdfView?.go(to: selection)
        pdfView?.setCurrentSelection(selection, animate: true)
    }

    func clearSearch(keepQuery: Bool = false) {
        if !keepQuery { searchQuery = "" }
        searchResults = []
        searchIndex = 0
        pdfView?.highlightedSelections = nil
        pdfView?.clearSelection()
    }

    var searchSummary: String {
        if searching { return "Searching…" }
        if searchQuery.trimmingCharacters(in: .whitespaces).count < 2 { return "" }
        return searchResults.isEmpty ? "No results" : "\(searchIndex + 1) of \(searchResults.count)"
    }
}

struct ModulaPDFImmersiveReader: View {
    @State private var model: PDFReaderModel
    var onDismiss: () -> Void

    @State private var showsGrid = false
    @State private var showsOutline = false
    @State private var showsSearch = false
    @State private var shareItems: [Any]?
    @State private var copiedTick = 0
    @State private var scrubPage: Int?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app

    init(url: URL, key: String, title: String, startPage: Int? = nil, onDismiss: @escaping () -> Void) {
        _model = State(initialValue: PDFReaderModel(url: url, key: key, title: title, startPage: startPage))
        self.onDismiss = onDismiss
    }

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if model.document != nil {
                    PDFReaderCanvas(model: model, twoUp: landscape && model.pageCount > 2)
                        .ignoresSafeArea()
                        .accessibilityIdentifier("pdf.reader")
                        .accessibilityLabel("\(model.title), page \(model.currentPage + 1) of \(model.pageCount)")
                } else {
                    ContentUnavailableView("PDF unavailable", systemImage: "doc.richtext", description: Text("This file couldn’t be opened."))
                        .foregroundStyle(.white)
                }
                if model.chromeVisible {
                    chrome(landscape: landscape)
                        .transition(.opacity)
                }
            }
        }
        .onDisappear { model.close() }
        .preferredColorScheme(.dark)
        .statusBarHidden(!model.chromeVisible)
        .persistentSystemOverlays(model.chromeVisible ? .automatic : .hidden)
        .animation(motion, value: model.chromeVisible)
        .sensoryFeedback(.selection, trigger: model.pageTick)
        .sensoryFeedback(.impact(weight: .light), trigger: model.zoomTick)
        .sensoryFeedback(.success, trigger: model.bookmarkTick)
        .sensoryFeedback(.success, trigger: copiedTick)
        .sheet(isPresented: $showsGrid) { PDFPageGridSheet(model: model) { showsGrid = false } }
        .sheet(isPresented: $showsOutline) { PDFOutlineSheet(model: model) { showsOutline = false } }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            ActivitySheet(items: shareItems ?? []).presentationDetents([.medium, .large])
        }
    }

    // MARK: Chrome

    private func chrome(landscape: Bool) -> some View {
        VStack(spacing: 10) {
            topBar
            if showsSearch { searchBar }
            Spacer(minLength: 0)
            if let scrubPage { previewBubble(scrubPage) }
            if !landscape || model.pageCount <= 40 { thumbnailStrip }
            scrubber
        }
        .padding(.horizontal, ModulaSpacing.sm)
        .padding(.bottom, 4)
    }

    private var topBar: some View {
        ModulaGlassGroup(spacing: 10) {
            HStack(spacing: 8) {
                ModulaGlassIconButton(title: "Close reader", systemImage: "chevron.down", size: 40) { model.close(); onDismiss() }
                    .accessibilityIdentifier("pdf.reader.close")
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.counterText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("pdf.reader.counter")
                        .accessibilityLabel("Page \(model.currentPage + 1) of \(model.pageCount)")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modulaGlass(in: Capsule(), interactive: false)
                ModulaGlassIconButton(title: "Search in document", systemImage: "magnifyingglass", size: 40) {
                    withAnimation(motion) { showsSearch.toggle() }
                    searchFocused = showsSearch
                    if !showsSearch { model.clearSearch() }
                }
                .accessibilityIdentifier("pdf.reader.search")
                ModulaGlassIconButton(title: model.isBookmarked ? "Remove bookmark" : "Bookmark page",
                                      systemImage: model.isBookmarked ? "bookmark.fill" : "bookmark",
                                      size: 40, tint: model.isBookmarked ? app.appearance.accent.color : nil) { model.toggleBookmark() }
                    .accessibilityIdentifier("pdf.reader.bookmark")
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("All pages", systemImage: "square.grid.2x2") { showsGrid = true }
            if !model.outline.isEmpty || !model.bookmarks.isEmpty {
                Button("Contents & bookmarks", systemImage: "list.bullet.indent") { showsOutline = true }
            }
            Divider()
            Button("Share page as image", systemImage: "photo") { sharePageImage() }
            Button("Copy page text", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = model.currentPageText
                copiedTick &+= 1
            }
            .disabled(model.currentPageText.isEmpty)
            Button("Save or share PDF", systemImage: "square.and.arrow.up") { shareItems = [model.url] }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .modulaGlass(in: Circle(), specular: true)
        .accessibilityLabel("More actions")
        .accessibilityIdentifier("pdf.reader.more")
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search text", text: Binding(get: { model.searchQuery }, set: { model.updateSearch($0) }))
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { model.nextResult() }
                .accessibilityIdentifier("pdf.reader.searchField")
            Text(model.searchSummary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityIdentifier("pdf.reader.searchSummary")
            Button { model.nextResult(-1) } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Previous match").disabled(model.searchResults.isEmpty)
            Button { model.nextResult() } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Next match").disabled(model.searchResults.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .modulaGlass(in: Capsule(), interactive: false)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        Button { model.go(to: index) } label: {
                            PDFThumbnailCell(url: model.url, page: index, width: 34)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4).stroke(index == model.currentPage ? app.appearance.accent.color : .clear, lineWidth: 2)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if model.bookmarks.contains(index) {
                                        Image(systemName: "bookmark.fill").font(.system(size: 8)).foregroundStyle(app.appearance.accent.color).padding(2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Page \(index + 1)")
                        .accessibilityAddTraits(index == model.currentPage ? .isSelected : [])
                        .id(index)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .frame(height: 60)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
            .accessibilityIdentifier("pdf.reader.thumbnails")
            .onChange(of: model.currentPage, initial: true) { _, page in
                withAnimation(motion) { reader.scrollTo(page, anchor: .center) }
            }
        }
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let fraction = PDFReadingMath.fraction(forPage: scrubPage ?? model.currentPage, pageCount: model.pageCount)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(app.appearance.accent.color).frame(width: max(4, proxy.size.width * fraction), height: 4)
                Circle().fill(.white).frame(width: scrubPage == nil ? 14 : 20, height: scrubPage == nil ? 14 : 20)
                    .shadow(radius: 3)
                    .offset(x: max(0, proxy.size.width * fraction - 10))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let page = PDFReadingMath.page(forFraction: value.location.x / max(proxy.size.width, 1), pageCount: model.pageCount)
                        if page != scrubPage { scrubPage = page }
                    }
                    .onEnded { _ in
                        if let scrubPage { model.go(to: scrubPage) }
                        scrubPage = nil
                    }
            )
        }
        .frame(height: 30)
        .padding(.horizontal, 16)
        .modulaGlass(in: Capsule(), interactive: false)
        .sensoryFeedback(.selection, trigger: scrubPage)
        .accessibilityElement()
        .accessibilityIdentifier("pdf.reader.scrubber")
        .accessibilityLabel("Page scrubber")
        .accessibilityValue("Page \(model.currentPage + 1) of \(model.pageCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.go(to: model.currentPage + 1)
            case .decrement: model.go(to: model.currentPage - 1)
            @unknown default: break
            }
        }
    }

    private func previewBubble(_ page: Int) -> some View {
        VStack(spacing: 6) {
            PDFThumbnailCell(url: model.url, page: page, width: 110)
            Text("Page \(page + 1)").font(.caption.weight(.semibold).monospacedDigit())
        }
        .padding(10)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
        .accessibilityIdentifier("pdf.reader.preview")
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func sharePageImage() {
        let url = model.url, page = model.currentPage
        Task {
            if let image = try? await PDFPageRenderer.shared.render(url: url, page: page, quality: .sharp, pixelWidth: 1_600) {
                shareItems = [image]
            }
        }
    }
}

// MARK: - PDFView bridge

struct PDFReaderCanvas: UIViewRepresentable {
    let model: PDFReaderModel
    let twoUp: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .black
        view.displayDirection = .horizontal
        view.pageShadowsEnabled = true
        view.document = model.document
        context.coordinator.install(on: view)
        Self.configure(view, twoUp: twoUp)
        context.coordinator.twoUp = twoUp
        model.attach(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.twoUp != twoUp else { return }
        context.coordinator.twoUp = twoUp
        Self.configure(view, twoUp: twoUp)
        model.go(to: model.currentPage, animated: false)
    }

    static func configure(_ view: PDFView, twoUp: Bool) {
        if twoUp {
            view.usePageViewController(false)
            view.displayMode = .twoUp
            view.displaysAsBook = true
        } else {
            view.displayMode = .singlePage
            view.displaysAsBook = false
            view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 20])
        }
        view.autoScales = true
        DispatchQueue.main.async {
            view.minScaleFactor = view.scaleFactorForSizeToFit
            view.maxScaleFactor = max(view.scaleFactorForSizeToFit * 6, 4)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: PDFReaderModel
        var twoUp = false

        init(model: PDFReaderModel) { self.model = model }

        func install(on view: PDFView) {
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            double.delegate = self
            let single = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
            single.require(toFail: double)
            single.delegate = self
            let left = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:))); left.direction = .left; left.delegate = self
            let right = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:))); right.direction = .right; right.delegate = self
            [double, single, left, right].forEach(view.addGestureRecognizer)
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        }

        @objc private func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, view.window != nil, let page = view.currentPage, let document = view.document else { return }
            model.pageChanged(to: document.index(for: page))
        }

        @objc private func singleTap(_ gesture: UITapGestureRecognizer) { model.toggleChrome() }

        /// Spread mode has no page controller; swipe flips spreads (only when not zoomed).
        @objc private func swipe(_ gesture: UISwipeGestureRecognizer) {
            guard twoUp, let view = gesture.view as? PDFView, view.scaleFactor <= view.scaleFactorForSizeToFit * 1.05 else { return }
            if gesture.direction == .left { view.goToNextPage(nil) } else { view.goToPreviousPage(nil) }
        }

        /// Smart zoom: fit ↔ 2.5× centred on the tapped point.
        @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PDFView else { return }
            let fit = view.scaleFactorForSizeToFit
            if view.scaleFactor > fit * 1.2 {
                view.scaleFactor = fit
            } else {
                let point = gesture.location(in: view)
                guard let page = view.page(for: point, nearest: true) else { return }
                let pagePoint = view.convert(point, to: page)
                view.scaleFactor = fit * 2.5
                view.go(to: CGRect(x: pagePoint.x - 60, y: pagePoint.y - 60, width: 120, height: 120), on: page)
            }
            model.didZoom()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

// MARK: - Thumbnails, grid, outline, share

struct PDFThumbnailCell: View {
    let url: URL
    let page: Int
    let width: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Color.white.opacity(0.12).aspectRatio(0.72, contentMode: .fit) }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .task(id: page) {
            image = try? await PDFPageRenderer.shared.render(url: url, page: page, quality: .thumbnail, pixelWidth: PDFCarouselMath.thumbnailPixelWidth)
        }
    }
}

struct PDFPageGridSheet: View {
    let model: PDFReaderModel
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 16) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        Button {
                            model.go(to: index); onClose()
                        } label: {
                            VStack(spacing: 4) {
                                PDFThumbnailCell(url: model.url, page: index, width: 96)
                                    .overlay { if index == model.currentPage { RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 2) } }
                                Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to page \(index + 1)")
                    }
                }
                .padding()
            }
            .navigationTitle("All pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
        }
        .accessibilityIdentifier("pdf.reader.grid")
    }
}

struct PDFOutlineSheet: View {
    let model: PDFReaderModel
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !model.bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(model.bookmarks, id: \.self) { page in
                            Button { model.go(to: page); onClose() } label: {
                                Label("Page \(page + 1)", systemImage: "bookmark.fill")
                            }
                        }
                    }
                }
                if !model.outline.isEmpty {
                    Section("Contents") {
                        ForEach(model.outline) { entry in
                            Button { model.go(to: entry.page); onClose() } label: {
                                HStack {
                                    Text(entry.title).padding(.leading, CGFloat(entry.depth) * 14)
                                    Spacer()
                                    Text("\(entry.page + 1)").monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("\(entry.title), page \(entry.page + 1)")
                        }
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
        }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
