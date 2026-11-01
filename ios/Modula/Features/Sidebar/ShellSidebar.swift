import SwiftUI

private extension EdgeInsets {
    var inverted: EdgeInsets { EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing) }
}

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

/// ChatGPT-style push sidebar. The sidebar sits *behind* the app at full height; the app
/// slides right as a rounded, slightly dimmed card. Drag is interactive (edge swipe to open,
/// drag or tap the card to close) and only drives `offset`/`cornerRadius`/`opacity` —
/// lightweight render properties, never layout — so it tracks the finger at 120 Hz.
struct ShellSidebarContainer<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Live finger translation. `@GestureState` resets automatically when the gesture ends
    /// *or is cancelled* (system edge swipe, scroll view stealing the touch, app backgrounding),
    /// so the card can never be left parked half-open with `presented == false`.
    @GestureState(resetTransaction: Transaction(animation: ShellSidebarContainer.settleSpring))
    private var drag: CGFloat = 0
    @GestureState private var dragging = false

    static var settleSpring: Animation { .interpolatingSpring(mass: 1, stiffness: 320, damping: 32) }

    static var cardCornerRadius: CGFloat { 48 }

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

    static func cardShape(radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        let presented = app.navigation.sidebarPresented
        GeometryReader { geometry in
            let width = Self.sidebarWidth(for: geometry.size.width)
            let base: CGFloat = presented ? width : 0
            let offset = min(max(base + drag, 0), width)
            let progress = width > 0 ? offset / width : 0
            let visible = presented || dragging
            let insets = geometry.safeAreaInsets
            let radius = Self.displayCornerRadius(safeTop: insets.top)

            ZStack(alignment: .leading) {
                if visible {
                    ShellSidebarView(width: width, onSelect: open, onClose: { close(haptic: true) })
                        .frame(width: reduceMotion ? geometry.size.width : width)
                        .frame(maxHeight: .infinity)
                        // Panel: continuous rounded trailing corners matching the display radius.
                        .background {
                            UnevenRoundedRectangle(bottomTrailingRadius: reduceMotion ? 0 : radius,
                                                   topTrailingRadius: reduceMotion ? 0 : radius,
                                                   style: .continuous)
                                .fill(Color.primary.opacity(scheme == .dark ? 0.04 : 0.03))
                                .overlay(
                                    UnevenRoundedRectangle(bottomTrailingRadius: reduceMotion ? 0 : radius,
                                                           topTrailingRadius: reduceMotion ? 0 : radius,
                                                           style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
                                )
                                .padding(EdgeInsets(top: -insets.top, leading: -insets.leading, bottom: -insets.bottom, trailing: 0))
                                .accessibilityHidden(true)
                        }
                        .opacity(reduceMotion ? progress : 1)
                        // Subtle parallax: the sidebar drifts in slightly slower than the card.
                        .offset(x: reduceMotion ? 0 : (progress - 1) * 36)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close(haptic: true) }
                        .onKeyPress(.escape) {
                            close(haptic: true)
                            return .handled
                        }
                        .zIndex(reduceMotion ? 1 : 0)
                }

                content
                    // Card-local space: feed geometry (Edge Picker bulge + rows) is measured here,
                    // so the card's offset / settle spring never changes those values.
                    .coordinateSpace(.named(ShellChromeFreeze.cardSpace))
                    .background(sidebarBackdrop.ignoresSafeArea())
                    // One shape for mask, dim and hairline, sized to the *whole screen* (safe areas
                    // added back explicitly) so all four corners round identically and follow the
                    // display corner radius. (Before, the mask's frame differed at the top edge, so
                    // the top corner rendered square while the bottom one was rounded.)
                    .mask {
                        Self.cardShape(radius: radius * progress)
                            .padding(insets.inverted)
                    }
                    .overlay {
                        Self.cardShape(radius: radius * progress)
                            .fill(Color.black.opacity((scheme == .dark ? 0.34 : 0.16) * progress))
                            .overlay(
                                Self.cardShape(radius: radius * progress)
                                    .strokeBorder(Color.primary.opacity(0.10 * progress), lineWidth: 0.75)
                            )
                            .padding(insets.inverted)
                            .allowsHitTesting(false)
                    }
                    // Hide the main screen's nav-bar chrome (… / + buttons) on the peeking card so
                    // it doesn't sit beside the drawer's own search button.
                    .overlay(alignment: .top) {
                        if progress > 0.01 {
                            sidebarBackdrop
                                .frame(height: ProfileFullBleedMetrics.windowSafeAreaTop + 52)
                                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.75), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                                .opacity(Double(min(1, progress * 1.4)))
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                        }
                    }
                    .shadow(color: .black.opacity(0.22 * progress), radius: 24 * progress, x: -4, y: 0)
                    // Pushed card recedes slightly (depth cue); never under Reduce Motion.
                    .scaleEffect(reduceMotion ? 1 : 1 - 0.07 * progress, anchor: .leading)
                    .offset(x: reduceMotion ? 0 : offset)
                    .opacity(reduceMotion ? 1 - progress * 0.6 : 1)
                    .accessibilityHidden(presented)
                    // Freeze UIKit chrome hooks + Home geometry writers while the card is
                    // being dragged so the transform can't feed back into layout.
                    .onChange(of: dragging) { _, isDragging in
                        ShellChromeFreeze.isSidebarDragging = isDragging
                        // Cancelled gesture (notification, system swipe): settle back to a clean state.
                        if !isDragging, !app.navigation.sidebarPresented { ShellChromeFreeze.holdForSettle() }
                    }
                    // A push while the card is moving (or open) cancels the sidebar cleanly.
                    .onChange(of: app.navigation.selectedStackHasPushedViews) { _, pushed in
                        if pushed, app.navigation.sidebarPresented { close(haptic: false) }
                    }
                    .overlay {
                        if presented {
                            Color.clear
                                .contentShape(Rectangle())
                                .offset(x: reduceMotion ? 0 : offset)
                                .ignoresSafeArea()
                                .highPriorityGesture(closeDrag(width: width))
                                .simultaneousGesture(TapGesture().onEnded { close(haptic: true) })
                                .accessibilityLabel("Close sidebar")
                                .accessibilityIdentifier("shell.sidebar.scrim")
                                .accessibilityAddTraits(.isButton)
                                .zIndex(2)
                        }
                    }
                    .overlay(alignment: .leading) {
                        // Mutually exclusive with the navigation back swipe: only on a stack root
                        // with nothing presented, so Back-from-Search can never drag the sidebar.
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(sidebarBackdrop.ignoresSafeArea())
        }
        .animation(settle, value: presented)
    }

    static func sidebarWidth(for total: CGFloat) -> CGFloat {
        min(total * 0.80, 380)
    }

    /// Velocity-aware decision used by both gestures: projected end beats raw distance.
    static func shouldEndOpen(translation: CGFloat, predicted: CGFloat, startOpen: Bool, width: CGFloat) -> Bool {
        let base: CGFloat = startOpen ? width : 0
        let projected = base + predicted
        let current = base + translation
        // A quick flick decides by direction; otherwise snap to the nearer side.
        if abs(predicted - translation) > width * 0.25 { return projected > width / 2 }
        return current > width / 2
    }

    private var sidebarBackdrop: some View {
        // Translucent glass drawer (was an opaque canvas slab).
        let palette = ModulaPalette.resolve(app.appearance, scheme: scheme)
        return ZStack {
            if reduceTransparency {
                palette.canvas
            } else {
                Rectangle().fill(.regularMaterial)
                palette.canvas.opacity(0.45)
            }
        }
    }

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
                // Mostly-vertical drags never open the sidebar.
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
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true; ShellChromeFreeze.isSidebarDragging = true }
            .updating($drag) { value, state, transaction in
                transaction.disablesAnimations = true
                state = max(min(0, value.translation.width), -width)
            }
            .onEnded { value in
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

/// One sidebar row in the ChatGPT style: monochrome glyph + title, no chevron.
struct ShellSidebarItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let route: AppRoute
    let requiresSignIn: Bool
    var tint: Color = .gray

    static func sections() -> [(ShellSidebarDestination.Section, [ShellSidebarItem])] {
        ShellSidebarDestination.Section.allCases.map { section in
            var items = ShellSidebarDestination.allCases
                .filter { $0.section == section }
                .map { ShellSidebarItem(id: $0.id, title: $0.title, symbol: $0.symbol + ".fill", route: $0.route, requiresSignIn: $0.requiresSignIn, tint: $0.tint) }
            #if DEBUG
            if section == .developer {
                items.append(ShellSidebarItem(id: "components", title: "Component Catalog", symbol: "square.grid.3x3", route: .developer(.components), requiresSignIn: false, tint: .teal))
                items.append(ShellSidebarItem(id: "diagnostics", title: "Diagnostics & Labs", symbol: "stethoscope", route: .settings(.developer(.root)), requiresSignIn: false, tint: .mint))
            }
            #endif
            #if !DEBUG
            // Developer tools are debug/dev builds only.
            if section == .developer { items = [] }
            #endif
            return (section, items)
        }
        .filter { !$0.1.isEmpty }
    }
}

