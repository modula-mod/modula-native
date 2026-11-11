import SwiftUI


/// Destinations that live in the global sidebar instead of the five root tabs.
/// Add cases here as new shell surfaces land — do not put Home/Discover/Modules/Activity/Profile in this list.
enum ShellSidebarDestination: String, CaseIterable, Identifiable {
    case saved
    case drafts
    case collections
    case settings
    case appearance
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved: "Saved"
        case .drafts: "Drafts"
        case .collections: "Collections"
        case .settings: "Settings"
        case .appearance: "Appearance"
        case .developer: "Module Studio"
        }
    }

    var subtitle: String? {
        switch self {
        case .saved: "Bookmarks and later"
        case .drafts: "Unpublished work"
        case .collections: "Private groupings"
        case .settings: "Account and device"
        case .appearance: "Theme, type and motion"
        case .developer: "Create and edit modules"
        }
    }

    var symbol: String {
        switch self {
        case .saved: "bookmark"
        case .drafts: "doc.text"
        case .collections: "rectangle.stack"
        case .settings: "gearshape"
        case .appearance: "paintpalette"
        case .developer: "wrench.and.screwdriver"
        }
    }

    var tint: Color {
        switch self {
        case .saved: .orange
        case .drafts: .blue
        case .collections: .purple
        case .settings: .gray
        case .appearance: .pink
        case .developer: .indigo
        }
    }

    var route: AppRoute {
        switch self {
        case .saved: .saved(.root)
        case .drafts: .drafts(.root)
        case .collections: .collections(.root)
        case .settings: .settings(.root)
        case .appearance: .settings(.appearance(.root))
        case .developer: .developer(.studio)
        }
    }

    var requiresSignIn: Bool {
        switch self {
        case .saved, .drafts, .collections: true
        case .settings, .appearance, .developer: false
        }
    }

    var section: Section {
        switch self {
        case .saved, .drafts, .collections: .library
        case .settings, .appearance: .manage
        case .developer: .developer
        }
    }

    enum Section: String, CaseIterable, Identifiable {
        case library
        case manage
        case developer
        var id: String { rawValue }
        var title: String {
            switch self {
            case .library: "Library"
            case .manage: "Manage"
            case .developer: "Developer"
            }
        }
    }
}

