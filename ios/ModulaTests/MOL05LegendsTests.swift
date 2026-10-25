import XCTest
import SwiftUI
@testable import Modula

/// Family 007 — Legends: numbering, the untouched canonical 001–100 roster, and the non-wearable rule.
@MainActor
final class MOL05LegendsTests: XCTestCase {
    /// The canonical roster in catalogue order. Must never be renumbered or reordered.
    private static let canonical: [String] = [
        "pip", "moss", "nimbus", "mochi", "sprout", "ember", "tuck", "bloop", "bun", "pebble", "tofu", "comet", "puff", "bolt", "glim",
        "echo", "quill", "orbit", "prism", "wisp", "doodle", "chime", "rolo", "pogo", "fable",
        "aura", "soli", "luma", "vela", "cheri", "hush", "haloa", "lyra", "celio", "dovee", "twila", "gleam", "novael", "sera", "auri",
        "riff", "graff", "nyx", "zip", "vex", "koda", "glitch", "jinx", "static", "holo", "fuse", "skid", "mica", "rumble", "flick",
        "bramble", "ferni", "truffle", "rootle", "willow", "pollen", "mallow", "acora", "spindle", "glade", "lichen", "thimble", "wyrmi", "kiko", "eldra",
        "astra", "nebbi", "quori", "vesper", "pulsa", "stellan", "cosmi", "eclipa", "meteo", "asteri", "zenith", "liora", "nocta", "glint", "polaris",
        "dozi", "lulli", "moona", "nuzzle", "drifty", "hushby", "swayla", "snoomi", "velvi", "minku", "tufti", "winkle", "sonata", "comfi", "somna",
    ]
    private static let legends: [String] = ["kringle", "sasqui", "lochie", "yetti", "krakie", "pyra", "unika", "gryff", "frostie", "pearli", "kitsu", "chupi", "motho", "jacko", "thundra"]

    // MARK: Roster

    func testCanonicalRosterIDsAndNumbersUnchanged() {
        XCTAssertEqual(Self.canonical.count, 100)
        for (i, raw) in Self.canonical.enumerated() {
            let kind = try? XCTUnwrap(ModulaMascotKind(rawValue: raw), raw)
            XCTAssertEqual(kind?.number, i + 1, raw)
            XCTAssertEqual(kind?.catalogueNumber, String(format: "%03d", i + 1), raw)
            XCTAssertEqual(kind?.supportsWardrobe, true, "\(raw) must keep the wardrobe")
        }
        XCTAssertEqual(Array(ModulaMascotKind.allCases.prefix(100).map(\.rawValue)), Self.canonical, "001–100 keep their order")
        XCTAssertEqual(MolibooFamily.originals.range, 1...25)
        XCTAssertEqual(MolibooFamily.angels.range, 26...40)
        XCTAssertEqual(MolibooFamily.underground.range, 41...55)
        XCTAssertEqual(MolibooFamily.enchanted.range, 56...70)
        XCTAssertEqual(MolibooFamily.stardust.range, 71...85)
        XCTAssertEqual(MolibooFamily.dreamers.range, 86...100)
        for fam in MolibooFamily.allCases where fam != .legends {
            XCTAssertEqual(fam.kinds.map(\.number), Array(fam.range), fam.rawValue)
            XCTAssertTrue(fam.supportsWardrobe, fam.rawValue)
        }
    }

    func testLegendsFamilyIsNumbered101To115() {
        XCTAssertEqual(MolibooFamily.allCases.count, 7)
        XCTAssertEqual(MolibooFamily.legends.range, 101...115)
        XCTAssertEqual(MolibooFamily.legends.label, "Legends")
        XCTAssertEqual(MolibooFamily.legends.name, "Moliboo Legends")
        XCTAssertFalse(MolibooFamily.legends.supportsWardrobe)
        let kinds = MolibooFamily.legends.kinds
        XCTAssertEqual(kinds.map(\.rawValue), Self.legends)
        XCTAssertEqual(kinds.map(\.number), Array(101...115))
        XCTAssertEqual(ModulaMascotKind.allCases.count, 115)
        XCTAssertEqual(Set(ModulaMascotKind.allCases.map(\.number)).count, 115, "numbers are unique")
        XCTAssertEqual(Set(ModulaMascotKind.allCases.map(\.name)).count, 115, "names are unique")
        for k in kinds {
            XCTAssertEqual(k.family, .legends)
            XCTAssertFalse(k.supportsWardrobe, k.rawValue)
            XCTAssertNotNil(k.spec, "\(k.rawValue) is drawn by the 2D parts kit")
            XCTAssertFalse(k.title.isEmpty)
            XCTAssertFalse(k.shortPersonality.isEmpty)
        }
        XCTAssertEqual(ModulaMascotKind.kringle.shortPersonality, "Santa Claus")
        XCTAssertEqual(ModulaMascotKind.sasqui.shortPersonality, "Bigfoot")
        XCTAssertEqual(ModulaMascotKind.lochie.shortPersonality, "Loch Ness monster")
    }

    // MARK: Non-wearable rule

