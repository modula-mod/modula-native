import Foundation
import XCTest
@testable import Modula

final class CollectionDraftSyncTests: XCTestCase {
    func testSyncFlagIsOffByDefaultAndAlwaysOffInRelease() {
        let defaults = suite()
        XCTAssertFalse(CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: false))
        XCTAssertFalse(CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: true))
        defaults.set(true, forKey: CollectionDraftSyncFeatureFlags.storageKey)
        XCTAssertTrue(CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: false))
        XCTAssertFalse(CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: true))
        defaults.set(false, forKey: CollectionDraftSyncFeatureFlags.storageKey)
        XCTAssertFalse(CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: false))
    }

    func testRegistryEntryIsOffAndHiddenFromProduction() {
        XCTAssertFalse(FeatureFlagRegistry.isEnabled("collections.drafts.sync"))
        let flag = FeatureFlagRegistry.all.first { $0.id == "collections.drafts.sync" }
        XCTAssertEqual(flag?.enabled, false)
        XCTAssertEqual(flag?.exposedToProduction, false)
    }

    func testProductionCapabilitiesStayLocalFirstWhenFlagIsOff() {
        let defaults = suite()
        XCTAssertFalse(CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: false))
        var collections = CollectionBackendCapabilities()
        collections.serverCollections = CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: false)
        XCTAssertFalse(collections.serverCollections)
        XCTAssertTrue(collections.localCollections)

        var drafts = DraftBackendCapabilities()
        drafts.serverPostDrafts = CollectionDraftSyncFeatureFlags.isEnabled(defaults: defaults, release: false)
        XCTAssertFalse(drafts.serverPostDrafts)
        XCTAssertTrue(drafts.localCache)
    }

    @MainActor
    func testCollectionStoreDoesNotEnqueueSyncWhenFlagOff() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CollectionStore(
            capabilities: CollectionBackendCapabilities(),
            fileStore: PrivateFileStore(domain: .collections, rootURL: root)
        )
        store.setAccountID("account-1")
        let created = store.create(name: "Local notes")
        XCTAssertEqual(created?.syncState, .localOnly)
        XCTAssertTrue(store.pendingMutations.isEmpty)
        XCTAssertFalse(store.capabilities.serverCollections)
    }

    @MainActor
    func testDraftStoreStaysLocalOnlyWhenFlagOff() {
        let store = DraftStore(
            capabilities: DraftBackendCapabilities(),
            fileStore: PrivateFileStore(
                domain: .drafts,
                rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            autosaveMilliseconds: 1
        )
        store.setAccountID("account-1")
        store.upsertPost(PostDraft(
            id: "post-1", accountID: "account-1", text: "Local only",
            mediaReferences: [], lastEdited: Date()
        ), debounce: false)
        _ = store.flush()
        XCTAssertEqual(store.postDraft(id: "post-1")?.syncState, .localOnly)
        XCTAssertFalse(store.capabilities.serverPostDrafts)
        XCTAssertFalse(CreationCapabilities.production.serverDrafts)
    }

    private func suite() -> UserDefaults {
        let name = "collections.drafts.sync.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
