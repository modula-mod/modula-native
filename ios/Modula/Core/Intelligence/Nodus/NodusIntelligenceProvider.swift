import Foundation

struct NodusIntelligenceProvider: IntelligenceProvider {
    static let providerID = "modula.nodus"
    static let supportedCapabilities: Set<IntelligenceCapability> = [
        .generate, .rewrite, .summarize, .classify, .extract, .intent,
    ]

    let id = Self.providerID
    let executionKind: IntelligenceExecutionKind = .local
    let capabilities = Self.supportedCapabilities
    private let runtime: any NodusRuntime
    private let freshnessClassifier: NodusFreshnessClassifier
    private let confidenceEngine: NodusConfidenceEngine

    init(
        runtime: any NodusRuntime = UnavailableNodusRuntime(),
        freshnessClassifier: NodusFreshnessClassifier = NodusFreshnessClassifier(),
        confidenceEngine: NodusConfidenceEngine = NodusConfidenceEngine()
    ) {
        self.runtime = runtime
        self.freshnessClassifier = freshnessClassifier
        self.confidenceEngine = confidenceEngine
    }

    func availability() async -> IntelligenceAvailability { await runtime.availability() }

    func loadState() async -> NodusLoadState { await runtime.loadState() }

    func modelIdentity() async -> NodusModelIdentity? { await runtime.modelIdentity() }

    func unload() async { await runtime.unload() }

    func execute(_ request: IntelligenceRequest, context: IntelligenceExecutionContext) async throws -> IntelligenceResponse {
        try Task.checkCancellation()
        guard capabilities.contains(request.capability) else { throw IntelligenceError.capabilityUnsupported }
        guard let prompt = Self.prompt(from: request.input), !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntelligenceError.invalidRequest(detail: "Nodus requires a non-empty string or object text")
        }
        let taskMode = Self.taskMode(from: request.input) ?? .defaultMode(for: request.capability)
        let contractedPrompt = NodusPromptContract.prompt(mode: taskMode, input: prompt)
        let started = ContinuousClock.now
        try await runtime.load()
        let generation: NodusRuntimeGeneration
        do {
            generation = try await runtime.generate(
                prompt: contractedPrompt,
                capability: request.capability,
                budget: NodusGenerationBudget(
                    maximumOutputTokens: Self.maximumOutputTokens(from: request.input),
                    reasoningMode: Self.reasoningMode(from: request.input)
                )
            )
        } catch is CancellationError {
            throw IntelligenceError.requestCancelled
        }
        try Task.checkCancellation()
        // Conversation requests contain identity, history, and evidence scaffolding with phrases such as
        // "current request". Classifying that assembled prompt makes otherwise stable questions look live.
        // Prefer the router's classification when the trusted conversation engine supplies it.
        let freshness = Self.freshness(from: request.input) ?? freshnessClassifier.classify(prompt)
        let normalizedText = NodusPromptContract.normalize(generation.text)
        let normalized = normalizedText.lowercased()
        let uncertain = normalized.contains("not enough reliable") || normalized.contains("uncertain") || normalized.contains("verify")
        let confidence = confidenceEngine.evaluate(NodusConfidenceSignals(
            freshness: freshness,
            domainPerformance: nil,
            modelConsistency: generation.modelConsistency,
            generationCompleted: generation.completed,
            structuredOutputValid: request.capability == .classify || request.capability == .intent ? !generation.text.isEmpty : nil,
            localEvidenceCoverage: nil,
            explicitUncertainty: uncertain,
            highRiskClaim: Self.isHighRisk(prompt)
        ))
        let verify = freshness == .currentDataRequired || confidence.band == .low || confidence.band == .needsVerification
        let abstained = normalized.contains("don't have enough") || normalized.contains("cannot answer reliably")
        var reasons: [String] = []
        if freshness == .currentDataRequired { reasons.append("Current evidence is required") }
        if freshness == .possiblyStale { reasons.append("Local knowledge may be stale") }
        if confidence.band == .low { reasons.append("Answer confidence is low") }
        if Self.isHighRisk(prompt) { reasons.append("High-risk factual claim") }
        let elapsed = ContinuousClock.now - started
        let components = elapsed.components
        let latency = Double(components.seconds) + Double(components.attoseconds) / 1e18
        let envelope = NodusAnswer(
            answer: normalizedText,
            confidence: confidence,
            freshness: freshness,
            evidenceState: .modelKnowledge,
            verificationRecommended: verify,
            abstained: abstained,
            reasons: reasons,
            modelVersion: generation.modelVersion,
            latencySeconds: latency,
            tokensPerSecond: generation.tokensPerSecond,
            taskMode: taskMode
        )
        return IntelligenceResponse(
            requestID: request.id,
            capability: request.capability,
            output: envelope.intelligenceValue,
            providerID: id,
            executionKind: .local,
            duration: elapsed
        )
    }

    private static func prompt(from input: IntelligenceValue) -> String? {
        switch input {
        case .string(let value): value
        case .object(let object): object["text"]?.stringValue ?? object["prompt"]?.stringValue
        default: nil
        }
    }

    private static func taskMode(from input: IntelligenceValue) -> NodusTaskMode? {
        guard case .object(let object) = input,
              let raw = object["taskMode"]?.stringValue else { return nil }
        return NodusTaskMode(rawValue: raw)
    }

    private static func maximumOutputTokens(from input: IntelligenceValue) -> Int {
        guard case .object(let object) = input,
              let requested = object["maxOutputTokens"]?.integerValue else { return 384 }
        return min(max(requested, 64), 768)
    }

    private static func reasoningMode(from input: IntelligenceValue) -> NodusReasoningMode {
        guard case .object(let object) = input,
              let raw = object["reasoningMode"]?.stringValue,
              let mode = NodusReasoningMode(rawValue: raw) else { return .standard }
        return mode
    }

    private static func freshness(from input: IntelligenceValue) -> NodusFreshness? {
        guard case .object(let object) = input,
              let raw = object["freshness"]?.stringValue else { return nil }
        return NodusFreshness(rawValue: raw)
    }

    private static func isHighRisk(_ prompt: String) -> Bool {
        let text = prompt.lowercased()
        return ["diagnos", "medication", "legal advice", "invest ", "tax advice"].contains(where: text.contains)
    }
}
