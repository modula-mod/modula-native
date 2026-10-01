import SwiftUI
import Observation

@MainActor @Observable
final class ProductHubStore {
    private let client: GreenfieldClient
    private(set) var products: [CatalogueProduct] = []
    /// Account installations keyed by module id, including transitional states.
    private(set) var installations: [String: ModuleInstallation] = [:]
    /// Store listings (`/v1/registry/modules/:id`) fetched on demand for detail pages.
    private(set) var listings: [String: ModuleListing] = [:]
    private(set) var listingFailed: Set<String> = []
    /// Install / update / uninstall in flight from this device.
    private(set) var operations: [String: ModuleOperation] = [:]
    var lifecycleErrors: [String: String] = [:]
    /// Registry versions per module, relative to the account's installation.
    private(set) var versionLists: [String: ModuleVersionList] = [:]
    private(set) var versionsFailed: Set<String> = []
    private(set) var loading = false
    private(set) var loaded = false
    var error: String?
    /// Poll cadence while the server settles a lifecycle change; tests shorten it.
    var settlePollInterval: Duration = .milliseconds(900)
    var settleAttempts = 30

    init(client: GreenfieldClient) { self.client = client }

    /// Modules the account has installed (any non-removed state).
    var installedIDs: Set<String> { Set(installations.values.filter(\.isPresent).map(\.moduleId)) }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        do {
            products = try await client.catalogue()
            loaded = true
            installations = await Self.installations(client: client, previous: installations)
        } catch {
            self.error = "Product catalogue is unavailable. Pull to refresh."
        }
    }

    func product(_ id: String) -> CatalogueProduct? { products.first { $0.moduleId == id } }

    func loadListing(_ id: String, force: Bool = false) async {
        guard force || listings[id] == nil else { return }
        do {
            listings[id] = try await client.moduleListing(id)
            listingFailed.remove(id)
        } catch {
            listingFailed.insert(id)
        }
    }

    func refreshInstallations() async {
        installations = await Self.installations(client: client, previous: installations)
    }

    /// Installed modules belong to the signed-in account. Signed out (or the session was
    /// rejected) means nothing is installed; a transient failure keeps the last known set.
    /// Previously a failed fetch always kept the old set, so after signing out (or into
    /// another account) the hub still showed the previous account's modules as "Open".
    static func installations(client: GreenfieldClient, previous: [String: ModuleInstallation]) async -> [String: ModuleInstallation] {
        guard await client.hasSession() else { return [:] }
        do {
            let items = try await client.installedModules()
            return Dictionary(items.map { ($0.moduleId, $0) }, uniquingKeysWith: { first, _ in first })
        } catch APIError.unauthenticated, APIError.rejected(401, _), APIError.rejected(403, _), APIError.accountChanged {
            return [:]
        } catch {
            return previous
        }
    }

    static func installedIDs(client: GreenfieldClient, previous: Set<String>) async -> Set<String> {
        let prior = Dictionary(uniqueKeysWithValues: previous.map { ($0, ModuleInstallation(moduleId: $0, status: "enabled", version: nil)) })
        return Set(await installations(client: client, previous: prior).values.filter(\.isPresent).map(\.moduleId))
    }

    /// Installs (granting the permissions the listing declared and the user reviewed),
    /// then waits until the installation is enabled. Returns true when it can be opened.
    @discardableResult
    func install(_ id: String, permissions: [String]) async -> Bool {
        guard operations[id] == nil else { return false }
        operations[id] = .installing
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            _ = try await client.installModule(id, version: product(id)?.latestVersion, approvedPermissions: permissions, idempotencyKey: Self.key("install", id))
            return try await settle(id) { $0?.isRunnable == true }
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: "install")
            await refreshInstallations()
            return false
        }
    }

    @discardableResult
    func update(_ id: String) async -> Bool {
        guard operations[id] == nil, let latest = product(id)?.latestVersion else { return false }
        operations[id] = .updating
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            try await client.updateModule(id, version: latest, approvedPermissionIncrease: false, idempotencyKey: Self.key("update", id))
            return try await settle(id) { $0?.isRunnable == true && $0?.version.map { !ModuleVersion.isOlder($0, than: latest) } ?? true }
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: "update")
            await refreshInstallations()
            return false
        }
    }

    /// Loads the registry's versions for a module relative to this account's installation.
    func loadVersions(_ id: String) async {
        guard await client.hasSession() else {
            versionLists[id] = nil
            return
        }
        do {
            versionLists[id] = try await client.moduleVersions(id)
            versionsFailed.remove(id)
        } catch {
            versionsFailed.insert(id)
        }
    }

    /// Fetches the confirmation facts for moving to `version` and verifies the target's
    /// install descriptor against the public registry before anything is shown or sent.
    func prepareVersionSwitch(_ id: String, to version: String) async throws -> ModuleVersionPreview {
        let preview = try await client.previewModuleVersion(id, version: version)
        guard preview.toVersion == version else { throw InstallDescriptorVerificationError.wrongRelease }
        let facts = try await client.registryReleaseFacts(id, version: version)
        try InstallDescriptorVerifier.verify(preview.descriptor, moduleId: id, version: version, registry: facts, registryHost: await client.apiOriginHost)
        return preview
    }

    /// Switches the installation to the previewed version (upgrade or downgrade), consenting
    /// to exactly the new permissions the user saw, then waits for the server to settle.
    @discardableResult
    func switchVersion(_ id: String, preview: ModuleVersionPreview) async -> Bool {
        guard operations[id] == nil else { return false }
        operations[id] = .updating
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        let verb = preview.isDowngrade ? "downgrade" : "update"
        do {
            let issued = try await client.switchModuleVersion(
                id, version: preview.toVersion, approvedPermissions: preview.requiresConsent,
                acknowledgeDowngradeRisk: preview.dataSchemaOlder, idempotencyKey: Self.key("version", id))
            // The registry must issue the descriptor the user confirmed, byte for byte.
            guard let issued, issued.computedSha256 == issued.descriptorSha256,
                  issued.descriptorSha256 == preview.descriptor.descriptorSha256 else {
                throw InstallDescriptorVerificationError.digestMismatch
            }
            let target = preview.toVersion
            let settled = try await settle(id) { $0?.isRunnable == true && $0?.version == target }
            await loadVersions(id)
            return settled
        } catch let error as InstallDescriptorVerificationError {
            lifecycleErrors[id] = error.errorDescription
            await refreshInstallations()
            return false
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: verb)
            await refreshInstallations()
            return false
        }
    }

    @discardableResult
    func uninstall(_ id: String) async -> Bool {
        guard operations[id] == nil else { return false }
        operations[id] = .uninstalling
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            try await client.uninstallModule(id, idempotencyKey: Self.key("uninstall", id))
            return try await settle(id) { $0 == nil || $0?.isPresent == false }
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: "remove")
            await refreshInstallations()
            return false
        }
    }

    /// Polls installations until `done` holds. An installation that lands disabled is
    /// enabled once; failure states end the wait with an error.
    private func settle(_ id: String, until done: (ModuleInstallation?) -> Bool) async throws -> Bool {
        var enableRequested = false
        for attempt in 0..<settleAttempts {
            if attempt > 0 { try await Task.sleep(for: settlePollInterval) }
            let items = try await client.installedModules()
            installations = Dictionary(items.map { ($0.moduleId, $0) }, uniquingKeysWith: { first, _ in first })
            let current = installations[id]
            if done(current) { return true }
            if current?.status == "failed" || current?.status == "incompatible" || current?.status == "quarantined" {
                lifecycleErrors[id] = "The module couldn’t be set up (\(current?.status ?? "failed")). Try again."
                return false
            }
            if current?.needsEnable == true, !enableRequested {
                enableRequested = true
                try await client.enableModule(id, idempotencyKey: Self.key("enable", id))
            }
        }
        lifecycleErrors[id] = "This is taking longer than usual. Pull to refresh in a moment."
        return false
    }

    private static func key(_ verb: String, _ id: String) -> String { "ios-\(verb)-\(id)-\(UUID().uuidString)" }

    static func message(_ error: Error, verb: String) -> String {
        switch error {
        case APIError.unauthenticated, APIError.rejected(401, _): "Sign in to Modula to \(verb) modules."
        case APIError.rejected(_, "CAPABILITY_DISABLED"): "Installing modules is turned off on this server."
        case APIError.rejected(_, "CONFLICT"), APIError.rejected(409, _): "Another change to this module is in progress. Try again shortly."
        case let api as APIError: "Couldn’t \(verb) the module. \(api.userFacingMessage)"
        default: "Couldn’t \(verb) the module. Check your connection and try again."
        }
    }
}