/// Overlay drawer. The main screen stays put at full size (no scale, no rounding); a floating
/// glass card slides in from the left over it, with a light dim behind. Drag is interactive
/// (edge swipe to open, drag the card or the dim to close) and only drives `offset`/`opacity`
/// — render properties, never layout — so it tracks the finger at 120 Hz.
struct ShellSidebarContainer<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// Live finger translation; resets on end *or cancel*, so the card can't park half-open.
    @GestureState(resetTransaction: Transaction(animation: ShellSidebarContainer.settleSpring))
    private var drag: CGFloat = 0
    @GestureState private var dragging = false

    /// Quick, crisp, critically damped (no bounce).
    static var settleSpring: Animation { .spring(duration: 0.3, bounce: 0) }

    /// Gap between the floating card and the screen edges.
    static var cardInset: CGFloat { ModulaSpacing.xs }

    /// Approximates the hardware display corner radius from the top safe-area inset (public API only):
    /// Dynamic Island Pro/Air ≈ 62, Dynamic Island/notch ≈ 55, older notch ≈ 47, home-button ≈ 28 (soft card).
    static func displayCornerRadius(safeTop: CGFloat) -> CGFloat {
        switch safeTop {
        case 59...: 62
        case 50..<59: 55
        case 44..<50: 47
        default: 28
        }
    }

    /// Concentric with the display: display radius minus the inset.
    static func cardRadius(safeTop: CGFloat) -> CGFloat {
        max(displayCornerRadius(safeTop: safeTop) - cardInset, ModulaRadius.large)
    }

    var body: some View {
        let presented = app.navigation.sidebarPresented
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let fullWidth = geometry.size.width + insets.leading + insets.trailing
            let width = Self.sidebarWidth(for: fullWidth)
            let base: CGFloat = presented ? width : 0
            let offset = min(max(base + drag, 0), width)
            let progress = width > 0 ? offset / width : 0
            let visible = presented || dragging || progress > 0.001
            let radius = Self.cardRadius(safeTop: insets.top)
            let travel = width + Self.cardInset + 24 // fully off-screen including shadow

            ZStack(alignment: .topLeading) {
                content
                    .coordinateSpace(.named(ShellChromeFreeze.cardSpace))
                    .accessibilityHidden(presented)
                    .onChange(of: dragging) { _, isDragging in
                        ShellChromeFreeze.isSidebarDragging = isDragging
                        if !isDragging, !app.navigation.sidebarPresented { ShellChromeFreeze.holdForSettle() }
                    }
                    .onChange(of: app.navigation.selectedStackHasPushedViews) { _, pushed in
                        if pushed, app.navigation.sidebarPresented { close(haptic: false) }
                    }
                    .overlay(alignment: .leading) {
                        // Mutually exclusive with the navigation back swipe: only on a stack root.
                        if !presented, app.appearance.edgePicker.side != .left,
                           !app.navigation.selectedStackHasPushedViews, app.navigation.presented == nil {
                            Color.clear
                                .frame(width: 22)
                                .contentShape(Rectangle())
                                .ignoresSafeArea(edges: .leading)
                                .highPriorityGesture(openDrag(width: width))
                                .accessibilityHidden(true)
                        }
                    }

                if visible {
                    // Light dim over the untouched main screen; tap or drag it to close.
                    Color.black
                        .opacity((scheme == .dark ? 0.32 : 0.18) * progress)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .highPriorityGesture(closeDrag(width: width))
                        .simultaneousGesture(TapGesture().onEnded { close(haptic: true) })
                        .accessibilityLabel("Close sidebar")
                        .accessibilityIdentifier("shell.sidebar.scrim")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHidden(!presented)

                    ShellSidebarView(width: width, onSelect: open, onClose: { close(haptic: true) })
                        // Content respects the safe areas; the card itself floats concentric to the display.
                        .padding(.top, max(insets.top - Self.cardInset, ModulaSpacing.sm))
                        .padding(.bottom, max(insets.bottom - Self.cardInset, ModulaSpacing.sm))
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background { ShellSidebarCardBackground(radius: radius) }
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .shadow(color: .black.opacity(0.18 * progress), radius: 28, x: 6, y: 0)
                        .padding(Self.cardInset)
                        .ignoresSafeArea()
                        .offset(x: reduceMotion ? 0 : (progress - 1) * travel)
                        .opacity(reduceMotion ? progress : 1)
                        .simultaneousGesture(closeDrag(width: width))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close(haptic: true) }
                        .onKeyPress(.escape) {
                            close(haptic: true)
                            return .handled
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(settle, value: presented)
    }

    static func sidebarWidth(for total: CGFloat) -> CGFloat {
        min(total * 0.82, 380)
    }

    /// Velocity-aware decision used by both gestures: projected end beats raw distance.
    static func shouldEndOpen(translation: CGFloat, predicted: CGFloat, startOpen: Bool, width: CGFloat) -> Bool {
        let base: CGFloat = startOpen ? width : 0
        let projected = base + predicted
        let current = base + translation
        if abs(predicted - translation) > width * 0.25 { return projected > width / 2 }
        return current > width / 2
    }

    /// Reduce Motion: a short crossfade instead of the slide.
    private var settle: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Self.settleSpring
    }

    private func openDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragging) { value, state, _ in
                if value.startLocation.x < 30 { state = true; ShellChromeFreeze.isSidebarDragging = true }
            }
            .updating($drag) { value, state, transaction in
                guard value.startLocation.x < 30 else { return }
                transaction.disablesAnimations = true
                state = min(max(0, value.translation.width), width)
            }
            .onEnded { value in
                ShellChromeFreeze.isSidebarDragging = false
                guard value.startLocation.x < 30, !app.navigation.selectedStackHasPushedViews else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let open = Self.shouldEndOpen(translation: value.translation.width,
                                              predicted: value.predictedEndTranslation.width,
                                              startOpen: false, width: width)
                ShellChromeFreeze.holdForSettle()
                withAnimation(settle) {
                    if open { app.navigation.presentSidebar() } else { app.navigation.dismissSidebar() }
                }
                if open { HapticEngine.shared.play(.contextOpen) }
            }
    }

    private func closeDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($dragging) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = true; ShellChromeFreeze.isSidebarDragging = true
            }
            .updating($drag) { value, state, transaction in
                // Mostly-vertical drags belong to the sidebar's scroll view.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                transaction.disablesAnimations = true
                state = max(min(0, value.translation.width), -width)
            }
            .onEnded { value in
                ShellChromeFreeze.isSidebarDragging = false
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let open = Self.shouldEndOpen(translation: value.translation.width,
                                              predicted: value.predictedEndTranslation.width,
                                              startOpen: true, width: width)
                ShellChromeFreeze.holdForSettle()
                withAnimation(settle) {
                    if open { app.navigation.presentSidebar() } else { app.navigation.dismissSidebar() }
                }
                if !open { HapticEngine.shared.play(.navigation) }
            }
    }

    private func close(haptic: Bool) {
        ShellChromeFreeze.holdForSettle()
        withAnimation(settle) { app.navigation.dismissSidebar() }
        if haptic { HapticEngine.shared.play(.navigation) }
    }

    private func open(_ route: AppRoute, requiresSignIn: Bool) {
        close(haptic: false)
        if requiresSignIn, !app.auth.isSignedIn {
            app.navigation.requestAuthentication(returningTo: route)
        } else {
            app.navigation.open(route)
        }
        HapticEngine.shared.play(.navigation)
    }
}

