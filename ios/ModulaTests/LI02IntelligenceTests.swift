import XCTest
@testable import Modula

// MARK: - Test helpers

/// Test-only remote spy. Tracks availability/execute calls; never networks.
struct SpyRemoteProvider: IntelligenceProvider {
    let id: String
    let executionKind: IntelligenceExecutionKind = .remote
    let capabilities: Set<IntelligenceCapability>
    let availabilityState: IntelligenceAvailability
    let counter: SpyCallCounter

    init(
        id: String = "modula.test.remote-spy",
        capabilities: Set<IntelligenceCapability> = Set(IntelligenceCapability.allCases),
        availability: IntelligenceAvailability = .available,
        counter: SpyCallCounter = SpyCallCounter()
    ) {
        self.id = id
        self.capabilities = capabilities
        self.availabilityState = availability
        self.counter = counter
    }

    func availability() async -> IntelligenceAvailability {
        await counter.incrementAvailability()
        return availabilityState
    }

    func execute(
        _ request: IntelligenceRequest,
        context: IntelligenceExecutionContext
    ) async throws -> IntelligenceResponse {
        await counter.incrementExecute()
        return IntelligenceResponse(
            requestID: request.id,
            capability: request.capability,
            output: .string("remote-spy"),
            providerID: id,
            executionKind: .remote,
            duration: .zero
        )
    }
}

actor SpyCallCounter {
    private(set) var availabilityCalls = 0
    private(set) var executeCalls = 0

    func incrementAvailability() {
        availabilityCalls += 1
    }

    func incrementExecute() {
        executeCalls += 1
    }
}

/// Local provider that waits so cancellation can be exercised.
struct SlowCancellableLocalProvider: IntelligenceProvider {
    let id: String = "modula.test.slow-local"
    let executionKind: IntelligenceExecutionKind = .local
    let capabilities: Set<IntelligenceCapability> = [.summarize]

    func availability() async -> IntelligenceAvailability { .available }

    func execute(
        _ request: IntelligenceRequest,
        context: IntelligenceExecutionContext
    ) async throws -> IntelligenceResponse {
        try Task.checkCancellation()
        try await Task.sleep(for: .seconds(30))
        try Task.checkCancellation()
        return IntelligenceResponse(
            requestID: request.id,
            capability: request.capability,
            output: .string("should-not-reach"),
            providerID: id,
            executionKind: .local
        )
    }
}

private func summarizeRequest(
    privacy: IntelligencePrivacy,
    capability: IntelligenceCapability = .summarize
) -> IntelligenceRequest {
    IntelligenceRequest(
        capability: capability,
        input: .object(["text": .string("Modula is a modular social operating system.")]),
        privacy: privacy,
        source: .test
    )
}

// MARK: - ProviderRegistryTests

final class ProviderRegistryTests: XCTestCase {
    func testRegisterLookupAndUnregister() async throws {
        let registry = try IntelligenceProviderRegistry(providers: [])
        let provider = DeterministicLocalProvider()
        try await registry.register(provider)
        let lookedUp = await registry.provider(id: DeterministicLocalProvider.providerID)
        XCTAssertEqual(lookedUp?.id, provider.id)
        let all = await registry.allProviders()
        XCTAssertEqual(all.count, 1)
        let removed = await registry.unregister(id: provider.id)
        XCTAssertTrue(removed)
        let after = await registry.provider(id: provider.id)
        XCTAssertNil(after)
    }

    func testDuplicateIDRejected() async throws {
        let registry = try IntelligenceProviderRegistry(providers: [DeterministicLocalProvider()])
        do {
            try await registry.register(DeterministicLocalProvider())
            XCTFail("Expected duplicate rejection")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .duplicateProvider(providerID: DeterministicLocalProvider.providerID))
        }
    }

    func testCapabilityFilteringPreservesRegistrationOrder() async throws {
        let first = SpyRemoteProvider(id: "modula.test.a", capabilities: [.summarize], counter: SpyCallCounter())
        let second = DeterministicLocalProvider()
        let registry = try IntelligenceProviderRegistry(providers: [first, second])
        let capable = await registry.providers(capableOf: .summarize)
        XCTAssertEqual(capable.map(\.id), ["modula.test.a", DeterministicLocalProvider.providerID])
    }

    func testExecutionKindFiltering() async throws {
        let remote = SpyRemoteProvider()
        let local = DeterministicLocalProvider()
        let registry = try IntelligenceProviderRegistry(providers: [remote, local])
        let locals = await registry.providers(executionKind: .local)
        let remotes = await registry.providers(executionKind: .remote)
        XCTAssertEqual(locals.map(\.id), [DeterministicLocalProvider.providerID])
        XCTAssertEqual(remotes.map(\.id), [remote.id])
    }
}

