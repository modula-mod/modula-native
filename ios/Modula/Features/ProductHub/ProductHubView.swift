import SwiftUI
import Observation

@MainActor @Observable
final class ProductHubStore {
    private let client: GreenfieldClient
    private(set) var products: [CatalogueProduct] = []
    private(set) var installedIDs: Set<String> = []
    private(set) var loading = false
    private(set) var loaded = false
    var error: String?

    init(client: GreenfieldClient) { self.client = client }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        do {
            products = try await client.catalogue()
            loaded = true
            if let installed = try? await client.installedModuleIDs() { installedIDs = installed }
        } catch {
            self.error = "Product catalogue is unavailable. Pull to refresh."
        }
    }

    func product(_ id: String) -> CatalogueProduct? { products.first { $0.moduleId == id } }
}

private struct VaultFoldMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.18
        let fold = rect.width * 0.28
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset - fold, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset + fold))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.maxX - inset - fold, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset - fold, y: rect.minY + inset + fold))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset + fold))
        return path
    }
}

struct ProductArtwork: View {
    let product: CatalogueProduct
    var size = 66.0
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(baseColor)
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .padding(size * 0.06)
            if product.moduleId.contains("vault") {
                VaultFoldMark()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: max(2, size * 0.055), lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.58, height: size * 0.58)
                VStack(spacing: size * 0.055) {
                    Capsule().fill(app.appearance.accent.color).frame(width: size * 0.23, height: max(2, size * 0.035))
                    Capsule().fill(app.appearance.accent.color.opacity(0.68)).frame(width: size * 0.17, height: max(2, size * 0.035))
                }
                .offset(x: -size * 0.045, y: size * 0.07)
            } else {
                Text(product.name.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: baseColor.opacity(0.28), radius: size * 0.16, y: size * 0.08)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name) artwork")
    }

    private var baseColor: Color {
        product.moduleId.contains("vault") ? Color(hex: "#103B41") : Color(hex: "#343752")
    }
}

private struct ProductBackdrop: View {
    let product: CatalogueProduct
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: product.moduleId.contains("vault") ? "#061E22" : "#171827")
                Circle()
                    .fill(app.appearance.accent.color.opacity(0.2))
                    .frame(width: proxy.size.width * 0.8)
                    .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.24)
                Circle()
                    .stroke(app.appearance.accent.color.opacity(0.4), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.56)
                    .offset(x: proxy.size.width * 0.35, y: -proxy.size.height * 0.24)
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.07 + Double(index) * 0.025))
                        .frame(width: proxy.size.width * (0.46 - Double(index) * 0.055), height: 7)
                        .rotationEffect(.degrees(-22))
                        .offset(x: -proxy.size.width * 0.25, y: CGFloat(index * 27) - 18)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProductBadge: View {
    var title: String
    var body: some View { ModulaBadge(title: title, symbol: "checkmark.seal") }
}