    func testLegendRigFitsNoWornItem() {
        for k in MolibooFamily.legends.kinds {
            let rig = MascotRig.stock(k)
            XCTAssertTrue(rig.wearsOwnLook, k.rawValue)
            for item in MascotWardrobeCatalog.all {
                if item.slot == .background {
                    XCTAssertTrue(item.fit(on: rig).isWearable, "\(item.id) scene stays behind \(k.rawValue)")
                } else {
                    XCTAssertFalse(item.fit(on: rig).isWearable, "\(item.id) must not fit \(k.rawValue)")
                }
            }
            XCTAssertTrue(Self.fullOutfit.wearables(on: rig).isEmpty, k.rawValue)
        }
        XCTAssertFalse(MascotRig.stock(.pip).wearsOwnLook)
        XCTAssertFalse(Self.fullOutfit.wearables(on: MascotRig.stock(.pip)).isEmpty)
    }

    func testRendererIgnoresEquippedItemsForLegends() {
        let outfit = Self.fullOutfit
        for k in MolibooFamily.legends.kinds {
            XCTAssertTrue(ModulaMascotFigure(kind: k, pose: .still(), size: 48, outfit: outfit).worn.isEmpty, k.rawValue)
        }
        XCTAssertEqual(ModulaMascotFigure(kind: .pip, pose: .still(), size: 48, outfit: outfit).worn, outfit)
        XCTAssertFalse(MascotSelection.stock(.kringle).supportsWardrobe)
        XCTAssertTrue(MascotSelection.stock(.pip).supportsWardrobe)
    }

    func testMergeKeepsWornSlotsForLegends() {
        let current = MascotOutfit(items: ["hat": "hat.beanie", "top": "top.tee"], dyes: ["hat": 2])
        let next = MascotOutfit(items: ["face": "face.blush", "background": "bg.night"])
        let merged = MascotWardrobeStore.merged(next, onto: current, supportsWardrobe: false)
        XCTAssertEqual(merged.items, ["hat": "hat.beanie", "top": "top.tee", "background": "bg.night"])
        XCTAssertEqual(merged.dyes["hat"], 2)
        XCTAssertEqual(MascotWardrobeStore.merged(next, onto: current, supportsWardrobe: true), next)
        XCTAssertTrue(MascotWardrobeStore.editable(.background, supportsWardrobe: false))
        XCTAssertFalse(MascotWardrobeStore.editable(.hat, supportsWardrobe: false))
        XCTAssertTrue(MascotWardrobeStore.editable(.hat, supportsWardrobe: true))
    }

    /// With a Legend selected, nothing worn is applied, changed or cleared, and the saved outfit survives intact.
    func testStoreNeverAppliesItemsWhileALegendIsSelected() throws {
        let defaults = UserDefaults.standard
        let key = ModulaMascotSettings.kindKey
        let previousKind = defaults.string(forKey: key)
        let store = MascotWardrobeStore.shared
        let hat = try XCTUnwrap(MascotWardrobeCatalog.item(id: "hat.beanie"))
        let tee = try XCTUnwrap(MascotWardrobeCatalog.item(id: "top.tee"))
        defer {
            if let previousKind { defaults.set(previousKind, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        // A wardrobe Moliboo wears a hat (durable user data).
        defaults.set(ModulaMascotKind.pip.rawValue, forKey: key)
        let original = store.outfit
        store.equip(hat)
        XCTAssertTrue(store.outfit.contains(hat))
        let saved = store.outfit

        // Switching to a Legend never clears it…
        defaults.set(ModulaMascotKind.kringle.rawValue, forKey: key)
        XCTAssertFalse(store.selectionSupportsWardrobe)
        XCTAssertEqual(store.outfit, saved)

        // …and nothing can be put on, changed or taken off.
        store.equip(tee)
        store.toggle(hat)
        store.unequip(.hat)
        store.setDye(1, for: .hat)
        store.randomize(for: MascotRig.stock(.kringle))
        store.applyPreset(MascotOutfitPreset(id: "t", name: "t", outfit: MascotOutfit(items: ["top": "top.tee"]), createdAt: Date()))
        store.apply(MascotOutfit(items: ["top": "top.tee"]))
        store.clearOutfit()
        let presets = store.presets.count
        store.savePreset(named: "Legend")
        XCTAssertEqual(store.presets.count, presets, "no outfit is saved from a Legend")
        XCTAssertFalse(store.applyOutfitOfTheDayIfNeeded())
        XCTAssertEqual(store.outfit, saved, "worn slots are untouched while a Legend is selected")

        // Back on a wardrobe Moliboo, the outfit is exactly as it was.
        defaults.set(ModulaMascotKind.pip.rawValue, forKey: key)
        XCTAssertTrue(store.selectionSupportsWardrobe)
        XCTAssertTrue(store.outfit.contains(hat))
        store.apply(original)
    }

    private static var fullOutfit: MascotOutfit {
        var o = MascotOutfit.empty
        for slot in MascotWardrobeSlot.allCases where slot != .background {
            if let item = MascotWardrobeCatalog.items(in: slot).first { o.equip(item) }
        }
        return o
    }
}
