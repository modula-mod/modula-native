import CryptoKit
import XCTest
@testable import Modula

actor FakeNodusRuntime: NodusRuntime {
    let generation: NodusRuntimeGeneration
    private(set) var generateCalls = 0
    private(set) var loadCalls = 0
    private var state: NodusLoadState = .unloaded

    init(text: String, version: String = "Nodus test") {
        generation = NodusRuntimeGeneration(
            text: text, modelVersion: version, completed: true, tokensPerSecond: 20, modelConsistency: 0.9
        )
    }

    func availability() -> IntelligenceAvailability { .available }
    func loadState() -> NodusLoadState { state }
    func load() { loadCalls += 1; state = .loaded }
    func generate(prompt: String, capability: IntelligenceCapability) -> NodusRuntimeGeneration {
        generateCalls += 1
        return generation
    }
    func unload() { state = .unloaded }
}

final class NodusFreshnessAndConfidenceTests: XCTestCase {
    func testStableKnowledge() {
        XCTAssertEqual(NodusFreshnessClassifier().classify("Explain photosynthesis simply."), .stable)
    }

    func testUndocumentedKnowledgeIsUnknown() {
        XCTAssertEqual(
            NodusFreshnessClassifier().classify("Give the packet format for the undocumented Zorven protocol."),
            .unknown
        )
    }

    func testNodusAvailabilityStates() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nodus-availability-\(UUID().uuidString)")
        let accepted = root.appending(path: "accepted")
        try FileManager.default.createDirectory(at: accepted, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let disabled = MLXNodusRuntime(modelDirectory: accepted, enabled: false, minimumMemoryBytes: 0)
        let disabledAvailability = await disabled.availability()
        XCTAssertEqual(disabledAvailability, .disabled)

        let insufficient = MLXNodusRuntime(
            modelDirectory: accepted, enabled: true, minimumMemoryBytes: UInt64.max
        )
        let insufficientAvailability = await insufficient.availability()
        XCTAssertEqual(insufficientAvailability, .insufficientMemory)

        try Data().write(to: root.appending(path: "download.in-progress"))
        let downloading = MLXNodusRuntime(modelDirectory: accepted, minimumMemoryBytes: 0)
        let downloadingAvailability = await downloading.availability()
        XCTAssertEqual(downloadingAvailability, .modelDownloading)
    }

    func testLiveDataOverridesConfidence() {
        let freshness = NodusFreshnessClassifier().classify("What's today's weather?")
        let confidence = NodusConfidenceEngine().evaluate(NodusConfidenceSignals(
            freshness: freshness, domainPerformance: 0.99, modelConsistency: 0.99,
            generationCompleted: true, structuredOutputValid: nil, localEvidenceCoverage: nil,
            explicitUncertainty: false, highRiskClaim: false
        ))
        XCTAssertEqual(freshness, .currentDataRequired)
        XCTAssertEqual(confidence.band, .needsVerification)
        XCTAssertLessThan(confidence.answer, 0.4)
    }

    func testNodusProviderIsLocalAndReturnsEnvelope() async throws {
        let runtime = FakeNodusRuntime(text: "Bucharest is the capital of Romania.")
        let provider = NodusIntelligenceProvider(runtime: runtime)
        let request = IntelligenceRequest(
            capability: .generate, input: .string("What is the capital of Romania?"),
            privacy: .localOnly, source: .test
        )
        let response = try await provider.execute(request, context: IntelligenceExecutionContext(source: .test))
        XCTAssertEqual(response.providerID, "modula.nodus")
        XCTAssertEqual(response.executionKind, .local)
        XCTAssertEqual(response.output.objectValue?["freshness"]?.stringValue, NodusFreshness.stable.rawValue)
        XCTAssertEqual(response.output.objectValue?["verificationRecommended"]?.boolValue, false)
    }

