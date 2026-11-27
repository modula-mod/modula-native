import SwiftUI

// MARK: - Modules Dock (swipe up from the in-app bottom bar)
//
// Three states, owned by SpatialNavigationCoordinator:
// - collapsed: nothing but the normal bottom bar;
// - half: favourites (pinned) + recently used, for one-handed switching;
// - expanded: the full launcher — search, sort, pinned, every installed module.
// Every tile is an installed module from the Product Hub installation registry
// (`ProductHubStore.installations` + catalogue listing): name, registry icon, availability
// (runnable or not) and its entry point (`/module/:id`). Nothing is hardcoded.

/// On-device favourites + their order. No server route exists for dock pins.
enum SpatialDockPins {
    static let key = "spatial.dock.pinned"

    static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func isPinned(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        load(defaults: defaults).contains(id)
    }

    static func toggle(_ id: String, defaults: UserDefaults = .standard) {
        var list = load(defaults: defaults)
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
        defaults.set(list, forKey: key)
    }

    /// Long-press arrange: move a pinned module one place earlier (-1) or later (+1).
    static func move(_ id: String, by step: Int, defaults: UserDefaults = .standard) {
        var list = load(defaults: defaults)
        guard let index = list.firstIndex(of: id) else { return }
        let target = min(max(index + step, 0), list.count - 1)
        guard target != index else { return }
        list.remove(at: index)
        list.insert(id, at: target)
        defaults.set(list, forKey: key)
    }
}

/// One launcher tile, resolved from the registry.
struct SpatialDockModule: Identifiable, Hashable {
    let product: CatalogueProduct
    let runnable: Bool
    var id: String { product.moduleId }
    var entryPoint: AppRoute { .module(product.moduleId, localPath: nil) }
}

enum SpatialDockSort: String, CaseIterable, Identifiable {
    case recent, name, publisher
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recently used"
        case .name: "Name"
        case .publisher: "Publisher"
        }
    }

    func sorted(_ modules: [SpatialDockModule], recents: [String]) -> [SpatialDockModule] {
        switch self {
        case .name:
            return modules.sorted { $0.product.name.localizedCaseInsensitiveCompare($1.product.name) == .orderedAscending }
        case .publisher:
            return modules.sorted {
                let order = $0.product.publisherName.localizedCaseInsensitiveCompare($1.product.publisherName)
                if order == .orderedSame { return $0.product.name.localizedCaseInsensitiveCompare($1.product.name) == .orderedAscending }
                return order == .orderedAscending
            }
        case .recent:
            let rank = Dictionary(recents.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            return modules.sorted {
                let a = rank[$0.id] ?? Int.max, b = rank[$1.id] ?? Int.max
                if a != b { return a < b }
                return $0.product.name.localizedCaseInsensitiveCompare($1.product.name) == .orderedAscending
            }
        }
    }
}

