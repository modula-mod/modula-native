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
        if let featured = ProductHubCatalogue.featured(in: scoped, installed: installedIDs) {
            ProductHero(product: featured) { onOpen(featured) }
        }
        if !installed.isEmpty {
            sectionHeader("Installed on your account", action: "Manage all", handler: onUpdates)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(installed) { product in
                    ProductHubInstalledTile(product: product, installed: true) { onOpen(product) }
                }
            }
            updatesButton
        }
        purposeGrid
        categorySprout
        if !discover.isEmpty {
            sectionHeader("Discover next")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(discover.prefix(8)) { product in
                        ProductHubDiscoverCard(product: product, installed: false) { onOpen(product) }
                            .frame(width: 168)
                    }
                }
            }
            .scrollClipDisabled()
        }
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
