import XCTest
@testable import Modula

@MainActor
final class SpatialNavigationTests: XCTestCase {
    // MARK: One primary sheet

    func testStartsAtHomeWithNothingOpen() {
        let spatial = SpatialNavigationCoordinator()
        XCTAssertTrue(spatial.isHome)
        XCTAssertNil(spatial.activeSheet)
        XCTAssertEqual(spatial.dockState, .collapsed)
    }

    func testOpeningProfileWhileDockIsOpenClosesTheDock() {
        let spatial = SpatialNavigationCoordinator()
        spatial.openDock(.half)
        XCTAssertTrue(spatial.isDockOpen)
        spatial.openProfile(.me)
        XCTAssertTrue(spatial.isProfileOpen)
        XCTAssertFalse(spatial.isDockOpen)
        XCTAssertEqual(spatial.dockState, .collapsed)
        XCTAssertTrue(spatial.lastTransition.replaced)
        XCTAssertEqual(spatial.lastTransition.from, .dock(.half))
    }

    func testSidebarAndProfileNeverCoexist() {
        let spatial = SpatialNavigationCoordinator()
        spatial.openSidebar()
        spatial.openProfile(SpatialProfileTarget(userID: "sophia"))
        XCTAssertFalse(spatial.isSidebarOpen)
        XCTAssertEqual(spatial.profileTarget?.userID, "sophia")
        spatial.openSidebar()
        XCTAssertTrue(spatial.isSidebarOpen)
        XCTAssertFalse(spatial.isProfileOpen)
    }

    func testCloseKindOnlyClosesThatLayer() {
        let spatial = SpatialNavigationCoordinator()
        spatial.openProfile(.me)
        spatial.close(.sidebar)
        XCTAssertTrue(spatial.isProfileOpen, "A stale sidebar close must not close the profile")
        spatial.close(.profile)
        XCTAssertTrue(spatial.isHome)
    }

    func testToggleSidebar() {
        let spatial = SpatialNavigationCoordinator()
        spatial.toggleSidebar()
        XCTAssertTrue(spatial.isSidebarOpen)
        spatial.toggleSidebar()
        XCTAssertTrue(spatial.isHome)
    }

    // MARK: Dock states

    func testDockRaisesAndLowersThroughThreeStates() {
        let spatial = SpatialNavigationCoordinator()
        spatial.raiseDock()
        XCTAssertEqual(spatial.dockState, .half)
        spatial.raiseDock()
        XCTAssertEqual(spatial.dockState, .expanded)
        spatial.raiseDock()
        XCTAssertEqual(spatial.dockState, .expanded)
        spatial.lowerDock()
        XCTAssertEqual(spatial.dockState, .half)
        spatial.lowerDock()
        XCTAssertEqual(spatial.dockState, .collapsed)
        XCTAssertTrue(spatial.isHome, "Collapsing the dock dismisses it")
    }

    func testSettingDockCollapsedDoesNotCloseOtherSheets() {
        let spatial = SpatialNavigationCoordinator()
        spatial.openSidebar()
        spatial.setDock(.collapsed)
        XCTAssertTrue(spatial.isSidebarOpen)
        spatial.open(.dock(.collapsed))
        XCTAssertTrue(spatial.isHome, "Opening a collapsed dock is a close")
    }

    func testDockSettleFollowsVelocityAndDistance() {
        let container: CGFloat = 800
        // Slow short drag up from collapsed stays collapsed.
        XCTAssertEqual(SpatialNavigationCoordinator.settledDock(from: .collapsed, translation: -40, predicted: -60, container: container), .collapsed)
        // Drag up past half lands on half.
        XCTAssertEqual(SpatialNavigationCoordinator.settledDock(from: .collapsed, translation: -330, predicted: -360, container: container), .half)
        // Strong flick up from half expands.
        XCTAssertEqual(SpatialNavigationCoordinator.settledDock(from: .half, translation: -60, predicted: -420, container: container), .expanded)
        // Flick down from expanded collapses past half.
        XCTAssertEqual(SpatialNavigationCoordinator.settledDock(from: .expanded, translation: 120, predicted: 900, container: container), .collapsed)
        // Small drag down from expanded stays expanded.
        XCTAssertEqual(SpatialNavigationCoordinator.settledDock(from: .expanded, translation: 30, predicted: 50, container: container), .expanded)
    }