/// The sidebar panel. Layout, top to bottom (most-used first, Fitts + Hick):
/// wordmark + search, profile card (avatar, name, handle, stats, Moliboo greeting),
/// a 3×2 grid of shortcuts with badges, grouped glass sections with tinted squircle glyphs,
/// a gated Premium upsell, version, and a sticky New-post button in the thumb zone.
struct ShellSidebarView: View {
    var width: CGFloat = 320
    var onSelect: (AppRoute, Bool) -> Void
    var onClose: () -> Void = {}
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(ModulaMascotSettings.kindKey) private var mascotRaw = ModulaMascotKind.pip.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileCard
                    shortcuts
                    ForEach(ShellSidebarItem.sections(), id: \.0.id) { section, items in
                        sectionView(section, items: items)
                    }
                    if !PremiumEntitlementStore.shared.plan.isPaid {
                        premiumCard
                    }
                    Text(versionLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .accessibilityLabel(versionLabel)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .modulaSoftScrollEdge()

            footer
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shell.sidebar")
        .accessibilityLabel("Sidebar")
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModulaWordmark(height: 20)
                .accessibilityAddTraits(.isHeader)
                .frame(minHeight: 32)
            Button {
                onClose()
                CommandPaletteCenter.shared.present()
                HapticEngine.shared.play(.selection)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Search Modula")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Capsule(), interactive: true)
            .accessibilityLabel("Search")
            .accessibilityHint("Opens search and commands")
            .accessibilityIdentifier("shell.sidebar.search")
        }
    }

