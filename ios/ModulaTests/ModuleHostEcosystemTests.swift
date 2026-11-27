import XCTest
@testable import Modula

@MainActor
final class ModuleHostEcosystemTests: XCTestCase {
    private var environment: ModuleEnvironment {
        ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)
    }

    func testParsesDeclarativeFrontendAndRejectsExecutableFields() throws {
        let document = try ProductUIDocument.parse(data: Self.frontend(title: "Basic"), productId: "digital.modula.basic", version: "0.1.0")
        XCTAssertEqual(document.entry, "home")
        XCTAssertEqual(document.sha256.count, 64)
        XCTAssertThrowsError(try ProductUIDocument.parse(data: Self.frontend(title: "X", extra: ["script": "alert(1)"]), productId: "digital.modula.basic", version: "0.1.0")) { error in
            XCTAssertEqual(error as? ProductUIDocument.ParseError, .forbiddenField("script"))
        }
    }

    func testIdentityMismatchAndOversizedFrontendFailClosed() {
        XCTAssertThrowsError(try ProductUIDocument.parse(data: Self.frontend(title: "Basic"), productId: "other.module", version: "0.1.0"))
        let huge = Data(repeating: 0x61, count: ProductUIDocument.maxBytes + 1)
        XCTAssertThrowsError(try ProductUIDocument.parse(data: huge, productId: "digital.modula.basic", version: "0.1.0")) { error in
            XCTAssertEqual(error as? ProductUIDocument.ParseError, .oversized)
        }
    }

    func testCacheSlotsActivateAndRollbackWithoutTouchingPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        let account = "acct-1"
        let v1 = try controller.installLocalPackage(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "Basic 0.1.0"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        XCTAssertEqual(v1.version, "0.1.0")
        XCTAssertEqual(controller.store.index(accountID: account, moduleId: "digital.modula.basic").activeReleaseId, "r1")

        let v2bytes = Self.frontend(title: "Basic 0.1.1", version: "0.1.1")
        _ = try controller.installLocalPackage(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.1", releaseId: "r2",
            frontend: v2bytes, hostManifest: Self.manifest("digital.modula.basic", "0.1.1")
        )
        XCTAssertEqual(controller.active(accountID: account, moduleId: "digital.modula.basic")?.version, "0.1.1")
        XCTAssertEqual(controller.store.release(in: .previousGood, accountID: account, moduleId: "digital.modula.basic")?.version, "0.1.0")

        let restored = try controller.rollback(accountID: account, moduleId: "digital.modula.basic", reason: "health")
        XCTAssertEqual(restored?.version, "0.1.0")
        XCTAssertEqual(controller.lastRollbackReason, "health")
    }

    func testBadStagedReleaseKeepsActive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "Basic 0.1.0"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        XCTAssertThrowsError(try controller.stageVerified(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.1", releaseId: "r-bad",
            frontend: Self.frontend(title: "Broken", version: "0.1.1"), frontendSha256: String(repeating: "ab", count: 32),
            mediaType: ProductUIDocument.mediaType, hostManifest: Self.manifest("digital.modula.basic", "0.1.1"),
            descriptor: nil
        ))
        XCTAssertEqual(controller.active(accountID: "acct-1", moduleId: "digital.modula.basic")?.version, "0.1.0")
    }

    func testActivationHealthFailureRestoresPreviousGood() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.tasks", version: "0.1.0-beta.1", releaseId: "t1",
            frontend: Self.frontend(title: "Tasks", productId: "digital.modula.tasks", version: "0.1.0-beta.1"),
            hostManifest: Self.manifest("digital.modula.tasks", "0.1.0-beta.1")
        )
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.tasks", version: "0.1.1-beta.1", releaseId: "t2",
            frontend: Self.frontend(title: "Tasks 0.1.1", productId: "digital.modula.tasks", version: "0.1.1-beta.1"),
            hostManifest: Self.manifest("digital.modula.tasks", "0.1.1-beta.1"),
            activate: false
        )
        controller.failNextActivationHealth = true
        XCTAssertThrowsError(try controller.activate(accountID: "acct-1", moduleId: "digital.modula.tasks"))
        XCTAssertEqual(controller.active(accountID: "acct-1", moduleId: "digital.modula.tasks")?.version, "0.1.0-beta.1")
        XCTAssertEqual(controller.lastRollbackReason, "activation-health")
    }

    func testDeclarativePrepareDoesNotUseBundledReactRegistry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let activation = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try activation.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "Hello Basic"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        let runtime = ModuleRuntimeController(manifests: [])
        runtime.setAccount("acct-1")
        runtime.activation = activation
        runtime.installationGate = { _ in .runnable(descriptor: nil) }
        let session = runtime.prepare(moduleID: "digital.modula.basic", environment: environment)
        XCTAssertEqual(session?.runtimeKind, .declarativeProductUI)
        XCTAssertEqual(session?.state, .ready)
        XCTAssertEqual(session?.productUI?.entry, "home")
        XCTAssertNil(session?.productUI?.raw["script"])
        XCTAssertNotEqual(session?.manifest.id, "digital.modula.vault-notes")
    }

    func testNoModuleIdSpecialCaseForVaultOrTasks() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Modula/ModuleRuntime/ProductUIRenderer.swift"))
        XCTAssertFalse(source.contains("digital.modula.vault-notes"))
        XCTAssertFalse(source.contains("digital.modula.tasks"))
        let host = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Modula/ModuleRuntime/ProductUIDocument.swift"))
        XCTAssertFalse(host.contains("digital.modula.vault-notes"))
    }

    func testHostAdvertisesBothLegacyAndProductUIContracts() {
        XCTAssertEqual(ModulaHost.version, "1.1.0", "Registry install plans must see the current Product UI host contract")
        let vault2 = ModuleManifest(
            id: "digital.modula.vault-notes", name: "Vault Notes", version: "2.0.0-rc.2",
            runtime: "declarative", entry: "product-ui", permissions: [],
            minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: ["note"]
        )
        let bundled = ModuleManifest(
            id: "digital.modula.vault-notes", name: "Vault Notes", version: "1.7.0",
            runtime: "react-native", entry: "vault", permissions: [],
            minHostVersion: "0.1.0", minBridgeVersion: "0.1.0", collections: ["note"]
        )
        XCTAssertEqual(
            ModuleCompatibility.evaluate(vault2, hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: "0.1.0"),
            .compatible
        )
        XCTAssertEqual(
            ModuleCompatibility.evaluate(bundled, hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: "0.1.0"),
            .compatible
        )
        XCTAssertEqual(
            ModuleCompatibility.evaluate(ModuleManifest(
                id: "digital.modula.generic-notes", name: "Notes", version: "2.1.0-rc.1",
                runtime: "declarative", entry: "product-ui", permissions: [],
                minHostVersion: ">=1.1.0", minBridgeVersion: "0.1.0", collections: ["note"]
            ), hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: "0.1.0"),
            .compatible
        )
    }

    func testPermissionReviewDoesNotCarryForwardNewCapabilities() {
        let store = ModulePermissionReviewStore()
        store.record(ModulePermissionReview(
            moduleId: "digital.modula.tasks", releaseId: "t1", descriptorRevision: "1",
            granted: ["storage:records"], denied: [], reviewedAt: Date()
        ))
        XCTAssertTrue(store.allows(moduleId: "digital.modula.tasks", releaseId: "t1", requested: ["storage:records"]))
        XCTAssertFalse(store.allows(moduleId: "digital.modula.tasks", releaseId: "t2", requested: ["storage:records", "mediaPicker"]))
        XCTAssertEqual(ModuleHostPermissions.purpose(for: "settings:register"),
                       "Register settings screens. This does not allow reading or writing settings values.")
    }

    func testLocalOnlyIntelligenceNeverInvented() {
        let session = ModuleSession(manifest: Self.manifest("digital.modula.intel", "0.1.0"), environment: environment)
        let result = ModuleCapabilityBroker.invoke("localIntelligence", session: session, localOnly: true)
        XCTAssertEqual(result, "CAPABILITY_UNAVAILABLE")
    }

    func testAccountIsolationOfArtifactCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-a", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "A"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        XCTAssertNil(controller.active(accountID: "acct-b", moduleId: "digital.modula.basic"))
        XCTAssertNotNil(controller.active(accountID: "acct-a", moduleId: "digital.modula.basic"))
    }

    func testGeneratedFrontendsParseAndActivateWithoutModuleIdBranch() throws {
        let basic = try Self.fixture("digital.modula.basic-0.1.0.frontend.json")
        let tasks = try Self.fixture("digital.modula.tasks-0.1.0-beta.1.frontend.json")
        let vault = try Self.fixture("digital.modula.vault-notes-2.0.0-rc.2.frontend.json")
        let basicDoc = try ProductUIDocument.parse(data: basic, productId: "digital.modula.basic", version: "0.1.0")
        let tasksDoc = try ProductUIDocument.parse(data: tasks, productId: "digital.modula.tasks", version: "0.1.0-beta.1")
        let vaultDoc = try ProductUIDocument.parse(data: vault, productId: "digital.modula.vault-notes", version: "2.0.0-rc.2")
        XCTAssertEqual(basicDoc.entry, "home")
        XCTAssertGreaterThanOrEqual(tasksDoc.views.count, 4)
        XCTAssertGreaterThanOrEqual(vaultDoc.views.count, 10)
        XCTAssertGreaterThanOrEqual(vaultDoc.actions.count, 20)
        XCTAssertNil(vaultDoc.raw["script"])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-real-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "b1",
            frontend: basic, hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.tasks", version: "0.1.0-beta.1", releaseId: "t1",
            frontend: tasks, hostManifest: Self.manifest("digital.modula.tasks", "0.1.0-beta.1")
        )
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.vault-notes", version: "2.0.0-rc.2", releaseId: "v2",
            frontend: vault, hostManifest: Self.manifest("digital.modula.vault-notes", "2.0.0-rc.2")
        )
        let runtime = ModuleRuntimeController(manifests: [])
        runtime.setAccount("acct-1")
        runtime.activation = controller
        runtime.installationGate = { _ in .runnable(descriptor: nil) }
        for id in ["digital.modula.basic", "digital.modula.tasks", "digital.modula.vault-notes"] {
            let session = runtime.prepare(moduleID: id, environment: environment)
            XCTAssertEqual(session?.runtimeKind, .declarativeProductUI, id)
            XCTAssertEqual(session?.state, .ready, id)
        }
    }

    func testLocalDevModulesInstallAndUpdateWithoutRegistry() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("devmodules-\(UUID().uuidString)", isDirectory: true)
        let v1 = workspace.appendingPathComponent("digital.modula.basic/0.1.0", isDirectory: true)
        let v2 = workspace.appendingPathComponent("digital.modula.basic/0.1.1", isDirectory: true)
        try FileManager.default.createDirectory(at: v1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: v2, withIntermediateDirectories: true)
        try Self.frontend(title: "Basic 0.1.0").write(to: v1.appendingPathComponent("frontend.manifest.json"))
        try Self.frontend(title: "Basic 0.1.1 updated", version: "0.1.1").write(to: v2.appendingPathComponent("frontend.manifest.json"))

        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        let store = ProductHubStore(client: GreenfieldClient(baseURL: nil))
        store.localDevRoots = [workspace]
        store.accountID = "acct-1"
        store.activation = ModuleActivationController(store: ModuleArtifactStore(root: cache))
        store.mergeLocalDevModules()
        XCTAssertEqual(store.product("digital.modula.basic")?.latestVersion, "0.1.1")
        let installed = await store.install("digital.modula.basic", permissions: ["settings:register"])
        XCTAssertEqual(installed, true)
        XCTAssertEqual(store.activation?.active(accountID: "acct-1", moduleId: "digital.modula.basic")?.version, "0.1.1")
        if case .runnable = store.installGate(for: "digital.modula.basic") {} else {
            XCTFail("local install should be runnable")
        }
    }

    func testLocalDevelopmentInstallationSurvivesRelaunchAndOffersUpdate() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("devmodules-\(UUID().uuidString)", isDirectory: true)
        let v1 = workspace.appendingPathComponent("digital.modula.basic/0.1.0", isDirectory: true)
        try FileManager.default.createDirectory(at: v1, withIntermediateDirectories: true)
        try Self.frontend(title: "Basic 0.1.0").write(to: v1.appendingPathComponent("frontend.manifest.json"))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        let first = ProductHubStore(client: GreenfieldClient(baseURL: nil))
        first.localDevRoots = [workspace]
        first.accountID = "acct-1"
        first.activation = ModuleActivationController(store: ModuleArtifactStore(root: cache))
        first.mergeLocalDevModules()
        let installed = await first.install("digital.modula.basic", permissions: ["settings:read"])
        XCTAssertEqual(installed, true)
        XCTAssertEqual(first.installations["digital.modula.basic"]?.version, "0.1.0")

        let v2 = workspace.appendingPathComponent("digital.modula.basic/0.1.1", isDirectory: true)
        try FileManager.default.createDirectory(at: v2, withIntermediateDirectories: true)
        try Self.frontend(title: "Basic 0.1.1 updated", version: "0.1.1").write(to: v2.appendingPathComponent("frontend.manifest.json"))
        let relaunched = ProductHubStore(client: GreenfieldClient(baseURL: nil))
        relaunched.localDevRoots = [workspace]
        relaunched.accountID = "acct-1"
        relaunched.activation = ModuleActivationController(store: ModuleArtifactStore(root: cache))
        await relaunched.load()
        XCTAssertEqual(relaunched.product("digital.modula.basic")?.latestVersion, "0.1.1")
        XCTAssertEqual(relaunched.installations["digital.modula.basic"]?.version, "0.1.0")
        let presentation = ModuleDetailPresentation(
            product: try XCTUnwrap(relaunched.product("digital.modula.basic")),
            installation: relaunched.installations["digital.modula.basic"],
            operation: nil, bundled: false, bundledVersion: nil, signedIn: true, declarativeHost: true
        )
        XCTAssertEqual(presentation.primaryAction, .update)
        relaunched.dropAccountScope()
        XCTAssertNil(relaunched.installations["digital.modula.basic"])
    }

    func testVaultToTasksGovernedActionIsTargetOwnedAndIdempotent() throws {
        let broker = ModuleActionBroker.Session()
        let request = ModuleActionBroker.Request(
            requestId: "req-1",
            idempotencyKey: "vault-note-42-task",
            sourceModuleId: "digital.modula.vault-notes",
            sourceReleaseId: "v2",
            targetModuleId: "digital.modula.tasks",
            targetActionId: "createRecord",
            payload: ["title": "From note"]
        )
        var applied = 0
        let apply: (ModuleActionBroker.Request) throws -> ModuleActionBroker.Result = { req in
            applied += 1
            return ModuleActionBroker.Result(
                requestId: req.requestId, status: "applied",
                targetRecordId: "task-1", mutationId: "mut-1", error: nil
            )
        }
        let first = try broker.invoke(
            request, sourceInstalled: true, targetInstalled: true,
            granted: ["actions:invoke"],
            targetActions: [.object(["id": .string("createRecord"), "family": .string("record.create")])],
            apply: apply
        )
        let second = try broker.invoke(
            request, sourceInstalled: true, targetInstalled: true,
            granted: ["actions:invoke"],
            targetActions: [.object(["id": .string("createRecord"), "family": .string("record.create")])],
            apply: apply
        )
        XCTAssertEqual(first.targetRecordId, "task-1")
        XCTAssertEqual(second.mutationId, first.mutationId)
        XCTAssertEqual(applied, 1)
        XCTAssertThrowsError(try broker.invoke(
            ModuleActionBroker.Request(
                requestId: "req-2", idempotencyKey: "other",
                sourceModuleId: "digital.modula.vault-notes", sourceReleaseId: "v2",
                targetModuleId: "digital.modula.tasks", targetActionId: "createRecord",
                payload: ["title": "X"]
            ),
            sourceInstalled: true, targetInstalled: false, granted: ["actions:invoke"],
            targetActions: [.object(["id": .string("createRecord")])], apply: apply
        ))
    }

    func testProductUIRuntimeSearchAndOfflineQueue() throws {
        let document = try ProductUIDocument.parse(data: Self.frontend(title: "Tasks", productId: "digital.modula.tasks"), productId: "digital.modula.tasks", version: "0.1.0")
        let session = ModuleSession(manifest: Self.manifest("digital.modula.tasks", "0.1.0"), environment: environment)
        let runtime = ProductUIRuntime(document: document, session: session, initialPath: "/")
        runtime.recordSource = { _, _ in
            [
                ProductUIRecord(id: "1", revision: 1, data: ["title": .string("Write report"), "status": .string("open")], deleted: false),
                ProductUIRecord(id: "2", revision: 1, data: ["title": .string("Buy milk"), "status": .string("done")], deleted: false),
            ]
        }
        runtime.refresh()
        runtime.query = "milk"
        XCTAssertEqual(runtime.bindingRecords("items").map(\.id), ["2"])
        runtime.online = false
        runtime.drafts["title"] = "Queued"
        runtime.perform(actionId: "createRecord")
        XCTAssertFalse(runtime.pendingMutations.isEmpty)
        XCTAssertTrue(runtime.pendingMutations[0].queuedOffline)
        XCTAssertEqual(runtime.viewState, "populated")
    }

    func testFrontendScreenStaysPopulatedWhenCapabilityBindingsAreEmpty() throws {
        let json = """
        {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","productId":"digital.modula.vault-notes","releaseVersion":"2.0.0","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"collection","title":"Vault Notes","bindings":[{"id":"notes","source":"record.query","recordType":"note"},{"id":"tableCapability","source":"capability","capability":"ui.table@1"}],"root":{"type":"section","children":[{"type":"search","text":"Search"},{"type":"button","text":"New note","action":"newNote"},{"type":"recordList","binding":"notes"}]},"states":{"empty":{"type":"emptyState","text":"Your vault is ready for its first note","children":[{"type":"button","text":"Create your first note","action":"newNote"}]}}}],"actions":[{"id":"newNote","family":"route.open","route":"/new"}]}
        """.data(using: .utf8)!
        let document = try ProductUIDocument.parse(data: json, productId: "digital.modula.vault-notes", version: "2.0.0")
        let session = ModuleSession(manifest: Self.manifest("digital.modula.vault-notes", "2.0.0"), environment: environment)
        let waiting = ProductUIRuntime(document: document, session: session, initialPath: "/")
        waiting.refresh()
        XCTAssertEqual(waiting.viewState, "loading")
        let runtime = ProductUIRuntime(document: document, session: session, initialPath: "/")
        runtime.recordSource = { _, _ in [
            ProductUIRecord(id: "note-1", revision: 2, data: ["title": .string("Welcome")], deleted: false)
        ] }
        runtime.refresh()
        XCTAssertEqual(runtime.viewState, "populated")
        XCTAssertEqual(runtime.bindingRecords("notes").map(\.id), ["note-1"])
        let decoded = ProductUIRuntime.records(from: .object([
            "items": .array([.object([
                "record_id": .string("note-9"),
                "revision": .number(3),
                "data": .object(["title": .string("Saved")])
            ])])
        ]))
        XCTAssertEqual(decoded.map(\.id), ["note-9"])
        XCTAssertEqual(decoded.first?.value("title"), "Saved")
        XCTAssertTrue(ProductUILayout.scrollsHorizontally(childCount: 12, declared: nil))
        XCTAssertFalse(ProductUILayout.scrollsHorizontally(childCount: 2, declared: nil))
        XCTAssertTrue(ProductUILayout.isQuietCopy(String(repeating: "a", count: 91)))
        XCTAssertFalse(ProductUILayout.showsBadge("false"))
        XCTAssertTrue(ProductUILayout.showsBadge("Local only"))
        XCTAssertTrue(ModuleCapabilityBroker.hostSupports("media.picker@1"))
        XCTAssertEqual(ModuleCapabilityBroker.canonical("ui.property-editor@1"), "ui.propertyEditor@1")
        XCTAssertEqual(
            ModulePolicy.hostCapabilities(coveredBy: ["media:module.digital.modula.vault-notes.note:write"]),
            ["mediaPicker"]
        )
        let pickerSession = ModuleSession(manifest: Self.manifest("digital.modula.vault-notes", "2.0.0"), environment: environment)
        XCTAssertEqual(ModuleCapabilityBroker.invoke("media.picker@1", session: pickerSession, localOnly: false), "ok")
    }

    func testAccountNoteWriteUsesTheSignedInRecordAPI() throws {
        let action: JSONValue = .object([
            "id": .string("createNote"),
            "family": .string("record.create"),
            "recordType": .string("note"),
            "input": .object([
                "defaults": .object([
                    "archived": .bool(false),
                    "contentFormat": .string("blocks-v1"),
                    "dataSchemaVersion": .string("1.0.0"),
                    "document": .object(["schemaVersion": .string("1.0.0"), "blocks": .array([])]),
                    "favourite": .bool(false),
                    "pinned": .bool(false),
                    "tagIds": .array([]),
                ]),
                "transforms": .array([.object([
                    "source": .string("document"),
                    "target": .string("plainTextProjection"),
                    "transform": .string("richText.plainText@1"),
                ])]),
            ]),
        ])
        let fields: [JSONValue] = [
            .object(["id": .string("title"), "type": .string("text"), "required": .bool(true)]),
            .object(["id": .string("document"), "type": .string("richText")]),
            .object(["id": .string("pinned"), "type": .string("boolean")]),
            .object(["id": .string("folderId"), "type": .string("recordReference"), "recordType": .string("folder")]),
        ]
        let mutation = ProductUIMutation(
            id: "ios-note-1", actionId: "createNote", family: "record.create", recordType: "note",
            recordId: nil, expectedRevision: nil,
            payload: ["title": "  Grocery  ", "document": "Milk", "pinned": "true", "folderId": ""],
            queuedOffline: false
        )
        let request = try ProductUIRecords.prepare(
            moduleId: "digital.modula.vault-notes", mutation: mutation, action: action, fields: fields, existing: nil
        ).get()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/modules/digital.modula.vault-notes/records/note")
        XCTAssertEqual(request.body["data"]?["title"]?.string, "Grocery")
        XCTAssertEqual(request.body["data"]?["plainTextProjection"]?.string, "Milk")
        XCTAssertEqual(request.body["data"]?["pinned"]?.bool, true)
        XCTAssertEqual(request.body["data"]?["document"]?["blocks"]?.array?.first?["text"]?.string, "Milk")
        XCTAssertNil(request.body["data"]?["folderId"])
        XCTAssertEqual(request.body["mutationId"]?.string, "ios-note-1")

        let rich = #"{"schemaVersion":"1.0.0","blocks":[{"id":"h1","type":"heading","level":2,"text":"Hhh"},{"id":"x1","type":"future-block","payload":{"keep":true}}]}"#
        var richMutation = mutation
        richMutation.payload["document"] = rich
        let richRequest = try ProductUIRecords.prepare(
            moduleId: "digital.modula.vault-notes", mutation: richMutation, action: action, fields: fields, existing: nil
        ).get()
        XCTAssertEqual(richRequest.body["data"]?["document"]?["blocks"]?.array?.first?["type"]?.string, "heading")
        XCTAssertEqual(richRequest.body["data"]?["document"]?["blocks"]?.array?.last?["payload"]?["keep"]?.bool, true)
        XCTAssertEqual(richRequest.body["data"]?["plainTextProjection"]?.string, "Hhh")

        let labelAction: JSONValue = .object([
            "id": .string("createLabel"), "family": .string("record.create"), "recordType": .string("label"),
            "input": .object(["transforms": .array([.object([
                "source": .string("name"), "target": .string("normalizedName"), "transform": .string("text.slug@1"),
            ])])]),
        ])
        let labelMutation = ProductUIMutation(id: "label-1", actionId: "createLabel", family: "record.create",
            recordType: "label", recordId: nil, expectedRevision: nil, payload: ["name": "  Project Ideas  "], queuedOffline: false)
        let labelRequest = try ProductUIRecords.prepare(moduleId: "digital.modula.labels", mutation: labelMutation,
            action: labelAction, fields: [.object(["id": .string("name"), "type": .string("text"), "required": .bool(true)])], existing: nil).get()
        XCTAssertEqual(labelRequest.body["data"]?["normalizedName"]?.string, "project-ideas")

        let legacy = ProductUIRecord(id: "older-note", revision: 2,
            data: ["title": .string("Before"), "folderId": .string("legacy-folder")], deleted: false)
        let legacyEdit = ProductUIMutation(id: "legacy-note-edit", actionId: "updateNote", family: "record.update",
            recordType: "note", recordId: legacy.id, expectedRevision: legacy.revision,
            payload: ["title": "After", "folderId": "legacy-folder"], queuedOffline: false)
        let legacyRequest = try ProductUIRecords.prepare(moduleId: "digital.modula.vault-notes", mutation: legacyEdit,
            action: .object(["family": .string("record.update"), "recordType": .string("note")]),
            fields: fields, existing: legacy).get()
        XCTAssertNil(legacyRequest.body["data"]?["folderId"])
        XCTAssertEqual(legacyRequest.body["data"]?["title"]?.string, "After")
        var removedFolder = legacyEdit
        removedFolder.payload["folderId"] = ""
        let removedFolderRequest = try ProductUIRecords.prepare(moduleId: "digital.modula.vault-notes",
            mutation: removedFolder, action: .object(["family": .string("record.update"), "recordType": .string("note")]),
            fields: fields, existing: legacy).get()
        XCTAssertEqual(removedFolderRequest.body["data"]?["folderId"], .null)

        let direct: JSONValue = .object([
            "record_id": .string("server-note"), "revision": .number(3),
            "updated_at": .string("2026-10-17T12:00:00.000Z"),
            "data": .object(["title": .string("From direct lookup")]),
        ])
        XCTAssertEqual(ProductUIRuntime.records(from: direct).first?.id, "server-note")
        XCTAssertEqual(ProductUIRuntime.records(from: direct).first?.value("updatedAt"), "2026-10-17T12:00:00.000Z")

        let untitled = ProductUIMutation(
            id: "ios-note-2", actionId: "createNote", family: "record.create", recordType: "note",
            recordId: nil, expectedRevision: nil, payload: ["document": "No title"], queuedOffline: false
        )
        XCTAssertThrowsError(try ProductUIRecords.prepare(
            moduleId: "digital.modula.vault-notes", mutation: untitled, action: action, fields: fields, existing: nil
        ).get())

        let notes = [
            ProductUIRecord(id: "a", revision: 1, data: ["title": .string("Hello"), "archived": .bool(false)], deleted: false),
            ProductUIRecord(id: "b", revision: 1, data: ["title": .string("Old"), "archived": .bool(true)], deleted: false),
        ]
        let home: JSONValue = .object([
            "source": .string("record.query"),
            "query": .object(["filters": .object(["archived": .bool(false)]), "filterParam": .string("filter")]),
        ])
        XCTAssertEqual(ProductUIRecords.visibleRecords(notes, binding: home).map(\.id), ["a"])
        let backlinks: JSONValue = .object([
            "source": .string("record.query"),
            "query": .object(["filterParam": .string("references")]),
        ])
        XCTAssertTrue(ProductUIRecords.visibleRecords(notes, binding: backlinks).isEmpty)
        XCTAssertTrue(ProductUILayout.isContractCopy("Backlinks require a generic reverse-reference query with account and installation scoping."))
    }

    func testEditorSeedsTheOpenNote() throws {
        let json = """
        {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","productId":"digital.modula.vault-notes","releaseVersion":"2.0.2","mode":"declarative","entry":"editor","hostRuntime":{"versionRange":">=1.0.0"},"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true},"routes":[{"path":"/note/:noteId/edit","viewId":"editor"}],"views":[{"id":"editor","kind":"form","title":"Edit Note","bindings":[{"id":"note","source":"record.detail","recordType":"note","recordIdParam":"noteId"}],"root":{"type":"section","children":[{"type":"field","field":{"id":"title","type":"text","required":true}},{"type":"field","field":{"id":"document","type":"richText"}},{"type":"field","field":{"id":"pinned","type":"boolean"}}]}}],"actions":[{"id":"updateNote","family":"record.update","recordType":"note","recordIdBinding":"note"}]}
        """.data(using: .utf8)!
        let document = try ProductUIDocument.parse(data: json, productId: "digital.modula.vault-notes", version: "2.0.2")
        let runtime = ProductUIRuntime(document: document, session: ModuleSession(manifest: Self.manifest("digital.modula.vault-notes", "2.0.2"), environment: environment), initialPath: "/note/note-1/edit")
        runtime.serverRecords["note|active"] = [
            ProductUIRecord(id: "note-1", revision: 4, data: [
                "title": .string("Hello"),
                "plainTextProjection": .string("Hi"),
                "pinned": .bool(true),
            ], deleted: false)
        ]
        runtime.refresh()
        XCTAssertEqual(runtime.drafts["title"], "Hello")
        XCTAssertEqual(runtime.drafts["document"], "Hi")
        XCTAssertEqual(runtime.drafts["pinned"], "true")
        runtime.online = true
        runtime.perform(actionId: "updateNote")
        XCTAssertEqual(runtime.serverMutation?.recordId, "note-1")
        XCTAssertEqual(runtime.serverMutation?.expectedRevision, 4)
        XCTAssertTrue(runtime.pendingMutations.isEmpty)
    }

    func testGenericRevisionPresentationAndAuditedRestoreRequest() throws {
        let list: JSONValue = .object(["revisions": .array([
            .object(["revision": .number(3), "operation": .string("update"), "changedAt": .string("2026-10-18T09:00:00Z")]),
        ])])
        XCTAssertEqual(ProductUIRuntime.revisions(from: list).first?.id, "3")
        XCTAssertEqual(ProductUIRuntime.revisions(from: list).first?.value("changeSource"), "update")
        let detail: JSONValue = .object([
            "revision": .number(2), "operation": .string("create"), "changedAt": .string("2026-10-17T09:00:00Z"),
            "data": .object(["title": .string("Original"), "document": .object([
                "schemaVersion": .string("1.0.0"), "blocks": .array([.object([
                    "id": .string("p1"), "type": .string("paragraph"), "text": .string("Original body"),
                ])]),
            ])]),
        ])
        let prior = try XCTUnwrap(ProductUIRuntime.revisions(from: detail).first)
        XCTAssertEqual(prior.value("snapshot.title"), "Original")
        XCTAssertEqual(prior.value("snapshot.document"), "Original body")

        let mutation = ProductUIMutation(
            id: "restore-2", actionId: "restoreItem", family: "record.restore", recordType: "item",
            recordId: "item-1", expectedRevision: 4, payload: ["sourceRevision": "2"], queuedOffline: false
        )
        let action: JSONValue = .object(["id": .string("restoreItem"), "family": .string("record.restore"), "recordType": .string("item")])
        let request = try ProductUIRecords.prepare(moduleId: "digital.modula.tasks", mutation: mutation,
            action: action, fields: [], existing: nil).get()
        XCTAssertEqual(request.path, "/v1/modules/digital.modula.tasks/records/item/item-1/restore")
        XCTAssertEqual(request.body["expectedRevision"]?.number, 4)
        XCTAssertEqual(request.body["sourceRevision"]?.number, 2)
        let trashRestore = ProductUIMutation(
            id: "restore-trash", actionId: "restoreItem", family: "record.restore", recordType: "item",
            recordId: "item-1", expectedRevision: 4, payload: [:], queuedOffline: false
        )
        let trashRequest = try ProductUIRecords.prepare(moduleId: "digital.modula.tasks", mutation: trashRestore,
            action: action, fields: [], existing: nil).get()
        XCTAssertEqual(trashRequest.body["sourceRevision"]?.number, 4)

        let frontend = #"{"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","productId":"digital.modula.tasks","releaseVersion":"0.1.0","mode":"declarative","entry":"history","hostRuntime":{"versionRange":">=1.0.0"},"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true},"routes":[{"path":"/task/:taskId/history","viewId":"history"},{"path":"/task/:taskId/history/:revisionId","viewId":"prior"}],"views":[{"id":"history","kind":"collection","title":"History","bindings":[{"id":"versions","source":"record.revisions","recordType":"item","recordIdParam":"taskId"}],"root":{"type":"recordList","binding":"versions","action":"openPrior"}},{"id":"prior","kind":"detail","title":"Prior","root":{"type":"text","text":"Prior"}}],"actions":[{"id":"openPrior","family":"route.open","label":"Open prior","route":"/task/:taskId/history/:revisionId","recordParam":"revisionId"}]}"#
        let document = try ProductUIDocument.parse(data: Data(frontend.utf8), productId: "digital.modula.tasks", version: "0.1.0")
        let runtime = ProductUIRuntime(document: document,
            session: ModuleSession(manifest: Self.manifest("digital.modula.tasks", "0.1.0"), environment: environment),
            initialPath: "/task/task-1/history")
        runtime.serverRecords["item|revisions|task-1"] = [prior]
        runtime.refresh()
        runtime.perform(actionId: "openPrior", record: prior)
        XCTAssertEqual(runtime.route, "/task/task-1/history/2")
    }

    func testGenericMediaBindingAndAttachmentAction() throws {
        let response: JSONValue = .object(["bindings": .array([
            .object(["bindingId": .string("bind-1"), "assetId": .string("asset-1"),
                     "filename": .string("drawing.pdf"), "contentType": .string("application/pdf"),
                     "createdAt": .string("2026-10-18T09:00:00Z")]),
        ])])
        let media = ProductUIRuntime.media(from: response)
        XCTAssertEqual(media.first?.id, "bind-1")
        XCTAssertEqual(media.first?.value("filename"), "drawing.pdf")
        XCTAssertEqual(media.first?.value("assetId"), "asset-1")

        let frontend = #"{"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","productId":"digital.modula.tasks","releaseVersion":"0.1.0","mode":"declarative","entry":"detail","hostRuntime":{"versionRange":">=1.0.0"},"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true},"routes":[{"path":"/task/:taskId","viewId":"detail"}],"views":[{"id":"detail","kind":"detail","title":"Task","bindings":[{"id":"task","source":"record.detail","recordType":"item","recordIdParam":"taskId"},{"id":"media","source":"record.media","recordType":"item","recordIdParam":"taskId"}],"root":{"type":"button","action":"attach","label":"Attach"}}],"actions":[{"id":"attach","family":"media.attach","label":"Attach","recordType":"item","recordIdBinding":"task","capability":"ui.mediaAttach@1"},{"id":"openMedia","family":"media.open","label":"Open","capability":"ui.mediaOpen@1"},{"id":"detach","family":"media.detach","label":"Remove","recordType":"item","recordIdBinding":"task","confirm":true}]}"#
        let document = try ProductUIDocument.parse(data: Data(frontend.utf8), productId: "digital.modula.tasks", version: "0.1.0")
        let runtime = ProductUIRuntime(document: document,
            session: ModuleSession(manifest: Self.manifest("digital.modula.tasks", "0.1.0"), environment: environment),
            initialPath: "/task/task-1")
        runtime.serverRecords["item|active"] = [ProductUIRecord(id: "task-1", revision: 1, data: [:], deleted: false)]
        runtime.serverRecords["item|media|task-1"] = media
        runtime.refresh()
        XCTAssertEqual(runtime.bindingRecords("media").first?.value("filename"), "drawing.pdf")
        runtime.perform(actionId: "attach")
        XCTAssertEqual(runtime.pendingMediaAttachment?.recordId, "task-1")
        XCTAssertEqual(runtime.pendingMediaAttachment?.recordType, "item")
        XCTAssertEqual(runtime.filePickToken, 1)
        runtime.perform(actionId: "openMedia", record: media[0])
        XCTAssertEqual(runtime.pendingMediaOpen?.assetId, "asset-1")
        runtime.perform(actionId: "detach", record: media[0])
        XCTAssertEqual(runtime.pendingMediaDetachment?.recordId, "task-1")
        XCTAssertEqual(runtime.pendingMediaDetachment?.bindingId, "bind-1")
    }

    func testGenericBooleanTogglePatchesOnlyOneFieldWithRevision() throws {
        let mutation = ProductUIMutation(
            id: "toggle-1", actionId: "toggleDone", family: "record.toggle", recordType: "task",
            recordId: "task-1", expectedRevision: 6, payload: [:], queuedOffline: false
        )
        let action: JSONValue = .object([
            "id": .string("toggleDone"), "family": .string("record.toggle"),
            "recordType": .string("task"), "recordField": .string("done"),
        ])
        let existing = ProductUIRecord(id: "task-1", revision: 6, data: [
            "done": .bool(false), "title": .string("Keep this title"),
        ], deleted: false)
        let request = try ProductUIRecords.prepare(
            moduleId: "digital.modula.tasks", mutation: mutation, action: action,
            fields: [], existing: existing
        ).get()
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.body["expectedRevision"]?.number, 6)
        XCTAssertEqual(request.body["data"]?["done"]?.bool, true)
        XCTAssertNil(request.body["data"]?["title"])
    }

    func testEditorDraftRequiresDiscardAndDoesNotLeakIntoAnotherRecord() throws {
        let frontend = #"{"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","productId":"digital.modula.tasks","releaseVersion":"0.1.0","mode":"declarative","entry":"detail","hostRuntime":{"versionRange":">=1.0.0"},"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true},"routes":[{"path":"/task/:taskId","viewId":"detail"},{"path":"/task/:taskId/edit","viewId":"editor"}],"views":[{"id":"detail","kind":"detail","title":"Task","root":{"type":"text","text":"Read"}},{"id":"editor","kind":"form","title":"Edit","bindings":[{"id":"task","source":"record.detail","recordType":"task","recordIdParam":"taskId"}],"root":{"type":"field","field":{"id":"title","type":"text","label":"Title"}}}],"actions":[]}"#
        let document = try ProductUIDocument.parse(data: Data(frontend.utf8), productId: "digital.modula.tasks", version: "0.1.0")
        let runtime = ProductUIRuntime(document: document,
            session: ModuleSession(manifest: Self.manifest("digital.modula.tasks", "0.1.0"), environment: environment),
            initialPath: "/task/task-1")
        runtime.serverRecords["task|active"] = [
            ProductUIRecord(id: "task-1", revision: 1, data: ["title": .string("First")], deleted: false),
            ProductUIRecord(id: "task-2", revision: 1, data: ["title": .string("Second")], deleted: false),
        ]
        runtime.open("/task/task-1/edit")
        XCTAssertEqual(runtime.drafts["title"], "First")
        runtime.drafts["title"] = "Uncommitted"
        runtime.goBack()
        XCTAssertEqual(runtime.route, "/task/task-1/edit")
        XCTAssertTrue(runtime.showsUnsavedChanges)
        runtime.discardAndLeave()
        XCTAssertEqual(runtime.route, "/task/task-1")
        runtime.open("/task/task-2/edit")
        XCTAssertEqual(runtime.drafts["title"], "Second")
    }

    func testInAppTemplatesGenerateHostParsableFrontends() throws {
        for template in DeveloperModuleDraft.templates {
            var draft = DeveloperModuleDraft.new(name: "Sample", template: template)
            draft.moduleId = "digital.modula.\(template)"
            draft.version = "0.1.0"
            let generated = ModuleProjectGenerator.generate(draft)
            XCTAssertTrue(generated.issues.isEmpty, "\(template): \(generated.issues.joined(separator: " "))")
            let document = try ProductUIDocument.parse(data: generated.frontend, productId: draft.moduleId, version: draft.version)
            XCTAssertEqual(document.entry, "home", template)
            XCTAssertFalse(document.views.isEmpty, template)
        }
        var edited = DeveloperModuleDraft.new(name: "Tasks", template: "records")
        edited.moduleId = "digital.modula.tasks"
        edited.intro = "Tasks before"
        let before = ModuleProjectGenerator.generate(edited)
        edited.intro = "Tasks after edit"
        edited.version = edited.bumpedVersion()
        let after = ModuleProjectGenerator.generate(edited)
        XCTAssertNotEqual(before.frontendSha256, after.frontendSha256)
        XCTAssertTrue(String(decoding: after.frontend, as: UTF8.self).contains("Tasks after edit"))
        let parsed = try ProductUIDocument.parse(data: after.frontend, productId: "digital.modula.tasks", version: "0.1.1")
        XCTAssertEqual(parsed.releaseVersion, "0.1.1")
        var invalid = edited
        invalid.moduleId = "../evil"
        XCTAssertFalse(ModuleProjectGenerator.validate(invalid).isEmpty)
    }

    private static func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private static func manifest(_ id: String, _ version: String) -> ModuleManifest {
        ModuleManifest(
            id: id, name: id, version: version, runtime: "declarative", entry: "product-ui",
            permissions: ["backend.records.list", "backend.records.create"],
            minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: ["item"]
        )
    }

    private static func frontend(title: String, productId: String = "digital.modula.basic", version: String = "0.1.0", extra: [String: String] = [:]) -> Data {
        var extraJSON = ""
        for (key, value) in extra { extraJSON += ",\"\(key)\":\"\(value)\"" }
        let json = """
        {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"\(productId)","releaseVersion":"\(version)","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"collection","title":"\(title)","bindings":[{"id":"items","source":"record.query","recordType":"item"}],"root":{"type":"section","children":[{"type":"text","text":"\(title)"},{"type":"search","text":"Search"},{"type":"recordList","binding":"items","action":"openRecord","children":[{"type":"recordRow","binding":"items","children":[{"type":"text","binding":"items","valuePath":"title"}]}]},{"type":"button","text":"New","action":"createRecord"}]},"states":{"loading":{"type":"loadingState","text":"Loading"},"empty":{"type":"emptyState","text":"Empty"},"error":{"type":"errorState","text":"Error"}}}],"actions":[{"id":"openRecord","family":"route.open","label":"Open","route":"/"},{"id":"createRecord","family":"record.create","label":"Create","recordType":"item"}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}\(extraJSON)}
        """
        return Data(json.utf8)
    }
}