/// Floating card surface: modulaGlass, or an opaque design-token canvas under Reduce Transparency.
private struct ShellSidebarCardBackground: View {
    let radius: CGFloat
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if reduceTransparency {
                shape.fill(ModulaPalette.resolve(app.appearance, scheme: scheme).canvas)
            } else {
                shape.fill(.clear).modulaGlass(in: shape, interactive: false)
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// One sidebar row: monochrome glyph + title (+ optional badge).
struct ShellSidebarItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let route: AppRoute
    let requiresSignIn: Bool
    var badge: Int = 0
    /// Extra words matched by the inline search (never shown).
    var keywords: String = ""
}

/// ChatGPT-density sidebar inside the floating glass card. Top to bottom: bold title + round search
/// (filters destinations inline), tight primary rows, Library, Pinned and Recents chats from data the
/// messaging store already holds (hidden when empty, never invented), a collapsed Developer group in
/// debug builds, then a compact footer: profile chip, settings gear and a small floating New post pill.
/// Plain fills only (no nested blur), so drag-to-open stays at display rate.
struct ShellSidebarView: View {
    var width: CGFloat = 320
    var onSelect: (AppRoute, Bool) -> Void
    var onClose: () -> Void = {}
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(ModulaMascotSettings.kindKey) private var mascotRaw = ModulaMascotKind.pip.rawValue
    @AppStorage("shell.sidebar.developerExpanded") private var developerExpanded = false
    @State private var query = ""
    /// Local-only, newest first, newline separated (never synced).
    @AppStorage("shell.sidebar.recentSearches") private var recentSearchesRaw = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    /// Scales with Dynamic Type; 40pt at the default size (tighter than the old 46pt rows).
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var wordmarkScaled: CGFloat = 26
    private var wordmarkHeight: CGFloat { min(wordmarkScaled, 34) }

    private let rowInset = ModulaSpacing.sm
    private static let recentLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, ModulaSpacing.md)
                .padding(.top, ModulaSpacing.xs)
            if searching {
                searchField
                    .padding(.horizontal, ModulaSpacing.sm)
                    .padding(.top, ModulaSpacing.xs)
                    .transition(.opacity)
            }