    // MARK: Profile card

    private var mascot: ModulaMascotKind? {
        mascotRaw == ModulaMascotSettings.off ? nil : ModulaMascotKind(rawValue: mascotRaw)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let first = app.profile.ownProfile?.displayName.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? part
    }

    @ViewBuilder
    private var profileCard: some View {
        if let profile = app.profile.ownProfile, app.auth.isSignedIn {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        onSelect(.me(.overview), true)
                    } label: {
                        HStack(spacing: 12) {
                            ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 52, name: profile.displayName)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("@\(profile.handle)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(profile.displayName), @\(profile.handle)")
                    .accessibilityHint("Opens your profile")
                    .accessibilityIdentifier("shell.sidebar.profile")

                    Button {
                        onSelect(.me(.edit), true)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true)
                    .accessibilityLabel("Edit profile")
                    .accessibilityIdentifier("shell.sidebar.edit")
                }

                HStack(spacing: 0) {
                    stat(profile.postCount, "Posts", route: .me(.posts))
                    stat(profile.followerCount, "Followers", route: .me(.followers))
                    stat(profile.followingCount, "Following", route: .me(.following))
                }

                if let mascot {
                    Button {
                        onSelect(.settings(.moliboo), false)
                    } label: {
                        HStack(spacing: 10) {
                            ModulaMascotFigure(kind: mascot, pose: .still(.happy), size: 20)
                                .frame(width: 40, height: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(greeting)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(mascot.name) is happy to see you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(greeting). \(mascot.name), your Moliboo")
                    .accessibilityHint("Opens Moliboo settings")
                    .accessibilityIdentifier("shell.sidebar.moliboo")
                }
            }
            .padding(14)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.auth.isSignedIn ? "Loading profile…" : "Welcome to Modula")
                        .font(.headline)
                    if !app.auth.isSignedIn {
                        Text("Sign in to sync your library").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if !app.auth.isSignedIn {
                    Button("Sign In") { onSelect(.auth(.login), false) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .modulaAccentCTA()
                        .accessibilityIdentifier("shell.sidebar.sign-in")
                }
            }
            .padding(14)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        }
    }

    private func stat(_ value: Int, _ label: String, route: AppRoute) -> some View {
        Button { onSelect(route, true) } label: {
            VStack(spacing: 1) {
                Text(value, format: .number.notation(.compactName))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        let unreadMessages = app.messaging.accountUnreadCount ?? 0
        let unreadActivity = app.activity.state(for: .all).unreadCount ?? 0
        let items: [ShellSidebarShortcut] = [
            .init(id: "messages", title: "Messages", symbol: "bubble.left.and.bubble.right.fill", tint: .blue,
                  badge: unreadMessages, route: .messages(.inbox), requiresSignIn: true),
            .init(id: "notifications", title: "Alerts", symbol: "bell.fill", tint: .red,
                  badge: unreadActivity, route: .activity(.all), requiresSignIn: true),
            .init(id: "vault", title: "Vault", symbol: "lock.doc.fill", tint: .indigo,
                  badge: 0, route: .module("digital.modula.vault-notes", localPath: nil), requiresSignIn: true),
            .init(id: "games", title: "GUBIC", symbol: "gamecontroller.fill", tint: .green,
                  badge: 0, route: .productHub(.category("games")), requiresSignIn: false),
            .init(id: "moliboos", title: "Moliboos", symbol: "sparkles", tint: .pink,
                  badge: 0, route: .settings(.moliboo), requiresSignIn: false),
            .init(id: "premium", title: "Premium", symbol: "sun.horizon.fill", tint: .orange,
                  badge: 0, route: .settings(.premium(.root)), requiresSignIn: false),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items) { item in
                Button {
                    onSelect(item.route, item.requiresSignIn)
                } label: {
                    VStack(spacing: 6) {
                        ShellSidebarGlyph(symbol: item.symbol, tint: item.tint, size: 34)
                            .overlay(alignment: .topTrailing) {
                                if item.badge > 0 {
                                    Text(item.badge > 99 ? "99+" : "\(item.badge)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(Color.red, in: Capsule())
                                        .offset(x: 8, y: -6)
                                }
                            }
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(ShellSidebarPressStyle())
                .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge) unread" : item.title)
                .accessibilityIdentifier("shell.sidebar.shortcut.\(item.id)")
            }
        }
    }

    // MARK: Sections

    private func sectionView(_ section: ShellSidebarDestination.Section, items: [ShellSidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item.route, item.requiresSignIn)
                    } label: {
                        HStack(spacing: 12) {
                            ShellSidebarGlyph(symbol: item.symbol, tint: item.tint, size: 30)
                            Text(item.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ShellSidebarRowStyle())
                    .accessibilityIdentifier("shell.sidebar.\(item.id)")
                    if index < items.count - 1 {
                        Divider().padding(.leading, 54).opacity(0.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        }
    }

    // MARK: Premium

    private var premiumCard: some View {
        Button {
            onSelect(.settings(.premium(.root)), false)
        } label: {
            HStack(spacing: 12) {
                ShellSidebarGlyph(symbol: "sun.horizon.fill", tint: PremiumPlan.horizon.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go Premium")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Premium Moliboos, more Vault and early modules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(ShellSidebarPressStyle())
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true,
                     tint: PremiumPlan.horizon.tint.opacity(reduceTransparency ? 0.25 : 0.18))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Modula Premium")
        .accessibilityIdentifier("shell.sidebar.premium")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onSelect(.settings(.root), false)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Circle(), interactive: true)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("shell.sidebar.gear")

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
            .accessibilityIdentifier("shell.sidebar.create")
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Modula \(version) (\(build))"
    }
}

struct ShellSidebarShortcut: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let badge: Int
    let route: AppRoute
    let requiresSignIn: Bool
}

/// SF Symbol in a tinted continuous squircle (Settings-style), one colour per destination.
struct ShellSidebarGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(tint) : AnyShapeStyle(tint.gradient))
            )
            .accessibilityHidden(true)
    }
}

private struct ShellSidebarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.3), value: configuration.isPressed)
    }
}

private struct ShellSidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
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

    /// ChatGPT-style push sidebar: the app slides right as a rounded card over the sidebar.
    func modulaSidebarContainer() -> some View {
        ShellSidebarContainer { self }
    }
}
