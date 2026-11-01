import XCTest
@testable import Modula

final class EdgePickerPreferencesTests: XCTestCase {
    func testDefaultsAreCanonical() {
        let prefs = EdgePickerPreferences.default
        XCTAssertEqual(prefs.position, .middle)
        XCTAssertEqual(prefs.size, .standard)
        XCTAssertEqual(prefs.side, .right)
        XCTAssertEqual(prefs.labelBehavior, .onChange)
        XCTAssertEqual(prefs.glassIntensity, .standard)
        XCTAssertEqual(prefs.visibility, .always)
        XCTAssertEqual(prefs.motion, .followAppearance)
        XCTAssertEqual(prefs.haptics, .followAppearance)
    }

    @MainActor
    func testResetEdgePickerDoesNotResetTheme() {
        let defaults = UserDefaults(suiteName: "modula.edge-picker.test.\(UUID().uuidString)")!
        let store = AppearanceStore(defaults: defaults)
        store.theme = .dark
        store.accent = .ocean
        store.edgePicker.size = .large
        store.edgePicker.side = .left
        store.resetEdgePicker()
        XCTAssertEqual(store.theme, .dark)
        XCTAssertEqual(store.accent, .ocean)
        XCTAssertEqual(store.edgePicker, .default)
    }

    @MainActor
    func testLegacySnapshotMigratesMissingEdgePicker() throws {
        let defaults = UserDefaults(suiteName: "modula.edge-picker.migrate.\(UUID().uuidString)")!
        // Encode a v2-shaped blob without edgePicker via a minimal JSON object.
        let legacy = """
        {"theme":"light","darkStyle":"standard","accent":"modulaTeal","fontFamily":"system","textSize":"standard","appIcon":"default","density":"standard","motion":"standard","haptics":"standard","contrastTransparency":"standard","iconStyle":"balanced","interfaceShape":"balanced","moduleBranding":"blend"}
        """.data(using: .utf8)!
        defaults.set(legacy, forKey: "modula.native.appearance.v2")
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.theme, .light)
        XCTAssertEqual(store.edgePicker, .default)
    }
}

final class ModulaSurfaceSystemTests: XCTestCase {
    func testMaterialAndShapeTokensExist() {
        XCTAssertEqual(ModulaMaterial.allCases.count, 8)
        XCTAssertEqual(ModulaShapeRole.allCases.count, 8)
        XCTAssertGreaterThan(ModulaShapeRole.contentCard.radius(for: .soft), ModulaShapeRole.contentCard.radius(for: .precise))
        XCTAssertEqual(ModulaShapeRole.capsule.radius(for: .balanced), 999)
    }

    func testTrailingSafeAreaSeparatesLoopAndActionRail() {
        XCTAssertGreaterThanOrEqual(TrailingInteractionSafeArea.edgeLoop, 46)
        XCTAssertGreaterThanOrEqual(TrailingInteractionSafeArea.postActionRail, 44)
        XCTAssertGreaterThan(TrailingInteractionSafeArea.contentClearance, 0)
    }

    func testCountFormatDoesNotInventZero() {
        XCTAssertNil(ModulaCountFormat.compact(0))
        XCTAssertEqual(ModulaCountFormat.compact(368), "368")
        XCTAssertEqual(ModulaCountFormat.compact(1_280), "1.3K")
        XCTAssertEqual(ModulaCountFormat.compact(24_600), "24.6K")
    }
}

final class N4GChromeContractTests: XCTestCase {
    func testHomeActivityProfileKeepEdgeLoopWithoutDuplicateTabs() {
        XCTAssertTrue(ShellChromePolicy.policy(for: .home(.following)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .activity(.all)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .me(.overview)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .discover(.trending)).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .settings(.appearance(.typography))).contextRailVisible)
        XCTAssertFalse(ShellChromePolicy.policy(for: .productHub(.featured)).contextRailVisible)
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["home", "discover", "modules", "activity", "profile"])
    }

    func testProfileLoopStaysOnFrozenSections() {
        XCTAssertEqual(Array(ProfileSection.allCases.prefix(3)), [.overview, .posts, .modules])
        XCTAssertEqual(HomeMode.allCases, [.following, .forYou, .modules])
        XCTAssertEqual(ActivityMode.allCases, [.all, .mentions, .requests])
    }

    func testFontSamplesCoverUsefulGlyphs() {
        XCTAssertEqual(FontSampleKind.allCases.map(\.id), ["letters", "numbers", "body", "symbols"])
        XCTAssertEqual(FontSampleKind.letters.label, "Letters")
        XCTAssertEqual(FontSampleKind.numbers.label, "Numbers")
    }

    func testOnboardingStillHasFiveStepsAndThreeValueRows() {
        XCTAssertEqual(OnboardingStep.count, 5)
        XCTAssertLessThanOrEqual(OnboardingStep.world.points.count, 3)
        XCTAssertEqual(OnboardingStep.world.next, .profile)
        XCTAssertNil(OnboardingStep.control.next)
    }
}