    func testCurrentQuestionRecommendsVerificationWithoutNetwork() async throws {
        let runtime = FakeNodusRuntime(text: "I need current data and recommend verification.")
        let provider = NodusIntelligenceProvider(runtime: runtime)
        let request = IntelligenceRequest(
            capability: .generate, input: .string("What's today's weather?"),
            privacy: .localOnly, source: .test
        )
        let response = try await provider.execute(request, context: IntelligenceExecutionContext(source: .test))
        XCTAssertEqual(response.output.objectValue?["verificationRecommended"]?.boolValue, true)
        XCTAssertEqual(response.output.objectValue?["freshness"]?.stringValue, NodusFreshness.currentDataRequired.rawValue)
        let generateCalls = await runtime.generateCalls
        XCTAssertEqual(generateCalls, 1)
    }

    func testLocalOnlyNodusNeverExecutesRemoteAIProvider() async throws {
        let runtime = FakeNodusRuntime(text: "Photosynthesis converts light energy into chemical energy.")
        let nodus = NodusIntelligenceProvider(runtime: runtime)
        let remoteCounter = SpyCallCounter()
        let remote = SpyRemoteProvider(counter: remoteCounter)
        let registry = try IntelligenceProviderRegistry(providers: [remote, nodus])
        let intelligence = ModulaIntelligence(
            providers: registry,
            remoteIntelligencePermitted: true,
            registerDeterministicLocalProvider: false
        )
        let request = IntelligenceRequest(
            capability: .generate, input: .string("Explain photosynthesis simply."),
            privacy: .localOnly, source: .test
        )
        let response = try await intelligence.execute(request)
        XCTAssertEqual(response.providerID, NodusIntelligenceProvider.providerID)
        XCTAssertEqual(response.executionKind, .local)
        let remoteExecuteCalls = await remoteCounter.executeCalls
        XCTAssertEqual(remoteExecuteCalls, 0, "localOnly + modula.nodus must make zero remote AI calls")
    }
}

final class NodusLearningLoopTests: XCTestCase {
    private var stateURL: URL!

    override func setUp() {
        super.setUp()
        stateURL = FileManager.default.temporaryDirectory
            .appending(path: "nodus-tests-\(UUID().uuidString)/state.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent())
        super.tearDown()
    }

    func testPersistedMissionAndGovernedCorrection() async throws {
        let store = NodusVerificationStore(fileURL: stateURL)
        let answer = NodusAnswer(
            answer: "The current value is probably 100.",
            confidence: NodusConfidence(answer: 0.2, evidence: 0.1, freshness: 0.04, band: .needsVerification),
            freshness: .currentDataRequired, evidenceState: .noReliableEvidence,
            verificationRecommended: true, abstained: false, reasons: ["Current evidence is required"],
            modelVersion: "Nodus test", latencySeconds: 0.1, tokensPerSecond: 20
        )
        let mission = try await store.createMission(
            question: "What is the current value?", answer: answer,
            reason: .freshnessRequired, connectivityAvailable: false
        )
        XCTAssertEqual(mission.state, .queuedOffline)
        let reloaded = NodusVerificationStore(fileURL: stateURL)
        let restoredState = await reloaded.snapshot()
        XCTAssertEqual(restoredState.missions.first?.id, mission.id)
        try await reloaded.setConnectivityAvailable(true)
        let connectedState = await reloaded.snapshot()
        XCTAssertEqual(connectedState.missions.first?.state, .readyToSync)

        let key = P256.Signing.PrivateKey()
        let unsigned = NodusVerificationResult.SignedPayload(
            schemaVersion: 1, verificationID: mission.id, question: mission.question,
            verifiedAnswer: "Checked against current evidence: the value is 120.", result: .corrected,
            sources: [NodusVerificationSource(
                id: UUID(), title: "Fixture evidence", url: URL(string: "https://example.invalid/evidence")!,
                publisher: "Nodus test", retrievedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )],
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_000), confidence: 0.9,
            provenance: NodusVerificationProvenance(missionID: mission.id.uuidString, akiDecisionID: "aki-fixture"),
            signerID: "modula.test.aki"
        )
        let signature = try key.signature(for: NodusVerificationTrustStore.payloadData(unsigned)).derRepresentation
        let result = NodusVerificationResult(
            schemaVersion: unsigned.schemaVersion, verificationID: unsigned.verificationID,
            question: unsigned.question, verifiedAnswer: unsigned.verifiedAnswer, result: unsigned.result,
            sources: unsigned.sources, verifiedAt: unsigned.verifiedAt, confidence: unsigned.confidence,
            provenance: unsigned.provenance, signerID: unsigned.signerID, signature: signature
        )
        let pipeline = NodusLearningPipeline(
            store: reloaded,
            trustStore: NodusVerificationTrustStore(publicKeys: ["modula.test.aki": key.publicKey])
        )
        let (reconciliation, candidate) = try await pipeline.ingest(result)
        XCTAssertEqual(reconciliation.result, .stale)
        XCTAssertEqual(candidate?.trainingEligibility, .ineligible)
        XCTAssertEqual(candidate?.globalTrainingConsent, false)
        let reviewed = try await pipeline.review(candidateID: try XCTUnwrap(candidate?.id), approve: true)
        XCTAssertEqual(reviewed?.trainingEligibility, .ineligible, "Verification is not training consent")
    }

