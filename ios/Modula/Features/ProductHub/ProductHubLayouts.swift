import SwiftUI

/// Local presentation of the Product Hub. The catalogue itself always comes from
/// `GET /v1/registry/products` and `GET /v1/modules/installed`.
enum ProductHubLayout: String, CaseIterable, Identifiable, Codable {
    case story, list, space, store
    var id: String { rawValue }
    var title: String {
        switch self {
        case .story: "Story"
        case .list: "List"
        case .space: "Your space"
        case .store: "Store"
        }
    }
}

enum ProductHubSpaceSegment: String, CaseIterable, Identifiable {
    case discover, installed, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: "Discover"
        case .installed: "Installed"
        case .updates: "Updates"
        }
    }
}

struct ProductHubPurpose: Equatable, Identifiable, Sendable {
    var id: String { kind }
    let kind: String
    let title: String
    let count: Int

    var symbol: String {
        switch kind.lowercased() {
        case "game": "gamecontroller"
        case "tool", "utility", "utilities": "wrench.and.screwdriver"
        case "function": "function"
        case "plugin": "puzzlepiece.extension"
        case "widget": "square.dashed"
        case "connection": "link"
        default: "square.grid.2x2"
        }
    }
}

enum ProductHubCatalogue {
    static func featured(in products: [CatalogueProduct], installed: Set<String>) -> CatalogueProduct? {
        products.first(where: { $0.installable && !installed.contains($0.id) })
            ?? products.first { $0.moduleId == "digital.modula.vault-notes" }
            ?? products.first
    }

    static func installedProducts(_ products: [CatalogueProduct], installed: Set<String>) -> [CatalogueProduct] {
        products.filter { installed.contains($0.id) }
    }

    static func discoverable(_ products: [CatalogueProduct], installed: Set<String>) -> [CatalogueProduct] {
        products.filter { !installed.contains($0.id) }
    }

    /// An update exists only when both versions are published and the registry version is newer.
    static func updates(products: [CatalogueProduct], installations: [String: ModuleInstallation]) -> [CatalogueProduct] {
        products.filter { product in
            guard let current = installations[product.id]?.version, let latest = product.latestVersion else { return false }
            return ModuleVersion.isOlder(current, than: latest)
        }
    }

