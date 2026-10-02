import SwiftUI

/// App Store–style module page: hero cover, icon, live Install/Open/Update state,
/// stats strip, screenshots, description, What's New, ratings, privacy, permissions and
/// information. Listing data (and artwork) comes from the registry only; neutral
/// placeholders cover anything missing. Bundled module code never supplies artwork.
struct ModuleDetailV2View: View {
    let moduleID: String
    let section: ModuleDetailSection
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var headerProgress: CGFloat = 0
    @State private var confirmInstall = false
    @State private var confirmUninstall = false
    @State private var expandedDescription = false
    @State private var zoomedShot: ModuleScreenshot?
    @State private var showAllPermissions = false
    @State private var versionTarget: ModuleVersionOption?
    @State private var versionPhase: ModuleVersionSwitchSheet.Phase = .loading

    private var product: CatalogueProduct? { app.catalogue.product(moduleID) }
    private var manifest: ModuleManifest? { app.runtime.manifests.first { $0.id == moduleID } }
    private var bundled: Bool { manifest != nil }
    private var listing: ModuleListing? { app.catalogue.listings[moduleID] }
    private var installed: Bool { app.catalogue.installedIDs.contains(moduleID) }
    private var installedVersion: String? { installed ? app.catalogue.installations[moduleID]?.version : nil }

