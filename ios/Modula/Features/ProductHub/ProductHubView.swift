import SwiftUI
import Observation
import CryptoKit
import UIKit

@MainActor @Observable
final class ProductHubStore {
    private let client: GreenfieldClient
    var activation: ModuleActivationController?
    var accountID: String?
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
    /// Install descriptors this device verified against the registry and the server then
    /// issued byte-for-byte (version switching). The module host re-checks them before load.
    private(set) var verifiedDescriptors: [String: ModuleInstallDescriptor] = [:]
    /// Online launch eligibility is exact-release and account-scoped. Offline
    /// launches use the previously verified cache only when catalogue load fails.
    private var eligibleGameReleases: [String: String] = [:]
    private(set) var loading = false
    private(set) var loaded = false
    var error: String?
    /// Poll cadence while the server settles a lifecycle change; tests shorten it.
    var settlePollInterval: Duration = .milliseconds(900)
    var settleAttempts = 30
    /// Override in tests. Production scans Application Support and ~/Developer/modula-dev-modules.
    var localDevRoots: [URL] = ProductHubStore.defaultLocalDevRoots()
    /// Account-scoped catalogue metadata for previously verified web games.
    /// Offline entries are rebuilt from ACTIVE cache slots before display.
    var offlineGameCatalogueRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Modula/OfflineGameCatalogue", isDirectory: true)
    /// Local-only versions discovered on disk, keyed by module id.
    private(set) var localDevVersions: [String: [String]] = [:]
    /// Permissions the account reviewed for a local development module.
    private(set) var reviewedGrants: [String: [String]] = [:]

    init(client: GreenfieldClient) { self.client = client }