            let chats = chatLists
            ScrollView {
                VStack(alignment: .leading, spacing: ModulaSpacing.md) {
                    if isFiltering {
                        searchResults(chats: chats)
                    } else if searching, !recentSearches.isEmpty {
                        recentSearchSection
                        section(nil) { ForEach(primaryItems) { row($0) } }
                    } else {
                        section(nil) { ForEach(primaryItems) { row($0) } }
                        section("Library") { ForEach(libraryItems) { row($0) } }
                        if !chats.pinned.isEmpty {
                            section("Pinned") { ForEach(chats.pinned) { chatRow($0) } }
                        }
                        if !chats.recent.isEmpty {
                            section("Recents") { ForEach(chats.recent) { chatRow($0) } }
                        }
                        developerGroup
                    }
                }
                .padding(.horizontal, ModulaSpacing.xs)
                .padding(.top, ModulaSpacing.sm)
                .padding(.bottom, ModulaSpacing.lg)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .modulaSoftScrollEdge()

            footer
                .padding(.horizontal, ModulaSpacing.sm)
                .padding(.bottom, ModulaSpacing.xs)
                .padding(.top, ModulaSpacing.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: searching)
        .onChange(of: app.navigation.sidebarPresented) { _, presented in
            if !presented { endSearch() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shell.sidebar")
        .accessibilityLabel("Sidebar")
    }

    // MARK: Header

    private var mascot: ModulaMascotKind? {
        mascotRaw == ModulaMascotSettings.off ? nil : ModulaMascotKind(rawValue: mascotRaw)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ModulaSpacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                // Same brand wordmark asset as the Home top bar (follows the wordmark setting).
                Group {
                    switch app.appearance.brandWordmark {
                    case .modula: ModulaWordmark(height: wordmarkHeight)
                    case .moliboos: MoliboosWordmark(height: wordmarkHeight)
                    }
                }
                .frame(maxWidth: width - 120, alignment: .leading)
                .padding(.vertical, 4)
                .accessibilityAddTraits(.isHeader)
                if let mascot, app.auth.isSignedIn {
                    Text("\(greeting) from \(mascot.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("shell.sidebar.moliboo")
                }
            }
            Spacer(minLength: 0)
            Button {
                if searching { endSearch() } else { searching = true; searchFocused = true }
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: searching ? "xmark" : "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searching ? "Close search" : "Search sidebar")
            .accessibilityIdentifier("shell.sidebar.search")
        }
    }

    private var searchField: some View {
        HStack(spacing: ModulaSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search destinations", text: $query)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit {
                    rememberQuery()
                    if let first = filteredItems.first { onSelect(first.route, first.requiresSignIn) }
                }
                .accessibilityIdentifier("shell.sidebar.search.field")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, ModulaSpacing.sm)
        .frame(minHeight: 40)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), interactive: true)
    }

    private func endSearch() {
        query = ""
        searchFocused = false
        searching = false
    }

    // MARK: Destinations

    private var primaryItems: [ShellSidebarItem] {
        var items: [ShellSidebarItem] = [
            .init(id: "messages", title: "Messages", symbol: "bubble.left.and.bubble.right",
                  route: .messages(.inbox), requiresSignIn: true, badge: app.messaging.accountUnreadCount ?? 0,
                  keywords: "chat dm inbox"),
            .init(id: "notifications", title: "Alerts", symbol: "bell",
                  route: .activity(.all), requiresSignIn: true, badge: app.activity.state(for: .all).unreadCount ?? 0,
                  keywords: "notifications activity"),
            .init(id: "reels", title: "Reels", symbol: "play.rectangle.on.rectangle",
                  route: .reels(.feed), requiresSignIn: false, keywords: "videos clips watch"),
            .init(id: "story", title: "New story", symbol: "circle.dashed.inset.filled",
                  route: .stories(.create), requiresSignIn: true, keywords: "stories camera add"),
            .init(id: "vault", title: "Vault", symbol: "lock.doc",
                  route: .module("digital.modula.vault-notes", localPath: nil), requiresSignIn: true, keywords: "notes"),
        ]
        if GubicFeature.enabled() {
            items.append(.init(id: "games", title: "GUBIC", symbol: "gamecontroller", route: .productHub(.gubic), requiresSignIn: false, keywords: "games"))
        }
        items.append(.init(id: "moliboos", title: "Moliboos", symbol: "sparkles", route: .settings(.moliboo), requiresSignIn: false, keywords: "mascot pet"))
        // Premium is gated: the upsell row only appears for free accounts.
        if !PremiumEntitlementStore.shared.plan.isPaid {
            items.append(.init(id: "premium", title: "Premium", symbol: "sun.horizon", route: .settings(.premium(.root)), requiresSignIn: false))
        }
        return items
    }

    private var libraryItems: [ShellSidebarItem] {
        var items = ShellSidebarDestination.allCases
            .filter { $0.section == .library }
            .map { ShellSidebarItem(id: $0.id, title: $0.title, symbol: $0.symbol, route: $0.route,
                                    requiresSignIn: $0.requiresSignIn,
                                    // Unpublished posts/stories on this device, so drafts aren't forgotten.
                                    badge: $0 == .drafts ? app.drafts.posts.count + app.drafts.stories.count : 0,
                                    keywords: $0.subtitle ?? "") }
        #if DEBUG
        items.append(.init(id: "developer", title: "Module Studio", symbol: "wrench.and.screwdriver", route: .developer(.studio), requiresSignIn: false))
        #endif
        return items
    }

    /// Debug-build tools, collapsed by default.
    private var developerItems: [ShellSidebarItem] {
        #if DEBUG
        [
            .init(id: "components", title: "Component Catalog", symbol: "square.grid.3x3", route: .developer(.components), requiresSignIn: false),
            .init(id: "diagnostics", title: "Diagnostics & Labs", symbol: "stethoscope", route: .settings(.developer(.root)), requiresSignIn: false),
        ]
        #else
        []
        #endif
    }

    /// Reachable from the footer gear and the profile chip menu; listed here so search finds them.
    private var manageItems: [ShellSidebarItem] {
        ShellSidebarDestination.allCases
            .filter { $0.section == .manage }
            .map { ShellSidebarItem(id: $0.id, title: $0.title, symbol: $0.symbol, route: $0.route,
                                    requiresSignIn: $0.requiresSignIn, keywords: $0.subtitle ?? "") }
    }

    // MARK: Chats (real, already-loaded data only)

    /// One pass over the loaded conversations per render (only while the sidebar is on screen).
    private var chatLists: (pinned: [Conversation], recent: [Conversation]) {
        guard app.auth.isSignedIn else { return ([], []) }
        let live = app.messaging.conversations.filter { !$0.isArchived }
        guard !live.isEmpty else { return ([], []) }
        let pinnedIDs = app.messaging.pinnedIDs
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let pinned = pinnedIDs.compactMap { byID[$0] }
        let pinnedSet = Set(pinnedIDs)
        let recent = MessagingOrdering.conversationsNewestFirst(live.filter { !pinnedSet.contains($0.id) })
        return (pinned, Array(recent.prefix(Self.recentLimit)))
    }

    private func chatTitle(_ chat: Conversation) -> String {
        let nick = app.messaging.nicknames[chat.id] ?? ""
        return nick.isEmpty ? chat.title : nick
    }

    // MARK: Search

    private var recentSearches: [String] {
        recentSearchesRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func rememberQuery() {
        let q = trimmedQuery
        guard q.count >= 2 else { return }
        var list = recentSearches.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        recentSearchesRaw = list.prefix(6).joined(separator: "\n")
    }

    private var recentSearchSection: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
            HStack {
                Text("Recent searches")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") { recentSearchesRaw = "" }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.appearance.liveAccent)
                    .accessibilityIdentifier("shell.sidebar.recent.clear")
            }
            .padding(.horizontal, rowInset)
            ScrollView(.horizontal) {
                HStack(spacing: ModulaSpacing.xs) {
                    ForEach(recentSearches, id: \.self) { term in
                        Button { query = term } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .modulaGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search \(term)")
                        .contextMenu {
                            Button("Remove", systemImage: "xmark", role: .destructive) {
                                recentSearchesRaw = recentSearches.filter { $0 != term }.joined(separator: "\n")
                            }
                        }
                    }
                }
                .padding(.horizontal, rowInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFiltering: Bool { searching && !trimmedQuery.isEmpty }

    private var filteredItems: [ShellSidebarItem] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return (primaryItems + libraryItems + manageItems + developerItems).filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.keywords.localizedCaseInsensitiveContains(q)
        }
    }

    private func filteredChats(_ chats: (pinned: [Conversation], recent: [Conversation])) -> [Conversation] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        let shown = chats.pinned + chats.recent
        return shown.filter { chatTitle($0).localizedCaseInsensitiveContains(q) || ($0.handleLabel?.localizedCaseInsensitiveContains(q) ?? false) }
    }

    @ViewBuilder
    private func searchResults(chats lists: (pinned: [Conversation], recent: [Conversation])) -> some View {
        let items = filteredItems
        let chats = filteredChats(lists)
        if !items.isEmpty {
            section("Destinations") { ForEach(items) { row($0).simultaneousGesture(TapGesture().onEnded { rememberQuery() }) } }
        }
        if !chats.isEmpty {
            section("Chats") { ForEach(chats) { chatRow($0).simultaneousGesture(TapGesture().onEnded { rememberQuery() }) } }
        }
        section(items.isEmpty && chats.isEmpty ? "No matches" : nil) {
            Button {
                onClose()
                CommandPaletteCenter.shared.present()
                HapticEngine.shared.play(.selection)
            } label: {
                rowLabel(symbol: "magnifyingglass", title: "Search all of Modula")
            }
            .buttonStyle(ShellSidebarRowStyle())
            .accessibilityHint("Opens search and commands")
            .accessibilityIdentifier("shell.sidebar.search.all")
        }
    }

    // MARK: Building blocks

    private func section<Rows: View>(_ title: String?, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, rowInset)
                    .padding(.bottom, ModulaSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)
            }
            rows()
        }
    }

    private func rowLabel(symbol: String, title: String, badge: Int = 0, selected: Bool = false) -> some View {
        HStack(spacing: ModulaSpacing.sm) {
            Image(systemName: symbol)
                .font(.body.weight(selected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selected ? AnyShapeStyle(app.appearance.liveAccent) : AnyShapeStyle(Color.primary.opacity(0.78)))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(selected ? .body.weight(.semibold) : .body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(app.appearance.liveAccent, in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, rowInset)
        .frame(minHeight: rowHeight)
        .background {
            if selected {
                // Current destination: one tinted Liquid Glass pill.
                let pill = RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous)
                Color.clear
                    .modulaGlass(in: pill, interactive: false, tint: app.appearance.liveAccent.opacity(0.4), specular: true)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
    }

    private func row(_ item: ShellSidebarItem) -> some View {
        let selected = item.route == app.navigation.root(for: app.navigation.selectedTab)
        return Button { onSelect(item.route, item.requiresSignIn) } label: {
            rowLabel(symbol: item.symbol, title: item.title, badge: item.badge, selected: selected)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .buttonStyle(ShellSidebarRowStyle())
        .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge) unread" : item.title)
        .accessibilityIdentifier("shell.sidebar.\(item.id)")
    }

    /// Plain text row, like a chat-history list: title, then a small unread dot.
    private func chatRow(_ chat: Conversation) -> some View {
        let title = chatTitle(chat)
        return Button { onSelect(.messages(.conversation(chat.id)), true) } label: {
            HStack(spacing: ModulaSpacing.xs) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(chat.isMuted ? .secondary : .primary)
                    .fontWeight(chat.isUnread ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if chat.isUnread {
                    Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(chat.isMuted ? Color.secondary : Color.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(chat.isMuted ? Color.primary.opacity(0.12) : app.appearance.liveAccent, in: Capsule())
                        .accessibilityLabel("\(chat.unreadCount) unread")
                }
            }
            .padding(.horizontal, rowInset)
            .frame(minHeight: rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
        }
        .buttonStyle(ShellSidebarRowStyle())
        .accessibilityLabel(chat.isUnread ? "\(title), unread" : title)
        .accessibilityHint("Opens the chat")
        .accessibilityIdentifier("shell.sidebar.chat.\(chat.id)")
    }

    @ViewBuilder
    private var developerGroup: some View {
        let items = developerItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { developerExpanded.toggle() }
                } label: {
                    HStack(spacing: ModulaSpacing.xxs) {
                        Text("Developer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(developerExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, rowInset)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Developer tools")
                .accessibilityValue(developerExpanded ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("shell.sidebar.developer.toggle")
                if developerExpanded {
                    ForEach(items) { row($0) }
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ModulaSpacing.xs))
                             : AnyLayout(HStackLayout(spacing: ModulaSpacing.xs))
        return layout {
            profileChip
            if !stacked { Spacer(minLength: 0) }
            HStack(spacing: ModulaSpacing.xs) {
                settingsButton
                newPostPill
            }
        }
    }

    @ViewBuilder
    private var profileChip: some View {
        if app.auth.isSignedIn {
            let profile = app.profile.ownProfile
            Button { onSelect(.me(.overview), true) } label: {
                HStack(spacing: ModulaSpacing.xs) {
                    ModulaAvatar(initials: profile?.initials ?? "", url: profile?.avatarURL, size: 32, name: profile?.displayName)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(profile?.displayName ?? "Profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let handle = profile?.handle, !handle.isEmpty, !typeSize.isAccessibilitySize {
                            Text("@\(handle)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 4).padding(.trailing, ModulaSpacing.sm)
                .frame(minHeight: 44)
                .modulaGlass(in: Capsule(), interactive: true, specular: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Profile", systemImage: "person.crop.circle") { onSelect(.me(.overview), true) }
                Button("Settings", systemImage: "gearshape") { onSelect(.settings(.root), false) }
                Button("Appearance", systemImage: "circle.lefthalf.filled") { onSelect(.settings(.appearance(.root)), false) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(profile.map { "\($0.displayName), @\($0.handle)" } ?? "Profile")
            .accessibilityHint("Opens your profile. Touch and hold for settings.")
            .accessibilityIdentifier("shell.sidebar.profile")
        } else {
            Button { onSelect(.auth(.login), false) } label: {
                Label("Sign in", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, ModulaSpacing.sm)
                    .frame(minHeight: 40)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sign in to sync your library")
            .accessibilityIdentifier("shell.sidebar.sign-in")
        }
    }

    private var settingsButton: some View {
        Button { onSelect(.settings(.root), false) } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Appearance", systemImage: "circle.lefthalf.filled") { onSelect(.settings(.appearance(.root)), false) }
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("shell.sidebar.settings")
    }

    private var newPostPill: some View {
        Button {
            onClose()
            if app.auth.isSignedIn {
                app.navigation.presented = .composer(.post)
            } else {
                app.navigation.requestAuthentication(returningTo: .compose(.post))
            }
            HapticEngine.shared.play(.contextOpen)
        } label: {
            Label("New post", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, ModulaSpacing.md)
                .frame(height: 40)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaAccentCTA()
        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        // Long-press: quick-create straight into a specific composer.
        .contextMenu {
            Button("Text post", systemImage: "text.alignleft") { quickCreate(.post) }
            Button("Photo", systemImage: "photo") { quickCreate(.photo) }
            Button("Video", systemImage: "video") { quickCreate(.video) }
            Button("Poll", systemImage: "chart.bar.xaxis") { quickCreate(.poll) }
            Button("Link", systemImage: "link") { quickCreate(.link) }
            Divider()
            Button("All create options", systemImage: "plus.square.on.square") {
                onClose()
                app.navigation.presented = .createPicker
            }
        }
        .accessibilityHint("Long-press for photo, video, poll or link")
        .accessibilityIdentifier("shell.sidebar.create")
    }

    private func quickCreate(_ route: ComposeRoute) {
        onClose()
        if app.auth.isSignedIn {
            app.navigation.presented = .composer(route)
        } else {
            app.navigation.requestAuthentication(returningTo: .compose(route))
        }
        HapticEngine.shared.play(.contextOpen)
    }
}

private struct ShellSidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : 0),
                        in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ShellSidebarTrigger: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button("Sidebar", systemImage: "line.3.horizontal") {
            app.navigation.presentSidebar()
            HapticEngine.shared.play(.contextOpen)
        }
        .accessibilityIdentifier("shell.sidebar.trigger")
    }
}

struct ShellSidebarTriggerModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var app

    func body(content: Content) -> some View {
        content.toolbar {
            if app.navigation.isAtTabRoot {
                ToolbarItem(placement: .topBarLeading) {
                    ShellSidebarTrigger()
                }
            }
        }
    }
}

extension View {
    func modulaSidebarTrigger() -> some View {
        modifier(ShellSidebarTriggerModifier())
    }

    /// Overlay drawer: a floating glass card slides in over the unscaled main screen.
    func modulaSidebarContainer() -> some View {
        ShellSidebarContainer { self }
    }
}