    var body: some View {
        Group {
            if let product {
                content(product)
            } else if app.catalogue.loading || !app.catalogue.loaded {
                ModulaLoadingState(title: "Loading module…")
            } else {
                ModulaErrorState(message: "This module couldn’t be found.") {
                    Task { await app.catalogue.load() }
                }
            }
        }
        .task(id: moduleID) {
            if !app.catalogue.loaded { await app.catalogue.load() }
            await app.catalogue.loadListing(moduleID)
        }
        .task(id: installedVersion) {
            if installedVersion != nil { await app.catalogue.loadVersions(moduleID) }
        }
        .modulaImmersiveSystemNavigation()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ModulaShareLink.module(moduleID)) {
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
                        if installed {
                            Button("Configure", systemImage: "slider.horizontal.3") {
                                app.navigation.open(.settings(.modules(.module(moduleID, .general))))
                            }
                        }
                        Button("Publisher", systemImage: "person.crop.square") {
                            app.navigation.open(.productHub(.publisher(product.publisherId)))
                        }
                        if presentation(product).canUninstall {
                            Button("Uninstall", systemImage: "trash", role: .destructive) { confirmUninstall = true }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog(installTitle, isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Install") { Task { await runInstall() } }
                .accessibilityIdentifier("module.install.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installMessage)
        }
        .confirmationDialog("Uninstall \(product?.name ?? "module")?", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { Task { await runUninstall() } }
                .accessibilityIdentifier("module.uninstall.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data is kept on your account, so reinstalling brings it back.")
        }
        .sheet(item: $versionTarget) { option in
            ModuleVersionSwitchSheet(
                moduleName: product?.name ?? "Module",
                option: option,
                phase: versionPhase,
                onConfirm: { preview in
                    versionTarget = nil
                    Task { await runVersionSwitch(preview) }
                },
                onCancel: { versionTarget = nil }
            )
            .task(id: option.version) { await prepareVersionSwitch(option) }
        }
        .sheet(item: $zoomedShot) { shot in
            ModuleArtImage(source: shot.source, contentMode: .fit) { Color.clear }
                .padding()
                .presentationDragIndicator(.visible)
                .accessibilityLabel(shot.alt)
        }
        .accessibilityIdentifier("module-detail.\(moduleID)")
    }

    private func presentation(_ product: CatalogueProduct) -> ModuleDetailPresentation {
        ModuleDetailPresentation(
            product: product,
            installation: app.catalogue.installations[moduleID],
            operation: app.catalogue.operations[moduleID],
            bundled: bundled,
            bundledVersion: manifest?.version,
            signedIn: app.auth.account != nil
        )
    }

    // MARK: Layout

    private func content(_ product: CatalogueProduct) -> some View {
        let state = presentation(product)
        let art = app.moduleArtwork(moduleID)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(product)
                    VStack(alignment: .leading, spacing: 22) {
                        header(product, state: state, art: art)
                        if let message = app.catalogue.lifecycleErrors[moduleID] {
                            lifecycleNotice(message)
                        }
                        stats(product)
                        Divider()
                        whatsNew(product).id(ModuleDetailSection.whatsNew)
                        if installed {
                            versions(state).id(ModuleDetailSection.versionHistory)
                        }
                        screenshots(art).id(ModuleDetailSection.screenshots)
                        about(product)
                        ratings
                        privacy.id(ModuleDetailSection.privacy)
                        permissions.id(ModuleDetailSection.permissions)
                        information(product, state: state).id(ModuleDetailSection.information)
                        if state.canUninstall { uninstallButton }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.top, 18)
                    .padding(.bottom, 44)
                }
            }
            .ignoresSafeArea(edges: .top)
            .modulaSoftScrollEdge()
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                headerProgress = ModulaScrollProgress.progress(offsetY: max(0, offset), collapseDistance: 140)
            }
            .refreshable {
                await app.catalogue.load()
                await app.catalogue.loadListing(moduleID, force: true)
            }
            .task(id: section) {
                guard let anchor = anchor(for: section) else { return }
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo(anchor, anchor: .top) }
            }
        }
        .modulaCanvas()
        .navigationTitle(product.name)
        .accessibilityElement(children: .contain)
    }

    private func anchor(for section: ModuleDetailSection) -> ModuleDetailSection? {
        switch section {
        case .overview: nil
        case .whatsNew: .whatsNew
        case .versionHistory: installed ? .versionHistory : .whatsNew
        case .screenshots: .screenshots
        case .permissions: .permissions
        case .privacy: .privacy
        case .information, .compatibility, .publisher, .support, .configure: .information
        }
    }

    private func hero(_ product: CatalogueProduct) -> some View {
        FullBleedHero(height: 300, scrollProgress: headerProgress) {
            ProductBackdrop(product: product)
        } overlay: {
            EmptyView()
        }
        .accessibilityHidden(true)
    }

    private func header(_ product: CatalogueProduct, state: ModuleDetailPresentation, art: ModuleArtwork) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ProductArtwork(product: product, size: 108)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(listing?.category ?? product.productKind.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button {
                    app.navigation.open(.productHub(.publisher(product.publisherId)))
                } label: {
                    PublisherLabel(name: listing?.publisherName ?? product.publisherName)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Developer \(listing?.publisherName ?? product.publisherName)")
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    primaryButton(state)
                    if state.primaryAction == .update {
                        Button("Open") { open() }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("module.open")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilitySortPriority(90)
    }

    private func primaryButton(_ state: ModuleDetailPresentation) -> some View {
        let action = state.primaryAction
        return Button {
            perform(action)
        } label: {
            HStack(spacing: 8) {
                if action.isBusy { ProgressView().controlSize(.small).tint(.white) }
                Text(action == .open || action == .install || action == .update ? action.title.uppercased() : action.title)
                    .font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 20)
            .frame(minWidth: 84, minHeight: 34)
            .foregroundStyle(action.isEnabled || action.isBusy ? Color.white : Color.secondary)
            .background(action.isEnabled || action.isBusy ? brand : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .animation(.snappy, value: action)
        .accessibilityLabel(action.title)
        .accessibilityHint(action == .install ? "Installs to your Modula account" : "")
        .accessibilityIdentifier("module.primary")
    }

    private var brand: Color {
        app.appearance.accent.color
    }

    private func lifecycleNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline)
            Spacer(minLength: 0)
            Button {
                app.catalogue.lifecycleErrors[moduleID] = nil
            } label: { Image(systemName: "xmark").font(.caption.bold()) }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("module.lifecycle-error")
    }

    // MARK: Stats

    private struct Stat: Identifiable { let id: String; let caption: String; let value: String; let detail: String; var symbol: String? = nil }

    private func statItems(_ product: CatalogueProduct) -> [Stat] {
        var items: [Stat] = []
        if let listing, listing.ratingCount > 0, let average = listing.ratingAverage {
            items.append(Stat(id: "rating", caption: "\(listing.ratingCount) RATINGS", value: String(format: "%.1f", average), detail: stars(average)))
        } else {
            items.append(Stat(id: "rating", caption: "RATINGS", value: "—", detail: "Not enough ratings"))
        }
        if let age = listing?.ageRating { items.append(Stat(id: "age", caption: "AGE", value: age, detail: "Years Old")) }
        if let rank = listing?.chartRank, let category = listing?.chartCategory {
            items.append(Stat(id: "chart", caption: "CHART", value: "#\(rank)", detail: category))
        } else if let category = listing?.category {
            items.append(Stat(id: "category", caption: "CATEGORY", value: "", detail: category, symbol: "square.grid.2x2"))
        }
        items.append(Stat(id: "developer", caption: "DEVELOPER", value: "", detail: listing?.publisherName ?? product.publisherName, symbol: "person.crop.square"))
        items.append(Stat(id: "size", caption: "SIZE", value: listing?.sizeBytes.map(Self.size) ?? "—", detail: listing?.sizeBytes == nil ? "Not published" : "MB"))
        if let count = listing?.installCount { items.append(Stat(id: "installs", caption: "INSTALLS", value: "\(count)", detail: count == 1 ? "Account" : "Accounts")) }
        items.append(Stat(id: "version", caption: "VERSION", value: product.latestVersion ?? manifest?.version ?? "—", detail: "Latest"))
        return items
    }

    private func stats(_ product: CatalogueProduct) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(statItems(product).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().frame(height: 40) }
                    VStack(spacing: 5) {
                        Text(item.caption).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        if let symbol = item.symbol {
                            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        } else {
                            Text(item.value).font(.title3.weight(.bold)).foregroundStyle(.secondary)
                        }
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(minWidth: 96)
                    .padding(.horizontal, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.caption.capitalized): \(item.value) \(item.detail)")
                }
            }
        }
        .accessibilityIdentifier("module.stats")
    }

    private func stars(_ value: Double) -> String {
        let full = Int(value.rounded())
        return String(repeating: "★", count: max(0, min(5, full))) + String(repeating: "☆", count: max(0, 5 - full))
    }

    private static func size(_ bytes: Int) -> String {
        String(format: bytes >= 10_000_000 ? "%.0f" : "%.1f", Double(bytes) / 1_000_000)
    }

    // MARK: Sections

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
    }

    private func whatsNew(_ product: CatalogueProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("What’s New")
            HStack {
                Text("Version \(product.latestVersion ?? manifest?.version ?? "—")")
                Spacer()
                if let date = listing?.publishedAt { Text(date, format: .dateTime.day().month(.abbreviated).year()) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            let notes = listing?.releaseNotes ?? []
            if notes.isEmpty {
                Text(listing == nil && !app.catalogue.listingFailed.contains(moduleID) ? "Loading release notes…" : "No release notes were published for this version.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(note)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func screenshots(_ art: ModuleArtwork) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Preview")
            if art.screenshots.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary)
                    Text("No screenshots have been published yet.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("module.screenshots")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(art.screenshots) { shot in
                            Button { zoomedShot = shot } label: {
                                ModuleArtImage(source: shot.source) {
                                    Rectangle().fill(Color.primary.opacity(0.06))
                                }
                                .frame(width: 220, height: 220 / max(0.3, min(shot.aspect, 2)))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(shot.alt)
                            .accessibilityHint("Shows the screenshot larger")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .accessibilityIdentifier("module.screenshots")
            }
        }
    }

    private func about(_ product: CatalogueProduct) -> some View {
        let text = listing?.description ?? product.description
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("About")
            Text(text)
                .lineLimit(expandedDescription ? nil : 3)
            if text.count > 140 {
                Button(expandedDescription ? "less" : "more") { withAnimation { expandedDescription.toggle() } }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var ratings: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Ratings & Reviews")
            if let listing, listing.ratingCount > 0, let average = listing.ratingAverage {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(String(format: "%.1f", average)).font(.system(size: 52, weight: .bold, design: .rounded))
                    VStack(alignment: .leading) {
                        Text(stars(average)).foregroundStyle(.orange)
                        Text("\(listing.ratingCount) ratings").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rated \(String(format: "%.1f", average)) out of 5 from \(listing.ratingCount) ratings")
            } else {
                Text("This module hasn’t received enough ratings yet.").foregroundStyle(.secondary)
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("App Privacy")
            ModulaCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(listing?.privacy ?? "Not declared", systemImage: "hand.raised.fill").font(.headline)
                    Text(listing?.privacy == nil
                         ? "The developer hasn’t published a privacy declaration for this module."
                         : "Module data is stored with your Modula account and is not shared with other modules unless you allow it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let listing {
                        Divider()
                        feature("Syncs across devices", listing.syncSupport)
                        feature("Works offline", listing.offlineSupport)
                        feature("In-module purchases", listing.inAppPurchases)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func feature(_ title: String, _ value: Bool?) -> some View {
        if let value {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: value ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(value ? Color.green : Color.secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value ? "Yes" : "No")")
        }
    }

    private var permissions: some View {
        let server = listing?.permissions ?? []
        let host = ModuleHostPermissions.records(from: manifest)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Permissions")
                Spacer()
                if let listing, listing.highRiskCount > 0 {
                    Text("\(listing.highRiskCount) high risk").font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            if server.isEmpty && host.isEmpty {
                Text("This module declares no permissions.").foregroundStyle(.secondary)
            }
            if !server.isEmpty {
                ModulaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(showAllPermissions ? server : Array(server.prefix(4))) { permission in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: riskSymbol(permission.risk)).foregroundStyle(riskColor(permission.risk)).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(permission.reason.isEmpty ? permission.permission : permission.reason).font(.subheadline)
                                    Text("\(permission.permission) · \(permission.risk.capitalized) risk").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if server.count > 4 {
                            Button(showAllPermissions ? "Show fewer" : "Show all \(server.count) permissions") {
                                withAnimation { showAllPermissions.toggle() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("module.permissions.toggle")
                        }
                    }
                }
            }
            if !host.isEmpty {
                DisclosureGroup("On this device (\(host.count) host actions)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(host) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.capability).font(.subheadline.monospaced())
                                Text(record.purpose).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
    }

    private func riskSymbol(_ risk: String) -> String {
        switch risk { case "high", "restricted": "exclamationmark.shield.fill"; case "medium": "shield.lefthalf.filled"; default: "checkmark.shield" }
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk { case "high", "restricted": .red; case "medium": .orange; default: .green }
    }

    private func information(_ product: CatalogueProduct, state: ModuleDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Information")
            ModulaCard {
                VStack(alignment: .leading, spacing: 10) {
                    info("Provider", listing?.publisherName ?? product.publisherName)
                    info("Size", listing?.sizeBytes.map { "\(Self.size($0)) MB" } ?? "Not published")
                    if let category = listing?.category { info("Category", category) }
                    info("Compatibility", compatibility(product))
                    if let age = listing?.ageRating { info("Age Rating", age) }
                    info("Version", product.latestVersion ?? "—")
                    if let installed = state.installation?.version, state.installed { info("Installed", installed) }
                    if let trust = listing?.trust { info("Trust", trust == "firstParty" ? "First party" : trust.capitalized) }
                    info("Module ID", product.moduleId)
                    if let website = listing?.publisherWebsite {
                        Link(destination: website) { Label("Developer Website", systemImage: "safari") }
                    }
                    if installed {
                        Button { app.navigation.open(.settings(.modules(.module(moduleID, .general)))) } label: {
                            Label("Module Settings", systemImage: "slider.horizontal.3")
                        }
                    }
                }
            }
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func compatibility(_ product: CatalogueProduct) -> String {
        let platforms = (listing?.platforms.isEmpty == false ? listing!.platforms : product.platforms)
        let names = platforms.contains { $0.lowercased() == "ios" } ? "Works on this iPhone" : "Not declared for iOS"
        let host = listing?.minimumHostVersion ?? manifest?.minHostVersion
        return host.map { "\(names) · Modula \($0)+" } ?? names
    }

    private var uninstallButton: some View {
        Button(role: .destructive) { confirmUninstall = true } label: {
            Label("Uninstall \(product?.name ?? "Module")", systemImage: "trash")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("module.uninstall")
    }

    // MARK: Actions

    private var installTitle: String { "Install \(product?.name ?? "module")?" }

    private var installMessage: String {
        let permissions = listing?.permissions ?? []
        guard !permissions.isEmpty else { return "It will be added to your Modula account." }
        let high = listing?.highRiskCount ?? 0
        return "It will be added to your Modula account with \(permissions.count) permissions" + (high > 0 ? " (\(high) high risk)." : ".") + " You can review them under Permissions."
    }

    private func perform(_ action: ModulePrimaryAction) {
        switch action {
        case .open:
            open()
        case .install:
            if listing == nil { Task { await app.catalogue.loadListing(moduleID) } }
            confirmInstall = true
        case .update:
            Task {
                // Updates go through the same registry preview + consent sheet as any switch.
                if app.catalogue.versionLists[moduleID] == nil { await app.catalogue.loadVersions(moduleID) }
                if let latest = app.catalogue.versionLists[moduleID]?.versions.first(where: { $0.isLatest && $0.direction == .upgrade && $0.switchable }) {
                    selectVersion(latest)
                } else if await app.catalogue.update(moduleID) {
                    HapticEngine.shared.play(.success)
                    app.navigation.banner = ModulaBanner(message: "\(product?.name ?? "Module") updated", symbol: "checkmark.circle")
                } else {
                    HapticEngine.shared.play(.failure)
                }
            }
        case .signIn:
            app.navigation.open(.auth(.login))
        default:
            break
        }
    }

    // MARK: Versions

    private func versions(_ state: ModuleDetailPresentation) -> some View {
        ModuleVersionsSection(
            list: app.catalogue.versionLists[moduleID],
            failed: app.catalogue.versionsFailed.contains(moduleID),
            installedVersion: installedVersion,
            busy: app.catalogue.operations[moduleID] != nil,
            onSelect: selectVersion,
            onRetry: { Task { await app.catalogue.loadVersions(moduleID) } }
        )
    }

    private func selectVersion(_ option: ModuleVersionOption) {
        HapticEngine.shared.play(.selection)
        versionPhase = .loading
        versionTarget = option
    }

    private func prepareVersionSwitch(_ option: ModuleVersionOption) async {
        versionPhase = .loading
        do {
            versionPhase = .ready(try await app.catalogue.prepareVersionSwitch(moduleID, to: option.version))
        } catch let error as InstallDescriptorVerificationError {
            versionPhase = .failed(error.errorDescription ?? "The release failed verification.")
        } catch {
            versionPhase = .failed(ProductHubStore.message(error, verb: "check this version"))
        }
    }

    private func runVersionSwitch(_ preview: ModuleVersionPreview) async {
        let name = product?.name ?? "Module"
        if await app.catalogue.switchVersion(moduleID, preview: preview) {
            HapticEngine.shared.play(.success)
            let verb = preview.isDowngrade ? "downgraded" : "updated"
            app.navigation.banner = ModulaBanner(message: "\(name) \(verb) to \(preview.toVersion)", symbol: "checkmark.circle")
        } else {
            HapticEngine.shared.play(.failure)
        }
    }

    private func open() {
        HapticEngine.shared.play(.confirmation)
        app.navigation.open(.module(moduleID, localPath: nil))
    }

    private func runInstall() async {
        let granted = (listing?.permissions ?? []).map(\.permission)
        if await app.catalogue.install(moduleID, permissions: granted) {
            HapticEngine.shared.play(.success)
            app.navigation.banner = ModulaBanner(message: "\(product?.name ?? "Module") installed", symbol: "checkmark.circle")
        } else {
            HapticEngine.shared.play(.failure)
        }
    }

    private func runUninstall() async {
        if await app.catalogue.uninstall(moduleID) {
            HapticEngine.shared.play(.success)
            app.navigation.banner = ModulaBanner(message: "\(product?.name ?? "Module") removed", symbol: "trash")
        } else {
            HapticEngine.shared.play(.failure)
        }
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
