import XCTest
import UIKit
@testable import Modula

@MainActor
final class MOL03WardrobeTests: XCTestCase {
    private let cap = MolibooCosmetics.signatureCapID
    private var store: MascotWardrobeStore { .shared }
    private var original: MascotOutfit = .empty
    private var presetIDs: Set<String> = []

    override func setUp() async throws {
        original = store.outfit
        presetIDs = Set(store.presets.map(\.id))
        store.clearOutfit()
    }
    override func tearDown() async throws {
        for p in store.presets where !presetIDs.contains(p.id) { store.deletePreset(p) }
        store.apply(original)
    }

    func testCatalogIDsUniqueAndCapStaysSeparateFromPartyHat() throws {
        let ids = MascotWardrobeCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "wardrobe IDs must stay unique")
        let c = try XCTUnwrap(MascotWardrobeCatalog.item(id: cap))
        let party = try XCTUnwrap(MascotWardrobeCatalog.item(id: "hat.party"))
        XCTAssertNotEqual(c.id, party.id)
        XCTAssertEqual(c.slot, .hat); XCTAssertEqual(party.slot, .hat)
        XCTAssertEqual(cap, "cap.moliboo.signature")
    }

    func testSearchAndFilters() {
        let all = MascotWardrobeCatalog.all
        var q = MolibooWardrobeQuery(text: "party")
        let r = q.filter(all, owns: { _ in true }, supports3D: { _ in false }).map(\.id)
        XCTAssertTrue(r.contains("hat.party")); XCTAssertFalse(r.contains(cap))
        q = MolibooWardrobeQuery(text: "signature")
        XCTAssertEqual(q.filter(all, owns: { _ in true }, supports3D: { _ in false }).map(\.id), [cap])
        q = MolibooWardrobeQuery(slot: .hat)
        XCTAssertTrue(q.filter(all, owns: { _ in true }, supports3D: { _ in false }).allSatisfy { $0.slot == .hat })
        q = MolibooWardrobeQuery(ownership: .owned)
        let owned = q.filter(all, owns: { if case .free = $0.unlock { return true }; return false }, supports3D: { _ in false })
        XCTAssertFalse(owned.isEmpty); XCTAssertTrue(owned.count < all.count)
        q = MolibooWardrobeQuery(only3D: true)
        XCTAssertEqual(q.filter(all, owns: { _ in true }, supports3D: { $0 == self.cap }).map(\.id), [cap])
    }

    func testPreviewApplyUndoAndSlotSwap() throws {
        let s = MolibooWardrobeSession(store: store)
        let c = try XCTUnwrap(MascotWardrobeCatalog.item(id: cap))
        let party = try XCTUnwrap(MascotWardrobeCatalog.item(id: "hat.party"))
        s.tryOn(c)
        XCTAssertEqual(s.previewIDs, [cap]); XCTAssertTrue(s.isPreviewing)
        XCTAssertTrue(store.outfit.isEmpty, "preview must not touch the saved outfit")
        s.tryOn(party)   // same slot: replaces, never merges
        XCTAssertEqual(s.previewIDs, ["hat.party"])
        s.revert(); XCTAssertTrue(s.previewIDs.isEmpty)
        s.tryOn(c); s.apply()
        XCTAssertEqual(store.outfit.equippedIDs, [cap]); XCTAssertFalse(s.isPreviewing)
        s.tryOn(party); s.apply()
        XCTAssertEqual(store.outfit.equippedIDs, ["hat.party"])
        s.undo()
        XCTAssertEqual(store.outfit.equippedIDs, [cap]); XCTAssertEqual(s.previewIDs, [cap])
    }

    func testSavedOutfitsRoundTrip() throws {
        let s = MolibooWardrobeSession(store: store)
        let c = try XCTUnwrap(MascotWardrobeCatalog.item(id: cap))
        s.tryOn(c)
        let n = store.presets.count
        s.save(named: "MOL03 cap look")
        XCTAssertEqual(store.presets.count, n + 1)
        XCTAssertEqual(store.outfit.equippedIDs, [cap], "saving applies the previewed look")
        store.clearOutfit(); s.resync()
        let p = try XCTUnwrap(store.presets.first { $0.name == "MOL03 cap look" })
        s.load(p)
        XCTAssertEqual(store.outfit.equippedIDs, [cap])
    }

    func testUnownedItemsArePreviewOnly() throws {
        guard !MascotEntitlements.isPremium else { throw XCTSkip("premium entitlement owns everything") }
        let locked = try XCTUnwrap(MascotWardrobeCatalog.all.first { !store.owns($0) })
        let s = MolibooWardrobeSession(store: store)
        s.tryOn(locked)
        XCTAssertTrue(s.isPreviewing); XCTAssertEqual(s.blocked.map(\.id), [locked.id]); XCTAssertFalse(s.canApply)
        s.apply()
        XCTAssertTrue(store.outfit.isEmpty, "ownership is enforced on apply")
        s.save(named: "nope")
        XCTAssertFalse(store.presets.contains { $0.name == "nope" })
    }

    func testPhotoSubjectDetection() {
        func img(blob: Bool) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 300, height: 600)).image { ctx in
                let g = CGGradient(colorsSpace: nil, colors: [UIColor.systemTeal.cgColor, UIColor.white.cgColor] as CFArray, locations: nil)!
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 600), options: [])
                if blob { UIColor.systemPink.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 90, y: 230, width: 120, height: 120)) }
            }
        }
        XCTAssertFalse(MolibooPhotoCapture.showsSubject(img(blob: false)))
        XCTAssertTrue(MolibooPhotoCapture.showsSubject(img(blob: true)))
    }

    /// Device crash regression: concurrent premium loads must share one NSBundleResourceRequest begin.
    @MainActor
    func testConcurrentPremiumPackRequestsBeginOnce() async throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        async let a = MolibooWardrobeAssets.ensurePremium()
        async let b = MolibooWardrobeAssets.ensurePremium()
        async let c = MolibooWardrobeAssets.ensurePremium()
        async let d = MolibooWardrobeAssets.ensurePremium()
        async let e = MolibooWardrobeAssets.ensurePremium()
        async let f = MolibooWardrobeAssets.ensurePremium()
        let results = await [a, b, c, d, e, f]
        XCTAssertEqual(results.count, 6)
        XCTAssertEqual(Set(results).count, 1, "all callers must see the same outcome")
    }
}