    static func defaultLocalDevRoots() -> [URL] {
        [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Modula/DevModules"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Developer/modula-dev-modules"),
        ].compactMap { $0 }
    }

    /// Modules the account has installed (any non-removed state).
    var installedIDs: Set<String> { Set(installations.values.filter(\.isPresent).map(\.moduleId)) }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-local-module-session") {
            loaded = true
            mergeLocalDevModules()
            loadReviewedGrants()
            restoreLocalDevelopmentInstallations()
            return
        }
        #endif
        do {
            products = try await client.catalogue()
            loaded = true
            installations = await Self.installations(client: client, previous: installations)
            await refreshGameEligibility()
            saveOfflineGameCatalogue()
        } catch {
            self.error = "Product catalogue is unavailable. Pull to refresh."
            if GreenfieldClient.isConnectivityFailure(error) { restoreOfflineGameCatalogue() }
        }
        mergeLocalDevModules()
        restoreLocalDevelopmentInstallations()
    }

    /// Local-development installs live in the account artifact cache, not GreenField.
    /// A relaunch must keep that installation so a newer package is an update.
    private func restoreLocalDevelopmentInstallations() {
        guard let accountID, let activation else { return }
        for product in products where product.betaClassification == "local-development" {
            guard installations[product.moduleId]?.isPresent != true,
                  let release = activation.active(accountID: accountID, moduleId: product.moduleId) else { continue }
            installations[product.moduleId] = ModuleInstallation(
                moduleId: product.moduleId, status: "enabled", version: release.version
            )
        }
    }

    private func offlineGameCatalogueURL(account: String) -> URL {
        let digest = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return offlineGameCatalogueRoot.appendingPathComponent("\(digest).json")
    }

    private func verifiedOfflineGame(_ product: CatalogueProduct, account: String) -> ModuleCachedRelease? {
        guard product.productKind == "game", let activation,
              let release = activation.active(accountID: account, moduleId: product.moduleId),
              release.hostManifest.runtime == "web-game", release.gameSha256 != nil,
              (try? activation.store.frontendData(for: release)) != nil,
              (try? activation.store.verifiedGameEntry(for: release)) != nil else { return nil }
        return release
    }

    private func saveOfflineGameCatalogue() {
        guard let accountID else { return }
        let games = products.filter { verifiedOfflineGame($0, account: accountID) != nil }
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? FileManager.default.createDirectory(at: offlineGameCatalogueRoot, withIntermediateDirectories: true)
        try? data.write(to: offlineGameCatalogueURL(account: accountID), options: .atomic)
    }

    private func restoreOfflineGameCatalogue() {
        guard let accountID,
              let data = try? Data(contentsOf: offlineGameCatalogueURL(account: accountID)),
              let cached = try? JSONDecoder().decode([CatalogueProduct].self, from: data) else { return }
        let games = cached.compactMap { product -> (CatalogueProduct, ModuleCachedRelease)? in
            guard let release = verifiedOfflineGame(product, account: accountID) else { return nil }
            return (product, release)
        }
        products = games.map { $0.0 }
        installations = Dictionary(uniqueKeysWithValues: games.map { item in
            (item.0.moduleId, ModuleInstallation(moduleId: item.0.moduleId, status: "enabled", version: item.1.version))
        })
        // Keep `loaded` false: offline launch uses the verified local release,
        // while install/update and online revocation decisions still need the registry.
        loaded = false
    }

    /// Drops the signed-in account's hub installation list. Cached bytes stay in that
    /// account's store and are not offered again until the same account signs in.
    func dropAccountScope() {
        accountID = nil
        installations = [:]
        eligibleGameReleases = [:]
    }

    func product(_ id: String) -> CatalogueProduct? { products.first { $0.moduleId == id } }

    /// Whether `/module/<id>` may open for this account. Before the catalogue has loaded
    /// (offline launch) the host can't decide and defers to the backend, which still
    /// rejects records for modules that aren't installed.
    func installGate(for id: String) -> ModuleInstallGate {
        if let cached = activation?.active(accountID: accountID, moduleId: id) {
            if loaded, product(id)?.betaClassification != "local-development" {
                guard let installation = installations[id], installation.isRunnable,
                      installation.version == cached.version else { return .notInstalled }
                if product(id)?.productKind == "game",
                   eligibleGameReleases[id] != cached.releaseId { return .notInstalled }
            }
            return .runnable(descriptor: verifiedDescriptors[id] ?? cached.descriptor)
        }
        guard loaded else { return .runnable(descriptor: nil) }
        guard let installation = installations[id], installation.isRunnable else { return .notInstalled }
        let descriptor = verifiedDescriptors[id].flatMap { $0.version == installation.version ? $0 : nil }
        return .runnable(descriptor: descriptor)
    }

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
        await refreshGameEligibility()
        restoreLocalDevelopmentInstallations()
    }

    private func refreshGameEligibility() async {
        eligibleGameReleases = [:]
        for product in products where product.productKind == "game" && product.betaClassification != "local-development" {
            guard installations[product.moduleId]?.isRunnable == true,
                  let descriptor = try? await client.installedDistributionDescriptor(product.moduleId),
                  descriptor["moduleId"]?.string == product.moduleId,
                  descriptor["launchEligible"]?.bool == true,
                  descriptor["currentRelease"]?["trust"]?["verified"]?.bool == true,
                  descriptor["currentRelease"]?["revoked"]?.bool == false,
                  let releaseID = descriptor["currentRelease"]?["releaseId"]?.string,
                  descriptor["permissionReview"]?["releaseId"]?.string == releaseID,
                  descriptor["permissionReview"]?["status"]?.string == "approved" else { continue }
            eligibleGameReleases[product.moduleId] = releaseID
        }
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
        if product(id)?.betaClassification == "local-development",
           let local = await installLocalDevelopment(id, permissions: permissions) { return local }
        guard operations[id] == nil else { return false }
        operations[id] = .installing
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            _ = try await client.installModule(id, version: product(id)?.latestVersion, approvedPermissions: permissions, idempotencyKey: Self.key("install", id))
            let settled = try await settle(id) { $0?.isRunnable == true }
            if settled { await activateVerifiedFrontend(id) }
            return settled
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: "install")
            await refreshInstallations()
            return false
        }
    }

    /// Approves the module's full permission list, including ones an earlier review left denied.
    @discardableResult
    func allowPermissions(_ id: String, permissions: [String]) async -> Bool {
        guard operations[id] == nil, !permissions.isEmpty else { return false }
        operations[id] = .updating
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            try await client.reviewModulePermissions(id, approvedPermissions: permissions, idempotencyKey: Self.key("permissions", id))
            await refreshInstallations()
            await activateVerifiedFrontend(id)
            return true
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: "update permissions")
            return false
        }
    }

    @discardableResult
    func update(_ id: String) async -> Bool {
        let reviewed = requestedLocalPermissions(id).map(\.permission)
        if product(id)?.betaClassification == "local-development",
           let local = await installLocalDevelopment(id, permissions: reviewed) { return local }
        guard operations[id] == nil, let latest = product(id)?.latestVersion else { return false }
        operations[id] = .updating
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            try await client.updateModule(id, version: latest, approvedPermissionIncrease: false, idempotencyKey: Self.key("update", id))
            let settled = try await settle(id) { $0?.isRunnable == true && $0?.version.map { !ModuleVersion.isOlder($0, than: latest) } ?? true }
            if settled { await activateVerifiedFrontend(id) }
            return settled
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
            verifiedDescriptors[id] = issued
            let target = preview.toVersion
            let settled = try await settle(id) { $0?.isRunnable == true && $0?.version == target }
            if settled { await activateVerifiedFrontend(id) }
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
        if product(id)?.betaClassification == "local-development" {
            return uninstallLocalDevelopment(id)
        }
        guard operations[id] == nil else { return false }
        operations[id] = .uninstalling
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        do {
            try await client.uninstallModule(id, idempotencyKey: Self.key("uninstall", id))
            let removed = try await settle(id) { $0 == nil || $0?.isPresent == false }
            restoreLocalDevelopmentInstallations()
            return removed
        } catch {
            lifecycleErrors[id] = Self.message(error, verb: "remove")
            await refreshInstallations()
            return false
        }
    }

    /// Development packages live in this device's cache. Removing one must not ask GreenField
    /// to delete an installation it never recorded.
    private func uninstallLocalDevelopment(_ id: String) -> Bool {
        guard operations[id] == nil else { return false }
        operations[id] = .uninstalling
        lifecycleErrors[id] = nil
        defer { operations[id] = nil }
        guard let activation else {
            lifecycleErrors[id] = "Couldn’t remove the module. Try again."
            return false
        }
        let account = accountID ?? "local-dev"
        do {
            try activation.removeLocalModule(accountID: account, moduleId: id)
            installations[id] = nil
            return true
        } catch {
            lifecycleErrors[id] = "Couldn’t remove the module. Try again."
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
            restoreLocalDevelopmentInstallations()
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

    /// Cache-first activation of a verified Product UI frontend. Bundled RN modules stay
    /// runnable if no frontend artifact is published.
    func activateVerifiedFrontend(_ id: String, accountID: String? = nil) async {
        guard let activation else { return }
        let installation = installations[id]
        let version = installation?.version ?? product(id)?.latestVersion
        guard let version else { return }
        let descriptor = verifiedDescriptors[id].flatMap { $0.version == version ? $0 : nil }
        let registryProduct = product(id)?.betaClassification != "local-development"
        let isWebGame = product(id)?.productKind == "game" && registryProduct
        var hosted: HostedModuleFrontend?
        if registryProduct, let fetched = try? await client.installedProductFrontend(id),
           fetched.productId == id, fetched.version == version {
            hosted = fetched
        }
        guard let account = accountID ?? self.accountID else { return }
        var gameSha256: String?
        var gameReleaseID: String?
        var gameFrontendSha256: String?
        var gameGrants: [String] = []
        if isWebGame {
            do {
                let installation = try await client.installedDistributionDescriptor(id)
                let release = installation["currentRelease"]
                guard installation["moduleId"]?.string == id,
                      installation["enabled"]?.bool == true,
                      installation["launchEligible"]?.bool == true,
                      installation["permissionReview"]?["status"]?.string == "approved",
                      let releaseID = release?["releaseId"]?.string,
                      installation["permissionReview"]?["releaseId"]?.string == releaseID,
                      release?["releaseId"]?.string == releaseID,
                      release?["moduleId"]?.string == id,
                      release?["version"]?.string == version,
                      let packageDigest = release?["packageDigest"]?.string,
                      InstallDescriptorVerifier.isHex64(packageDigest),
                      let frontendDigest = release?["frontendDigest"]?.string,
                      InstallDescriptorVerifier.isHex64(frontendDigest),
                      release?["signature"]?["algorithm"]?.string == "Ed25519",
                      release?["trust"]?["verified"]?.bool == true,
                      release?["trust"]?["signatureState"]?.string == "verified",
                      release?["revoked"]?.bool == false,
                      let artifacts = release?["artifacts"]?.array,
                      let game = artifacts.first(where: { $0["artifactId"]?.string == "release:\(releaseID):web-game" &&
                          $0["kind"]?.string == "asset" && $0["requiredForOfflineLaunch"]?.bool == true &&
                          $0["access"]?.string == "installation" && $0["immutable"]?.bool == true }),
                      let digest = game["digest"]?.string, InstallDescriptorVerifier.isHex64(digest),
                      game["contentType"]?.string == "application/gzip" else {
                    throw ModuleActivationError.untrusted
                }
                if let descriptor, (descriptor.registryReleaseId != releaseID ||
                    descriptor.artifactSha256 != packageDigest || descriptor.frontendSha256 != frontendDigest) {
                    throw ModuleActivationError.untrusted
                }
                gameReleaseID = releaseID
                gameFrontendSha256 = frontendDigest
                gameGrants = installation["permissionReview"]?["effectiveCapabilities"]?.array?.compactMap(\.string) ?? []
                gameSha256 = digest
            } catch {
                lifecycleErrors[id] = "The game release descriptor could not be verified."
                return
            }
        }
        let declaredSha = gameFrontendSha256
            ?? VerifiedFrontendSelection.normalized(descriptor?.frontendSha256)
            ?? VerifiedFrontendSelection.normalized(hosted?.sha256)
        if let declaredSha,
           let cached = activation.active(accountID: account, moduleId: id),
           cached.version == version, cached.frontendSha256 == declaredSha,
           (!isWebGame || cached.gameSha256 == gameSha256) {
            lifecycleErrors[id] = nil
            if isWebGame { saveOfflineGameCatalogue() }
            return
        }
        var artifact: Data?
        if registryProduct, let declaredSha {
            artifact = try? await client.downloadVerifiedArtifact(
                ref: "/v1/registry/artifacts/\(declaredSha)",
                expectedSha256: declaredSha,
                maximumBytes: ProductUIDocument.maxBytes
            )
        }
        var bytes = VerifiedFrontendSelection.choose(
            declaredSha256: declaredSha, artifact: artifact, hosted: hosted?.frontend
        )
        if bytes == nil, product(id)?.betaClassification == "local-development" {
            bytes = Self.localDevFrontend(moduleId: id, version: version, roots: localDevRoots)
        }
        guard let bytes else {
            if registryProduct, declaredSha != nil {
                lifecycleErrors[id] = ModuleActivationError.digestMismatch("frontend").errorDescription
            }
            return
        }
        let digest = VerifiedFrontendSelection.sha256(bytes)
        var gameArchive: Data?
        if let gameSha256 {
            do {
                gameArchive = try await client.downloadVerifiedArtifact(
                    ref: "/v1/registry/artifacts/\(gameSha256)",
                    expectedSha256: gameSha256,
                    maximumBytes: WebGamePackage.maximumCompressedBytes
                )
            } catch {
                lifecycleErrors[id] = "The verified game package could not be downloaded."
                return
            }
        }
        let grants = isWebGame ? gameGrants : descriptor?.grantedPermissions ?? []
        let manifest = ModuleManifest(
            id: id, name: product(id)?.name ?? id, version: version, runtime: isWebGame ? "web-game" : "declarative",
            entry: isWebGame ? "index.html" : "product-ui",
            permissions: Array(Set(grants + ModulePolicy.hostCapabilities(coveredBy: grants))).sorted(),
            minHostVersion: isWebGame ? ">=1.1.0" : ">=1.0.0", minBridgeVersion: "0.1.0",
            collections: ["item"]
        )
        do {
            try activation.stageVerified(
                accountID: account, moduleId: id, version: version,
                releaseId: gameReleaseID ?? descriptor?.registryReleaseId ?? "\(id)@\(version)",
                frontend: bytes, frontendSha256: digest, mediaType: ProductUIDocument.mediaType,
                hostManifest: manifest, descriptor: descriptor,
                gameArchive: gameArchive, gameSha256: gameSha256
            )
            _ = try activation.activate(accountID: account, moduleId: id)
            if let gameReleaseID { eligibleGameReleases[id] = gameReleaseID }
            lifecycleErrors[id] = nil
            if isWebGame { saveOfflineGameCatalogue() }
        } catch {
            lifecycleErrors[id] = error.localizedDescription
        }
    }

    /// Permissions declared by a local development package. They are requested, not granted,
    /// until the install confirmation names them.
    func requestedLocalPermissions(_ id: String) -> [ModuleListing.Permission] {
        let version = localDevVersions[id]?.last ?? product(id)?.latestVersion
        guard let version else { return [] }
        for root in localDevRoots {
            let url = root.appendingPathComponent("\(id)/\(version)/modula.module.json")
            guard let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let items = raw["permissions"]?.array else { continue }
            return items.compactMap { item in
                guard let permission = item["id"]?.string ?? item["permission"]?.string else { return nil }
                return ModuleListing.Permission(
                    permission: permission,
                    risk: item["risk"]?.string ?? "unknown",
                    reason: item["reason"]?.string ?? ""
                )
            }
        }
        return []
    }

    static func localDevFrontend(moduleId: String, version: String, roots: [URL]? = nil) -> Data? {
        let search = roots ?? defaultLocalDevRoots()
        for root in search {
            let url = root.appendingPathComponent("\(moduleId)/\(version)/frontend.manifest.json")
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    /// Discovers generator/Studio output on disk. Missing registry products are added;
    /// existing registry products keep their published latestVersion.
    func mergeLocalDevModules() {
        let discovered = Self.scanLocalDevModules(roots: localDevRoots)
        var versions: [String: [String]] = [:]
        for item in discovered {
            versions[item.moduleId, default: []].append(item.version)
            if products.contains(where: { $0.moduleId == item.moduleId }) { continue }
            products.append(item.asProduct)
        }
        for (id, list) in versions {
            let unique = Array(Set(list)).sorted { ModuleVersion.isOlder($0, than: $1) }
            localDevVersions[id] = unique
            if let latest = unique.last,
               let index = products.firstIndex(where: { $0.moduleId == id && $0.betaClassification == "local-development" }) {
                products[index] = itemReplacingVersion(products[index], version: latest)
            }
        }
    }

    /// Installs a signed local development package without GreenField. This is
    /// kept separate from the registry path and never marks a QA release trusted.
    func installLocalDevelopment(_ id: String, permissions: [String], version: String? = nil) async -> Bool? {
        let chosen = version
            ?? localDevVersions[id]?.last
            ?? product(id)?.latestVersion
        guard let chosen, let bytes = Self.localDevFrontend(moduleId: id, version: chosen, roots: localDevRoots) else {
            return nil
        }
        guard let activation else { return false }
        let account = accountID ?? "local-dev"
        accountID = account
        let gameArchive = localDevRoots.lazy.compactMap { root -> (Data, String)? in
            let directory = root.appendingPathComponent("\(id)/\(chosen)")
            guard let manifestData = try? Data(contentsOf: directory.appendingPathComponent("modula.product.json")),
                  let manifest = try? JSONDecoder().decode(JSONValue.self, from: manifestData),
                  manifest["gameRuntime"]?["type"]?.string == "web-mini-game",
                  manifest["gameRuntime"]?["artifact"]?["path"]?.string == "game/game.tgz",
                  let digest = manifest["gameRuntime"]?["artifact"]?["sha256"]?.string,
                  InstallDescriptorVerifier.isHex64(digest),
                  let archive = try? Data(contentsOf: directory.appendingPathComponent("game/game.tgz")) else { return nil }
            return (archive, digest)
        }.first
        let manifest = ModuleManifest(
            id: id, name: product(id)?.name ?? id, version: chosen,
            runtime: gameArchive == nil ? "declarative" : "web-game",
            entry: gameArchive == nil ? "product-ui" : "index.html", permissions: permissions,
            minHostVersion: gameArchive == nil ? ">=1.0.0" : ">=1.1.0",
            minBridgeVersion: "0.1.0", collections: ["item"]
        )
        do {
            try verifyLocalTrust(moduleId: id, version: chosen)
            let frontendDigest = VerifiedFrontendSelection.sha256(bytes)
            try activation.stageVerified(
                accountID: account, moduleId: id, version: chosen, releaseId: "local:\(id)@\(chosen)",
                frontend: bytes, frontendSha256: frontendDigest, mediaType: ProductUIDocument.mediaType,
                hostManifest: manifest, descriptor: nil,
                gameArchive: gameArchive?.0, gameSha256: gameArchive?.1
            )
            _ = try activation.activate(accountID: account, moduleId: id)
            activation.reviews.record(ModulePermissionReview(
                moduleId: id, releaseId: "local:\(id)@\(chosen)", descriptorRevision: "local",
                granted: permissions, denied: [], reviewedAt: Date()
            ))
            installations[id] = ModuleInstallation(moduleId: id, status: "enabled", version: chosen)
            rememberGrants(permissions, moduleId: id)
            return true
        } catch {
            lifecycleErrors[id] = error.localizedDescription
            return false
        }
    }

    func loadReviewedGrants() {
        guard let accountID else { return }
        let url = grantsURL(accountID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        reviewedGrants = decoded
    }

    private func rememberGrants(_ permissions: [String], moduleId: String) {
        reviewedGrants[moduleId] = permissions
        guard let accountID else { return }
        let url = grantsURL(accountID)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(reviewedGrants).write(to: url, options: .atomic)
    }

    private func grantsURL(_ accountID: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let safe = accountID.replacingOccurrences(of: "/", with: "_")
        return base.appendingPathComponent("Modula/permission-grants-\(safe).json")
    }

    private func verifyLocalTrust(moduleId: String, version: String) throws {
        guard let facts = signedFacts(moduleId: moduleId, version: version) else {
            if !ModuleTrustPolicy.current.allowsUnsignedLocalPackages { throw ModuleTrustError.unsigned }
            return
        }
        try ModuleReleaseTrust.verify(
            facts: facts,
            packagedDigest: packagedDigest(moduleId: moduleId, version: version),
            artifact: nil,
            policy: .current
        )
    }

    private func signedFacts(moduleId: String, version: String) -> ModuleSignedFacts? {
        for root in localDevRoots {
            let url = root.appendingPathComponent("\(moduleId)/\(version)/signed-facts.json")
            if let data = try? Data(contentsOf: url), let facts = ModuleSignedFacts(data: data) { return facts }
        }
        return nil
    }

    private func packagedDigest(moduleId: String, version: String) -> String? {
        for root in localDevRoots {
            let url = root.appendingPathComponent("\(moduleId)/\(version)/package.sha256")
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let digest = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !digest.isEmpty { return digest }
            }
        }
        return nil
    }

    #if DEBUG
    func debugStageBadDigest(_ id: String) throws -> String {
        guard let activation, let account = accountID else { throw ModuleActivationError.wrongAccount }
        guard let active = activation.active(accountID: account, moduleId: id) else { throw ModuleActivationError.missingStaged }
        let bytes = try activation.store.frontendData(for: active)
        try activation.store.stageDeclaredDigestMismatch(
            accountID: account, moduleId: id, version: active.version,
            releaseId: "\(active.releaseId)#bad-digest", frontend: bytes,
            declaredSha256: String(repeating: "ab", count: 32), hostManifest: active.hostManifest
        )
        return "staged-bad-digest"
    }

    func debugActivateStaged(_ id: String) throws -> String {
        guard let activation, let account = accountID else { throw ModuleActivationError.wrongAccount }
        do {
            _ = try activation.activate(accountID: account, moduleId: id)
            return "activated"
        } catch {
            return activation.store.index(accountID: account, moduleId: id).lastAuditReason ?? error.localizedDescription
        }
    }

    func debugFailActivationHealth(_ id: String) throws -> String {
        guard let activation, let account = accountID else { throw ModuleActivationError.wrongAccount }
        guard let active = activation.active(accountID: account, moduleId: id) else { throw ModuleActivationError.missingStaged }
        let versions = localDevVersions[id] ?? []
        guard let next = versions.last(where: { ModuleVersion.isOlder(active.version, than: $0) }) else {
            throw ModuleActivationError.missingStaged
        }
        guard let bytes = Self.localDevFrontend(moduleId: id, version: next, roots: localDevRoots) else {
            throw ModuleActivationError.missingStaged
        }
        try verifyLocalTrust(moduleId: id, version: next)
        let manifest = ModuleManifest(
            id: id, name: product(id)?.name ?? id, version: next, runtime: "declarative",
            entry: "product-ui", permissions: [], minHostVersion: ">=1.0.0",
            minBridgeVersion: "0.1.0", collections: ["item"]
        )
        _ = try activation.installLocalPackage(
            accountID: account, moduleId: id, version: next, releaseId: "local:\(id)@\(next)",
            frontend: bytes, hostManifest: manifest, activate: false
        )
        activation.failNextActivationHealth = true
        do {
            _ = try activation.activate(accountID: account, moduleId: id)
            return "activated-unexpectedly"
        } catch {
            return activation.store.index(accountID: account, moduleId: id).lastAuditReason ?? error.localizedDescription
        }
    }
    #endif

    private func itemReplacingVersion(_ product: CatalogueProduct, version: String) -> CatalogueProduct {
        CatalogueProduct(
            moduleId: product.moduleId,
            productKind: product.productKind,
            name: product.name,
            description: product.description,
            publisherId: product.publisherId,
            publisherName: product.publisherName,
            latestVersion: version,
            status: product.status,
            installable: product.installable,
            platforms: product.platforms,
            betaClassification: product.betaClassification,
            installability: product.installability,
            presentation: product.presentation
        )
    }

    private struct LocalDevListing {
        var moduleId: String
        var version: String
        var name: String
        var description: String
        var productKind: String = "module"

        var asProduct: CatalogueProduct {
            CatalogueProduct(
                moduleId: moduleId,
                productKind: productKind,
                name: name,
                description: description,
                publisherId: "modula",
                publisherName: "modula",
                latestVersion: version,
                status: "published",
                installable: true,
                platforms: ["ios"],
                betaClassification: "local-development",
                installability: CatalogueProduct.Installability(status: "installable", reasonCode: nil, reason: nil)
            )
        }
    }

    private static func scanLocalDevModules(roots: [URL]) -> [LocalDevListing] {
        var found: [LocalDevListing] = []
        for root in roots {
            guard let modules = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for moduleDir in modules {
                guard let versions = try? FileManager.default.contentsOfDirectory(at: moduleDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                for versionDir in versions {
                    let frontend = versionDir.appendingPathComponent("frontend.manifest.json")
                    guard let data = try? Data(contentsOf: frontend),
                          let raw = try? JSONDecoder().decode(JSONValue.self, from: data),
                          let moduleId = raw["productId"]?.string,
                          let version = raw["releaseVersion"]?.string else { continue }
                    var name = moduleId
                    var description = "Local development module"
                    let sidecar = versionDir.appendingPathComponent("modula.module.json")
                    if let moduleData = try? Data(contentsOf: sidecar),
                       let moduleRaw = try? JSONDecoder().decode(JSONValue.self, from: moduleData) {
                        name = moduleRaw["name"]?.string ?? name
                        description = moduleRaw["description"]?.string ?? description
                    }
                    let productKind = FileManager.default.fileExists(atPath: versionDir.appendingPathComponent("game/game.tgz").path)
                        ? "game" : "module"
                    found.append(LocalDevListing(moduleId: moduleId, version: version, name: name,
                                                 description: description, productKind: productKind))
                }
            }
        }
        return found
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
    /// `product` is the caller's list item (e.g. Discover tiles); when it carries
    /// registry presentation it is used, otherwise the hub catalogue's copy is.
    func moduleArtwork(_ id: String, product: CatalogueProduct? = nil) -> ModuleArtwork {
        let item = product?.presentation != nil ? product : catalogue.product(id)
        return ModuleArtwork(listing: catalogue.listings[id], product: item)
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
        let art = app.moduleArtwork(product.moduleId, product: product)
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
        let art = app.moduleArtwork(product.moduleId, product: product)
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
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        Button {
            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "product", key: product.id), for: .productHub(.module(product.id, .overview)))
            action()
        } label: {
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
                ProductGetOpenControl(product: product, installed: installed)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background {
                let surface = ModulaPalette.resolve(app.appearance, scheme: scheme).surface
                ZStack {
                    RoundedRectangle(cornerRadius: 21, style: .continuous).fill(surface)
                    // Faint accent wash from the icon side ties the card to its artwork.
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(LinearGradient(colors: [app.appearance.accent.color.opacity(scheme == .dark ? 0.10 : 0.06), .clear], startPoint: .leading, endPoint: .center))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(LinearGradient(colors: [.primary.opacity(0.10), .primary.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .modulaHeroSource("product", key: product.id)
        }
        .buttonStyle(.modulaPress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(product.publisherName)")
        .accessibilityValue(installed ? "Installed" : (product.installable ? "Available" : "Coming soon"))
        .accessibilityIdentifier("product.\(product.moduleId)")
    }
}


struct ProductGetOpenControl: View {
    let product: CatalogueProduct
    let installed: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    private var busy: Bool {
        switch app.catalogue.operations[product.id] {
        case .installing, .updating: true
        default: false
        }
    }
    var body: some View {
        let accent = app.appearance.accent.color
        ZStack {
            if busy {
                Circle().trim(from: 0, to: 0.72)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(ModulaEffectGate.reduceMotion(reduceMotion) ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }.onDisappear { spin = false }
                Image(systemName: "arrow.down").font(.caption.weight(.bold)).foregroundStyle(accent)
            } else {
                Text(installed ? "OPEN" : (product.installable ? "GET" : "SOON"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(product.installable || installed ? accent : .secondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .modulaGlass(in: Capsule(), interactive: false, tint: (product.installable || installed) ? accent.opacity(0.14) : nil)
            }
        }
        .frame(minWidth: 52, minHeight: 36)
        .accessibilityLabel(busy ? "Installing" : (installed ? "Open" : (product.installable ? "Get" : "Coming soon")))
    }
}

struct ProductCategoryChips: View {
    let products: [CatalogueProduct]
    var selected: String? = nil
    var onOpen: (String) -> Void
    @Environment(AppEnvironment.self) private var app
    private var kinds: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in products {
            let k = p.productKind.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty, seen.insert(k).inserted else { continue }
            out.append(k)
        }
        return out
    }
    var body: some View {
        let accent = app.appearance.accent.color
        VStack(alignment: .leading, spacing: 10) {
            ModulaSectionHeader(title: "Categories")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.self) { kind in
                        Button { onOpen(kind); HapticEngine.shared.play(.selection) } label: {
                            Text(kind.capitalized).font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected == kind ? accent : .primary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(selected == kind ? 0.32 : 0.12))
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
                        .accessibilityIdentifier("product-hub.category.\(kind)")
                        .accessibilityAddTraits(selected == kind ? .isSelected : [])
                    }
                }
            }.scrollClipDisabled()
        }
    }
}

struct ProductRankedList: View {
    var title: String; var subtitle: String? = nil
    var products: [CatalogueProduct]; var installedIDs: Set<String>
    var action: (CatalogueProduct) -> Void
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModulaSectionHeader(title: title, subtitle: subtitle)
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                Button { action(product) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.title3.weight(.bold)).monospacedDigit()
                            .foregroundStyle(index < 3 ? app.appearance.accent.color : .secondary).frame(width: 28)
                        ProductArtwork(product: product, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            Text(product.publisherName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        ProductGetOpenControl(product: product, installed: installedIDs.contains(product.id))
                    }
                    .padding(12)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
                .modulaScrollReveal()
                .accessibilityLabel("\(index + 1). \(product.name)")
            }
        }
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
            ModulaSectionHeader(title: title, subtitle: subtitle)
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                ProductCard(product: product, installed: installedIDs.contains(product.id)) { action(product) }
                    .modulaScrollReveal(depth: true)
                    .modulaPageEntrance(delay: min(Double(index), 6) * 0.04)
            }
        }
    }
}

struct ProductHero: View {
    let product: CatalogueProduct
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modulaHeroScope) private var heroScope

    var body: some View {
        Button {
            ModulaHeroMorph.arm(ModulaHeroMorph.sourceID(scope: heroScope, kind: "product-hero", key: product.id), for: .productHub(.module(product.id, .overview)))
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                ProductBackdrop(product: product)
                    .modulaHeroSheen(intensity: 0.55)
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.35), location: 0.38), .init(color: .black.opacity(0.9), location: 1)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("TODAY")
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .modulaGlass(in: Capsule(), interactive: false, tint: .white.opacity(0.14))
                        Spacer()
                        ProductArtwork(product: product, size: 44)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    }
                    Spacer(minLength: 12)
                    Text(product.name).font(.largeTitle.bold()).foregroundStyle(.white).lineLimit(2)
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                    Text(product.description).font(.subheadline).foregroundStyle(.white.opacity(0.88)).lineLimit(3).padding(.top, 6)
                    HStack(spacing: 8) {
                        Text(product.publisherName).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("Read story").font(.caption.weight(.bold)).foregroundStyle(.white)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                    }.padding(.top, 14)
                }.padding(20)
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            )
            .shadow(color: app.appearance.accent.color.opacity(0.22), radius: 18, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .modulaHeroSource("product-hero", key: product.id)
        }
        .buttonStyle(.modulaPressTilt)
        .modulaScrollReveal(depth: true)
        .accessibilityLabel("Featured module, \(product.name)")
        .accessibilityIdentifier("product-hub.featured")
    }
}