    func testInvalidSignatureIsRejected() async throws {
        let store = NodusVerificationStore(fileURL: stateURL)
        let answer = NodusAnswer(
            answer: "Maybe.", confidence: NodusConfidence(answer: 0.2, evidence: 0.1, freshness: 0.3, band: .low),
            freshness: .unknown, evidenceState: .noReliableEvidence, verificationRecommended: true,
            abstained: false, reasons: [], modelVersion: "test", latencySeconds: nil, tokensPerSecond: nil
        )
        let mission = try await store.createMission(
            question: "Question?", answer: answer, reason: .lowConfidence, connectivityAvailable: true
        )
        let trusted = P256.Signing.PrivateKey()
        let result = NodusVerificationResult(
            schemaVersion: 1, verificationID: mission.id, question: mission.question,
            verifiedAnswer: "Correction", result: .corrected,
            sources: [NodusVerificationSource(
                id: UUID(), title: "Evidence", url: URL(string: "https://example.invalid")!,
                publisher: "Test", retrievedAt: Date()
            )],
            verifiedAt: Date(), confidence: 0.8,
            provenance: NodusVerificationProvenance(missionID: mission.id.uuidString, akiDecisionID: nil),
            signerID: "trusted", signature: Data([0, 1, 2])
        )
        let pipeline = NodusLearningPipeline(
            store: store, trustStore: NodusVerificationTrustStore(publicKeys: ["trusted": trusted.publicKey])
        )
        do {
            _ = try await pipeline.ingest(result)
            XCTFail("Expected invalid signature rejection")
        } catch let error as NodusVerificationValidationError {
            XCTAssertEqual(error, .invalidSignature)
        }
    }

    func testExplicitlyEligibleCorrectionBuildsDatasetRevision() async throws {
        let store = NodusVerificationStore(fileURL: stateURL)
        let answer = NodusAnswer(
            answer: "GAIA authorizes every action.",
            confidence: NodusConfidence(answer: 0.25, evidence: 0.1, freshness: 0.9, band: .low),
            freshness: .stable, evidenceState: .noReliableEvidence, verificationRecommended: true,
            abstained: false, reasons: ["Low confidence"], modelVersion: "Nodus test",
            latencySeconds: nil, tokensPerSecond: nil
        )
        let mission = try await store.createMission(
            question: "Does GAIA authorize actions?", answer: answer,
            reason: .lowConfidence, connectivityAvailable: false
        )
        let key = P256.Signing.PrivateKey()
        let payload = NodusVerificationResult.SignedPayload(
            schemaVersion: 1, verificationID: mission.id, question: mission.question,
            verifiedAnswer: "No. GAIA proposes and plans; the Governor remains the authorization boundary.",
            result: .corrected,
            sources: [NodusVerificationSource(
                id: UUID(), title: "Modula architecture fixture",
                url: URL(string: "https://example.invalid/modula-architecture")!,
                publisher: "Modula", retrievedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )],
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_000), confidence: 0.98,
            provenance: NodusVerificationProvenance(
                missionID: mission.id.uuidString, akiDecisionID: "aki-approved-fixture"
            ),
            signerID: "modula.test.aki"
        )
        let signature = try key.signature(
            for: NodusVerificationTrustStore.payloadData(payload)
        ).derRepresentation
        let result = NodusVerificationResult(
            schemaVersion: payload.schemaVersion, verificationID: payload.verificationID,
            question: payload.question, verifiedAnswer: payload.verifiedAnswer, result: payload.result,
            sources: payload.sources, verifiedAt: payload.verifiedAt, confidence: payload.confidence,
            provenance: payload.provenance, signerID: payload.signerID, signature: signature
        )
        let pipeline = NodusLearningPipeline(
            store: store,
            trustStore: NodusVerificationTrustStore(publicKeys: ["modula.test.aki": key.publicKey])
        )
        let (_, candidate) = try await pipeline.ingest(
            result, privacyClass: .internalNonSecret, globalTrainingConsent: true
        )
        let candidateID = try XCTUnwrap(candidate?.id)
        let reviewed = try await pipeline.review(candidateID: candidateID, approve: true)
        XCTAssertEqual(reviewed?.trainingEligibility, .approved)

