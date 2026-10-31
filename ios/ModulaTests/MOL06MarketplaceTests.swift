import XCTest
@testable import Modula

/// Series 2 marketplace: local drafts only. No prices, no sales, no server catalogue.
final class MOL06MarketplaceTests: XCTestCase {
    private func registry() throws -> MolibooCharacterRegistry {
        try XCTUnwrap(MolibooRegistryStore.bundled)
    }

    func testMarketplaceListsOnlyNonPurchasableDrafts() throws {
        let registry = try registry()
        let drafts = MolibooMarketplaceFacts.drafts(in: registry)
        XCTAssertEqual(drafts.map(\.number), Array(116...215))
        XCTAssertTrue(drafts.allSatisfy { $0.availability == "draft" && !$0.purchasable })
        XCTAssertEqual(MolibooMarketplaceFacts.families(in: registry).count, 10)
        XCTAssertFalse(MolibooMarketplaceFacts.purchaseTitle.isEmpty)
        XCTAssertTrue(MolibooMarketplaceFacts.purchaseReason.contains("nothing") || MolibooMarketplaceFacts.purchaseReason.contains("Nothing") || MolibooMarketplaceFacts.purchaseReason.lowercased().contains("no moliboo"))
        XCTAssertFalse(MolibooMarketplaceFacts.stickersReason.isEmpty)
        let tideborn = MolibooMarketplaceFacts.showing(drafts, family: "tideborn", search: "", families: registry.families)
        XCTAssertEqual(tideborn.map(\.number), Array(116...125))
        XCTAssertEqual(MolibooMarketplaceFacts.showing(drafts, family: nil, search: "brinlo", families: registry.families).map(\.key), ["brinlo"])
        XCTAssertTrue(MolibooMarketplaceFacts.showing(drafts, family: nil, search: "101", families: registry.families).isEmpty, "concept number 101 is Kringle, not a Series 2 draft")
    }

    func testInstalledPortraitIsReadWholeAndTraversalIsRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moliboo-market-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MolibooPackageStore(root: root)
        let package = "moliboo.character.116"
        let dir = store.versionDir(package, "0.1.0")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bytes = Data("full-portrait".utf8)
        try bytes.write(to: dir.appendingPathComponent("portrait.png"))
        try store.writeIndex(MolibooPackageIndex(packageId: package, active: "0.1.0", previous: nil, history: ["0.1.0"]))
        XCTAssertEqual(store.activeMedia(packageId: package, path: "portrait.png"), bytes)
        XCTAssertNil(store.activeMedia(packageId: package, path: "../portrait.png"))
        XCTAssertNil(store.activeMedia(packageId: package, path: "/etc/passwd.png"))
        XCTAssertNil(store.activeMedia(packageId: "moliboo.character.117", path: "portrait.png"))
    }
}
