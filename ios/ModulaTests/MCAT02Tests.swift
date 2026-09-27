import XCTest
@testable import Modula

final class MCAT02ContextTests: XCTestCase {
    func testActionRolesDisabledStateAndSubmenuRemainExplicit() {
        let submenu = ModulaContextAction(id: "copy", title: "Copy", systemImage: "doc.on.doc")
        let destructive = ModulaContextAction(id: "delete", title: "Delete", role: .destructive)
        let disabled = ModulaContextAction(id: "disabled", title: "Unavailable", role: .disabled)
        let parent = ModulaContextAction(id: "more", title: "More", children: [submenu, destructive])
        let group = ModulaContextActionGroup(id: "primary", title: "Actions", actions: [disabled, parent])

        XCTAssertFalse(disabled.isInteractive)
        XCTAssertEqual(destructive.role, .destructive)
        XCTAssertEqual(parent.children.map(\.id), ["copy", "delete"])
        XCTAssertEqual(group.actions.count, 2)
    }
}

final class MCAT02ReactionTests: XCTestCase {
    func testSelectionCanReplaceAndToggle() {
        var selection = ModulaReactionSelection<String>("like")
        XCTAssertEqual(selection.replace(with: "love"), "like")
        XCTAssertEqual(selection.selectedID, "love")
        selection.toggle("love")
        XCTAssertNil(selection.selectedID)
    }

    func testDragMapsOnlyInsideItemBounds() {
        XCTAssertEqual(ModulaReactionGesture.itemIndex(at: 10, itemCount: 4, itemWidth: 40, spacing: 4, leadingInset: 8), 0)
        XCTAssertNil(ModulaReactionGesture.itemIndex(at: 50, itemCount: 4, itemWidth: 40, spacing: 4, leadingInset: 8))
        XCTAssertEqual(ModulaReactionGesture.itemIndex(at: 54, itemCount: 4, itemWidth: 40, spacing: 4, leadingInset: 8), 1)
        XCTAssertNil(ModulaReactionGesture.itemIndex(at: 400, itemCount: 4, itemWidth: 40, spacing: 4, leadingInset: 8))
    }
}

final class MCAT02TabAndSpaceTests: XCTestCase {
    func testTabSelectionRejectsMissingAndTracksDynamicItems() {
        var selection = ModulaTabSelection("all")
        XCTAssertTrue(selection.select("mentions", available: ["all", "mentions"]))
        XCTAssertEqual(selection.selectedID, "mentions")
        XCTAssertFalse(selection.select("requests", available: ["all", "mentions"]))
        XCTAssertEqual(selection.selectedID, "mentions")
    }

    func testSpaceIdentityAndOrderingAreStable() {
        let space = ModulaSpace(id: "work", title: "Work", systemImage: "briefcase", badgeCount: 2)
        XCTAssertEqual(space.id, "work")
        XCTAssertEqual(ModulaSpaceOrder.moving(["a", "b", "c"], from: 0, to: 3), ["b", "c", "a"])
        XCTAssertEqual(ModulaSpaceOrder.moving(["a", "b"], from: 8, to: 0), ["a", "b"])
    }
}

@MainActor
final class MCAT02SelectionTests: XCTestCase {
    func testSelectDeselectSelectAllAndClear() {
        let state = ModulaSelectionState<String>()
        state.enter(selecting: "a")
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.selectedIDs, ["a"])
        state.toggle("a")
        XCTAssertTrue(state.selectedIDs.isEmpty)
        state.selectAll(["a", "b", "c"])
        XCTAssertEqual(state.selectedIDs.count, 3)
        state.deselect("b")
        XCTAssertEqual(state.selectedIDs, ["a", "c"])
        state.deselectAll()
        XCTAssertTrue(state.selectedIDs.isEmpty)
        state.clear()
        XCTAssertFalse(state.isActive)
    }
}

final class MCAT02SheetIndicatorComposerTests: XCTestCase {
    func testSheetDetentsDismissibilityAndRestoration() {
        var state = ModulaSheetState(selectedDetent: .compact, isDismissible: false)
        state.remember()
        XCTAssertTrue(state.select(.large, from: [.compact, .large]))
        XCTAssertEqual(state.selectedDetent, .large)
        XCTAssertFalse(state.isDismissible)
        state.restore()
        XCTAssertEqual(state.selectedDetent, .compact)
        XCTAssertFalse(state.select(.full, from: [.compact, .large]))
    }

    func testCountFormattingBoundaries() {
        XCTAssertNil(ModulaCountBadge.label(for: 0))
        XCTAssertEqual(ModulaCountBadge.label(for: 1), "1")
        XCTAssertEqual(ModulaCountBadge.label(for: 99), "99")
        XCTAssertEqual(ModulaCountBadge.label(for: 100), "99+")
    }

    func testComposerSendPolicyIncludesAttachmentsAndSendingState() {
        XCTAssertFalse(ModulaComposerState().canSend)
        XCTAssertTrue(ModulaComposerState(text: "Hello").canSend)
        XCTAssertFalse(ModulaComposerState(text: "Hello", isSending: true).canSend)
        XCTAssertTrue(ModulaComposerState(attachments: [.init(id: "a", title: "File", systemImage: "doc")]).canSend)
    }
}