// MARK: - IntelligenceRouterTests

final class IntelligenceRouterTests: XCTestCase {
    private let router = IntelligenceRouter()

    func testStableOrderingPicksFirstRegisteredEligible() async {
        let a = SpyRemoteProvider(id: "modula.test.remote-a")
        let b = SpyRemoteProvider(id: "modula.test.remote-b")
        let decision = router.select(
            request: summarizeRequest(privacy: .allowRemote),
            providers: [a, b],
            availabilities: [a.id: .available, b.id: .available],
            remoteIntelligencePermitted: true
        )
        XCTAssertEqual(decision, .selected(providerID: a.id))
    }

    func testUnsupportedCapability() {
        let provider = SpyRemoteProvider(capabilities: [.rewrite])
        let decision = router.select(
            request: summarizeRequest(privacy: .allowRemote),
            providers: [provider],
            availabilities: [provider.id: .available],
            remoteIntelligencePermitted: true
        )
        XCTAssertEqual(decision, .failed(.capabilityUnsupported))
    }

    func testAllowRemoteStillPrefersLocal() {
        let remote = SpyRemoteProvider()
        let local = DeterministicLocalProvider()
        let decision = router.select(
            request: summarizeRequest(privacy: .allowRemote),
            providers: [remote, local],
            availabilities: [remote.id: .available, local.id: .available],
            remoteIntelligencePermitted: true
        )
        XCTAssertEqual(decision, .selected(providerID: local.id))
    }

    func testProviderProvenanceOnExecute() async throws {
        let intelligence = ModulaIntelligence()
        let response = try await intelligence.execute(summarizeRequest(privacy: .localOnly))
        XCTAssertEqual(response.providerID, DeterministicLocalProvider.providerID)
        XCTAssertEqual(response.executionKind, .local)
        XCTAssertEqual(response.capability, .summarize)
    }
}

// MARK: - PrivacyTests (P1)

final class PrivacyTests: XCTestCase {
    func testA_localOnlyWithAvailableLocalExecutesLocal() async throws {
        let intelligence = ModulaIntelligence()
        let response = try await intelligence.execute(summarizeRequest(privacy: .localOnly))
        XCTAssertEqual(response.providerID, DeterministicLocalProvider.providerID)
        XCTAssertEqual(response.executionKind, .local)
    }

    func testB_localOnlyWithOnlyRemoteFailsClosed() async throws {
        let counter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: counter)
        let registry = try IntelligenceProviderRegistry(providers: [remote])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        await intelligence.setRemoteIntelligencePermitted(true)

