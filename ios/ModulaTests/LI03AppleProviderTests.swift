import XCTest
@testable import Modula

actor FakeAppleFoundationModelRuntime: AppleFoundationModelRuntime {
    let availabilityState: AppleFoundationModelAvailability
    let result: Result<AppleFoundationModelOutput, AppleFoundationModelFailure>
    private(set) var respondCalls = 0
    private(set) var requests: [AppleFoundationModelRequest] = []

    init(
        availability: AppleFoundationModelAvailability = .available,
        result: Result<AppleFoundationModelOutput, AppleFoundationModelFailure> = .success(.text("Local result"))
    ) {
        self.availabilityState = availability
        self.result = result
    }

    func availability() async -> AppleFoundationModelAvailability { availabilityState }

    func respond(to request: AppleFoundationModelRequest) async throws -> AppleFoundationModelOutput {
        respondCalls += 1
        requests.append(request)
        return try result.get()
    }
}

private func appleRequest(
    capability: IntelligenceCapability = .summarize,
    privacy: IntelligencePrivacy = .localOnly,
    input: IntelligenceValue = .object(["text": .string("Modula is modular.")])
) -> IntelligenceRequest {
    IntelligenceRequest(capability: capability, input: input, privacy: privacy, source: .test)
}

private func execute(
    provider: AppleSystemIntelligenceProvider,
    request: IntelligenceRequest = appleRequest()
) async throws -> IntelligenceResponse {
    try await provider.execute(
        request,
        context: IntelligenceExecutionContext(source: .test)
    )
}

final class AppleProviderAvailabilityTests: XCTestCase {
    func testAvailableMapsToAvailable() async {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime(availability: .available))
        let availability = await provider.availability()
        XCTAssertEqual(availability, .available)
    }

    func testDeviceNotEligibleMapsToUnsupportedDevice() async {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime(availability: .deviceNotEligible))
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unsupportedDevice)
    }

    func testAppleIntelligenceNotEnabledMapsToDisabled() async {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime(availability: .appleIntelligenceNotEnabled))
        let availability = await provider.availability()
        XCTAssertEqual(availability, .disabled)
    }

    func testModelNotReadyMapsToModelNotInstalled() async {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime(availability: .modelNotReady))
        let availability = await provider.availability()
        XCTAssertEqual(availability, .modelNotInstalled)
    }

    func testUnsupportedOSMapsToTypedAvailability() async {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime(availability: .unsupportedOS))
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unsupportedOS)
    }

    func testUnknownMapsToTemporarilyUnavailable() async {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime(availability: .unknown))
        let availability = await provider.availability()
        XCTAssertEqual(availability, .temporarilyUnavailable)
    }
}

final class AppleProviderExecutionTests: XCTestCase {
    func testProviderIdentityAndExecutionKind() {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime())
        XCTAssertEqual(provider.id, "apple.system")
        XCTAssertEqual(provider.executionKind, .local)
    }

    func testSupportedCapabilitiesExcludeToolCall() {
        let provider = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime())
        XCTAssertEqual(provider.capabilities, [.generate, .rewrite, .summarize, .classify, .extract, .intent])
        XCTAssertFalse(provider.capabilities.contains(.toolCall))
    }

    func testTextResponsePreservesProvenance() async throws {
        let runtime = FakeAppleFoundationModelRuntime(result: .success(.text("A concise summary.")))
        let provider = AppleSystemIntelligenceProvider(runtime: runtime)
        let request = appleRequest()
        let response = try await execute(provider: provider, request: request)
        XCTAssertEqual(response.requestID, request.id)
        XCTAssertEqual(response.capability, .summarize)
        XCTAssertEqual(response.providerID, "apple.system")
        XCTAssertEqual(response.executionKind, .local)
        XCTAssertEqual(response.output, .string("A concise summary."))
        XCTAssertNotNil(response.duration)
    }

    func testRewriteExecutes() async throws {
        let provider = AppleSystemIntelligenceProvider(
            runtime: FakeAppleFoundationModelRuntime(result: .success(.text("Rewritten.")))
        )
        let response = try await execute(provider: provider, request: appleRequest(capability: .rewrite))
        XCTAssertEqual(response.output, .string("Rewritten."))
    }

    func testUnsupportedCapabilityDoesNotCallRuntime() async {
        let runtime = FakeAppleFoundationModelRuntime()
        let provider = AppleSystemIntelligenceProvider(runtime: runtime)
        do {
            _ = try await execute(provider: provider, request: appleRequest(capability: .toolCall))
            XCTFail("Expected capabilityUnsupported")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .capabilityUnsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let respondCalls = await runtime.respondCalls
        XCTAssertEqual(respondCalls, 0)
    }
}

final class ApplePromptAdapterTests: XCTestCase {
    private let adapter = ApplePromptAdapter()