struct PublisherLabel: View {
    var name: String
    var body: some View {
        Label(name, systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct ModuleHealthBadge: View {
    var available: Bool
    var body: some View {
        ModulaBadge(title: available ? "Available" : "Coming Soon", symbol: available ? "checkmark.circle" : "clock")
    }
}

struct ProductMetadata: View {
    let product: CatalogueProduct
    var body: some View {
        ModulaMetadataRail(values: [
            (product.latestVersion ?? "—", "Version"),
            (product.platforms.contains("ios") ? "iOS" : "—", "Platform"),
            (product.status.capitalized, "Status")
        ])
    }
}

struct InstallStateButton: View {
    let product: CatalogueProduct
    let installed: Bool
    var open: () -> Void

    var body: some View {
        if installed {
            ModulaButton(title: "Open", symbol: "arrow.up.forward.app", action: open)
                .accessibilityIdentifier("module.open")
        } else if product.installable {
            Button("Available to install", systemImage: "arrow.down.circle") {}
                .buttonStyle(.bordered)
                .disabled(true)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Button("Coming Soon", systemImage: "clock") {}
                .buttonStyle(.bordered)
                .disabled(true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

struct ProductCard: View {
    let product: CatalogueProduct
    let installed: Bool
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ProductArtwork(product: product, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(product.name).font(.headline)
                    PublisherLabel(name: product.publisherName)
                    Text(installed ? "Installed" : (product.installability?.reason ?? product.status.capitalized))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.primary.opacity(0.065)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("product.\(product.moduleId)")
    }
}

struct ProductShelf: View {
    var title: String
    var subtitle: String? = nil
    var products: [CatalogueProduct]
    var installedIDs: Set<String>
    var action: (CatalogueProduct) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(products) { product in
                ProductCard(product: product, installed: installedIDs.contains(product.id)) { action(product) }
            }
        }
    }
}

struct ProductHero: View {
    let product: CatalogueProduct
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ProductBackdrop(product: product)
                VStack(alignment: .leading, spacing: 10) {
                    Spacer()
                    ProductArtwork(product: product, size: 86)
                    Text(product.name)
                        .font(.largeTitle.bold())
                    Text(product.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                    Label("View module", systemImage: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Featured module, \(product.name)")
    }
}

struct ProductHubView: View {
    let route: ProductHubRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""

    private var visible: [CatalogueProduct] {
        query.isEmpty ? app.catalogue.products : app.catalogue.products.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Product Hub").font(.largeTitle.bold())
                        Text("Native modules, grounded in catalogue truth.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Installed", systemImage: "checkmark.circle") { app.navigation.open(.productHub(.collection(.installed))) }
                        Button("Updates", systemImage: "arrow.triangle.2.circlepath") { app.navigation.open(.productHub(.collection(.updates))) }
                        Button("Module Settings", systemImage: "gearshape") { app.navigation.open(.settings(.modules(.root))) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Product Hub menu")
                }
                ModulaSearchField(text: $query, prompt: "Search the Product Hub")
                sessionState
                catalogueContent
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 8)
            .padding(.bottom, 26)
        }
        .refreshable { await app.catalogue.load() }
        .navigationTitle("Product Hub")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("product-hub")
        .modulaCanvas()
    }

    @ViewBuilder private var sessionState: some View {
        if app.auth.busy {
            ProgressView("Restoring secure session…")
        } else if let account = app.auth.account {
            Label("Signed in as \(account.primaryHandle)", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("account.ready")
        } else {
            Button("Sign in to Modula") { app.navigation.open(.auth(.login)) }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var catalogueContent: some View {
        if app.catalogue.loading && app.catalogue.products.isEmpty {
            ModulaLoadingState(title: "Loading Product Hub…")
        } else if let error = app.catalogue.error, app.catalogue.products.isEmpty {
            ModulaErrorState(message: error) { Task { await app.catalogue.load() } }
        } else {
            if query.isEmpty, let vault = app.catalogue.product("digital.modula.vault-notes") {
                ProductHero(product: vault) { open(vault) }
            }
            ProductShelf(
                title: query.isEmpty ? "From Modula" : "Results",
                subtitle: query.isEmpty ? "Products returned by Greenfield" : nil,
                products: visible,
                installedIDs: app.catalogue.installedIDs,
                action: open
            )
        }
    }

    private func open(_ product: CatalogueProduct) {
        app.navigation.open(.productHub(.module(product.id, .overview)))
    }
}

struct ModuleDetailView: View {
    let moduleID: String
    let section: ModuleDetailSection
    @Environment(AppEnvironment.self) private var app

    private var product: CatalogueProduct? { app.catalogue.product(moduleID) }
    private var bundled: Bool { app.runtime.manifests.contains { $0.id == moduleID } }

    var body: some View {
        Group {
            if let product {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .bottomLeading) {
                            ProductBackdrop(product: product)
                                .frame(height: 330)
                            ProductArtwork(product: product, size: 104)
                                .offset(y: 48)
                                .padding(.leading, 20)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 7) {
                                ModulaText(text: product.name, role: .hero)
                                PublisherLabel(name: product.publisherName)
                                Text(product.description)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            FlowLayout(spacing: 8) {
                                ProductBadge(title: product.productKind.capitalized)
                                ModuleHealthBadge(available: product.installable)
                                if bundled { ModulaBadge(title: "Bundled launcher", symbol: "iphone") }
                            }
                            InstallStateButton(product: product, installed: app.catalogue.installedIDs.contains(moduleID)) {
                                app.navigation.open(.module(moduleID, localPath: nil))
                            }
                            ProductMetadata(product: product)
                            sectionView(product)
                            related(product)
                        }
                        .padding(.horizontal, ModulaLayout.contentInset)
                        .padding(.top, 62)
                        .padding(.bottom, 30)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .modulaCanvas()
            } else if app.catalogue.loading {
                ModulaLoadingState(title: "Loading module…")
            } else {
                ModulaErrorState(message: "Greenfield has no catalogue record for this module.") {
                    Task { await app.catalogue.load() }
                }
            }
        }
        .navigationTitle(product?.name ?? "Module")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "https://modula.digital/module/\(moduleID)")!) {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    Button("Version History", systemImage: "clock.arrow.circlepath") {
                        app.navigation.open(.productHub(.module(moduleID, .versionHistory)))
                    }
                    Button("Compatibility", systemImage: "checkmark.seal") {
                        app.navigation.open(.productHub(.module(moduleID, .compatibility)))
                    }
                    Button("Support", systemImage: "questionmark.circle") {
                        app.navigation.open(.productHub(.module(moduleID, .support)))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .accessibilityIdentifier("module-detail.\(moduleID)")
    }

    @ViewBuilder private func sectionView(_ product: CatalogueProduct) -> some View {
        ModulaSection(title: sectionTitle) {
            switch section {
            case .overview:
                ModulaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ModulaText(text: "About this module", role: .headline)
                        Text(product.description)
                        Divider()
                        ModulaListRow(title: "Permissions & privacy", subtitle: "Review available declarations", symbol: "hand.raised") {
                            app.navigation.open(.productHub(.module(moduleID, .permissions)))
                        }
                    }
                }
            case .permissions:
                truthCard("Permissions", "Greenfield exposes no product-level permission declaration in the current catalogue response. No permissions are being inferred from the native launcher manifest.", "hand.raised")
            case .privacy:
                truthCard("Privacy", "A product privacy disclosure is not present in the current catalogue response.", "lock.shield")
            case .compatibility:
                truthCard("Compatibility", product.platforms.isEmpty ? "No platform compatibility is declared." : "Declared platforms: \(product.platforms.joined(separator: ", ")).", "checkmark.seal")
            case .whatsNew, .versionHistory:
                truthCard("Release information", product.latestVersion.map { "Latest catalogue version: \($0). Release notes are not available in this response." } ?? "No published release is available.", "clock.arrow.circlepath")
            case .screenshots:
                truthCard("Screenshots", "No approved screenshots are published in the current catalogue response.", "photo.on.rectangle")
            default:
                truthCard(sectionTitle, "This route is valid. Greenfield does not currently provide content for this section.", "info.circle")
            }
        }
    }

    private func truthCard(_ title: String, _ text: String, _ symbol: String) -> some View {
        ModulaCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private func related(_ product: CatalogueProduct) -> some View {
        let products = app.catalogue.products.filter {
            $0.id != product.id && ($0.moduleId.hasPrefix("digital.modula.vault") || $0.productKind == "module")
        }
        return ProductShelf(
            title: "Related modules",
            products: Array(products.prefix(3)),
            installedIDs: app.catalogue.installedIDs
        ) { related in
            app.navigation.open(.productHub(.module(related.id, .overview)))
        }
    }

    private var sectionTitle: String {
        section.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

/// A compact wrapping layout keeps truthful badges readable at large Dynamic Type.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if width > 0, width + spacing + size.width > maxWidth {
                height += rowHeight + spacing
                width = 0
                rowHeight = 0
            }
            width += (width == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