@MainActor
extension AppEnvironment {
    /// Store artwork for a module from the registry listing; nil sources mean callers
    /// draw neutral placeholders. Bundled module code never supplies artwork.
    func moduleArtwork(_ id: String) -> ModuleArtwork {
        ModuleArtwork(listing: catalogue.listings[id])
    }
}

/// Renders a remote https image from the registry; `placeholder` covers missing art,
/// loading and failures so artwork never shows a broken state.
struct ModuleArtImage<Placeholder: View>: View {
    let source: ModuleArtSource?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        switch source {
        case .remote(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    placeholder()
                }
            }
        case nil:
            placeholder()
        }
    }
}

struct ProductArtwork: View {
    let product: CatalogueProduct
    var size = 66.0
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let art = app.moduleArtwork(product.moduleId)
        ModuleArtImage(source: art.icon) { placeholder }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: baseColor.opacity(0.28), radius: size * 0.16, y: size * 0.08)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(product.name) icon")
            .accessibilityIdentifier("artwork.\(product.moduleId)")
    }

    /// Neutral placeholder used when the registry has no icon: a plain tile with the
    /// product's initial. Never module-specific art.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [baseColor, baseColor.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .padding(size * 0.06)
            Text(product.name.prefix(1).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var baseColor: Color { Color(hex: "#343752") }
}

