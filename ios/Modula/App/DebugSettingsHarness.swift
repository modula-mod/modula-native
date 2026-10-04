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
#endif
