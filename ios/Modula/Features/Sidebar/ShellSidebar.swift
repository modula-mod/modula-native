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
    /// Live finger translation. `@GestureState` resets automatically when the gesture ends
    /// *or is cancelled* (system edge swipe, scroll view stealing the touch, app backgrounding),
    /// so the card can never be left parked half-open with `presented == false`.
    @GestureState(resetTransaction: Transaction(animation: ShellSidebarContainer.settleSpring))
    private var drag: CGFloat = 0
    @GestureState private var dragging = false

    static var settleSpring: Animation { .interpolatingSpring(mass: 1, stiffness: 320, damping: 32) }

    static var cardCornerRadius: CGFloat { 48 }

    var body: some View {
        let presented = app.navigation.sidebarPresented
        GeometryReader { geometry in
            let width = Self.sidebarWidth(for: geometry.size.width)
            let base: CGFloat = presented ? width : 0
            let offset = min(max(base + drag, 0), width)
            let progress = width > 0 ? offset / width : 0
            let visible = presented || dragging

            ZStack(alignment: .leading) {
                if visible {
                    ShellSidebarView(width: width, onSelect: open, onClose: { close(haptic: true) })
                        .frame(width: reduceMotion ? geometry.size.width : width)
                        .frame(maxHeight: .infinity)
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
                    // Mask (not clipShape) so the card keeps its full-screen, under-the-status-bar extent.
                    .mask {
                        RoundedRectangle(cornerRadius: Self.cardCornerRadius * progress, style: .continuous)
                            .ignoresSafeArea()
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cardCornerRadius * progress, style: .continuous)
                            .fill(Color.black.opacity((scheme == .dark ? 0.30 : 0.14) * progress))
                            .overlay(
                                RoundedRectangle(cornerRadius: Self.cardCornerRadius * progress, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10 * progress), lineWidth: 0.75)
                            )
                            .allowsHitTesting(false)
                            .ignoresSafeArea()
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
            Rectangle().fill(.regularMaterial)
            palette.canvas.opacity(0.45)
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

    static func sections() -> [(ShellSidebarDestination.Section, [ShellSidebarItem])] {
        ShellSidebarDestination.Section.allCases.map { section in
            var items = ShellSidebarDestination.allCases
                .filter { $0.section == section }
                .map { ShellSidebarItem(id: $0.id, title: $0.title, symbol: $0.symbol, route: $0.route, requiresSignIn: $0.requiresSignIn) }
            #if DEBUG
            if section == .developer {
                items.append(ShellSidebarItem(id: "components", title: "Component Catalog", symbol: "square.grid.3x3", route: .developer(.components), requiresSignIn: false))
                items.append(ShellSidebarItem(id: "diagnostics", title: "Diagnostics & Labs", symbol: "stethoscope", route: .settings(.developer(.root)), requiresSignIn: false))
            }
            #endif
            return (section, items)
        }
        .filter { !$0.1.isEmpty }
    }
}

struct ShellSidebarView: View {
    var width: CGFloat = 320
    var onSelect: (AppRoute, Bool) -> Void
    var onClose: () -> Void = {}
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(ShellSidebarItem.sections(), id: \.0.id) { section, items in
                            sectionView(section, items: items)
                        }
                        Text(versionLabel)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 12)
                            .accessibilityLabel(versionLabel)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .modulaSoftScrollEdge()

                // Post sits inline with the profile row instead of floating over the drawer list.
                HStack(spacing: 10) {
                    profileRow
                    createPill
                }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shell.sidebar")
        .accessibilityLabel("Sidebar")
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ModulaWordmark(height: 20)
            Spacer(minLength: 0)
            Button {
                onClose()
                CommandPaletteCenter.shared.present()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Circle())
            .accessibilityLabel("Search")
            .accessibilityIdentifier("shell.sidebar.search")
        }
        .frame(minHeight: 48)
    }

    private func sectionView(_ section: ShellSidebarDestination.Section, items: [ShellSidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                Button {
                    onSelect(item.route, item.requiresSignIn)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.regular))
                            .symbolVariant(.none)
                            .imageScale(.medium)
                            .foregroundStyle(.primary)
                            .frame(width: 24)
                        Text(item.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ShellSidebarRowStyle())
                .accessibilityIdentifier("shell.sidebar.\(item.id)")
            }
        }
    }

    @ViewBuilder
    private var profileRow: some View {
        if let profile = app.profile.ownProfile, app.auth.isSignedIn {
            HStack(spacing: 12) {
                Button {
                    onSelect(.me(.overview), true)
                } label: {
                    HStack(spacing: 12) {
                        ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("@\(profile.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shell.sidebar.profile")
                .accessibilityLabel("\(profile.displayName), @\(profile.handle)")

                Button {
                    onSelect(.settings(.root), false)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("shell.sidebar.gear")
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(app.auth.isSignedIn ? "Loading profile…" : "Not signed in")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !app.auth.isSignedIn {
                    Button("Sign In") { onSelect(.auth(.login), false) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .modulaGlass(in: Capsule())
                        .accessibilityIdentifier("shell.sidebar.sign-in")
                }
            }
        }
    }

    private var createPill: some View {
        Button {
            onClose()
            if app.auth.isSignedIn {
                app.navigation.presented = .composer(.post)
            } else {
                app.navigation.requestAuthentication(returningTo: .compose(.post))
            }
            HapticEngine.shared.play(.contextOpen)
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Circle(), tint: app.appearance.liveAccent, prominent: true)
        .accessibilityLabel("New post")
        .accessibilityIdentifier("shell.sidebar.create")
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Modula \(version) (\(build))"
    }
}

private struct ShellSidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
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