struct ProductBackdrop: View {
    let product: CatalogueProduct
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let art = app.moduleArtwork(product.moduleId)
        GeometryReader { proxy in
            ModuleArtImage(source: art.cover) { placeholder(proxy.size) }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }

    /// Neutral cover placeholder (no module-specific art) until the registry supplies one.
    private func placeholder(_ size: CGSize) -> some View {
        ZStack {
            Color(hex: "#171827")
            LinearGradient(colors: [app.appearance.accent.color.opacity(0.55), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
            Circle()
                .fill(app.appearance.accent.color.opacity(0.2))
                .frame(width: size.width * 0.8)
                .offset(x: size.width * 0.34, y: -size.height * 0.24)
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.07 + Double(index) * 0.025))
                    .frame(width: size.width * (0.46 - Double(index) * 0.055), height: 7)
                    .rotationEffect(.degrees(-22))
                    .offset(x: -size.width * 0.25, y: CGFloat(index * 27) - 18)
            }
        }
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
                ProductArtwork(product: product, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name).font(.headline).foregroundStyle(.primary)
                    Text(product.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    PublisherLabel(name: product.publisherName)
                }
                Spacer(minLength: 6)
                Text(installed ? "OPEN" : (product.installable ? "GET" : "SOON"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(product.installable || installed ? app.appearance.accent.color : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.primary.opacity(0.065)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(product.publisherName)")
        .accessibilityValue(installed ? "Installed" : (product.installable ? "Available" : "Coming soon"))
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
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ProductBackdrop(product: product)
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 14) {
                    ProductArtwork(product: product, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FEATURED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(product.name).font(.title2.bold())
                        Text(product.description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Featured module, \(product.name)")
        .accessibilityIdentifier("product-hub.featured")
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
                Text("Modules that extend Modula, installed to your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                sessionState
                catalogueContent
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 26)
            .modulaPullContentEffects()
        }
        .modulaSoftScrollEdge()
        .modulaShellPullActions { await app.catalogue.load() }
        .navigationTitle("Product Hub")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search Product Hub")
        .modulaMinimizedSearchToolbar()
        .modulaSidebarTrigger()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Library") {
                        Button("Installed", systemImage: "checkmark.circle") {
                            app.navigation.open(.productHub(.collection(.installed)))
                        }
                        Button("Updates", systemImage: "arrow.triangle.2.circlepath") {
                            app.navigation.open(.productHub(.collection(.updates)))
                        }
                    }
                    Section("Manage") {
                        Button("Module Settings", systemImage: "gearshape") {
                            app.navigation.open(.settings(.modules(.root)))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Product Hub menu")
            }
        }
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
                subtitle: query.isEmpty ? "Available modules" : nil,
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
                .modulaSoftScrollEdge()
                .modulaCanvas()
            } else if app.catalogue.loading {
                ModulaLoadingState(title: "Loading module…")
            } else {
                ModulaErrorState(message: "This module couldn’t be found.") {
                    Task { await app.catalogue.load() }
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(product?.name ?? "Module")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: ModulaShareLink.module(moduleID)) {
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
                truthCard("Permissions", "This module hasn’t listed any permissions.", "hand.raised")
            case .privacy:
                truthCard("Privacy", "The publisher hasn’t provided privacy details yet.", "lock.shield")
            case .compatibility:
                truthCard("Compatibility", product.platforms.isEmpty ? "No platform compatibility is declared." : "Declared platforms: \(product.platforms.joined(separator: ", ")).", "checkmark.seal")
            case .whatsNew, .versionHistory:
                truthCard("Release information", product.latestVersion.map { "Latest version: \($0). No release notes yet." } ?? "No published release is available.", "clock.arrow.circlepath")
            case .screenshots:
                truthCard("Screenshots", "This module doesn’t have screenshots yet.", "photo.on.rectangle")
            default:
                truthCard(sectionTitle, "Nothing here yet.", "info.circle")
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
