import XCTest
@testable import Modula

/// MOL-03A: the canonical registry covers every Moliboo (001–100, Legends 101–115, and Series 2 drafts
/// 116–215), agrees with the native roster, keeps saved selections resolvable, and rejects broken data.
@MainActor
final class MOL03RegistryTests: XCTestCase {
    private func bundled() throws -> MolibooCharacterRegistry {
        try XCTUnwrap(MolibooRegistryStore.bundled, "moliboo_registry.json must ship in the app bundle")
    }

    func testBundledRegistryDecodesAndValidates() throws {
        let r = try bundled()
        let issues = MolibooRegistryValidator.validate(r)
        XCTAssertEqual(issues, [], issues.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(r.characters.count, 215)
        XCTAssertEqual(r.characters.filter { $0.number <= 100 }.count, 100)
        XCTAssertEqual(r.characters.filter { $0.familyId == "legends" }.count, 15)
        XCTAssertEqual(r.characters.filter { $0.availability == "draft" }.count, 100)
        XCTAssertEqual(r.characters.map(\.number), Array(1...215))
        XCTAssertEqual(Set(r.characters.map(\.id)).count, 215)
        XCTAssertEqual(Set(r.characters.map(\.number)).count, 215)
        XCTAssertEqual(Set(r.characters.map(\.key)).count, 215)
        XCTAssertEqual(Set(r.characters.map(\.packageId)).count, 215)
        XCTAssertTrue(r.characters.allSatisfy { !$0.purchasable })
    }

    func testRegistryMatchesNativeRoster() throws {
        let r = try bundled()
        let builtIn = r.characters.filter { $0.kind != nil }
        XCTAssertEqual(builtIn.count, ModulaMascotKind.allCases.count)
        XCTAssertEqual(builtIn.map(\.number), Array(1...115))
        XCTAssertEqual(ModulaMascotKind.allCases.map(\.number), Array(1...115), "built-in numbers stay 001–115")
        for kind in ModulaMascotKind.allCases {
            let c = try XCTUnwrap(r.character(key: kind.rawValue), "\(kind.rawValue) missing from registry")
            XCTAssertEqual(c.number, kind.number, kind.rawValue)
            XCTAssertEqual(c.id, kind.registryID, kind.rawValue)
            XCTAssertEqual(c.name, kind.name, kind.rawValue)
            XCTAssertEqual(c.familyId, kind.family.rawValue, kind.rawValue)
            XCTAssertEqual(c.title, kind.title, kind.rawValue)
            XCTAssertEqual(c.traits, kind.traits, kind.rawValue)
            XCTAssertEqual(c.wearable, kind.supportsWardrobe, kind.rawValue)
            XCTAssertEqual(c.kind, kind)
            XCTAssertEqual(c.baseAsset.hasPrefix("native2d:spec/"), kind.spec != nil, "\(kind.rawValue) base asset must resolve to its renderer")
        }
        for fam in MolibooFamily.allCases {
            let f = try XCTUnwrap(r.family(id: fam.rawValue), fam.rawValue)
            XCTAssertEqual(f.name, fam.name)
            XCTAssertEqual(f.range, [fam.range.lowerBound, fam.range.upperBound])
            XCTAssertEqual(r.characters(in: fam.rawValue).map(\.key), fam.kinds.map(\.rawValue))
        }
    }

    func testSavedSelectionsStillResolveAndRegistryNeverWritesDefaults() throws {
        let before = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("composer.mascot") || $0.hasPrefix("moliboo") }
        let r = try bundled()
        for kind in ModulaMascotKind.allCases {
            // Saved selections are stored as the kind raw value; that never changes, it only gains a registry id.
            XCTAssertEqual(ModulaMascotKind(rawValue: kind.rawValue), kind)
            XCTAssertEqual(r.character(key: kind.rawValue)?.kind, kind)
            _ = kind.registryEntry
        }
        let after = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("composer.mascot") || $0.hasPrefix("moliboo") }
        XCTAssertEqual(Set(before), Set(after), "reading the registry must not create or clear saved Moliboo state")
    }

    func testExpressionContractUsesSharedMoods() throws {
        let r = try bundled()
        XCTAssertEqual(r.expressionContract.states, MolibooSemanticExpression.allCases)
        for e in MolibooSemanticExpression.allCases {
            XCTAssertEqual(r.expressionContract.moodMap[e.rawValue], "\(e.mood)")
        }
        XCTAssertEqual(Set(r.animationPrimitives), Set(MolibooAnimationPrimitive.allCases))
    }

    func testEveryCharacterHasDistinctSignatureLineAndFamilyMotion() throws {
        let r = try bundled()
        let lines = r.characters.compactMap { $0.signature?.line }
        XCTAssertEqual(lines.count, 215)
        XCTAssertEqual(Set(lines).count, 215, "every Moliboo needs its own signature detail")
        for f in r.families {
            XCTAssertNotNil(r.motionProfiles[f.motionProfile])
            XCTAssertTrue(r.characters(in: f.id).allSatisfy { $0.motionProfile == f.motionProfile })
        }
        XCTAssertEqual(Set(r.families.map(\.motionProfile)).count, r.families.count, "each family has its own motion language")
    }

    func testLegendsAreNonWearableByDesign() throws {
        let r = try bundled()
        for c in r.characters(in: "legends") {
            XCTAssertFalse(c.wearable, c.key)
            XCTAssertNil(c.accessoryProfile, c.key)
            XCTAssertEqual(c.reactions["equip"]?.primitive, .glowIntensity, c.key)
        }
        XCTAssertTrue(r.characters.filter { $0.number <= 100 }.allSatisfy(\.wearable))
    }

    // MARK: Validator catches broken data

    func testValidatorRejectsBrokenRegistries() throws {
        let good = try bundled()
        func issues(_ edit: (inout MolibooCharacterRegistry) -> Void) -> [String] {
            var r = good; edit(&r); return MolibooRegistryValidator.validate(r).map(\.description)
        }
        XCTAssertFalse(issues { $0.characters[1].id = "moliboo.001" }.isEmpty, "duplicate id")
        XCTAssertFalse(issues { $0.characters[1].number = 1 }.isEmpty, "duplicate number")
        XCTAssertFalse(issues { $0.characters[5].familyId = "nope" }.isEmpty, "unknown family")
        XCTAssertFalse(issues { $0.characters.remove(at: 40) }.isEmpty, "numbering gap")
        XCTAssertFalse(issues { $0.characters[2].packageId = "moliboo.character.999" }.isEmpty, "package id mismatch")
        XCTAssertFalse(issues { $0.characters[3].expressions.removeLast() }.isEmpty, "missing expression")
        XCTAssertFalse(issues { $0.characters[4].reactions["tap"]?.mood = "rage" }.isEmpty, "unknown mood")
        XCTAssertFalse(issues { $0.characters[6].reactions.removeValue(forKey: "signature") }.isEmpty, "missing signature")
        XCTAssertFalse(issues { $0.characters[110].accessoryProfile = "fit/kringle" }.isEmpty, "legend with fit profile")
        XCTAssertFalse(issues { $0.characters[0].rendering = "3d" }.isEmpty, "3D must stay dormant")
        XCTAssertFalse(issues { $0.schemaVersion = "modula.moliboo.registry.99" }.isEmpty, "unsupported schema")
        XCTAssertFalse(issues { $0.characters[7].personality.energy = 1.4 }.isEmpty, "personality range")
        XCTAssertFalse(MolibooRegistryValidator.validate(good, fitProfiles: []).isEmpty, "unresolved fit profiles")
        XCTAssertFalse(issues { $0.motionProfiles["dreamers.drift"]?.reducedMotion.idle = [MolibooMotionStep(primitive: .translate, amplitude: 0.1, period: 2)] }.isEmpty, "Reduce Motion must not move the body")
    }

    /// The runtime is not limited to the shipped roster: a new family and a package-provided character validate.
    func testRegistryExtendsBeyondShippedRoster() throws {
        var r = try bundled()
        r.families.append(MolibooRegistryFamily(id: "future", name: "Moliboo Future", label: "Future", range: [216, 230], world: "Tomorrow", wearable: true, motionProfile: "future.glide"))
        var motion = try XCTUnwrap(r.motionProfiles["originals.bouncy"]); motion.familyId = "future"
        r.motionProfiles["future.glide"] = motion
        var c = r.characters[0]
        c.id = "moliboo.216"; c.number = 216; c.key = "novaling"; c.name = "Novaling"; c.familyId = "future"
        c.packageId = "moliboo.character.216"; c.baseAsset = "package:moliboo.character.216/base"; c.motionProfile = "future.glide"
        c.accessoryProfile = "fit/novaling"; c.reactions["signature"]?.line = "Novaling glides in"
        c.conceptId = nil
        r.characters.append(c)
        XCTAssertEqual(MolibooRegistryValidator.validate(r), [])
        XCTAssertNil(r.character(id: "moliboo.216")?.kind, "package-only characters have no built-in renderer kind")
    }

    /// Series 2 is appended after Legends. Concept 101 is #116; concept 200 is #215. Nothing is renumbered or sold.
    func testSeries2DraftsDoNotCollideWithOriginalsOrLegends() throws {
        let r = try bundled()
        let originals = r.characters.filter { $0.number <= 100 }
        let legends = r.characters(in: "legends")
        let series2 = r.characters.filter { MolibooRegistryValidator.series2Range.contains($0.number) }
        XCTAssertEqual(originals.map(\.number), Array(1...100))
        XCTAssertEqual(legends.map(\.number), Array(101...115))
        XCTAssertEqual(legends.map(\.key), ["kringle", "sasqui", "lochie", "yetti", "krakie", "pyra", "unika", "gryff", "frostie", "pearli", "kitsu", "chupi", "motho", "jacko", "thundra"])
        XCTAssertEqual(series2.map(\.number), Array(116...215))
        XCTAssertEqual(series2.count, 100)
        XCTAssertTrue(series2.allSatisfy { $0.availability == "draft" && !$0.purchasable && $0.kind == nil && !$0.wearable })
        XCTAssertTrue(series2.allSatisfy { $0.baseAsset.hasPrefix("package:") })
        XCTAssertTrue(originals.allSatisfy { $0.availability == "released" && $0.conceptId == nil && $0.kind != nil })
        XCTAssertTrue(legends.allSatisfy { $0.availability == "released" && $0.conceptId == nil && !$0.wearable })
        let brinlo = try XCTUnwrap(r.character(number: 116))
        XCTAssertEqual(brinlo.key, "brinlo")
        XCTAssertEqual(brinlo.conceptId, "moliboo.concept.101")
        XCTAssertEqual(brinlo.familyId, "tideborn")
        XCTAssertEqual(brinlo.name, "Brinlo")
        let jubilo = try XCTUnwrap(r.character(number: 215))
        XCTAssertEqual(jubilo.key, "jubilo")
        XCTAssertEqual(jubilo.conceptId, "moliboo.concept.200")
        XCTAssertEqual(jubilo.familyId, "lantern-parade")
        let expected: [(String, ClosedRange<Int>)] = [
            ("tideborn", 116...125), ("skyweavers", 126...135), ("cinderlings", 136...145),
            ("mosslight-grove", 146...155), ("aurora-vale", 156...165), ("clocklings", 166...175),
            ("sugarvale", 176...185), ("inkbound-atelier", 186...195), ("neon-arcade", 196...205),
            ("lantern-parade", 206...215),
        ]
        let draftFamilies = r.families.filter { $0.series == 2 }
        XCTAssertEqual(draftFamilies.map(\.id), expected.map(\.0))
        for (fam, range) in expected {
            let f = try XCTUnwrap(r.family(id: fam))
            XCTAssertEqual(f.range, [range.lowerBound, range.upperBound])
            XCTAssertEqual(f.availability, "draft")
            XCTAssertEqual(f.series, 2)
            XCTAssertFalse(f.wearable)
            XCTAssertEqual(r.characters(in: fam).map(\.number), Array(range))
            XCTAssertEqual(MolibooRegistryValidator.isHexColor(f.accentHex ?? ""), true)
        }
        XCTAssertEqual(r.families.filter { $0.series == 1 }.map(\.id), ["originals", "angels", "underground", "enchanted", "stardust", "dreamers", "legends"])
        // Searching the old concept number must not return the Series 2 character.
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: nil, search: "101", families: r.families).map(\.key), ["kringle"])
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: nil, search: "116", families: r.families).map(\.key), ["brinlo"])
        XCTAssertFalse(try issues { if let i = $0.characters.firstIndex(where: { $0.number == 116 }) { $0.characters[i].purchasable = true } }.isEmpty, "a draft cannot be purchasable")
        XCTAssertFalse(try issues { if let i = $0.characters.firstIndex(where: { $0.number == 116 }) { $0.characters[i].conceptId = "moliboo.concept.116" } }.isEmpty, "concept 116 would be catalogue 131, not 116")
        XCTAssertFalse(try issues { if let i = $0.characters.firstIndex(where: { $0.number == 1 }) { $0.characters[i].number = 116; $0.characters[i].id = "moliboo.116" } }.isEmpty, "cannot collide with Series 2")
    }

    private func issues(_ edit: (inout MolibooCharacterRegistry) -> Void) throws -> [String] {
        var r = try bundled(); edit(&r); return MolibooRegistryValidator.validate(r).map(\.description)
    }

    // MOL-03D: the collection browser filters by family and search across the whole catalogue.
    func testCatalogueFilterAndSearch() throws {
        let r = try XCTUnwrap(MolibooRegistryStore.bundled)
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: nil, search: "", families: r.families).count, 215)
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: "legends", search: "", families: r.families).count, 15)
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: "originals", search: "", families: r.families).count, 25)
        let somna = MolibooCatalogueQuery.filter(r.characters, family: nil, search: "somna", families: r.families)
        XCTAssertEqual(somna.map(\.number), [100])
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: nil, search: "043", families: r.families).map(\.key), ["nyx"])
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: nil, search: "Moliboo Legends", families: r.families).count, 15)
        XCTAssertTrue(MolibooCatalogueQuery.filter(r.characters, family: "angels", search: "somna", families: r.families).isEmpty)
    }

    // MOL-03B developer fitting lab: live overrides are Debug-only and fully reversible.
    func testDebugFitLabOverrideIsReversible() throws {
        let k = ModulaMascotKind.somna
        let base = try XCTUnwrap(k.builtInSpec).hatScale
        MolibooPackageRuntime.shared.setDebugFit(.init(hatScale: 1.3, hatMaxWidth: 0.5, headTopExtra: 0.05), for: k)
        XCTAssertEqual(k.spec?.hatScale, 1.3)
        XCTAssertEqual(k.spec?.hatMaxWidth, 0.5)
        MolibooPackageRuntime.shared.setDebugFit(nil, for: k)
        XCTAssertEqual(k.spec?.hatScale, base)
        XCTAssertNil(MolibooPackageRuntime.shared.debugFit(for: k))
    }
}