        let revision = try await pipeline.buildDatasetRevision(
            id: "nodus-training-fixture-v0.2", parent: "nodus-training-v0.1"
        )
        XCTAssertEqual(revision.approvedCandidateIDs, [candidateID])
        XCTAssertEqual(revision.approvedCandidateHashes[candidateID.uuidString]?.count, 64)
        XCTAssertEqual(revision.sourceVerificationIDs, [result.verificationID])
        XCTAssertEqual(revision.contentHash.count, 64)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.datasetRevisions.last?.id, revision.id)
    }
}

final class NodusArtifactTests: XCTestCase {
    private func manifest(artifactHash: String, fileHash: String) -> NodusModelManifest {
        NodusModelManifest(
            schemaVersion: 1, nodusVersion: "Nodus test", parameters: 1,
            baseModel: "test", baseRevision: "revision", license: "Apache-2.0",
            fineTuningMethod: "LoRA", datasetRevision: "test", evalSuiteRevision: "test",
            quantization: "4-bit", artifactHash: artifactHash, trainingDate: "2026-09-20",
            knowledgeProvenance: ["test"], files: ["model.safetensors": fileHash]
        )
    }

    func testHashMismatchRejectsArtifact() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nodus-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = directory.appending(path: "model.safetensors")
        try Data("not-the-model".utf8).write(to: model)
        let manifest = NodusModelManifest(
            schemaVersion: 1, nodusVersion: "Nodus test", parameters: 1,
            baseModel: "test", baseRevision: "revision", license: "Apache-2.0",
            fineTuningMethod: "LoRA", datasetRevision: "test", evalSuiteRevision: "test",
            quantization: "4-bit", artifactHash: "sha256:test", trainingDate: "2026-09-20",
            knowledgeProvenance: ["test"], files: ["model.safetensors": String(repeating: "0", count: 64)]
        )
        XCTAssertThrowsError(try NodusArtifactInstaller.verify(manifest: manifest, in: directory)) { error in
            XCTAssertEqual(error as? NodusArtifactError, .hashMismatch("model.safetensors"))
        }
    }

    func testManifestArtifactHashMismatchIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nodus-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = directory.appending(path: "model.safetensors")
        try Data("fixture-model".utf8).write(to: model)
        let fileHash = SHA256.hash(data: Data("fixture-model".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let manifest = NodusModelManifest(
            schemaVersion: 1, nodusVersion: "Nodus test", parameters: 1,
            baseModel: "test", baseRevision: "revision", license: "Apache-2.0",
            fineTuningMethod: "LoRA", datasetRevision: "test", evalSuiteRevision: "test",
            quantization: "4-bit", artifactHash: "sha256:tampered", trainingDate: "2026-09-20",
            knowledgeProvenance: ["test"], files: ["model.safetensors": fileHash]
        )
        XCTAssertThrowsError(try NodusArtifactInstaller.verify(manifest: manifest, in: directory)) { error in
            XCTAssertEqual(error as? NodusArtifactError, .artifactHashMismatch)
        }
    }

    func testPythonCanonicalArtifactHashIsAcceptedByNativeVerifier() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nodus-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelData = Data("fixture-model".utf8)
        try modelData.write(to: directory.appending(path: "model.safetensors"))
        let decodedManifest = manifest(
            artifactHash: "sha256:c36b11cfd497d6d929cc34fa5cf7c926478d3f96b0df58eda622e6feeac7b33b",
            fileHash: "e6954ed9cce48114b2875996c433c4ada96795c4f7b5401b3ed7578086bbe242"
        )

        XCTAssertNoThrow(try NodusArtifactInstaller.verify(manifest: decodedManifest, in: directory))
    }

    func testUnlistedArtifactFileIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nodus-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelData = Data("fixture-model".utf8)
        try modelData.write(to: directory.appending(path: "model.safetensors"))
        try Data("not-in-manifest".utf8).write(to: directory.appending(path: "remote-code.py"))
        let fileHash = SHA256.hash(data: modelData).map { String(format: "%02x", $0) }.joined()

        XCTAssertThrowsError(
            try NodusArtifactInstaller.verify(
                manifest: manifest(artifactHash: "sha256:unused", fileHash: fileHash),
                in: directory
            )
        ) { error in
            XCTAssertEqual(error as? NodusArtifactError, .unexpectedFile("remote-code.py"))
        }
    }

    func testSymbolicLinkInArtifactIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nodus-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelData = Data("fixture-model".utf8)
        let model = directory.appending(path: "model.safetensors")
        try modelData.write(to: model)
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "tokenizer.json"),
            withDestinationURL: model
        )
        let fileHash = SHA256.hash(data: modelData).map { String(format: "%02x", $0) }.joined()

        XCTAssertThrowsError(
            try NodusArtifactInstaller.verify(
                manifest: manifest(artifactHash: "sha256:unused", fileHash: fileHash),
                in: directory
            )
        ) { error in
            XCTAssertEqual(error as? NodusArtifactError, .symbolicLink("tokenizer.json"))
        }
    }

    func testExternalExpectedHashIsRequiredForInstallation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nodus-source-\(UUID().uuidString)")
        let installRoot = FileManager.default.temporaryDirectory.appending(path: "nodus-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: installRoot)
        }
        let modelData = Data("fixture-model".utf8)
        try modelData.write(to: directory.appending(path: "model.safetensors"))
        let fileHash = SHA256.hash(data: modelData).map { String(format: "%02x", $0) }.joined()
        let decodedManifest = manifest(artifactHash: "sha256:" + String(repeating: "a", count: 64), fileHash: fileHash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(decodedManifest).write(to: directory.appending(path: "nodus-manifest.json"))

        let installer = NodusArtifactInstaller(root: installRoot)
        do {
            _ = try await installer.installVerifiedArtifact(
                from: directory,
                expectedArtifactHash: "sha256:" + String(repeating: "b", count: 64)
            )
            XCTFail("Expected an externally pinned hash mismatch")
        } catch let error as NodusArtifactError {
            XCTAssertEqual(error, .unexpectedArtifactHash)
        }
    }

    func testVerifiedInstallationRetainsPreviousArtifactForRollback() async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "nodus-install-test-\(UUID().uuidString)")
        let firstSource = temporary.appending(path: "first")
        let secondSource = temporary.appending(path: "second")
        let installRoot = temporary.appending(path: "models")
        try FileManager.default.createDirectory(at: firstSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        func writeSource(_ directory: URL, content: String, fileHash: String, artifactHash: String) throws {
            try Data(content.utf8).write(to: directory.appending(path: "model.safetensors"))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest(artifactHash: "sha256:" + artifactHash, fileHash: fileHash))
                .write(to: directory.appending(path: "nodus-manifest.json"))
        }
        try writeSource(
            firstSource, content: "fixture-model",
            fileHash: "e6954ed9cce48114b2875996c433c4ada96795c4f7b5401b3ed7578086bbe242",
            artifactHash: "c36b11cfd497d6d929cc34fa5cf7c926478d3f96b0df58eda622e6feeac7b33b"
        )
        try writeSource(
            secondSource, content: "fixture-model-v2",
            fileHash: "ac9ac9cdd2e8f1c615f163b2ffe321aeedf62bc47fec13a837a1cd180a835ecd",
            artifactHash: "235e592ddb623ac9701e7240e392a3d58fe48b0b810d082f026ba041287a7e73"
        )

        let installer = NodusArtifactInstaller(root: installRoot)
        _ = try await installer.installVerifiedArtifact(
            from: firstSource,
            expectedArtifactHash: "sha256:c36b11cfd497d6d929cc34fa5cf7c926478d3f96b0df58eda622e6feeac7b33b"
        )
        _ = try await installer.installVerifiedArtifact(
            from: secondSource,
            expectedArtifactHash: "sha256:235e592ddb623ac9701e7240e392a3d58fe48b0b810d082f026ba041287a7e73"
        )

        XCTAssertEqual(
            try String(contentsOf: installRoot.appending(path: "accepted/model.safetensors"), encoding: .utf8),
            "fixture-model-v2"
        )
        XCTAssertEqual(
            try String(contentsOf: installRoot.appending(path: "previous/model.safetensors"), encoding: .utf8),
            "fixture-model"
        )
        let rolledBack = try await installer.rollbackToPreviousArtifact()
        XCTAssertTrue(rolledBack)
        XCTAssertEqual(
            try String(contentsOf: installRoot.appending(path: "accepted/model.safetensors"), encoding: .utf8),
            "fixture-model"
        )
        XCTAssertEqual(
            try String(contentsOf: installRoot.appending(path: "previous/model.safetensors"), encoding: .utf8),
            "fixture-model-v2"
        )
    }
}