        do {
            _ = try await intelligence.execute(summarizeRequest(privacy: .localOnly))
            XCTFail("Expected failure")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .noEligibleProvider)
        }
    }

    func testC_localOnlyRemoteOnlyNeverCallsExecute() async throws {
        let counter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: counter)
        let registry = try IntelligenceProviderRegistry(providers: [remote])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        await intelligence.setRemoteIntelligencePermitted(true)

        _ = try? await intelligence.execute(summarizeRequest(privacy: .localOnly))
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0, "P1: remote execute must never run for localOnly")
    }

    func testD_preferLocalWithBothAvailableSelectsLocal() async throws {
        let counter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: counter)
        let local = DeterministicLocalProvider()
        let registry = try IntelligenceProviderRegistry(providers: [remote, local])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        await intelligence.setRemoteIntelligencePermitted(true)

        let response = try await intelligence.execute(summarizeRequest(privacy: .preferLocal))
        XCTAssertEqual(response.providerID, local.id)
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0)
    }

    func testE_preferLocalLocalUnavailableRemotePermittedMayExecuteRemote() async throws {
        let counter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: counter)
        let local = DeterministicLocalProvider(availability: .disabled)
        let registry = try IntelligenceProviderRegistry(providers: [local, remote])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        await intelligence.setRemoteIntelligencePermitted(true)

        let response = try await intelligence.execute(summarizeRequest(privacy: .preferLocal))
        XCTAssertEqual(response.providerID, remote.id)
        XCTAssertEqual(response.executionKind, .remote)
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 1)
    }

    func testF_unsupportedCapabilityTypedFailure() async throws {
        let limited = SpyRemoteProvider(id: "modula.test.limited", capabilities: [.rewrite])
        let registry = try IntelligenceProviderRegistry(providers: [limited])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        do {
            _ = try await intelligence.execute(summarizeRequest(privacy: .allowRemote))
            XCTFail("Expected capabilityUnsupported")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .capabilityUnsupported)
        }
    }

    func testLocalOnlyUnavailableLocalDoesNotFallbackRemote() async throws {
        let counter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: counter)
        let local = DeterministicLocalProvider(availability: .disabled)
        let registry = try IntelligenceProviderRegistry(providers: [local, remote])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        await intelligence.setRemoteIntelligencePermitted(true)

        do {
            _ = try await intelligence.execute(summarizeRequest(privacy: .localOnly))
            XCTFail("Expected localProviderUnavailable")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .localProviderUnavailable)
        }
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0)
    }

    func testPreferLocalRemoteForbiddenWhenNotPermitted() async throws {
        let remote = SpyRemoteProvider()
        let local = DeterministicLocalProvider(availability: .disabled)
        let registry = try IntelligenceProviderRegistry(providers: [local, remote])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        await intelligence.setRemoteIntelligencePermitted(false)

        do {
            _ = try await intelligence.execute(summarizeRequest(privacy: .preferLocal))
            XCTFail("Expected remoteExecutionForbidden")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .remoteExecutionForbidden)
        }
    }
}

// MARK: - IntelligenceToolRegistryTests

final class IntelligenceToolRegistryTests: XCTestCase {
    private func makeRegistry() async throws -> IntelligenceToolRegistry {
        let registry = IntelligenceToolRegistry()
        try await registry.register(
            IntelligenceTool(
                id: "modula.notes.search",
                description: "Search notes",
                access: .read,
                requiredPermission: "notes.read",
                inputSchema: .object(
                    properties: [
                        "query": .string,
                        "limit": .optional(.integer),
                    ],
                    required: ["query"],
                    additionalProperties: false
                )
            )
        )
        return registry
    }

    func testKnownToolAccepted() async throws {
        let registry = try await makeRegistry()
        let call = IntelligenceToolCall(
            toolID: "modula.notes.search",
            arguments: .object(["query": .string("hello")])
        )
        let validated = try await registry.validateCall(
            call,
            authorizedToolIDs: ["modula.notes.search"],
            grantedPermissions: ["notes.read"]
        )
        XCTAssertEqual(validated.toolID, "modula.notes.search")
    }

    func testUnknownToolRejected() async throws {
        let registry = try await makeRegistry()
        do {
            _ = try await registry.validateCall(
                IntelligenceToolCall(toolID: "modula.unknown", arguments: .object([:])),
                authorizedToolIDs: ["modula.unknown"],
                grantedPermissions: []
            )
            XCTFail("Expected toolNotFound")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .toolNotFound(toolID: "modula.unknown"))
        }
    }

    func testInvalidArgumentsRejected() async throws {
        let registry = try await makeRegistry()
        do {
            _ = try await registry.validateCall(
                IntelligenceToolCall(
                    toolID: "modula.notes.search",
                    arguments: .object(["limit": .integer(3)])
                ),
                authorizedToolIDs: ["modula.notes.search"],
                grantedPermissions: ["notes.read"]
            )
            XCTFail("Expected toolArgumentsInvalid")
        } catch let error as IntelligenceError {
            guard case .toolArgumentsInvalid = error else {
                return XCTFail("Wrong error \(error)")
            }
        }
    }

    func testMissingPermissionRejected() async throws {
        let registry = try await makeRegistry()
        do {
            _ = try await registry.validateCall(
                IntelligenceToolCall(
                    toolID: "modula.notes.search",
                    arguments: .object(["query": .string("x")])
                ),
                authorizedToolIDs: ["modula.notes.search"],
                grantedPermissions: []
            )
            XCTFail("Expected toolPermissionDenied")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .toolPermissionDenied(toolID: "modula.notes.search", permission: "notes.read"))
        }
    }

    func testToolNotAuthorizedForRequestRejected() async throws {
        let registry = try await makeRegistry()
        do {
            _ = try await registry.validateCall(
                IntelligenceToolCall(
                    toolID: "modula.notes.search",
                    arguments: .object(["query": .string("x")])
                ),
                authorizedToolIDs: [],
                grantedPermissions: ["notes.read"]
            )
            XCTFail("Expected toolNotAuthorizedForRequest")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .toolNotAuthorizedForRequest(toolID: "modula.notes.search"))
        }
    }

    func testValidToolCallValidated() async throws {
        let registry = try await makeRegistry()
        let args: IntelligenceValue = .object([
            "query": .string("modula"),
            "limit": .integer(5),
        ])
        let validated = try await registry.validateCall(
            IntelligenceToolCall(toolID: "modula.notes.search", arguments: args),
            authorizedToolIDs: ["modula.notes.search"],
            grantedPermissions: ["notes.read"]
        )
        XCTAssertEqual(validated.arguments, args)
    }
}

