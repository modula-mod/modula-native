import XCTest
@testable import Modula

final class EdgeLoopEngineTests: XCTestCase {
    func testLoopingWrapsInBothDirections() {
        var engine = EdgeLoopEngine(itemCount: 3, behavior: .looping, selectedIndex: 0)
        XCTAssertEqual(engine.index(offsetBy: -1), 2)
        XCTAssertEqual(engine.index(offsetBy: 1), 1)
        engine.setSelectedIndex(2, expandingLabel: false)
        XCTAssertEqual(engine.index(offsetBy: 1), 0)
    }

    func testBoundedDoesNotWrap() {
        let engine = EdgeLoopEngine(itemCount: 3, behavior: .bounded, selectedIndex: 0)
        XCTAssertEqual(engine.index(offsetBy: -1), 0)
        XCTAssertEqual(engine.index(offsetBy: 4), 2)
    }

    func testDragProposesNearestItemWithoutCommittingUntilEnd() {
        var engine = EdgeLoopEngine(itemCount: 3, behavior: .looping, selectedIndex: 0)
        engine.beginDrag()
        XCTAssertEqual(engine.phase, .dragging)
        XCTAssertEqual(engine.selectedIndex, 0)
        let crossed = engine.updateDrag(translation: -EdgeLoopEngine.itemStride)
        XCTAssertTrue(crossed)
        XCTAssertEqual(engine.proposedIndex, 1)
        XCTAssertEqual(engine.selectedIndex, 0)
        let committed = engine.endDrag()
        XCTAssertEqual(committed, 1)
        XCTAssertEqual(engine.selectedIndex, 1)
        XCTAssertEqual(engine.dragOffset, 0)
        XCTAssertEqual(engine.phase, .snapping)
    }

    func testDragHapticOnlyOnBoundary() {
        var engine = EdgeLoopEngine(itemCount: 3, behavior: .looping, selectedIndex: 0)
        engine.beginDrag()
        XCTAssertFalse(engine.updateDrag(translation: -8))
        XCTAssertTrue(engine.updateDrag(translation: -EdgeLoopEngine.itemStride))
        XCTAssertFalse(engine.updateDrag(translation: -EdgeLoopEngine.itemStride - 4))
    }

    func testBoundedRubberBandsAtEnds() {
        var engine = EdgeLoopEngine(itemCount: 3, behavior: .bounded, selectedIndex: 0)
        engine.beginDrag()
        _ = engine.updateDrag(translation: 80)
        XCTAssertEqual(engine.proposedIndex, 0)
        XCTAssertLessThan(engine.dragOffset, 80)
    }

    func testVisibleSlotsKeepApertureCentered() {
        let engine = EdgeLoopEngine(itemCount: 3, behavior: .looping, selectedIndex: 1)
        let slots = engine.visibleSlots(radius: 1)
        XCTAssertEqual(slots.map(\.slot), [-1, 0, 1])
        XCTAssertEqual(slots.first { $0.slot == 0 }?.index, 1)
        XCTAssertEqual(engine.visualOffset(forSlot: 0), 0, accuracy: 0.01)
    }

    func testLabelHoldDurationIsTransient() {
        XCTAssertEqual(EdgeLoopEngine.labelHoldDuration, 1.75, accuracy: 0.01)
        XCTAssertEqual(EdgeLoopEngine.restingWidth, 46, accuracy: 0.1)
        XCTAssertEqual(EdgeLoopEngine.revealedWidth, 126, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(EdgeLoopEngine.hitSlop, 44)
    }
}

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

    func testMetricsScaleCoherentlyAndKeepHitTarget() {
        let compact = EdgeLoopMetrics.resolve(size: .compact)
        let standard = EdgeLoopMetrics.resolve(size: .standard)
        let large = EdgeLoopMetrics.resolve(size: .large)
        XCTAssertLessThan(compact.restingDepth, standard.restingDepth)
        XCTAssertLessThan(standard.restingDepth, large.restingDepth)
        XCTAssertGreaterThanOrEqual(compact.hitSlop, 44)
        XCTAssertGreaterThanOrEqual(standard.hitSlop, 44)
        XCTAssertGreaterThanOrEqual(large.hitSlop, 44)
        XCTAssertEqual(standard.restingDepth, 46, accuracy: 0.1)
    }

    func testSideMapsToLoopPosition() {
        XCTAssertEqual(EdgePickerSide.right.loopPosition, .trailing)
        XCTAssertEqual(EdgePickerSide.left.loopPosition, .leading)
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
        XCTAssertTrue(ShellChromePolicy.policy(for: .activity(.all)).contextRailVisible)
        XCTAssertTrue(ShellChromePolicy.policy(for: .me(.overview)).contextRailVisible)
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
