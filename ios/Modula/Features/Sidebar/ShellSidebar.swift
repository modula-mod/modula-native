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
        case .developer: "Developer"
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
        case .developer: "hammer"
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
        case .settings, .appearance, .developer: .manage
        }
    }

    enum Section: String, CaseIterable, Identifiable {
        case library
        case manage
        var id: String { rawValue }
        var title: String {
            switch self {
            case .library: "Library"
            case .manage: "Manage"
            }
        }
    }
}

struct ShellSidebarHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var navigation = app.navigation
        GeometryReader { geometry in
            let width = min(320, geometry.size.width * 0.82)
            ZStack(alignment: .leading) {
                if navigation.sidebarPresented {
                    Color.black.opacity(reduceTransparency ? 0.45 : 0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { dismiss() }
                        .accessibilityLabel("Dismiss sidebar")
                        .accessibilityIdentifier("shell.sidebar.scrim")
                        .accessibilityAddTraits(.isButton)
                }

                if navigation.sidebarPresented {
                    ShellSidebarView(onSelect: open)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        // Keep VoiceOver inside the open sidebar; the two-finger
                        // "Z" scrub closes it like the scrim tap does.
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { dismiss() }
                        .onKeyPress(.escape) {
                            dismiss()
                            return .handled
                        }
                        .gesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { value in
                                    if value.translation.width < -60 { dismiss() }
                                }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(navigation.sidebarPresented)
        .animation(motion, value: navigation.sidebarPresented)
    }

    private var motion: Animation? {
        ModulaMotion.animation(.reveal, personality: app.appearance.motion, reduceMotion: reduceMotion)
    }

    private func dismiss() {
        app.navigation.dismissSidebar()
        HapticEngine.shared.play(.navigation)
    }

    private func open(_ route: AppRoute, requiresSignIn: Bool) {
        app.navigation.dismissSidebar()
        if requiresSignIn, !app.auth.isSignedIn {
            app.navigation.requestAuthentication(returningTo: route)
        } else {
            app.navigation.open(route)
        }
        HapticEngine.shared.play(.navigation)
    }
}

struct ShellSidebarView: View {
    var onSelect: (AppRoute, Bool) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = ModulaPalette.resolve(app.appearance, scheme: scheme)
        let opaque = reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    ForEach(ShellSidebarDestination.Section.allCases) { section in
                        sidebarSection(section)
                    }
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .modulaSoftScrollEdge()

            footer
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                palette.canvas
                if opaque {
                    Color(uiColor: .secondarySystemBackground).opacity(0.92)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [app.appearance.accent.color.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.separator.opacity(0.7))
                .frame(width: 1)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shell.sidebar")
        .accessibilityLabel("Sidebar")
    }

    @ViewBuilder
    private var header: some View {
        if let profile = app.profile.ownProfile, app.auth.isSignedIn {
            Button {
                onSelect(.me(.overview), true)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 60)
                        .overlay(Circle().strokeBorder(app.appearance.accent.color.opacity(0.45), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("@\(profile.handle)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(headerMetrics(profile))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shell.sidebar.profile")
            .accessibilityLabel("\(profile.displayName), @\(profile.handle)")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.auth.isSignedIn ? "Profile" : "Sign in")
                    .font(.title3.weight(.semibold))
                Text(app.auth.isSignedIn
                     ? "Your profile is still loading."
                     : "Saved, drafts and collections stay with your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !app.auth.isSignedIn {
                    Button("Sign In") {
                        onSelect(.auth(.login), false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(app.appearance.accent.color)
                    .accessibilityIdentifier("shell.sidebar.sign-in")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    private func sidebarSection(_ section: ShellSidebarDestination.Section) -> some View {
        let items = ShellSidebarDestination.allCases.filter { $0.section == section }
        return VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ModulaListRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        symbol: item.symbol
                    ) {
                        onSelect(item.route, item.requiresSignIn)
                    }
                    .accessibilityIdentifier("shell.sidebar.\(item.id)")
                    if index < items.count - 1 {
                        SettingsDivider()
                    }
                }
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Developer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ModulaListRow(title: "Component Catalog", subtitle: "Visual reference", symbol: "square.grid.3x3") {
                    onSelect(.developer(.components), false)
                }
                .accessibilityIdentifier("shell.sidebar.components")
                SettingsDivider()
                ModulaListRow(title: "Developer", subtitle: "Diagnostics and labs", symbol: "hammer") {
                    onSelect(.settings(.developer(.root)), false)
                }
                .accessibilityIdentifier("shell.sidebar.developer")
            }
        }
    }
    #endif

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModulaWordmark(height: 16)
            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(versionLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Modula \(version) (\(build))"
    }

    private func headerMetrics(_ profile: ModulaProfile) -> String {
        let posts = ProfileCountFormatter.compact(profile.postCount)
        let followers = ProfileCountFormatter.compact(profile.followerCount)
        return "\(posts) posts · \(followers) followers"
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

struct ShellSidebarEdgeOpenModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var app

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if shouldOfferEdgeOpen {
                Color.clear
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .ignoresSafeArea(edges: .leading)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 28)
                            .onEnded { value in
                                guard value.startLocation.x < 20, value.translation.width > 56 else { return }
                                app.navigation.presentSidebar()
                                HapticEngine.shared.play(.contextOpen)
                            }
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private var shouldOfferEdgeOpen: Bool {
        !app.navigation.sidebarPresented && app.appearance.edgePicker.side != .left
    }
}

extension View {
    func modulaSidebarTrigger() -> some View {
        modifier(ShellSidebarTriggerModifier())
    }

    func modulaSidebarEdgeOpen() -> some View {
        modifier(ShellSidebarEdgeOpenModifier())
    }
}
