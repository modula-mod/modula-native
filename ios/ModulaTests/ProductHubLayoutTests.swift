import XCTest
@testable import Modula

final class ProductHubLayoutTests: XCTestCase {
    func testFeaturedPrefersAnInstallableModuleYouDoNotHave() {
        let notes = product("digital.modula.vault-notes", name: "Vault Notes", installable: true)
        let echo = product("digital.modula.basic-echo", name: "Basic Echo", installable: true)
        let featured = ProductHubCatalogue.featured(in: [notes, echo], installed: [notes.id])
        XCTAssertEqual(featured?.moduleId, echo.moduleId)
    }

    func testFeaturedFallsBackToVaultNotesWhenEverythingInstallableIsInstalled() {
        let notes = product("digital.modula.vault-notes", name: "Vault Notes", installable: true)
        let echo = product("digital.modula.basic-echo", name: "Basic Echo", installable: false)
        let featured = ProductHubCatalogue.featured(in: [echo, notes], installed: [notes.id])
        XCTAssertEqual(featured?.moduleId, notes.moduleId)
    }

    func testUpdatesRequireBothVersionsAndANewerRegistryRelease() {
        let notes = product("digital.modula.vault-notes", name: "Vault Notes", installable: true, version: "2.0.2")
        let same = product("digital.modula.basic-echo", name: "Basic Echo", installable: true, version: "1.0.0")
        let unknown = product("digital.modula.browser", name: "Browser", installable: true, version: nil)
        let installations = [
            notes.id: ModuleInstallation(moduleId: notes.id, status: "enabled", version: "2.0.0"),
            same.id: ModuleInstallation(moduleId: same.id, status: "enabled", version: "1.0.0"),
            unknown.id: ModuleInstallation(moduleId: unknown.id, status: "enabled", version: nil),
        ]
        let updates = ProductHubCatalogue.updates(products: [notes, same, unknown], installations: installations)
        XCTAssertEqual(updates.map(\.moduleId), [notes.moduleId])
    }

    func testPurposesComeOnlyFromCatalogueKinds() {
        let products = [
            product("a", name: "A", kind: "module"),
            product("b", name: "B", kind: "module"),
            product("c", name: "C", kind: "game"),
        ]
        let purposes = ProductHubCatalogue.purposes(in: products)
        XCTAssertEqual(purposes.map(\.kind), ["module", "game"])
        XCTAssertEqual(purposes.map(\.count), [2, 1])
        XCTAssertFalse(purposes.contains { $0.title == "Entertainment" })
    }

    func testComingSoonIsOnlyNotInstallable() {
        let ready = product("a", name: "A", installable: true)
        let later = product("b", name: "B", installable: false)
        XCTAssertEqual(ProductHubCatalogue.comingSoon([ready, later]).map(\.id), [later.id])
    }

    func testQueryMatchesNameAndIgnoresOtherKinds() {
        let notes = product("digital.modula.vault-notes", name: "Vault Notes", kind: "module")
        let game = product("digital.modula.game", name: "Vault Game", kind: "game")
        let matched = ProductHubCatalogue.matching([notes, game], query: "vault", kind: "module")
        XCTAssertEqual(matched.map(\.id), [notes.id])
    }

    private func product(_ id: String, name: String, kind: String = "module", installable: Bool = true, version: String? = "1.0.0") -> CatalogueProduct {
        CatalogueProduct(
            moduleId: id,
            productKind: kind,
            name: name,
            description: "\(name) description",
            publisherId: "modula",
            publisherName: "Modula",
            latestVersion: version,
            status: "published",
            installable: installable,
            platforms: ["ios"],
            betaClassification: nil,
            installability: nil
        )
    }
}