    func testDockHeightsAreOrdered() {
        let c: CGFloat = 900
        XCTAssertEqual(SpatialNavigationCoordinator.dockHeight(for: .collapsed, container: c), 0)
        XCTAssertLessThan(SpatialNavigationCoordinator.dockHeight(for: .half, container: c),
                          SpatialNavigationCoordinator.dockHeight(for: .expanded, container: c))
        XCTAssertLessThan(SpatialNavigationCoordinator.dockHeight(for: .expanded, container: c), c)
    }

    // MARK: Horizontal settle

    func testHorizontalSettleUsesProjectedEndForFlicks() {
        XCTAssertTrue(SpatialNavigationCoordinator.settlesOpen(progress: 0.2, predicted: 0.9))
        XCTAssertFalse(SpatialNavigationCoordinator.settlesOpen(progress: 0.8, predicted: 0.1))
        XCTAssertTrue(SpatialNavigationCoordinator.settlesOpen(progress: 0.6, predicted: 0.65))
        XCTAssertFalse(SpatialNavigationCoordinator.settlesOpen(progress: 0.4, predicted: 0.45))
    }

    func testProgressFromTrailingAndLeadingEdges() {
        // Profile: finger moves left from the right edge.
        XCTAssertEqual(SpatialNavigationCoordinator.progress(translation: -200, width: 400, startOpen: false, fromTrailing: true), 0.5, accuracy: 0.001)
        // Dismissing: finger moves right.
        XCTAssertEqual(SpatialNavigationCoordinator.progress(translation: 100, width: 400, startOpen: true, fromTrailing: true), 0.75, accuracy: 0.001)
        // Sidebar: finger moves right from the left edge. Clamped.
        XCTAssertEqual(SpatialNavigationCoordinator.progress(translation: 900, width: 400, startOpen: false, fromTrailing: false), 1)
        XCTAssertEqual(SpatialNavigationCoordinator.progress(translation: 50, width: 0, startOpen: false, fromTrailing: false), 0)
    }

    func testSheetGeometryLeavesANarrowHomeStrip() {
        let width = SpatialSheetMetrics.sheetWidth(for: 402)
        let gutter = 402 - width
        XCTAssertGreaterThanOrEqual(gutter, 8)
        XCTAssertLessThanOrEqual(gutter, 12)
        XCTAssertGreaterThanOrEqual(width / 402, 0.97)
        XCTAssertGreaterThanOrEqual(SpatialSheetMetrics.cornerRadius, 28)
        XCTAssertLessThanOrEqual(SpatialSheetMetrics.cornerRadius, 36)
    }

    // MARK: Gesture arbitration

    func testInnerGalleriesWinOverSheetGestures() {
        let spatial = SpatialNavigationCoordinator()
        spatial.setExclusion("gallery", frame: CGRect(x: 0, y: 300, width: 400, height: 120))
        XCTAssertTrue(spatial.isExcluded(CGPoint(x: 390, y: 350)))
        XCTAssertFalse(spatial.canBegin(from: .trailingEdge, at: CGPoint(x: 390, y: 350), isAtStackRoot: true, systemSheetPresented: false, enabled: true))
        XCTAssertTrue(spatial.canBegin(from: .trailingEdge, at: CGPoint(x: 390, y: 600), isAtStackRoot: true, systemSheetPresented: false, enabled: true))
        spatial.setExclusion("gallery", frame: nil)
        XCTAssertFalse(spatial.isExcluded(CGPoint(x: 390, y: 350)))
    }

    func testEdgeGesturesYieldToBackSystemSheetsAndOpenLayers() {
        let spatial = SpatialNavigationCoordinator()
        let point = CGPoint(x: 5, y: 400)
        XCTAssertFalse(spatial.canBegin(from: .leadingEdge, at: point, isAtStackRoot: false, systemSheetPresented: false, enabled: true),
                       "On a pushed screen the leading edge is the system Back gesture")
        XCTAssertFalse(spatial.canBegin(from: .trailingEdge, at: point, isAtStackRoot: true, systemSheetPresented: true, enabled: true))
        XCTAssertFalse(spatial.canBegin(from: .trailingEdge, at: point, isAtStackRoot: true, systemSheetPresented: false, enabled: false))
        spatial.openSidebar()
        XCTAssertFalse(spatial.canBegin(from: .trailingEdge, at: point, isAtStackRoot: true, systemSheetPresented: false, enabled: true))
        spatial.close()
        spatial.openDock(.half)
        XCTAssertTrue(spatial.canBegin(from: .bottomBar, at: point, isAtStackRoot: true, systemSheetPresented: false, enabled: true))
    }