    static func purposes(in products: [CatalogueProduct]) -> [ProductHubPurpose] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for product in products {
            let kind = product.productKind.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !kind.isEmpty else { continue }
            if counts[kind] == nil { order.append(kind) }
            counts[kind, default: 0] += 1
        }
        return order.map { ProductHubPurpose(kind: $0, title: $0.replacingOccurrences(of: "-", with: " ").capitalized, count: counts[$0] ?? 0) }
    }

    static func matching(_ products: [CatalogueProduct], query: String, kind: String?) -> [CatalogueProduct] {
        products.filter { product in
            let matchesKind = kind == nil || product.productKind == kind
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matchesKind else { return false }
            guard !trimmed.isEmpty else { return true }
            return product.name.localizedCaseInsensitiveContains(trimmed)
                || product.description.localizedCaseInsensitiveContains(trimmed)
                || product.publisherName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func comingSoon(_ products: [CatalogueProduct]) -> [CatalogueProduct] {
        products.filter { !$0.installable }
    }
}

struct ProductHubVariantView: View {
    let layout: ProductHubLayout
    let products: [CatalogueProduct]
    let installedIDs: Set<String>
    let installations: [String: ModuleInstallation]
    var category: String?
    @Binding var segment: ProductHubSpaceSegment
    var onCategory: (String) -> Void
    var onOpen: (CatalogueProduct) -> Void
    var onUpdates: () -> Void

    private var scoped: [CatalogueProduct] { ProductHubCatalogue.matching(products, query: "", kind: category) }
    private var installed: [CatalogueProduct] { ProductHubCatalogue.installedProducts(scoped, installed: installedIDs) }
    private var discover: [CatalogueProduct] { ProductHubCatalogue.discoverable(scoped, installed: installedIDs) }
    private var updates: [CatalogueProduct] { ProductHubCatalogue.updates(products: scoped, installations: installations) }
    private var purposes: [ProductHubPurpose] { ProductHubCatalogue.purposes(in: products) }

    var body: some View {
        if scoped.isEmpty {
            ModulaEmptyState(title: "No modules in this category", message: "The registry has no products of this kind.", symbol: "square.grid.2x2")
            purposeGrid
        } else {
            switch layout {
            case .story: story
            case .list: list
            case .space: space
            case .store: store
            }
        }
    }

    @ViewBuilder private var story: some View {
        ProductHubFeaturedCarousel(products: featuredRail, installedIDs: installedIDs, onOpen: onOpen)
        ProductHubChipRow(purposes: purposes, total: products.count, selected: category, onCategory: onCategory)
        let recent = ProductHubRecents.load().compactMap { id in installed.first { $0.id == id } }
        if !recent.isEmpty {
            sectionHeader("Continue where you left off")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recent.prefix(6)) { product in
                        ProductHubContinueCard(product: product) { onOpen(product) }
                    }
                }
            }
            .scrollClipDisabled()
        }
        if !updates.isEmpty {
            HStack(spacing: 8) {
                Text("Updates available").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text("\(updates.count)").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 22).modulaAccentCTA()
                Spacer()
            }
            VStack(spacing: 8) {
                ForEach(updates) { product in
                    ProductHubVersionRow(product: product, installation: installations[product.id]) { onOpen(product) }
                }
            }
        }
        if !discover.isEmpty || !installed.isEmpty {
            sectionHeader("Recommended for you")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach((discover + installed).prefix(10)) { product in
                        ProductHubRecommendedCard(product: product, installed: installedIDs.contains(product.id)) { onOpen(product) }
                    }
                }
            }
            .scrollClipDisabled()
        }
        let withShots = scoped.filter { !($0.presentation?.screenshots ?? []).compactMap(\.url).isEmpty }
        if !withShots.isEmpty {
            sectionHeader("Module previews")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(withShots.prefix(6)) { product in
                        ProductHubPreviewCard(product: product) { onOpen(product) }
                    }
                }
            }
            .scrollClipDisabled()
        }
        ForEach(ProductHubCollections.make(scoped)) { collection in
            sectionHeader(collection.title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(collection.products.prefix(8)) { product in
                        ProductHubRecommendedCard(product: product, installed: installedIDs.contains(product.id)) { onOpen(product) }
                    }
                }
            }
            .scrollClipDisabled()
        }
        if !installed.isEmpty {
            HStack(spacing: 8) {
                Text("Installed").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text("\(installed.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 8).frame(height: 22)
                    .modulaGlass(in: Capsule(), interactive: false)
                Spacer()
                Button(action: onUpdates) {
                    Label("Manage", systemImage: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 34)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true)
            }
            VStack(spacing: 10) {
                ForEach(installed) { product in
                    ProductHubInstalledRow(product: product, version: installations[product.id]?.version ?? product.latestVersion) { onOpen(product) }
                }
            }
            updatesButton
        }
        categorySprout
    }

    private var featuredRail: [CatalogueProduct] {
        var out: [CatalogueProduct] = []
        if let f = ProductHubCatalogue.featured(in: scoped, installed: installedIDs) { out.append(f) }
        for p in scoped where !out.contains(where: { $0.id == p.id }) && out.count < 5 { out.append(p) }
        return out
    }

    @ViewBuilder private var list: some View {
        if let featured = ProductHubCatalogue.featured(in: scoped, installed: installedIDs) {
            ProductHero(product: featured) { onOpen(featured) }
        }
        if !installed.isEmpty {
            sectionHeader("Installed", action: "Manage all", handler: onUpdates)
            Text("Your modules, ready to open").font(.subheadline).foregroundStyle(.secondary)
            ForEach(installed) { product in
                ProductCard(product: product, installed: true) { onOpen(product) }
            }
            updatesButton
        }
        if !discover.isEmpty {
            sectionHeader("Discover something new")
            Text("From the registry").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(discover.prefix(4)) { product in
                    ProductHubDiscoverCard(product: product, installed: false, prominent: true) { onOpen(product) }
                }
            }
        }
        categorySprout
    }

    @ViewBuilder private var space: some View {
        SpaceHeader()
        Picker("Library", selection: $segment) {
            Text("Discover").tag(ProductHubSpaceSegment.discover)
            Text("Installed \(installed.count)").tag(ProductHubSpaceSegment.installed)
            Text("Updates").tag(ProductHubSpaceSegment.updates)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("product-hub.segments")
        switch segment {
        case .discover:
            if !installed.isEmpty {
                sectionHeader("Ready when you are", action: "Manage all", handler: onUpdates)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(installed.prefix(4)) { product in
                        ProductHubInstalledTile(product: product, installed: true) { onOpen(product) }
                    }
                }
            }
            purposeGrid
            if !discover.isEmpty {
                sectionHeader("Discover next")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(discover.prefix(8)) { product in
                            ProductHubDiscoverCard(product: product, installed: false) { onOpen(product) }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        case .installed:
            if installed.isEmpty {
                ModulaEmptyState(title: "Nothing installed", message: "Modules you install on this account show up here.", symbol: "square.and.arrow.down")
            } else {
                ForEach(installed) { product in
                    ProductCard(product: product, installed: true) { onOpen(product) }
                }
                updatesButton
            }
        case .updates:
            updatesList
        }
        categorySprout
    }

    @ViewBuilder private var store: some View {
        let featured = Array(ProductHubCatalogue.discoverable(scoped, installed: installedIDs).prefix(5))
        if !featured.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(featured.enumerated()), id: \.element.id) { index, product in
                        ProductHero(product: product, marksFeatured: index == 0) { onOpen(product) }
                            .frame(width: 320)
                    }
                }
            }
            .scrollClipDisabled()
        }
        ProductCategoryChips(products: products, selected: category, onOpen: onCategory)
        categorySprout
        if !discover.isEmpty {
            sectionHeader("Recommended for you")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(discover.prefix(8)) { product in
                        ProductHubDiscoverCard(product: product, installed: installedIDs.contains(product.id)) { onOpen(product) }
                            .frame(width: 150)
                    }
                }
            }
            .scrollClipDisabled()
        }
        if !installed.isEmpty {
            sectionHeader("Installed \(installed.count)", action: "Manage all", handler: onUpdates)
            ForEach(installed) { product in
                ProductHubVersionRow(product: product, installation: installations[product.id]) { onOpen(product) }
            }
            updatesButton
        }
    }

    @ViewBuilder private var purposeGrid: some View {
        if !purposes.isEmpty {
            sectionHeader("Explore by purpose")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(purposes) { purpose in
                    Button {
                        onCategory(purpose.kind)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(purpose.title).font(.headline).foregroundStyle(.primary)
                                Text("\(purpose.count) \(purpose.count == 1 ? "module" : "modules")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: purpose.symbol).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .background(Color.primary.opacity(category == purpose.kind ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("product-hub.purpose.\(purpose.kind)")
                    .accessibilityAddTraits(category == purpose.kind ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private var categorySprout: some View {
        if let category, let sprout = SproutIllustration.matching(text: category) {
            SproutIllustrationView(illustration: sprout, height: 132)
                .accessibilityIdentifier("product-hub.category.sprout")
        }
    }

    private var updatesButton: some View {
        Button(action: onUpdates) {
            Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
        .accessibilityIdentifier("product-hub.updates")
    }

    @ViewBuilder private var updatesList: some View {
        if updates.isEmpty {
            ModulaEmptyState(
                title: "No updates",
                message: "Installed modules match the latest version the registry published, or a version wasn’t included.",
                symbol: "checkmark.circle"
            )
            .accessibilityIdentifier("product-hub.updates.empty")
        } else {
            ForEach(updates) { product in
                ProductHubVersionRow(product: product, installation: installations[product.id]) { onOpen(product) }
            }
        }
    }

    private func sectionHeader(_ title: String, action: String? = nil, handler: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let action {
                Button(action, action: handler)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SpaceHeader: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch app.appearance.brandWordmark {
            case .modula: ModulaWordmark(height: 22)
            case .moliboos: MoliboosWordmark(height: 26)
            }
            Text("PRODUCT HUB")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(app.appearance.liveAccent)
            Text("Your space.\nYour modules.")
                .font(.largeTitle.bold())
            Text("Make Modula work the way you do.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Product Hub. Your space. Your modules.")
    }
}

struct ProductHubInstalledTile: View {
    let product: CatalogueProduct
    let installed: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    ProductArtwork(product: product, size: 48)
                    Spacer(minLength: 0)
                }
                Text(product.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(product.displayDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Label("Installed", systemImage: "circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 4)
                    ProductGetOpenControl(product: product, installed: installed)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("product.\(product.moduleId)")
    }
}

struct ProductHubDiscoverCard: View {
    let product: CatalogueProduct
    let installed: Bool
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ProductArtwork(product: product, size: prominent ? 56 : 44)
                Text(product.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(product.displayDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if installed {
                    Text("Installed").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: prominent ? 160 : 132, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("product-hub.discover.\(product.moduleId)")
    }
}

struct ProductHubVersionRow: View {
    let product: CatalogueProduct
    let installation: ModuleInstallation?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProductArtwork(product: product, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(product.displayDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(versionLine).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                ProductGetOpenControl(product: product, installed: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("product.\(product.moduleId)")
    }

    private var versionLine: String {
        let publisher = product.publisherName
        if let installed = installation?.version {
            return "\(publisher) · installed \(installed)"
        }
        if let latest = product.latestVersion {
            return "\(publisher) · \(latest)"
        }
        return publisher
    }
}


// MARK: - Reference-style Product Hub pieces (real registry + installation data only)

struct ProductHubFeaturedCarousel: View {
    let products: [CatalogueProduct]
    let installedIDs: Set<String>
    var onOpen: (CatalogueProduct) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    var body: some View {
        if !products.isEmpty {
            VStack(spacing: 8) {
                TabView(selection: $page) {
                    ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                        card(product).tag(index).padding(.horizontal, 2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 220)
                HStack(spacing: 6) {
                    ForEach(products.indices, id: \.self) { i in
                        Capsule().fill(i == page ? app.appearance.liveAccent : Color.primary.opacity(0.18))
                            .frame(width: i == page ? 18 : 6, height: 6)
                            .animation(reduceMotion ? nil : .snappy, value: page)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func card(_ product: CatalogueProduct) -> some View {
        Button { onOpen(product); HapticEngine.shared.play(.navigation) } label: {
            ZStack(alignment: .leading) {
                ProductBackdrop(product: product)
                LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(installedIDs.contains(product.id) ? "INSTALLED" : "FEATURED")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 24)
                            .modulaGlass(in: Capsule(), interactive: false)
                        Text(product.name).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                        Text(product.description).font(.subheadline).foregroundStyle(.white.opacity(0.88)).lineLimit(3)
                        HStack(spacing: 8) { Text("View module"); Image(systemName: "arrow.right") }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(.white, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    ProductArtwork(product: product, size: 96)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
        }
        .buttonStyle(.modulaPressTilt)
        .accessibilityLabel("Featured: \(product.name)")
    }
}

struct ProductHubChipRow: View {
    let purposes: [ProductHubPurpose]
    let total: Int
    let selected: String?
    var onCategory: (String) -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", symbol: "square.grid.2x2", count: total, on: selected == nil) {
                    if let selected { onCategory(selected) }
                }
                ForEach(purposes) { p in
                    chip(title: p.title, symbol: p.symbol, count: nil, on: selected == p.kind) { onCategory(p.kind) }
                }
            }
        }
        .scrollClipDisabled()
    }
    private func chip(title: String, symbol: String, count: Int?, on: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); HapticEngine.shared.play(.selection) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                if let count {
                    Text("\(count)").font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 6).frame(height: 18)
                        .background((on ? Color.white : Color.primary).opacity(0.2), in: Capsule())
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 14).frame(height: 38)
            .background(on ? app.appearance.liveAccent : .clear, in: Capsule())
            .modulaGlass(in: Capsule(), interactive: true)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct ProductHubRecommendedCard: View {
    let product: CatalogueProduct
    let installed: Bool
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ProductArtwork(product: product, size: 72)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(app.appearance.liveAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(product.productKind.replacingOccurrences(of: "-", with: " ").capitalized).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Group {
                    if installed {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    } else {
                        Text(product.installable ? "Install" : "Soon")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .modulaAccentCTA()
                            .disabled(!product.installable)
                    }
                }
                .padding(.top, 2)
            }
            .padding(10)
            .frame(width: 150)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.name), \(installed ? "installed" : "not installed")")
    }
}

struct ProductHubInstalledRow: View {
    let product: CatalogueProduct
    let version: String?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProductArtwork(product: product, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.headline).lineLimit(1)
                    Text(product.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").font(.caption2)
                        Text([product.publisherName, version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text("Open")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14).frame(height: 32)
                    .modulaAccentCTA()
            }
            .padding(12)
            .frame(minHeight: 80)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.name), open")
    }
}


// MARK: - Continue / previews / collections (real data; on-device recents)

/// Modules the user opened from the Hub, newest first. Stored on this iPhone only — there is no
/// "recently used modules" route.
enum ProductHubRecents {
    static let key = "productHub.recentModules"
    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func note(_ id: String) {
        var list = load().filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: key)
    }
}

struct ProductHubContinueCard: View {
    let product: CatalogueProduct
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProductArtwork(product: product, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Resume").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "play.fill").font(.caption.weight(.bold))
                    .frame(width: 32, height: 32).modulaAccentCTA(in: Circle())
            }
            .padding(10)
            .frame(minHeight: 64)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue \(product.name)")
    }
}

/// Registry screenshots only. Ratings aren't shown: the registry has no ratings field or route.
struct ProductHubPreviewCard: View {
    let product: CatalogueProduct
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array((product.presentation?.screenshots ?? []).compactMap { $0.url.flatMap(URL.init(string:)) }.prefix(3).enumerated()), id: \.offset) { _, url in
                            ModulaRemoteImage(url: url, cacheKey: "hub-shot:\(url.absoluteString)", maximumPixelSize: 600) { phase in
                                switch phase {
                                case .success(let image): Image(uiImage: image).resizable().scaledToFill()
                                default: Color.primary.opacity(0.06)
                                }
                            }
                            .frame(width: 96, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                HStack(spacing: 8) {
                    ProductArtwork(product: product, size: 32)
                    Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
            }
            .padding(10)
            .frame(width: 320, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.name) previews")
    }
}

/// Collections derived from registry fields (publisher, kind, installability). There is no
/// editorial collections route, so nothing is hand-picked.
struct ProductHubDerivedCollection: Identifiable { let id: String; let title: String; let products: [CatalogueProduct] }
enum ProductHubCollections {
    static func make(_ products: [CatalogueProduct]) -> [ProductHubDerivedCollection] {
        var out: [ProductHubDerivedCollection] = []
        let modula = products.filter { $0.publisherName.localizedCaseInsensitiveContains("modula") }
        if modula.count >= 2 { out.append(.init(id: "modula", title: "Made by Modula", products: modula)) }
        let games = products.filter { $0.productKind.lowercased() == "game" }
        if games.count >= 2 { out.append(.init(id: "games", title: "Games", products: games)) }
        let soon = products.filter { !$0.installable }
        if soon.count >= 2 { out.append(.init(id: "soon", title: "Coming soon", products: soon)) }
        return out
    }
}
