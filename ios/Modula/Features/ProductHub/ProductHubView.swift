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
        loading = true; defer { loading = false }; error = nil
        do {
            products = try await client.catalogue(); loaded = true
            if let installed = try? await client.installedModuleIDs() { installedIDs = installed }
        } catch { self.error = "Product catalogue is unavailable. Pull to refresh." }
    }
    func product(_ id: String) -> CatalogueProduct? { products.first { $0.moduleId == id } }
}

struct ProductArtwork: View {
    let product: CatalogueProduct
    var size = 66.0
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: colors[0].opacity(0.3), radius: 12, y: 6)
            .accessibilityLabel("\(product.name) artwork")
    }
    private var colors: [Color] { product.moduleId.contains("vault") ? [app.appearance.accent.color, .cyan.opacity(0.8), .indigo] : [.indigo, .purple] }
    private var symbol: String { product.moduleId.contains("vault") ? "note.text" : product.productKind == "plugin" ? "puzzlepiece.extension" : "shippingbox" }
}
struct ProductBadge: View { var title: String; var body: some View { ModulaBadge(title: title, symbol: "checkmark.seal") } }
struct PublisherLabel: View { var name: String; var body: some View { Label(name, systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.secondary) } }
struct ModuleHealthBadge: View { var available: Bool; var body: some View { ModulaBadge(title: available ? "Available" : "Coming Soon", symbol: available ? "checkmark.circle" : "clock") } }
struct ProductMetadata: View { let product: CatalogueProduct; var body: some View { ModulaMetadataRail(values: [(product.latestVersion ?? "—", "Version"), (product.platforms.contains("ios") ? "iOS" : "—", "Platform"), (product.status.capitalized, "Status")]) } }
struct InstallStateButton: View {
    let product: CatalogueProduct; let installed: Bool; var open: () -> Void
    var body: some View {
        if installed { ModulaButton(title: "Open", symbol: "arrow.up.forward.app", action: open).accessibilityIdentifier("module.open") }
        else if product.installable { Button("Available to install", systemImage: "arrow.down.circle") {}.buttonStyle(.bordered).disabled(true).frame(maxWidth: .infinity, minHeight: 44) }
        else { Button("Coming Soon", systemImage: "clock") {}.buttonStyle(.bordered).disabled(true).frame(maxWidth: .infinity, minHeight: 44) }
    }
}
struct ProductCard: View {
    let product: CatalogueProduct; let installed: Bool; var action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 14) { ProductArtwork(product: product); VStack(alignment: .leading, spacing: 4) { Text(product.name).font(.headline); PublisherLabel(name: product.publisherName); Text(installed ? "Installed" : (product.installability?.reason ?? product.status.capitalized)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous)) }.buttonStyle(.plain).accessibilityIdentifier("product.\(product.moduleId)") }
}
struct ProductShelf: View { var title: String; var products: [CatalogueProduct]; var installedIDs: Set<String>; var action: (CatalogueProduct) -> Void; var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.title2.bold()); ForEach(products) { product in ProductCard(product: product, installed: installedIDs.contains(product.id), action: { action(product) }) } } } }
struct ProductHero: View { let product: CatalogueProduct; var action: () -> Void; var body: some View { Button(action: action) { ModulaHero(title: product.name, subtitle: product.description) { LinearGradient(colors: [.cyan.opacity(0.72), .indigo.opacity(0.68), .black.opacity(0.76)], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(alignment: .topTrailing) { ProductArtwork(product: product, size: 94).padding(26) } } }.buttonStyle(.plain) } }

struct ProductHubView: View {
    let route: ProductHubRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""
    private var visible: [CatalogueProduct] { query.isEmpty ? app.catalogue.products : app.catalogue.products.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ModulaTopBar(title: "Modules") { app.navigation.open(.settings(.modules(.root))) }
                ModulaSearchField(text: $query, prompt: "Search the Product Hub")
                if app.auth.busy { ProgressView("Restoring secure session…") }
                else if let account = app.auth.account { Label("Signed in as \(account.primaryHandle)", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("account.ready") }
                else { Button("Sign in to Modula") { app.navigation.open(.auth(.login)) } }
                if app.catalogue.loading && app.catalogue.products.isEmpty { ModulaLoadingState(title: "Loading Product Hub…") }
                else if let error = app.catalogue.error, app.catalogue.products.isEmpty { ModulaErrorState(message: error) { Task { await app.catalogue.load() } } }
                else {
                    if let vault = app.catalogue.product("digital.modula.vault-notes") { ProductHero(product: vault) { open(vault) } }
                    ProductShelf(title: query.isEmpty ? "From Modula" : "Results", products: visible, installedIDs: app.catalogue.installedIDs, action: open)
                }
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }.refreshable { await app.catalogue.load() }.navigationTitle("Product Hub").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("product-hub")
    }
    private func open(_ product: CatalogueProduct) { app.navigation.open(.productHub(.module(product.id, .overview))) }
}

struct ModuleDetailView: View {
    let moduleID: String; let section: ModuleDetailSection
    @Environment(AppEnvironment.self) private var app
    private var product: CatalogueProduct? { app.catalogue.product(moduleID) }
    private var bundled: Bool { app.runtime.manifests.contains { $0.id == moduleID } }
    var body: some View {
        Group {
            if let product {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [app.appearance.accent.color.opacity(0.74), .indigo.opacity(0.58), .black.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 300).overlay(Image(systemName: "note.text").font(.system(size: 120, weight: .ultraLight)).foregroundStyle(.white.opacity(0.24)))
                            ProductArtwork(product: product, size: 92).offset(y: 38).padding(.leading, 20)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            ModulaText(text: product.name, role: .hero)
                            PublisherLabel(name: product.publisherName)
                            Text(product.description).foregroundStyle(.secondary)
                            HStack { ProductBadge(title: product.productKind.capitalized); ModuleHealthBadge(available: product.installable) }
                            if bundled { ModulaBadge(title: "Bundled launcher", symbol: "iphone") }
                            InstallStateButton(product: product, installed: app.catalogue.installedIDs.contains(moduleID)) { app.navigation.open(.module(moduleID, localPath: nil)) }
                            ProductMetadata(product: product)
                            sectionView(product)
                            related(product)
                        }.padding(.horizontal, 18).padding(.top, 42)
                    }
                }.ignoresSafeArea(edges: .top)
            } else if app.catalogue.loading { ModulaLoadingState(title: "Loading module…") }
            else { ModulaErrorState(message: "Greenfield has no catalogue record for this module.") { Task { await app.catalogue.load() } } }
        }
        .navigationTitle(product?.name ?? "Module").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { ShareLink(item: URL(string: "https://modula.digital/module/\(moduleID)")!) { Image(systemName: "square.and.arrow.up") }; Menu { Button("Version History") { app.navigation.open(.productHub(.module(moduleID, .versionHistory))) }; Button("Support") { app.navigation.open(.productHub(.module(moduleID, .support))) } } label: { Image(systemName: "ellipsis") } } }
        .accessibilityIdentifier("module-detail.\(moduleID)")
    }
    @ViewBuilder private func sectionView(_ product: CatalogueProduct) -> some View {
        ModulaSection(title: sectionTitle) {
            switch section {
            case .overview:
                ModulaCard { VStack(alignment: .leading, spacing: 8) { ModulaText(text: "About this module", role: .headline); Text(product.description); ModulaListRow(title: "Permissions & privacy", subtitle: "Review declared access", symbol: "hand.raised") { app.navigation.open(.productHub(.module(moduleID, .permissions))) } } }
            case .permissions: truthCard("Permissions", "Greenfield exposes no product-level permission declaration in the current catalogue response. No permissions are being inferred from the native launcher manifest.", "hand.raised")
            case .privacy: truthCard("Privacy", "A product privacy disclosure is not present in the current catalogue response.", "lock.shield")
            case .compatibility: truthCard("Compatibility", product.platforms.isEmpty ? "No platform compatibility is declared." : "Declared platforms: \(product.platforms.joined(separator: ", ")).", "checkmark.seal")
            case .whatsNew, .versionHistory: truthCard("Release information", product.latestVersion.map { "Latest catalogue version: \($0). Release notes are not available in this response." } ?? "No published release is available.", "clock.arrow.circlepath")
            case .screenshots: truthCard("Screenshots", "No approved screenshots are published in the current catalogue response.", "photo.on.rectangle")
            default: truthCard(sectionTitle, "This route is valid. Greenfield does not currently provide content for this section.", "info.circle")
            }
        }
    }
    private func truthCard(_ title: String, _ text: String, _ symbol: String) -> some View { ModulaCard { VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: symbol).font(.headline); Text(text).foregroundStyle(.secondary) } } }
    private func related(_ product: CatalogueProduct) -> some View { ModulaSection(title: "Related modules") { ForEach(app.catalogue.products.filter { $0.id != product.id && ($0.moduleId.hasPrefix("digital.modula.vault") || $0.productKind == "module") }.prefix(3)) { related in ProductCard(product: related, installed: app.catalogue.installedIDs.contains(related.id)) { app.navigation.open(.productHub(.module(related.id, .overview))) } } } }
    private var sectionTitle: String { section.rawValue.replacingOccurrences(of: "-", with: " ").capitalized }
}