    func testDirectStringBecomesPrompt() throws {
        let request = appleRequest(input: .string("Private user text"))
        XCTAssertEqual(
            try adapter.request(for: request),
            .text(
                instructions: "Summarize the supplied text accurately and concisely.",
                prompt: "Private user text"
            )
        )
    }

    func testObjectTextBecomesPrompt() throws {
        let adapted = try adapter.request(for: appleRequest(input: .object(["text": .string("Object text")])))
        guard case .text(_, let prompt) = adapted else { return XCTFail("Expected text prompt") }
        XCTAssertEqual(prompt, "Object text")
    }

    func testUserContentIsNotInterpolatedIntoInstructions() throws {
        let secret = "untrusted-content-marker"
        let adapted = try adapter.request(for: appleRequest(input: .string(secret)))
        guard case .text(let instructions, let prompt) = adapted else { return XCTFail("Expected text prompt") }
        XCTAssertFalse(instructions.contains(secret))
        XCTAssertEqual(prompt, secret)
    }

    func testUnsupportedInputShapeThrowsTypedError() {
        XCTAssertThrowsError(try adapter.request(for: appleRequest(input: .array([])))) { error in
            guard case IntelligenceError.invalidRequest = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testClassificationRequiresControlledCategories() throws {
        let input: IntelligenceValue = .object([
            "text": .string("Create and organize private notes."),
            "categories": .array(ApplePromptAdapter.classificationCategories.map(IntelligenceValue.string)),
        ])
        let adapted = try adapter.request(for: appleRequest(capability: .classify, input: input))
        guard case .classification(let instructions, let prompt) = adapted else {
            return XCTFail("Expected structured classification")
        }
        XCTAssertEqual(prompt, "Create and organize private notes.")
        XCTAssertFalse(instructions.contains(prompt))
    }
}

final class AppleStructuredGenerationTests: XCTestCase {
    func testClassificationMapsToProviderNeutralValue() async throws {
        let provider = AppleSystemIntelligenceProvider(
            runtime: FakeAppleFoundationModelRuntime(result: .success(.classification("productivity")))
        )
        let input: IntelligenceValue = .object([
            "text": .string("Create and organize private notes."),
            "categories": .array(ApplePromptAdapter.classificationCategories.map(IntelligenceValue.string)),
        ])
        let response = try await execute(
            provider: provider,
            request: appleRequest(capability: .classify, input: input)
        )
        XCTAssertEqual(response.output, .object(["category": .string("productivity")]))
    }

    func testUnexpectedClassificationIsRejected() async {
        let provider = AppleSystemIntelligenceProvider(
            runtime: FakeAppleFoundationModelRuntime(result: .success(.classification("other")))
        )
        let input: IntelligenceValue = .object([
            "text": .string("Text"),
            "categories": .array(ApplePromptAdapter.classificationCategories.map(IntelligenceValue.string)),
        ])
        do {
            _ = try await execute(provider: provider, request: appleRequest(capability: .classify, input: input))
            XCTFail("Expected invalid classification")
        } catch let error as IntelligenceError {
            guard case .providerFailure(let providerID, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(providerID, "apple.system")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class AppleErrorMappingTests: XCTestCase {
    private func assertMapping(
        _ failure: AppleFoundationModelFailure,
        expected: IntelligenceError
    ) async {
        let provider = AppleSystemIntelligenceProvider(
            runtime: FakeAppleFoundationModelRuntime(result: .failure(failure))
        )
        do {
            _ = try await execute(provider: provider)
            XCTFail("Expected error")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testContextLimit() async { await assertMapping(.contextLimitExceeded, expected: .contextLimitExceeded) }
    func testUnsupportedLanguage() async { await assertMapping(.unsupportedLanguage, expected: .unsupportedLanguage) }
    func testSafetyRefusal() async { await assertMapping(.safetyRefusal, expected: .safetyRefusal) }
    func testUnavailable() async { await assertMapping(.unavailable, expected: .providerUnavailable(providerID: "apple.system")) }
    func testSimulatorUnsupported() async { await assertMapping(.simulatorUnsupported, expected: .providerUnavailable(providerID: "apple.system")) }
    func testCancelled() async { await assertMapping(.cancelled, expected: .requestCancelled) }
    func testTimeout() async {
        let expected = IntelligenceError.providerFailure(providerID: "apple.system", detail: "TIMEOUT")
        await assertMapping(.timedOut, expected: expected)
    }
    func testProviderFailure() async {
        let expected = IntelligenceError.providerFailure(providerID: "apple.system", detail: "APPLE_RUNTIME_FAILURE")
        await assertMapping(.providerFailure, expected: expected)
    }
}

final class ApplePrivacyTests: XCTestCase {
    func testLocalOnlyAppleAvailableNeverExecutesRemote() async throws {
        let counter = SpyCallCounter()
        let apple = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime())
        let remote = SpyRemoteProvider(counter: counter)
        let registry = try IntelligenceProviderRegistry(providers: [apple, remote])
        let intelligence = ModulaIntelligence(providers: registry, registerDeterministicLocalProvider: false)
        await intelligence.setRemoteIntelligencePermitted(true)

        let response = try await intelligence.execute(appleRequest())
        XCTAssertEqual(response.providerID, "apple.system")
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0)
    }

    func testLocalOnlyAppleUnavailableDoesNotRescueWithRemote() async throws {
        let counter = SpyCallCounter()
        let apple = AppleSystemIntelligenceProvider(
            runtime: FakeAppleFoundationModelRuntime(availability: .modelNotReady)
        )
        let remote = SpyRemoteProvider(counter: counter)
        let registry = try IntelligenceProviderRegistry(providers: [apple, remote])
        let intelligence = ModulaIntelligence(providers: registry, registerDeterministicLocalProvider: false)
        await intelligence.setRemoteIntelligencePermitted(true)

        do {
            _ = try await intelligence.execute(appleRequest())
            XCTFail("Expected localProviderUnavailable")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .localProviderUnavailable)
        }
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0)
    }

    func testPreferLocalSelectsApple() async throws {
        let counter = SpyCallCounter()
        let apple = AppleSystemIntelligenceProvider(runtime: FakeAppleFoundationModelRuntime())
        let remote = SpyRemoteProvider(counter: counter)
        let registry = try IntelligenceProviderRegistry(providers: [remote, apple])
        let intelligence = ModulaIntelligence(providers: registry, registerDeterministicLocalProvider: false)
        await intelligence.setRemoteIntelligencePermitted(true)

        let response = try await intelligence.execute(appleRequest(privacy: .preferLocal))
        XCTAssertEqual(response.providerID, "apple.system")
        let executeCalls = await counter.executeCalls
        XCTAssertEqual(executeCalls, 0)
    }
}

final class AppleCancellationTests: XCTestCase {
    func testRuntimeCancellationMapsToRequestCancelled() async {
        let provider = AppleSystemIntelligenceProvider(
            runtime: FakeAppleFoundationModelRuntime(result: .failure(.cancelled))
        )
        do {
            _ = try await execute(provider: provider)
            XCTFail("Expected cancellation")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .requestCancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class RealFoundationModelsIntegrationTests: XCTestCase {
    func testRealSummarizeWhenAvailable() async throws {
        let provider = AppleSystemIntelligenceProvider()
        let availability = await provider.availability()
        guard availability == .available else {
            throw XCTSkip("SystemLanguageModel availability: \(availability.displayName)")
        }

        let registry = try IntelligenceProviderRegistry(providers: [provider])
        let intelligence = ModulaIntelligence(providers: registry, registerDeterministicLocalProvider: false)
        let request = appleRequest(
            input: .object([
                "text": .string("Modula is a modular social operating system that combines native experiences, modules, local intelligence and optional cloud services."),
            ])
        )
        let response: IntelligenceResponse
        do {
            response = try await intelligence.execute(request)
        } catch IntelligenceError.providerUnavailable {
            throw XCTSkip("SystemLanguageModel reported available, but simulator inference was rejected: operationNotAllowed — Simulator is not supported")
        }
        XCTAssertEqual(response.requestID, request.id)
        XCTAssertEqual(response.providerID, "apple.system")
        XCTAssertEqual(response.executionKind, .local)
        XCTAssertEqual(response.capability, .summarize)
        XCTAssertFalse(response.output.stringValue?.isEmpty ?? true)
        XCTAssertNotNil(response.duration)
    }

    func testRealGuidedClassificationWhenAvailable() async throws {
        let provider = AppleSystemIntelligenceProvider()
        let availability = await provider.availability()
        guard availability == .available else {
            throw XCTSkip("SystemLanguageModel availability: \(availability.displayName)")
        }

        let input: IntelligenceValue = .object([
            "text": .string("Create and organize private notes."),
            "categories": .array(ApplePromptAdapter.classificationCategories.map(IntelligenceValue.string)),
        ])
        let response: IntelligenceResponse
        do {
            response = try await execute(
                provider: provider,
                request: appleRequest(capability: .classify, input: input)
            )
        } catch IntelligenceError.providerUnavailable {
            throw XCTSkip("SystemLanguageModel reported available, but simulator guided generation was rejected: operationNotAllowed — Simulator is not supported")
        }
        let category = response.output.objectValue?["category"]?.stringValue
        XCTAssertTrue(ApplePromptAdapter.classificationCategories.contains(category ?? ""))
        XCTAssertEqual(response.providerID, "apple.system")
        XCTAssertEqual(response.executionKind, .local)
    }
}