    // MARK: Profile sheet stack

    func testProfileSheetHasItsOwnBackStack() {
        let spatial = SpatialNavigationCoordinator()
        spatial.openProfile(.me)
        spatial.pushInSheet(.me(.overview)) // same as the root: ignored
        XCTAssertTrue(spatial.sheetPath.isEmpty)
        spatial.pushInSheet(.post("p1", .root))
        spatial.pushInSheet(.post("p1", .root)) // deduped
        XCTAssertEqual(spatial.sheetPath, [.post("p1", .root)])
        spatial.back()
        XCTAssertTrue(spatial.sheetPath.isEmpty)
        XCTAssertTrue(spatial.isProfileOpen)
        spatial.back()
        XCTAssertTrue(spatial.isHome)
    }

    func testClosingTheSheetClearsItsStack() {
        let spatial = SpatialNavigationCoordinator()
        spatial.openProfile(.me)
        spatial.pushInSheet(.saved(.root))
        spatial.close()
        XCTAssertTrue(spatial.sheetPath.isEmpty)
        spatial.pushInSheet(.saved(.root))
        XCTAssertTrue(spatial.sheetPath.isEmpty, "No pushes into a closed sheet")
    }

    // MARK: NavigationCoordinator integration

    func testProfileRoutesOpenTheSheetInsteadOfSwappingTabs() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.select(.discover)
        navigation.open(.me(.overview))
        XCTAssertEqual(navigation.selectedTab, .discover)
        XCTAssertEqual(navigation.spatial.profileTarget, .me)
        XCTAssertTrue(navigation.isAtTabRoot)
    }

    func testProfileTabOpensSheet() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.select(.home)
        navigation.select(.profile)
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.spatial.isProfileOpen)
        navigation.select(.activity)
        XCTAssertEqual(navigation.selectedTab, .activity)
        XCTAssertTrue(navigation.spatial.isHome, "Tapping a tab closes the open layer")
    }

    func testRoutesFromInsideTheSheetStayInsideIt() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.open(.profile("sophia", .overview))
        navigation.push(.post("p1", .root))
        navigation.open(.profile("andrei.modula", .overview))
        XCTAssertEqual(navigation.spatial.sheetPath, [.post("p1", .root), .profile("andrei.modula", .overview)])
        XCTAssertTrue(navigation.path(for: navigation.selectedTab).isEmpty, "The tab stack underneath is untouched")
        navigation.close()
        XCTAssertEqual(navigation.spatial.sheetPath, [.post("p1", .root)])
    }

    func testFullScreenDestinationsCloseTheSheetFirst() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.select(.home)
        navigation.open(.me(.overview))
        navigation.open(.module("digital.modula.vault-notes", localPath: nil))
        XCTAssertTrue(navigation.spatial.isHome)
        XCTAssertFalse(navigation.path(for: navigation.selectedTab).isEmpty)
    }

    func testEditProfileStaysAPushedTask() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.select(.home)
        navigation.open(.me(.edit))
        XCTAssertFalse(navigation.spatial.isProfileOpen)
        XCTAssertEqual(navigation.currentRoute, .me(.edit))
    }

    func testSidebarFlagIsBackedBySpatialCoordinator() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.presentSidebar()
        XCTAssertTrue(navigation.sidebarPresented)
        navigation.open(.me(.overview))
        XCTAssertFalse(navigation.sidebarPresented, "Opening the profile closes the sidebar")
        XCTAssertTrue(navigation.spatial.isProfileOpen)
        navigation.sidebarPresented = true
        XCTAssertFalse(navigation.spatial.isProfileOpen)
        navigation.dismissSidebar()
        XCTAssertTrue(navigation.spatial.isHome)
    }

    func testDisabledKeepsClassicRouting() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = false
        navigation.open(.me(.overview))
        XCTAssertEqual(navigation.selectedTab, .profile)
        XCTAssertFalse(navigation.spatial.isProfileOpen)
    }

    func testDeepLinkToProfileOpensSheet() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.select(.home)
        if let route = RouteParser.parse("/me") {
            navigation.open(route)
            XCTAssertTrue(navigation.spatial.isProfileOpen)
            XCTAssertEqual(navigation.selectedTab, .home)
        }
    }
}

