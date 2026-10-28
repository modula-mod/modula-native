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
        XCTAssertEqual(EdgeLoopEngine.revealedWidth, 120, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(EdgeLoopEngine.hitSlop, 44)
    }

    func testCancelDragRestoresBaseSlot() {
        var engine = EdgeLoopEngine(itemCount: 3, behavior: .looping, selectedIndex: 0)
        engine.beginDrag()
        _ = engine.updateDrag(translation: -EdgeLoopEngine.itemStride * 0.3)
        let restored = engine.cancelDrag()
        XCTAssertEqual(restored, 0)
        XCTAssertEqual(engine.selectedIndex, 0)
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
        XCTAssertLessThan(compact.channelDepth, standard.channelDepth)
        XCTAssertLessThan(standard.channelDepth, large.channelDepth)
        XCTAssertLessThan(compact.selectionWidth, standard.selectionWidth)
        XCTAssertLessThanOrEqual(standard.selectionWidth, standard.channelDepth)
        XCTAssertGreaterThanOrEqual(compact.hitSlop, 44)
        XCTAssertGreaterThanOrEqual(standard.hitSlop, 44)
        XCTAssertGreaterThanOrEqual(large.hitSlop, 44)
        XCTAssertEqual(standard.channelDepth, 46, accuracy: 0.1)
        XCTAssertEqual(standard.restingDepth, standard.channelDepth, accuracy: 0.01)
        // Channel fractions are monotonic and leave a long straight middle.
        XCTAssertLessThan(standard.curveStartFraction, standard.channelStartFraction)
        XCTAssertLessThan(standard.channelStartFraction, standard.channelEndFraction)
        XCTAssertLessThan(standard.channelEndFraction, standard.curveEndFraction)
        let channelShare = standard.channelEndFraction - standard.channelStartFraction
        XCTAssertGreaterThanOrEqual(channelShare, 0.30)
    }

    func testVerticalRevealHeightTracksLabelWidth() {
        let metrics = EdgeLoopMetrics.resolve(size: .standard)
        let short = metrics.revealLength(for: "All")
        let long = metrics.revealLength(for: "Following")
        XCTAssertGreaterThanOrEqual(short, metrics.selectionExpandedMinHeight)
        XCTAssertLessThanOrEqual(long, metrics.selectionExpandedMaxHeight)
        XCTAssertGreaterThanOrEqual(long, short)
        // Collapsed aperture is a vertical pill (taller than wide), never a circle.
        XCTAssertGreaterThan(metrics.selectionCollapsedHeight / metrics.selectionWidth, 1.35)
        XCTAssertLessThan(metrics.selectionCollapsedHeight, metrics.selectionExpandedMinHeight)
    }

    func testSideMapsToLoopPosition() {
        XCTAssertEqual(EdgePickerSide.right.loopPosition, .trailing)
        XCTAssertEqual(EdgePickerSide.left.loopPosition, .leading)
    }
}

final class EdgePickerCarvedShapeTests: XCTestCase {
    func testChannelStaysInsideBounds() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 260)
        let depth: CGFloat = 46
        let path = EdgeLoopShape.carvedPath(in: rect, depth: depth, position: .trailing)
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5)
        // Inner wall should sit near maxX - depth.
        XCTAssertLessThanOrEqual(bounds.minX, rect.maxX - depth + 1)
    }

    func testCurveOrderingIsMonotonic() {
        let rect = CGRect(x: 0, y: 0, width: 56, height: 260)
        let marks = EdgeLoopShape.landmarks(in: rect)
        XCTAssertLessThan(marks.curveStart, marks.channelTop)
        XCTAssertLessThan(marks.channelTop, marks.selectionCentre)
        XCTAssertLessThan(marks.selectionCentre, marks.channelBottom)
        XCTAssertLessThan(marks.channelBottom, marks.curveEnd)
    }

    func testLeadingMirrorsTrailing() {
        let rect = CGRect(x: 0, y: 0, width: 56, height: 240)
        let depth: CGFloat = 44
        let trailing = EdgeLoopShape.carvedPath(in: rect, depth: depth, position: .trailing).boundingRect
        let leading = EdgeLoopShape.carvedPath(in: rect, depth: depth, position: .leading).boundingRect
        XCTAssertEqual(trailing.width, leading.width, accuracy: 0.5)
        XCTAssertEqual(trailing.height, leading.height, accuracy: 0.5)
        // Trailing hugs the right edge; leading hugs the left.
        XCTAssertGreaterThan(trailing.midX, rect.midX)
        XCTAssertLessThan(leading.midX, rect.midX)
    }

    func testSizePresetsKeepNarrowChannel() {
        for size in EdgePickerSize.allCases {
            let metrics = EdgeLoopMetrics.resolve(size: size)
            XCTAssertLessThanOrEqual(metrics.channelDepth, 58)
            XCTAssertGreaterThanOrEqual(metrics.channelDepth, 38)
            XCTAssertLessThanOrEqual(metrics.selectionWidth, metrics.channelDepth)
        }
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