struct ProductHubView: View {
    let route: ProductHubRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""
    @State private var categoryFilter: String?

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
            // Clear the floating Modules accessory and the tab bar.
            .padding(.bottom, 140)
            .modulaPullContentEffects()
        }
        .modulaSoftScrollEdge()
        .modulaShellPullActions { await app.catalogue.load() }
        .environment(\.modulaHeroScope, "hub.\(String(describing: route))")
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
                    Section("Developers") {
                        Button("Developer Studio", systemImage: "hammer") {
                            app.navigation.open(.developer(.studio))
                        }
                        .accessibilityIdentifier("product-hub.developer-studio")
                        Button("Create Module", systemImage: "plus.square.on.square") {
                            app.navigation.open(.developer(.studio))
                        }
                        .accessibilityIdentifier("product-hub.create-module")
                        Button("Web Studio", systemImage: "safari") {
                            app.openDeveloperStudio()
                        }
                        .accessibilityIdentifier("product-hub.web-studio")
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
        } else if app.auth.account != nil {
            // Signed-in state no longer needs a chip; the account lives in the menu.
            EmptyView()
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
        } else if query.isEmpty {
            let featured = app.catalogue.product("digital.modula.vault-notes")
                ?? app.catalogue.products.first(where: \.installable)
                ?? app.catalogue.products.first
            if let featured {
                ProductHero(product: featured) { open(featured) }
                    .modulaPageEntrance()
            }
            let installed = app.catalogue.products.filter { app.catalogue.installedIDs.contains($0.id) }
            if !installed.isEmpty {
                ProductShelf(
                    title: "Installed",
                    subtitle: "On your account",
                    products: installed,
                    installedIDs: app.catalogue.installedIDs,
                    action: open
                )
                Button {
                    app.navigation.open(.productHub(.collection(.updates)))
                } label: {
                    Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                }
                .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: nil))
                .accessibilityIdentifier("product-hub.updates")
            }
            ProductCategoryChips(products: app.catalogue.products, selected: categoryFilter) { kind in
                withAnimation(.snappy) { categoryFilter = categoryFilter == kind ? nil : kind }
            }
            ProductRankedList(
                title: categoryFilter.map { "Top \($0.capitalized)" } ?? "Top modules",
                subtitle: "Ranked by availability and publisher",
                products: Array(app.catalogue.products.filter { categoryFilter == nil || $0.productKind == categoryFilter }.sorted { lhs, rhs in
                    (lhs.installable ? 0 : 1, lhs.name) < (rhs.installable ? 0 : 1, rhs.name)
                }.prefix(8)),
                installedIDs: app.catalogue.installedIDs,
                action: open
            )
            ProductShelf(
                title: "From Modula",
                subtitle: "Every module from the registry",
                products: visible,
                installedIDs: app.catalogue.installedIDs,
                action: open
            )
        } else {
            ProductShelf(title: "Results", products: visible, installedIDs: app.catalogue.installedIDs, action: open)
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

/// Chooses frontend bytes only when they are the verified release file.
/// Re-encoded JSON from the API envelope is not that file, even when it parses.
enum VerifiedFrontendSelection {
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let digest = value.lowercased()
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { return nil }
        return digest
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func choose(declaredSha256: String?, artifact: Data?, hosted: Data?) -> Data? {
        guard let declared = normalized(declaredSha256) else { return nil }
        if let artifact, sha256(artifact) == declared { return artifact }
        if let hosted, sha256(hosted) == declared { return hosted }
        return nil
    }
}