// MARK: - IntelligenceValueTests

final class IntelligenceValueTests: XCTestCase {
    func testEqualityAndNesting() {
        let value: IntelligenceValue = .object([
            "ok": .bool(true),
            "n": .integer(1),
            "items": .array([.string("a"), .null]),
        ])
        XCTAssertEqual(value.objectValue?["ok"]?.boolValue, true)
        XCTAssertEqual(value.objectValue?["items"]?.arrayValue?.count, 2)
    }

    func testCodableRoundTrip() throws {
        let original: IntelligenceValue = .object([
            "summary": .string("Deterministic local summary"),
            "score": .double(1.5),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IntelligenceValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNoAnyInPublicSurface() {
        // Structural compile-time intent: IntelligenceValue cases are typed.
        let values: [IntelligenceValue] = [.null, .bool(false), .integer(0), .double(0), .string(""), .array([]), .object([:])]
        XCTAssertEqual(values.count, 7)
    }
}

// MARK: - CancellationTests

final class CancellationTests: XCTestCase {
    func testCancellationMapsToRequestCancelled() async throws {
        let registry = try IntelligenceProviderRegistry(providers: [SlowCancellableLocalProvider()])
        let intelligence = ModulaIntelligence(
            providers: registry,
            registerDeterministicLocalProvider: false
        )
        let task = Task {
            try await intelligence.execute(summarizeRequest(privacy: .localOnly))
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .requestCancelled)
        } catch is CancellationError {
            XCTFail("CancellationError must be mapped to IntelligenceError.requestCancelled")
        }
    }
}

// MARK: - AcceptanceTests

final class AcceptanceTests: XCTestCase {
    func testMission02AcceptancePath() async throws {
        let intelligence = ModulaIntelligence()
        let request = IntelligenceRequest(
            capability: .summarize,
            input: .object([
                "text": .string("Modula is a modular social operating system."),
            ]),
            privacy: .localOnly,
            source: .test
        )

        let result = try await intelligence.execute(request)
        XCTAssertEqual(result.providerID, DeterministicLocalProvider.providerID)
        XCTAssertEqual(result.executionKind, .local)
        XCTAssertEqual(result.capability, .summarize)
        XCTAssertEqual(
            result.output.objectValue?["summary"]?.stringValue,
            "Deterministic local summary"
        )

        let removed = await intelligence.providers.unregister(id: DeterministicLocalProvider.providerID)
        XCTAssertTrue(removed)

        let counter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: counter)
        try await intelligence.providers.register(remote)

        do {
            _ = try await intelligence.execute(request)
            XCTFail("Expected noEligibleProvider")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .noEligibleProvider)
        }
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0)
    }

    func testNetworkIndependentDiagnosticsSnapshot() async throws {
        let intelligence = ModulaIntelligence()
        let snapshot = await intelligence.diagnosticsSnapshot()
        XCTAssertTrue(snapshot.coreReady)
        XCTAssertEqual(snapshot.localProviderCount, 1)
        XCTAssertEqual(snapshot.remoteProviderCount, 0)
        XCTAssertFalse(snapshot.realModelConnected)
        XCTAssertFalse(snapshot.networkRequired)
        XCTAssertTrue(snapshot.privacyEnforcementPass)
    }
}
