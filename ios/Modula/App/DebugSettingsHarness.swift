#if DEBUG
import SwiftUI

/// DEBUG-only screenshot harness for Settings routes.
///
/// Launch with `--debug-settings-route /settings/help/status` to render a single
/// settings destination inside a navigation stack without passing AppGate. Used to
/// capture route screenshots on simulators that are signed out. Pushed settings
/// routes still resolve so the harness can be driven interactively. Never compiled
/// into Release builds; it never fakes a session — signed-out routes render their
/// real signed-out state.
enum DebugSettingsHarness {
    static var route: AppRoute? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--debug-settings-route"), args.indices.contains(index + 1) else {
            return nil
        }
        let value = args[index + 1]
        guard let route = RouteParser.parse(value), case .settings = route else { return nil }
        return route
    }

    /// `--debug-composer attach|gifs` opens the composer attach menu or GIF panel for screenshots.
    static var composerState: String? { value(after: "--debug-composer") }

    /// `--debug-browser https://… [--debug-browser-post <postID>]` opens the in-app browser for screenshots.
    static var browserURL: URL? { value(after: "--debug-browser").flatMap(URL.init(string:)) }
    static var browserPostID: String? { value(after: "--debug-browser-post") }

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    /// `--debug-studio-scene <n>` (with `--debug-moliboo-studio`): equip the n-th owned, available
    /// background scene, or clear it with `none`. Ownership-checked by the store; simulator only.
    @MainActor
    static func equipStudioSceneIfRequested() {
        guard let raw = value(after: "--debug-studio-scene") else { return }
        let store = MascotWardrobeStore.shared
        if raw == "none" { store.unequip(.background); return }
        let scenes = MascotWardrobeCatalog.items(in: .background).filter { store.canEquip($0) }
        guard let n = Int(raw), scenes.indices.contains(n) else { return }
        store.equip(scenes[n])
    }

    /// `--debug-modula-code mycode|scan` opens the Modula Code screen (sample public link only).
    static var modulaCodeMode: ModulaCodeMode? {
        switch value(after: "--debug-modula-code") {
        case "mycode": .myCode
        case "scan": .scan
        default: nil
        }
    }

    static var sampleCodeSubject: ModulaCodeSubject {
        ModulaCodeSubject(
            title: "Andrei",
            subtitle: "@andrei.modula",
            url: ModulaShareLink.profile("andrei.modula"),
            initials: "AN"
        )
    }

    /// `--debug-share profile|post|link` opens the universal share sheet for screenshots.
    static var sharePayload: SharePayload? {
        switch value(after: "--debug-share") {
        case "profile": .profile(identity: "andrei.modula", displayName: "Andrei", handle: "andrei.modula", avatarURL: nil)
        case "post": .post(id: "debug-post", authorName: "Andrei", excerpt: "Sample post for the share sheet", hasMedia: true)
        case "link": .link(url: URL(string: "https://modula.digital/docs") ?? ModulaShareLink.base, title: "Modula Docs")
        default: nil
        }
    }

    /// `--debug-sheet feeds|summary|discover-people|discover-posts|discover-modules` presents a shell sheet
    /// over a plain canvas, for screenshots (discover-* sets the Discover scope the sheet reads).
    static var sheetPresentation: (AppPresentation, AppRoute?)? {
        switch value(after: "--debug-sheet") {
        case "feeds": (.homeFeeds, .home(.following))
        case "summary": (.homeSummary, .home(.following))
        case "discover-people": (.discoverFilter, .discover(.people))
        case "discover-posts": (.discoverFilter, .discover(.posts))
        case "discover-modules": (.discoverFilter, .discover(.modules))
        default: nil
        }
    }

    /// `--debug-route /profile/andrei.modula` renders any route (signed-out real data only).
    static var anyRoute: AppRoute? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--debug-route"), args.indices.contains(index + 1) else {
            return nil
        }
        return RouteParser.parse(args[index + 1])
    }
}

struct DebugSettingsHarnessView: View {
    @Environment(AppEnvironment.self) private var app
    let route: AppRoute

    var body: some View {
        NavigationStack(path: app.navigation.binding(for: app.navigation.selectedTab)) {
            destination(route)
                .navigationDestination(for: AppRoute.self) { destination($0) }
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        if case .settings(let settings) = route {
            SettingsDestinationHost(route: settings)
        } else if DebugSettingsHarness.anyRoute != nil {
            RouteView(route: route)
        } else {
            ContentUnavailableView(
                "Outside harness",
                systemImage: "rectangle.dashed",
                description: Text(RouteSerializer.serialize(route))
            )
        }
    }
}

/// `--debug-moliboo-picker`: a composer bar (as on a post's comments) with the real composer Moliboo, so the
/// picker can be opened from the avatar with room above it. Add `-MOLPickerOpen` to open it on launch.
struct MolibooPickerHarnessView: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @State private var text = ""
    var body: some View {
        ZStack(alignment: .bottom) {
            MolibooAmbientBackground(ambience: .resolved(), showsSky: true).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("Comments").font(.title2.weight(.bold)).foregroundStyle(MolibooAmbience.resolved().isDark ? .white : .primary)
                Spacer()
                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $text)
                        .textFieldStyle(.plain).padding(.horizontal, 14).frame(height: 44)
                        .modulaGlass(in: Capsule(), interactive: false, specular: true)
                        .modulaMascotPerch()
                    ModulaGlassSendButton(title: "Send", ready: !text.isEmpty) { text = "" }
                }
                .overlayPreferenceValue(MascotPerchKey.self) { anchor in
                    GeometryReader { proxy in
                        if let kind = ModulaMascotKind(rawValue: kindRaw), let anchor {
                            let bar = proxy[anchor]
                            ModulaComposerMascot(kind: kind, busy: false, touch: nil, text: text, placement: .comments, size: 48) { kindRaw = $0.rawValue }
                                .position(x: bar.maxX - 26 - 24 * kind.bodySize.width, y: bar.minY + 6 - kind.footFraction * 48)
                        }
                    }
                }
            }
            .padding(16)
        }
        .environment(\.colorScheme, MolibooAmbience.resolved().isDark ? .dark : .light)
        .accessibilityIdentifier("moliboo.picker.harness")
    }
}
struct DebugSheetHarnessView: View {
    @Environment(AppEnvironment.self) private var app
    let presentation: AppPresentation
    let context: AppRoute?
    @State private var shown = false
    var body: some View {
        Color(uiColor: .systemBackground).ignoresSafeArea()
            .sheet(isPresented: $shown) {
                ModulaSheet(detents: presentation.sheetDetents) { PresentationView(presentation: presentation) }
            }
            .task {
                if let context { app.navigation.replaceContext(with: context) }
                try? await Task.sleep(for: .milliseconds(300))
                shown = true
            }
    }
}
#endif