/// Opt-in simulator acceptance. The test skips in ordinary CI until an externally
/// hashed Nodus artifact has been installed into the test host's accepted directory.
final class NodusInstalledRuntimeIntegrationTests: XCTestCase {
    private func installedDirectory() throws -> URL {
        let support = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let directory = support.appending(path: "Modula/Nodus/models/accepted")
        guard FileManager.default.fileExists(atPath: directory.appending(path: "nodus-manifest.json").path) else {
            throw XCTSkip("Install the externally verified Nodus artifact before runtime acceptance")
        }
        return directory
    }

    func testInstalledModelGeneralModulaFreshnessAndCancellation() async throws {
        let runtime = MLXNodusRuntime(modelDirectory: try installedDirectory(), minimumMemoryBytes: 0)
        let availability = await runtime.availability()
        XCTAssertEqual(availability, .available)
        let provider = NodusIntelligenceProvider(runtime: runtime)

        let general = try await provider.execute(
            IntelligenceRequest(
                capability: .generate, input: .string("What is the capital of Romania?"),
                privacy: .localOnly, source: .test
            ),
            context: IntelligenceExecutionContext(source: .test)
        )
        XCTAssertTrue(general.output.objectValue?["answer"]?.stringValue?.localizedCaseInsensitiveContains("Bucharest") == true)

        let modula = try await provider.execute(
            IntelligenceRequest(
                capability: .generate, input: .string("What's the difference between GAIA and AKI?"),
                privacy: .localOnly, source: .test
            ),
            context: IntelligenceExecutionContext(source: .test)
        )
        let modulaAnswer = try XCTUnwrap(modula.output.objectValue?["answer"]?.stringValue?.lowercased())
        XCTAssertTrue(modulaAnswer.contains("gaia"))
        XCTAssertTrue(modulaAnswer.contains("aki"))

        let freshness = try await provider.execute(
            IntelligenceRequest(
                capability: .generate, input: .string("What's today's weather?"),
                privacy: .localOnly, source: .test
            ),
            context: IntelligenceExecutionContext(source: .test)
        )
        XCTAssertEqual(
            freshness.output.objectValue?["freshness"]?.stringValue,
            NodusFreshness.currentDataRequired.rawValue
        )
        XCTAssertEqual(freshness.output.objectValue?["verificationRecommended"]?.boolValue, true)

        let cancellation = Task {
            try await provider.execute(
                IntelligenceRequest(
                    capability: .generate,
                    input: .string("Write a very long explanation of every layer of the Internet protocol stack."),
                    privacy: .localOnly,
                    source: .test
                ),
                context: IntelligenceExecutionContext(source: .test)
            )
        }
        cancellation.cancel()
        do {
            _ = try await cancellation.value
            XCTFail("Cancelled generation unexpectedly completed")
        } catch let error as IntelligenceError {
            XCTAssertEqual(error, .requestCancelled)
        }
        await runtime.unload()
        let finalLoadState = await runtime.loadState()
        XCTAssertEqual(finalLoadState, .unloaded)
    }
}
