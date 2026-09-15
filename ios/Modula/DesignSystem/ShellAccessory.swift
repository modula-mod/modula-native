import SwiftUI

// MARK: - Shell accessory configuration

struct ShellAccessoryAction: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let enabled: Bool
    let accessibilityIdentifier: String
}

struct ShellAccessoryConfiguration: Equatable {
    var title: String
    var symbol: String
    var actions: [ShellAccessoryAction]
    var showsSearch: Bool
    var showsMore: Bool

    @MainActor
    static func configuration(for route: AppRoute, activity: ActivityStore?, signedIn: Bool) -> Self {
        switch route {
        case .activity(let mode):
            let state = activity?.state(for: mode)
            let hasUnread = (state?.events.contains { !$0.isRead } ?? false)
                || ((state?.unreadCount ?? 0) > 0)
            return Self(
                title: "Activity",
                symbol: "bell",
                actions: [
                    ShellAccessoryAction(id: "summary", title: "Summary", symbol: "sparkles", enabled: signedIn, accessibilityIdentifier: "accessory.summary"),
                    ShellAccessoryAction(id: "filter", title: "Filter", symbol: "line.3.horizontal.decrease", enabled: signedIn, accessibilityIdentifier: "accessory.filter"),
                    ShellAccessoryAction(id: "mark-read", title: "Mark All Read", symbol: "checkmark.circle", enabled: signedIn && hasUnread, accessibilityIdentifier: "accessory.mark-read")
                ],
                showsSearch: false,
                showsMore: true
            )
        case .home:
            return Self(title: "Home", symbol: "sparkles", actions: [], showsSearch: true, showsMore: true)
        case .discover:
            return Self(
                title: "Tools",
                symbol: "safari",
                actions: [
                    ShellAccessoryAction(id: "search", title: "Search", symbol: "magnifyingglass", enabled: true, accessibilityIdentifier: "accessory.search"),
                    ShellAccessoryAction(id: "filter", title: "Filters", symbol: "line.3.horizontal.decrease", enabled: true, accessibilityIdentifier: "accessory.filter"),
                    ShellAccessoryAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise", enabled: true, accessibilityIdentifier: "accessory.refresh")
                ],
                showsSearch: false,
                showsMore: false
            )
        case .search:
            return Self(title: "Search", symbol: "magnifyingglass", actions: [], showsSearch: false, showsMore: false)
        case .productHub:
            return Self(title: "Modules", symbol: "shippingbox", actions: [], showsSearch: true, showsMore: true)
        case .profile, .me:
            return Self(title: "Profile", symbol: "person.crop.circle", actions: [], showsSearch: true, showsMore: true)
        default:
            return Self(title: "Modula", symbol: "m.circle", actions: [], showsSearch: true, showsMore: true)
        }
    }
}

