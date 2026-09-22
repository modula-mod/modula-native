import SwiftUI

struct ModuleDetailV2View: View {
    let moduleID: String
    let section: ModuleDetailSection
    @Environment(AppEnvironment.self) private var app
    @State private var headerProgress: CGFloat = 0
    @State private var mediaItem: ModulaMediaViewerItem?

    private var product: CatalogueProduct? { app.catalogue.product(moduleID) }
    private var bundled: Bool { app.runtime.manifests.contains { $0.id == moduleID } }
    private var installed: Bool { app.catalogue.installedIDs.contains(moduleID) || bundled }
    private var manifest: ModuleManifest? { app.runtime.manifests.first { $0.id == moduleID } }

    var body: some View {
        Group {
            if let product {
                content(product)
            } else if app.catalogue.loading {
                ModulaLoadingState(title: "Loading module…")
            } else {
                ModulaErrorState(message: "Greenfield has no catalogue record for this module.") {
                    Task { await app.catalogue.load() }
                }
            }
        }
        .modulaImmersiveSystemNavigation()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "https://modula.digital/product-hub/module/\(moduleID)")!) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let product {
                        Button("Share", systemImage: "square.and.arrow.up") {
                            app.navigation.presented = .universalShare(.module(id: moduleID, name: product.name, publisher: product.publisherName))
                        }
                        Button("Version History", systemImage: "clock.arrow.circlepath") {
                            app.navigation.open(.productHub(.module(moduleID, .versionHistory)))
                        }
                        if installed {
                            Button("Configure", systemImage: "slider.horizontal.3") {
                                app.navigation.open(.settings(.modules(.module(moduleID, .general))))
                            }
                        }
                        Button("Publisher", systemImage: "person.crop.square") {
                            app.navigation.open(.productHub(.publisher(product.publisherId)))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .fullScreenCover(item: $mediaItem) { item in
            ModulaMediaViewer(
                title: item.title,
                url: item.url,
                accessibilityDescription: item.accessibilityDescription,
                onDismiss: { mediaItem = nil }
            )
        }
        .accessibilityIdentifier("module-detail.\(moduleID)")
    }

    private func content(_ product: CatalogueProduct) -> some View {
        let presentation = ModuleDetailPresentation(
            product: product,
            installed: app.catalogue.installedIDs.contains(moduleID),
            bundled: bundled,
            coverURL: product.coverImageURL
        )
        return ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(product, presentation: presentation)
                    VStack(alignment: .leading, spacing: 20) {
                        identity(product, presentation: presentation)
                        primaryAction(presentation)
                        sectionNavigation
                        sectionBody(product, presentation: presentation)
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 56)
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .modulaSoftScrollEdge()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                headerProgress = ModulaScrollProgress.progress(offsetY: max(0, offset), collapseDistance: 120)
            }

        }
        .modulaCanvas()
        .modulaSoftScrollEdge()
        .navigationTitle(product.name)
        .accessibilityElement(children: .contain)
    }

    private func hero(_ product: CatalogueProduct, presentation _: ModuleDetailPresentation) -> some View {
        FullBleedHero(height: 340, scrollProgress: headerProgress) {
            ProductBackdrop(product: product)
        } overlay: {
            EmptyView()
        }
        .overlay(alignment: .bottomLeading) {
            ArtworkPocket(size: 92) {
                ProductArtwork(product: product, size: 92)
            }
            .accessibilityLabel("\(product.name) artwork")
        }
        .accessibilitySortPriority(100)
    }

    private func identity(_ product: CatalogueProduct, presentation: ModuleDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name)
                .font(.largeTitle.bold())
            Button {
                app.navigation.open(.productHub(.publisher(product.publisherId)))
            } label: {
                PublisherLabel(name: product.publisherName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Publisher \(product.publisherName)")
            Text(product.description)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(presentation.tags, id: \.self) { tag in
                    ProductBadge(title: tag)
                }
                if bundled { ModulaBadge(title: "Bundled", symbol: "iphone") }
            }
            ProductMetadata(product: product)
        }
        .accessibilitySortPriority(90)
    }

    private func primaryAction(_ presentation: ModuleDetailPresentation) -> some View {
        let action = presentation.primaryAction
        let brand = moduleBrandColor
        return Button {
            perform(action)
        } label: {
            Text(action.title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(brand)
        .disabled(!action.isEnabled)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("module.primary")
        .accessibilitySortPriority(80)
    }

    private var moduleBrandColor: Color {
        switch app.appearance.moduleBranding {
        case .preferUserAccent:
            return app.appearance.accent.color
        case .moduleIdentity, .blend:
            return app.appearance.accent.color
        }
    }

    private var sectionNavigation: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ModuleDetailSection.allCases, id: \.self) { item in
                    Button {
                        app.navigation.replaceTop(with: .productHub(.module(moduleID, item)))
                    } label: {
                        Text(sectionTitle(item))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(section == item ? app.appearance.accent.color.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
        }
        .accessibilitySortPriority(70)
    }

    @ViewBuilder
    private func sectionBody(_ product: CatalogueProduct, presentation: ModuleDetailPresentation) -> some View {
        switch section {
        case .overview:
            overview(product)
        case .whatsNew:
            truthful("What’s New", product.latestVersion.map { "Latest catalogue version: \($0). No release notes were provided." } ?? "No release notes provided.", "sparkles")
        case .screenshots:
            EmptyView()
        case .permissions:
            permissions
        case .privacy:
            truthful("Privacy", "A product privacy disclosure is not present in the current catalogue response. Native will not invent a privacy grade.", "lock.shield")
        case .compatibility:
            truthful("Compatibility", compatibilityText(product), "checkmark.seal")
        case .information:
            information(product)
        case .versionHistory:
            truthful("Version History", product.latestVersion.map { "Current version \($0). Additional catalogue releases were not included in this response." } ?? "No published release is available.", "clock.arrow.circlepath")
        case .publisher:
            Button("Open publisher") {
                app.navigation.open(.productHub(.publisher(product.publisherId)))
            }
        case .support:
            truthful("Support", "Support contact is available on the publisher page when Greenfield provides it.", "questionmark.circle")
        case .configure:
            if installed {
                Button("Module settings") {
                    app.navigation.open(.settings(.modules(.module(moduleID, .general))))
                }
            } else {
                truthful("Configure", "Configure appears after the module is installed.", "slider.horizontal.3")
            }
        }
    }

    private func overview(_ product: CatalogueProduct) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ModulaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About").font(.headline)
                    Text(product.description)
                }
            }
            permissionsPreview
        }
        .accessibilitySortPriority(60)
    }

    private var permissions: some View {
        let records = ModuleHostPermissions.records(from: manifest)
        return VStack(alignment: .leading, spacing: 12) {
            if records.isEmpty {
                Text("Greenfield exposes no product-level permission declaration in the current catalogue response. Native is not inferring permissions from the module name.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    ModulaCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.capability).font(.headline)
                            Text(record.purpose).foregroundStyle(.secondary)
                            Text(record.state).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilitySortPriority(50)
    }

    private var permissionsPreview: some View {
        let records = ModuleHostPermissions.records(from: manifest)
        return Group {
            if !records.isEmpty {
                ModulaSection(title: "Permissions") {
                    ForEach(records.prefix(3)) { record in
                        ModulaListRow(title: record.capability, subtitle: record.purpose, symbol: "hand.raised") {
                            app.navigation.open(.productHub(.module(moduleID, .permissions)))
                        }
                    }
                }
            }
        }
    }

    private func information(_ product: CatalogueProduct) -> some View {
        ModulaCard {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Module ID", value: product.moduleId)
                LabeledContent("Publisher", value: product.publisherName)
                LabeledContent("Status", value: product.status.capitalized)
                LabeledContent("Kind", value: product.productKind)
            }
        }
    }

    private func truthful(_ title: String, _ text: String, _ symbol: String) -> some View {
        ModulaCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private func compatibilityText(_ product: CatalogueProduct) -> String {
        if product.platforms.isEmpty {
            return "No platform compatibility is declared."
        }
        let platforms = product.platforms.map { $0.lowercased() == "ios" ? "iOS" : $0.capitalized }.joined(separator: ", ")
        let host = manifest.map { "Requires Modula \($0.minHostVersion) and HostBridge \($0.minBridgeVersion)." } ?? "Required Modula version is not declared in the catalogue response."
        return "Declared platforms: \(platforms). \(host)"
    }

    private func perform(_ action: ModulePrimaryAction) {
        switch action {
        case .open:
            HapticEngine.shared.play(.confirmation)
            app.navigation.open(.module(moduleID, localPath: nil))
        case .install, .update:
            app.navigation.banner = ModulaBanner(
                message: "Module install isn’t available until Greenfield install is verified.",
                symbol: "exclamationmark.triangle"
            )
            HapticEngine.shared.play(.warning)
        default:
            break
        }
    }

    private func sectionTitle(_ section: ModuleDetailSection) -> String {
        section.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

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
