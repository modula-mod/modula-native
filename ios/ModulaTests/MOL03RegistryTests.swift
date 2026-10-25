import XCTest
@testable import Modula

/// MOL-03A: the canonical registry covers every Moliboo (001–100 plus Legends 101–115), agrees with the native
/// roster, keeps saved selections resolvable, and rejects broken data.
@MainActor
final class MOL03RegistryTests: XCTestCase {
    private func bundled() throws -> MolibooCharacterRegistry {
        try XCTUnwrap(MolibooRegistryStore.bundled, "moliboo_registry.json must ship in the app bundle")
    }

    func testBundledRegistryDecodesAndValidates() throws {
        let r = try bundled()
        let issues = MolibooRegistryValidator.validate(r)
        XCTAssertEqual(issues, [], issues.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(r.characters.count, 115)
        XCTAssertEqual(r.characters.filter { $0.number <= 100 }.count, 100)
        XCTAssertEqual(r.characters.filter { $0.familyId == "legends" }.count, 15)
        XCTAssertEqual(r.characters.map(\.number), Array(1...115))
        XCTAssertEqual(Set(r.characters.map(\.id)).count, 115)
    }

    func testRegistryMatchesNativeRoster() throws {
        let r = try bundled()
        XCTAssertEqual(r.characters.count, ModulaMascotKind.allCases.count)
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
        XCTAssertEqual(lines.count, 115)
        XCTAssertEqual(Set(lines).count, 115, "every Moliboo needs its own signature detail")
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
        r.families.append(MolibooRegistryFamily(id: "future", name: "Moliboo Future", label: "Future", range: [116, 130], world: "Tomorrow", wearable: true, motionProfile: "future.glide"))
        var motion = try XCTUnwrap(r.motionProfiles["originals.bouncy"]); motion.familyId = "future"
        r.motionProfiles["future.glide"] = motion
        var c = r.characters[0]
        c.id = "moliboo.116"; c.number = 116; c.key = "novaling"; c.name = "Novaling"; c.familyId = "future"
        c.packageId = "moliboo.character.116"; c.baseAsset = "package:moliboo.character.116/base"; c.motionProfile = "future.glide"
        c.accessoryProfile = "fit/novaling"; c.reactions["signature"]?.line = "Novaling glides in"
        r.characters.append(c)
        XCTAssertEqual(MolibooRegistryValidator.validate(r), [])
        XCTAssertNil(r.character(id: "moliboo.116")?.kind, "package-only characters have no built-in renderer kind")
    }

    // MOL-03D: the collection browser filters by family and search across all 115.
    func testCatalogueFilterAndSearch() throws {
        let r = try XCTUnwrap(MolibooRegistryStore.bundled)
        XCTAssertEqual(MolibooCatalogueQuery.filter(r.characters, family: nil, search: "", families: r.families).count, 115)
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