/// Destination-scoped tool accessory. Modes stay on the context rail.
struct ShellAccessoryHost: View {
    let route: AppRoute
    var nativeHosted = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let config = ShellAccessoryConfiguration.configuration(
            for: route,
            activity: app.activity,
            signedIn: app.auth.isSignedIn
        )
        HStack(spacing: 8) {
            Image(systemName: config.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(app.appearance.accent.color)
                .frame(width: 24, height: 24)
                .background(app.appearance.accent.color.opacity(0.12), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            Text(config.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            ForEach(config.actions) { action in
                if action.enabled {
                    Button {
                        perform(action)
                    } label: {
                        Image(systemName: action.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                    .accessibilityIdentifier(action.accessibilityIdentifier)
                }
            }
            if config.showsSearch {
                Button {
                    app.navigation.open(.search(.root(nil)))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search Modula")
                .accessibilityIdentifier("accessory.search")
            }
            if config.showsMore {
                moreMenu
            }
        }
        .padding(.leading, nativeHosted ? 2 : 7)
        .padding(.trailing, nativeHosted ? 2 : 4)
        .frame(maxWidth: nativeHosted ? .infinity : 310, minHeight: 44)
        .modulaAccessorySurface(
            nativeHosted: nativeHosted,
            opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
        )
        .dynamicTypeSize(...DynamicTypeSize.large)
        .contentTransition(.interpolate)
        .animation(.snappy(duration: 0.28), value: config.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tab.accessory")
    }

    private var moreMenu: some View {
        Menu {
            if case .activity = route {
                Section("Activity") {
                    Button("Notification Settings", systemImage: "bell.badge") {
                        app.navigation.open(.settings(.notifications(.root)))
                    }
                }
            }
            Section("Quick Access") {
                Button("Settings", systemImage: "gearshape") { app.navigation.open(.settings(.root)) }
                Button("Appearance", systemImage: "paintpalette") { app.navigation.open(.settings(.appearance(.root))) }
                Button("Account", systemImage: "person.crop.circle") {
                    if app.auth.account == nil {
                        app.navigation.requestAuthentication(returningTo: .settings(.account(.root)))
                    } else {
                        app.navigation.open(.settings(.account(.root)))
                    }
                }
            }
            Section("Modules") {
                Button("Product Hub", systemImage: "shippingbox") { app.navigation.open(.productHub(.featured)) }
                Button("Installed Modules", systemImage: "checkmark.circle") {
                    app.navigation.open(.productHub(.collection(.installed)))
                }
                Button("Updates", systemImage: "arrow.triangle.2.circlepath") {
                    app.navigation.open(.productHub(.collection(.updates)))
                }
            }
            Section("Privacy & Information") {
                Button("Privacy & Security", systemImage: "lock.shield") { app.navigation.open(.settings(.privacy(.root))) }
                Button("About Modula", systemImage: "info.circle") { app.navigation.open(.settings(.about(.root))) }
                Button("Share Modula", systemImage: "square.and.arrow.up") {
                    PresentationCoordinator.present(.share(route), in: app.navigation)
                }
            }
            #if DEBUG
            Divider()
            Button("Component Catalog", systemImage: "square.grid.3x3") { app.navigation.open(.developer(.components)) }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("accessory.more")
    }

    private func perform(_ action: ShellAccessoryAction) {
        HapticEngine.shared.play(.selection)
        switch action.id {
        case "summary":
            PresentationCoordinator.present(.activitySummary, in: app.navigation)
        case "filter":
            if case .activity = route {
                PresentationCoordinator.present(.activityFilter, in: app.navigation)
            } else {
                PresentationCoordinator.present(.discoverFilter, in: app.navigation)
            }
        case "mark-read":
            if case .activity(let mode) = route {
                Task { await app.activity.markAllRead(mode: mode) }
            }
        case "search":
            app.navigation.open(.search(.root(nil)))
            HapticEngine.shared.play(.navigation)
        case "refresh":
            if case .discover(let scope) = route {
                Task {
                    await app.discover.refresh(scope)
                    HapticEngine.shared.play(.confirmation)
                }
            }
        default:
            break
        }
    }
}

/// Shell-owned bottom chrome for iOS versions without system tab accessories.
struct ModulaBottomChrome: View {
    let route: AppRoute
    var showsAccessory = true

    var body: some View {
        VStack(spacing: 6) {
            if showsAccessory {
                ShellAccessoryHost(route: route)
            }
            ModulaTabBar()
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 5)
    }
}

struct ModulaTabBar: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var navigation = app.navigation
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let selected = navigation.selectedTab == tab
                Button {
                    navigation.select(tab)
                    HapticEngine.shared.play(.navigation)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 17, weight: selected ? .semibold : .medium))
                            .symbolEffect(.bounce, value: selected)
                        Text(tab.title)
                            .font(.caption2.weight(selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(selected ? app.appearance.accent.color : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        if selected {
                            Capsule()
                                .fill(app.appearance.accent.color.opacity(0.11))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: 560)
        .modulaChrome(in: Capsule(), opaque: reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency)
        .shadow(color: .black.opacity(0.11), radius: 16, y: 8)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global navigation")
    }
}

/// Compatibility alias — prefer `ShellAccessoryHost`.
typealias ModulaTabAccessory = ShellAccessoryHost