@MainActor
final class SpatialRecentsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SpatialRecentsTests")
        defaults.removePersistentDomain(forName: "SpatialRecentsTests")
    }

    func testRecordsNamedDestinationsNewestFirstWithoutDuplicates() {
        SpatialRecents.note(.saved(.root), defaults: defaults)
        SpatialRecents.note(.settings(.appearance(.root)), defaults: defaults)
        SpatialRecents.note(.saved(.root), defaults: defaults)
        XCTAssertEqual(SpatialRecents.load(defaults: defaults).first, .saved(.root))
        XCTAssertEqual(SpatialRecents.load(defaults: defaults).count, 2)
    }

    func testIgnoresUnnamedOrTransientRoutes() {
        SpatialRecents.note(.post("p1", .root), defaults: defaults)
        SpatialRecents.note(.auth(.login), defaults: defaults)
        SpatialRecents.note(.home(.following), defaults: defaults)
        XCTAssertTrue(SpatialRecents.load(defaults: defaults).isEmpty)
    }

    func testKeepsModulesForTheRecentModulesSection() {
        SpatialRecents.note(.module("digital.modula.vault-notes", localPath: nil), defaults: defaults)
        XCTAssertEqual(SpatialRecents.load(defaults: defaults), [.module("digital.modula.vault-notes", localPath: nil)])
    }

    func testIsCapped() {
        let routes: [AppRoute] = [.saved(.root), .drafts(.root), .collections(.root), .messages(.inbox), .settings(.root),
                                  .settings(.moliboo), .settings(.privacy(.root)), .developer(.studio), .productHub(.featured),
                                  .settings(.notifications(.root))]
        routes.forEach { SpatialRecents.note($0, defaults: defaults) }
        XCTAssertEqual(defaults.stringArray(forKey: SpatialRecents.key)?.count, SpatialRecents.limit)
        XCTAssertLessThanOrEqual(SpatialRecents.load(defaults: defaults).count, SpatialRecents.limit)
    }
}

// MARK: - Gesture Navigation System round 2 (Release default, Modules Dock, quick tabs)

