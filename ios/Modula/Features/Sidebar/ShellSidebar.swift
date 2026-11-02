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
}

/// Calm sidebar. Top to bottom: compact identity row, search, two groups of
/// destinations (Go to · Library), then quiet Settings and the accent New-post button.
struct ShellSidebarView: View {
    var width: CGFloat = 320
    var onSelect: (AppRoute, Bool) -> Void
    var onClose: () -> Void = {}
    @Environment(AppEnvironment.self) private var app
    @AppStorage(ModulaMascotSettings.kindKey) private var mascotRaw = ModulaMascotKind.pip.rawValue

    private let rowInset = ModulaSpacing.sm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, ModulaSpacing.md)
                .padding(.top, ModulaSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                    group("Go to", items: primaryItems)
                    group("Library", items: libraryItems)
                }
                .padding(.horizontal, ModulaSpacing.xs)
                .padding(.top, ModulaSpacing.md)
                .padding(.bottom, ModulaSpacing.lg)
            }
            .scrollIndicators(.hidden)
            .modulaSoftScrollEdge()

            footer
                .padding(.horizontal, ModulaSpacing.xs)
                .padding(.bottom, ModulaSpacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            HStack(spacing: ModulaSpacing.xs) {
                identity
                Button {
                    onClose()
                    CommandPaletteCenter.shared.present()
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                .accessibilityHint("Opens search and commands")
                .accessibilityIdentifier("shell.sidebar.search")
            }
            if let mascot, app.auth.isSignedIn {
                Text("\(greeting) from \(mascot.name)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityIdentifier("shell.sidebar.moliboo")
            }
        }
    }

    @ViewBuilder
    private var identity: some View {
        if let profile = app.profile.ownProfile, app.auth.isSignedIn {
            Button { onSelect(.me(.overview), true) } label: {
                HStack(spacing: ModulaSpacing.sm) {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 32, name: profile.displayName)
                    (Text(profile.displayName).font(.headline).foregroundStyle(.primary)
                     + Text("  @\(profile.handle)").font(.subheadline).foregroundStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(profile.displayName), @\(profile.handle)")
            .accessibilityHint("Opens your profile")
            .accessibilityIdentifier("shell.sidebar.profile")
        } else if app.auth.isSignedIn {
            Text("Loading profile…").font(.headline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            Button { onSelect(.auth(.login), false) } label: {
                HStack(spacing: ModulaSpacing.sm) {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Sign in").font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sign in to sync your library")
            .accessibilityIdentifier("shell.sidebar.sign-in")
        }
    }

    // MARK: Destinations

    private var primaryItems: [ShellSidebarItem] {
        var items: [ShellSidebarItem] = [
            .init(id: "messages", title: "Messages", symbol: "bubble.left.and.bubble.right",
                  route: .messages(.inbox), requiresSignIn: true, badge: app.messaging.accountUnreadCount ?? 0),
            .init(id: "notifications", title: "Alerts", symbol: "bell",
                  route: .activity(.all), requiresSignIn: true, badge: app.activity.state(for: .all).unreadCount ?? 0),
            .init(id: "vault", title: "Vault", symbol: "lock.doc",
                  route: .module("digital.modula.vault-notes", localPath: nil), requiresSignIn: true),
        ]
        if GubicFeature.enabled() {
            items.append(.init(id: "games", title: "GUBIC", symbol: "gamecontroller", route: .productHub(.gubic), requiresSignIn: false))
        }
        items.append(.init(id: "moliboos", title: "Moliboos", symbol: "sparkles", route: .settings(.moliboo), requiresSignIn: false))
        // Premium is gated: the upsell row only appears for free accounts.
        if !PremiumEntitlementStore.shared.plan.isPaid {
            items.append(.init(id: "premium", title: "Premium", symbol: "sun.horizon", route: .settings(.premium(.root)), requiresSignIn: false))
        }
        return items
    }

    private var libraryItems: [ShellSidebarItem] {
        var items = ShellSidebarDestination.allCases
            .filter { $0.section == .library }
            .map { ShellSidebarItem(id: $0.id, title: $0.title, symbol: $0.symbol, route: $0.route, requiresSignIn: $0.requiresSignIn) }
        #if DEBUG
        items.append(.init(id: "developer", title: "Module Studio", symbol: "wrench.and.screwdriver", route: .developer(.studio), requiresSignIn: false))
        items.append(.init(id: "components", title: "Component Catalog", symbol: "square.grid.3x3", route: .developer(.components), requiresSignIn: false))
        items.append(.init(id: "diagnostics", title: "Diagnostics & Labs", symbol: "stethoscope", route: .settings(.developer(.root)), requiresSignIn: false))
        #endif
        return items
    }

    private func group(_ title: String, items: [ShellSidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, rowInset)
                .padding(.bottom, ModulaSpacing.xxs)
                .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in row(item) }
        }
    }

    private func row(_ item: ShellSidebarItem) -> some View {
        Button { onSelect(item.route, item.requiresSignIn) } label: {
            HStack(spacing: ModulaSpacing.sm) {
                Image(systemName: item.symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.badge > 0 {
                    Text(item.badge > 99 ? "99+" : "\(item.badge)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ModulaSpacing.xs)
                        .frame(minHeight: 22)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, rowInset)
            .frame(minHeight: 46)
            .contentShape(RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
        }
        .buttonStyle(ShellSidebarRowStyle())
        .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge) unread" : item.title)
        .accessibilityIdentifier("shell.sidebar.\(item.id)")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: ModulaSpacing.xs) {
            Divider().padding(.horizontal, rowInset).opacity(0.6)
            HStack(spacing: 0) {
                row(.init(id: "settings", title: "Settings", symbol: "gearshape", route: .settings(.root), requiresSignIn: false))
                Button { onSelect(.settings(.appearance(.root)), false) } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 46, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ShellSidebarRowStyle())
                .accessibilityLabel("Appearance")
                .accessibilityIdentifier("shell.sidebar.appearance")
            }
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modulaAccentCTA()
            .padding(.horizontal, ModulaSpacing.xxs)
            .accessibilityIdentifier("shell.sidebar.create")
        }
    }
}

private struct ShellSidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0),
                        in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