struct SpatialModulesDock: View {
    /// Container height (full screen) and bottom safe-area inset.
    let containerHeight: CGFloat
    let bottomInset: CGFloat
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorScheme) private var scheme
    @GestureState(resetTransaction: Transaction(animation: SpatialSheetMetrics.settleSpring))
    private var drag: CGFloat = 0
    @State private var query = ""
    @AppStorage("spatial.dock.sort") private var sortRaw = SpatialDockSort.recent.rawValue
    /// Bumped on pin changes so the grid re-reads UserDefaults.
    @State private var pinsVersion = 0
    @FocusState private var searchFocused: Bool

    private var spatial: SpatialNavigationCoordinator { app.navigation.spatial }
    private var sort: SpatialDockSort { SpatialDockSort(rawValue: sortRaw) ?? .recent }
    private var reduceTransparency: Bool {
        systemReduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
    }

    var body: some View {
        let state = spatial.dockState
        let base = SpatialNavigationCoordinator.dockHeight(for: state, container: containerHeight)
        let live = state == .collapsed ? -spatial.liveDockDrag : 0
        let maxHeight = SpatialNavigationCoordinator.dockHeight(for: .expanded, container: containerHeight)
        let height = min(max(base + live - drag, 0), maxHeight)
        let progress = maxHeight > 0 ? min(height / max(SpatialNavigationCoordinator.dockHeight(for: .half, container: containerHeight), 1), 1) : 0
        let shape = UnevenRoundedRectangle(topLeadingRadius: SpatialSheetMetrics.cornerRadius,
                                           bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                           topTrailingRadius: SpatialSheetMetrics.cornerRadius,
                                           style: .continuous)
        ZStack(alignment: .bottom) {
            if height > 0.5 {
                Color.black
                    .opacity((reduceTransparency ? 0.45 : (scheme == .dark ? 0.36 : 0.2)) * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { setDock(.collapsed) }
                    .accessibilityLabel("Close Modules Dock")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("spatial.dock.scrim")

                panel(state: state)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(height, 0) + bottomInset, alignment: .top)
                    .background { SpatialDockBackground(shape: shape, opaque: reduceTransparency) }
                    .clipShape(shape)
                    .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.16), radius: 24, y: -4)
                    .opacity(reduceMotion ? Double(progress) : 1)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityLabel("Modules Dock")
                    .accessibilityIdentifier("spatial.dock")
                    .accessibilityAction(.escape) { setDock(.collapsed) }
                    .onKeyPress(.escape) {
                        setDock(.collapsed)
                        return .handled
                    }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .task(id: state) {
            if state != .collapsed, app.auth.isSignedIn, !app.catalogue.loaded { await app.catalogue.load() }
        }
        .onChange(of: state) { _, new in if new != .expanded { searchFocused = false; query = "" } }
    }

    // MARK: Panel

    @ViewBuilder
    private func panel(state: SpatialDockState) -> some View {
        VStack(spacing: 0) {
            header(state: state)
                .contentShape(Rectangle())
                .gesture(detentDrag(from: state))
            content(state: state)
        }
        .padding(.bottom, bottomInset)
    }

    private func header(state: SpatialDockState) -> some View {
        VStack(spacing: ModulaSpacing.xs) {
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 38, height: 5)
                .padding(.top, ModulaSpacing.xs)
                .accessibilityHidden(true)
            HStack(spacing: ModulaSpacing.xs) {
                Text("Modules")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    setDock(state == .expanded ? .half : .expanded)
                } label: {
                    Image(systemName: state == .expanded ? "chevron.down" : "square.grid.2x2")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state == .expanded ? "Show less" : "Show all modules")
                .accessibilityIdentifier("spatial.dock.expand")
                Button {
                    setDock(.collapsed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Modules Dock")
                .accessibilityIdentifier("spatial.dock.close")
            }
            .padding(.horizontal, ModulaSpacing.lg)
        }
    }

    @ViewBuilder
    private func content(state: SpatialDockState) -> some View {
        let all = installedModules
        if !app.auth.isSignedIn {
            message(title: "Sign in to see your modules", detail: "Installed Product Hub modules appear here.", symbol: "shippingbox")
        } else if all.isEmpty, !app.catalogue.loaded {
            ProgressView("Loading modules…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if all.isEmpty {
            VStack(spacing: ModulaSpacing.sm) {
                message(title: "No modules installed", detail: "Install something from Product Hub and it lands here.", symbol: "shippingbox")
                Button("Open Product Hub") { navigate(.productHub(.featured)) }
                    .buttonStyle(.borderedProminent)
                    .tint(app.appearance.liveAccent)
                    .accessibilityIdentifier("spatial.dock.hub")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                    if state == .expanded {
                        controls
                    }
                    let pinned = pinnedModules(all)
                    let filtering = !trimmedQuery.isEmpty
                    if !pinned.isEmpty, !filtering {
                        grid(title: "Favourites", modules: pinned, arrangeable: true)
                    }
                    if state == .expanded {
                        let listed = filtered(sort.sorted(all, recents: ProductHubRecents.load()))
                        if listed.isEmpty {
                            message(title: "No matches", detail: "Nothing installed matches “\(trimmedQuery)”.", symbol: "magnifyingglass")
                        } else {
                            grid(title: filtering ? "Results" : "All modules", modules: listed, arrangeable: false)
                        }
                        comingSoon
                    } else {
                        let recent = recentModules(all, excluding: Set(pinned.map(\.id)))
                        if !recent.isEmpty {
                            grid(title: "Recent", modules: recent, arrangeable: false)
                        }
                        if pinned.isEmpty, recent.isEmpty {
                            grid(title: "Installed", modules: Array(sort.sorted(all, recents: []).prefix(8)), arrangeable: false)
                        }
                    }
                }
                .padding(.horizontal, ModulaSpacing.lg)
                .padding(.top, ModulaSpacing.xs)
                .padding(.bottom, ModulaSpacing.xl)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
        }
    }

    private var controls: some View {
        HStack(spacing: ModulaSpacing.xs) {
            HStack(spacing: ModulaSpacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search modules", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .accessibilityIdentifier("spatial.dock.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, ModulaSpacing.sm)
            .frame(minHeight: 44)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))

            Menu {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(SpatialDockSort.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.07), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Sort modules")
            .accessibilityValue(sort.title)
            .accessibilityIdentifier("spatial.dock.sort")
        }
    }

    private var comingSoon: some View {
        HStack(spacing: ModulaSpacing.xs) {
            Image(systemName: "folder").foregroundStyle(.tertiary).accessibilityHidden(true)
            Text("Folders").foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Coming soon")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folders, coming soon")
        .accessibilityIdentifier("spatial.dock.folders.soon")
    }

    private func message(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: ModulaSpacing.xs) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ModulaSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    private func grid(title: String, modules: [SpatialDockModule], arrangeable: Bool) -> some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ModulaSpacing.sm, alignment: .top), count: 4),
                      spacing: ModulaSpacing.md) {
                ForEach(modules) { module in
                    tile(module, arrangeable: arrangeable)
                }
            }
        }
    }

    private func tile(_ module: SpatialDockModule, arrangeable: Bool) -> some View {
        let pinned = isPinned(module.id)
        return Button { openModule(module) } label: {
            VStack(spacing: 6) {
                ProductArtwork(product: module.product, size: 58)
                    .saturation(module.runnable ? 1 : 0.2)
                    .opacity(module.runnable ? 1 : 0.55)
                    .overlay(alignment: .topTrailing) {
                        if pinned {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(app.appearance.liveAccent, in: Circle())
                                .offset(x: 4, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
                Text(module.product.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !module.runnable {
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(pinned ? "Remove from Favourites" : "Add to Favourites", systemImage: pinned ? "star.slash" : "star") {
                togglePin(module.id)
            }
            if arrangeable, pinned {
                Button("Move earlier", systemImage: "arrow.left") { movePin(module.id, by: -1) }
                Button("Move later", systemImage: "arrow.right") { movePin(module.id, by: 1) }
            }
            Button("Details", systemImage: "info.circle") {
                navigate(.productHub(.module(module.id, .overview)))
            }
        }
        .accessibilityLabel(module.runnable ? module.product.name : "\(module.product.name), unavailable")
        .accessibilityHint("Opens the module")
        .accessibilityAction(named: pinned ? "Remove from Favourites" : "Add to Favourites") { togglePin(module.id) }
        .accessibilityIdentifier("spatial.dock.module.\(module.id)")
    }

    // MARK: Data (installation registry)

    private var installedModules: [SpatialDockModule] {
        guard app.auth.isSignedIn else { return [] }
        let installed = app.catalogue.installedIDs
        return app.catalogue.products
            .filter { installed.contains($0.moduleId) }
            .map { SpatialDockModule(product: $0, runnable: app.catalogue.installations[$0.moduleId]?.isRunnable == true) }
    }

    private func pinnedModules(_ all: [SpatialDockModule]) -> [SpatialDockModule] {
        _ = pinsVersion
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return SpatialDockPins.load().compactMap { byID[$0] }
    }

    private func recentModules(_ all: [SpatialDockModule], excluding: Set<String>) -> [SpatialDockModule] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ProductHubRecents.load().filter { !excluding.contains($0) }.compactMap { byID[$0] }.prefix(8).map { $0 }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func filtered(_ modules: [SpatialDockModule]) -> [SpatialDockModule] {
        let q = trimmedQuery
        guard !q.isEmpty else { return modules }
        return modules.filter {
            $0.product.name.localizedCaseInsensitiveContains(q) || $0.product.publisherName.localizedCaseInsensitiveContains(q)
        }
    }

    private func isPinned(_ id: String) -> Bool {
        _ = pinsVersion
        return SpatialDockPins.isPinned(id)
    }

    // MARK: Actions

    private func togglePin(_ id: String) {
        SpatialDockPins.toggle(id)
        pinsVersion += 1
        HapticEngine.shared.play(.selection)
    }

    private func movePin(_ id: String, by step: Int) {
        SpatialDockPins.move(id, by: step)
        pinsVersion += 1
        HapticEngine.shared.play(.selection)
    }

    private func openModule(_ module: SpatialDockModule) {
        ProductHubRecents.note(module.id)
        navigate(module.runnable ? module.entryPoint : .productHub(.module(module.id, .overview)))
    }

    private func navigate(_ route: AppRoute) {
        setDock(.collapsed)
        app.navigation.open(route)
        HapticEngine.shared.play(.navigation)
    }

    private func setDock(_ state: SpatialDockState) {
        withAnimation(reduceMotion ? SpatialSheetMetrics.reduceMotionFade : SpatialSheetMetrics.settleSpring) {
            spatial.setDock(state)
        }
        if state == .collapsed { HapticEngine.shared.play(.lightImpact) }
    }

    private func detentDrag(from state: SpatialDockState) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, current, transaction in
                transaction.disablesAnimations = true
                current = value.translation.height
            }
            .onEnded { value in
                let next = SpatialNavigationCoordinator.settledDock(from: state, translation: value.translation.height,
                                                                     predicted: value.predictedEndTranslation.height,
                                                                     container: containerHeight)
                if next != state { HapticEngine.shared.play(.selection) }
                setDock(next)
            }
    }
}

/// Liquid Glass dock surface (navigation chrome), opaque canvas under Reduce Transparency.
private struct SpatialDockBackground<S: Shape>: View {
    let shape: S
    var opaque: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
        Group {
            if opaque {
                shape.fill(canvas)
            } else {
                shape.fill(canvas.opacity(0.55)).modulaGlass(in: shape, interactive: false)
            }
        }
        .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