@MainActor
final class SpatialNavigationReleaseTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let name = "spatial.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testSpatialNavigationIsOnByDefaultInEveryBuild() {
        XCTAssertTrue(SpatialNavigationFeature.enabled(defaults: scratchDefaults(), arguments: []))
    }

    func testDevToggleAndLaunchArgumentAreOffSwitches() {
        let defaults = scratchDefaults()
        defaults.set(false, forKey: SpatialNavigationFeature.enabledKey)
        XCTAssertFalse(SpatialNavigationFeature.enabled(defaults: defaults, arguments: []))
        XCTAssertFalse(SpatialNavigationFeature.enabled(defaults: scratchDefaults(), arguments: ["--spatial-navigation-disabled"]))
    }

    func testModulesDockOpensAtHalfThenRaises() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.openModulesDock()
        XCTAssertEqual(navigation.spatial.dockState, .half)
        XCTAssertNil(navigation.presented)
        navigation.openModulesDock()
        XCTAssertEqual(navigation.spatial.dockState, .expanded)
    }

    func testModulesDockFallsBackToSheetWhenSpatialIsOff() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = false
        navigation.openModulesDock()
        XCTAssertEqual(navigation.presented, .installedModules)
        XCTAssertFalse(navigation.spatial.isDockOpen)
    }

    func testDockThenProfileLeavesOnlyProfileOpen() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.openModulesDock()
        navigation.select(.profile)
        XCTAssertTrue(navigation.spatial.isProfileOpen)
        XCTAssertFalse(navigation.spatial.isDockOpen)
    }

    func testDockThenSidebarLeavesOnlySidebarOpen() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.openModulesDock()
        navigation.sidebarPresented = true
        XCTAssertTrue(navigation.spatial.isSidebarOpen)
        XCTAssertFalse(navigation.spatial.isDockOpen)
    }

    func testBottomTabTapClosesTheDock() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        navigation.openModulesDock()
        navigation.select(.discover)
        XCTAssertTrue(navigation.spatial.isHome)
        XCTAssertEqual(navigation.selectedTab, .discover)
    }

    func testDockPinsAreOrderedDedupedAndMovable() {
        XCTAssertEqual(ModulesDockPrefs.decode(ModulesDockPrefs.encode(["a", "b", "a", "c"])), ["a", "b", "c"])
        XCTAssertEqual(ModulesDockPrefs.move(["a", "b", "c"], id: "c", by: -1), ["a", "c", "b"])
        XCTAssertEqual(ModulesDockPrefs.move(["a", "b", "c"], id: "a", by: -1), ["a", "b", "c"])
        XCTAssertEqual(ModulesDockPrefs.move(["a"], id: "missing", by: 1), ["a"])
        XCTAssertEqual(ModulesDockPrefs.pinnedFirst(["x", "b", "y", "a"], pins: ["a", "b", "a"], id: { $0 }), ["a", "b", "x", "y"])
    }

    // MARK: Quick tabs (accessory page 0)

    func testQuickTabFollowsTheCurrentRoute() {
        XCTAssertEqual(ShellQuickTab.current(.home(.following)), .following)
        XCTAssertEqual(ShellQuickTab.current(.home(.forYou)), .forYou)
        XCTAssertNil(ShellQuickTab.current(.saved(.root)))
    }

    func testQuickTabsOpenTheirDestinations() {
        let navigation = NavigationCoordinator()
        navigation.spatialEnabledOverride = true
        ShellQuickTab.discover.open(in: navigation)
        XCTAssertEqual(navigation.selectedTab, .discover)
        ShellQuickTab.following.open(in: navigation)
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertEqual(ShellQuickTab.current(navigation.currentRoute), .following)
        ShellQuickTab.modules.open(in: navigation)
        XCTAssertEqual(navigation.selectedTab, .modules)
    }

    func testQuickTabsHaveDistinctTitlesAndSymbols() {
        let tabs = ShellQuickTab.allCases
        XCTAssertEqual(Set(tabs.map(\.title)).count, tabs.count)
        XCTAssertEqual(Set(tabs.map(\.symbol)).count, tabs.count)
    }
}

@MainActor
final class QuickTabNeighbourTests: XCTestCase {
    func testNeighboursFollowBarOrderWithoutWrapping() {
        XCTAssertEqual(ShellQuickTab.following.neighbour(1), .forYou)
        XCTAssertEqual(ShellQuickTab.discover.neighbour(-1), .forYou)
        XCTAssertNil(ShellQuickTab.following.neighbour(-1))
        XCTAssertNil(ShellQuickTab.modules.neighbour(1))
    }
}

final class HomeSectionLayoutTests: XCTestCase {
    func testDefaultShowsEverySectionInOrder() {
        XCTAssertEqual(HomeSectionLayout.visible(HomeSectionLayout.defaultRaw), HomeSection.allCases)
    }

    func testHiddenAndReorderedRoundTrip() {
        var entries = HomeSectionLayout.decode(HomeSectionLayout.defaultRaw)
        entries.move(fromOffsets: IndexSet(integer: 0), toOffset: entries.count)
        entries[0].visible = false
        let raw = HomeSectionLayout.encode(entries)
        XCTAssertEqual(HomeSectionLayout.decode(raw), entries)
        XCTAssertFalse(HomeSectionLayout.visible(raw).contains(entries[0].section))
        XCTAssertEqual(HomeSectionLayout.visible(raw).last, .stories)
    }

    func testUnknownAndDuplicateIdsAreDroppedAndNewSectionsAppended() {
        let entries = HomeSectionLayout.decode("modules,bogus,modules,-stories")
        XCTAssertEqual(entries.first?.section, .modules)
        XCTAssertEqual(entries.count, HomeSection.allCases.count)
        XCTAssertFalse(HomeSectionLayout.isVisible(.stories, in: "modules,bogus,modules,-stories"))
    }
}
