import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provider-neutral states exposed by the narrow Foundation Models test seam.
enum AppleFoundationModelAvailability: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedOS
    case frameworkUnavailable
    case unknown
}

enum AppleFoundationModelRequest: Sendable, Equatable {
    case text(instructions: String, prompt: String)
    case classification(instructions: String, prompt: String)
}

enum AppleFoundationModelOutput: Sendable, Equatable {
    case text(String)
    case classification(String)
}

enum AppleFoundationModelFailure: Error, Sendable, Equatable {
    case unavailable
    case simulatorUnsupported
    case contextLimitExceeded
    case unsupportedLanguage
    case safetyRefusal
    case invalidStructuredOutput
    case timedOut
    case cancelled
    case providerFailure
}

/// One deliberately narrow seam around Apple's runtime. Tests provide a fake;
/// production uses a fresh `LanguageModelSession` for every call.
protocol AppleFoundationModelRuntime: Sendable {
    func availability() async -> AppleFoundationModelAvailability
    func respond(to request: AppleFoundationModelRequest) async throws -> AppleFoundationModelOutput
}

struct ApplePromptAdapter: Sendable {
    static let classificationCategories = ["productivity", "social", "finance", "developer"]

    func request(for request: IntelligenceRequest) throws -> AppleFoundationModelRequest {
        switch request.capability {
        case .summarize:
            return .text(
                instructions: "Summarize the supplied text accurately and concisely.",
                prompt: try text(from: request.input)
            )
        case .rewrite:
            return .text(
                instructions: "Rewrite the supplied text while preserving its meaning.",
                prompt: try text(from: request.input)
            )
        case .generate:
            return .text(
                instructions: "Generate concise content that directly follows the supplied request.",
                prompt: try text(from: request.input)
            )
        case .extract:
            return .text(
                instructions: "Extract the important facts from the supplied text concisely.",
                prompt: try text(from: request.input)
            )
        case .intent:
            return .text(
                instructions: "Identify the primary intent of the supplied text concisely.",
                prompt: try text(from: request.input)
            )
        case .classify:
            let payload = try classificationPayload(from: request.input)
            return .classification(
                instructions: "Classify the supplied content into exactly one supported category.",
                prompt: payload.text
            )
        case .toolCall:
            throw IntelligenceError.capabilityUnsupported
        }
    }

    private func text(from value: IntelligenceValue) throws -> String {
        let text: String?
        switch value {
        case .string(let value):
            text = value
        case .object(let object):
            text = object["text"]?.stringValue
        default:
            text = nil
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntelligenceError.invalidRequest(detail: "Apple provider requires non-empty string input or an object with a text string")
        }
        return text
    }

    private func classificationPayload(from value: IntelligenceValue) throws -> (text: String, categories: [String]) {
        guard case .object(let object) = value,
              let text = object["text"]?.stringValue,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let categoryValues = object["categories"]?.arrayValue else {
            throw IntelligenceError.invalidRequest(detail: "Classification requires text and categories")
        }

        let categories = categoryValues.compactMap(\.stringValue)
        guard categories.count == categoryValues.count,
              categories.count == Self.classificationCategories.count,
              Set(categories) == Set(Self.classificationCategories) else {
            throw IntelligenceError.invalidRequest(
                detail: "Mission 03 classification categories must be productivity, social, finance, and developer"
            )
        }
        return (text, categories)
    }
}

struct AppleSystemIntelligenceProvider: IntelligenceProvider {
    static let providerID = "apple.system"
    static let supportedCapabilities: Set<IntelligenceCapability> = [
        .generate, .rewrite, .summarize, .classify, .extract, .intent,
    ]

    let id = Self.providerID
    let executionKind: IntelligenceExecutionKind = .local
    let capabilities = Self.supportedCapabilities

    private let runtime: any AppleFoundationModelRuntime
    private let promptAdapter = ApplePromptAdapter()

    init(runtime: any AppleFoundationModelRuntime = LiveAppleFoundationModelRuntime()) {
        self.runtime = runtime
    }

    func availability() async -> IntelligenceAvailability {
        switch await runtime.availability() {
        case .available: .available
        case .deviceNotEligible: .unsupportedDevice
        case .appleIntelligenceNotEnabled: .disabled
        case .modelNotReady: .modelNotInstalled
        case .unsupportedOS: .unsupportedOS
        case .frameworkUnavailable: .unavailable
        case .unknown: .temporarilyUnavailable
        }
    }

    func execute(
        _ request: IntelligenceRequest,
        context: IntelligenceExecutionContext
    ) async throws -> IntelligenceResponse {
        try Task.checkCancellation()
        guard capabilities.contains(request.capability) else {
            throw IntelligenceError.capabilityUnsupported
        }
        guard await availability() == .available else {
            throw IntelligenceError.providerUnavailable(providerID: id)
        }

        let runtimeRequest = try promptAdapter.request(for: request)
        let started = ContinuousClock.now

        do {
            let runtimeOutput = try await runtime.respond(to: runtimeRequest)
            try Task.checkCancellation()
            let output: IntelligenceValue
            switch runtimeOutput {
            case .text(let content):
                let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else {
                    throw IntelligenceError.providerFailure(providerID: id, detail: "EMPTY_RESPONSE")
                }
                output = .string(content)
            case .classification(let category):
                guard ApplePromptAdapter.classificationCategories.contains(category) else {
                    throw IntelligenceError.providerFailure(providerID: id, detail: "INVALID_CLASSIFICATION")
                }
                output = .object(["category": .string(category)])
            }

            return IntelligenceResponse(
                requestID: request.id,
                capability: request.capability,
                output: output,
                providerID: id,
                executionKind: .local,
                duration: ContinuousClock.now - started
            )
        } catch is CancellationError {
            throw IntelligenceError.requestCancelled
        } catch let failure as AppleFoundationModelFailure {
            if Task.isCancelled {
                throw IntelligenceError.requestCancelled
            }
            throw map(failure)
        } catch {
            if Task.isCancelled {
                throw IntelligenceError.requestCancelled
            }
            throw IntelligenceError.providerFailure(providerID: id, detail: "APPLE_RUNTIME_FAILURE")
        }
    }

    private func map(_ failure: AppleFoundationModelFailure) -> IntelligenceError {
        switch failure {
        case .unavailable, .simulatorUnsupported:
            .providerUnavailable(providerID: id)
        case .contextLimitExceeded:
            .contextLimitExceeded
        case .unsupportedLanguage:
            .unsupportedLanguage
        case .safetyRefusal:
            .safetyRefusal
        case .cancelled:
            .requestCancelled
        case .invalidStructuredOutput:
            .providerFailure(providerID: id, detail: "INVALID_STRUCTURED_OUTPUT")
        case .timedOut:
            .providerFailure(providerID: id, detail: "TIMEOUT")
        case .providerFailure:
            .providerFailure(providerID: id, detail: "APPLE_RUNTIME_FAILURE")
        }
    }
}

struct LiveAppleFoundationModelRuntime: AppleFoundationModelRuntime {
    func availability() async -> AppleFoundationModelAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .unsupportedOS }
        return Self.mapAvailability(SystemLanguageModel.default.availability)
        #else
        return .frameworkUnavailable
        #endif
    }

    func respond(to request: AppleFoundationModelRequest) async throws -> AppleFoundationModelOutput {
        try Task.checkCancellation()
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw AppleFoundationModelFailure.unavailable
        }
        return try await Self.respondOnSupportedOS(to: request)
        #else
        throw AppleFoundationModelFailure.unavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func mapAvailability(
        _ availability: SystemLanguageModel.Availability
    ) -> AppleFoundationModelAvailability {
        switch availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            .modelNotReady
        @unknown default:
            .unknown
        }
    }

    @available(iOS 26.0, *)
    private static func respondOnSupportedOS(
        to request: AppleFoundationModelRequest
    ) async throws -> AppleFoundationModelOutput {
        guard mapAvailability(SystemLanguageModel.default.availability) == .available else {
            throw AppleFoundationModelFailure.unavailable
        }

        do {
            switch request {
            case .text(let instructions, let prompt):
                let session = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: instructions
                )
                let response = try await session.respond(to: prompt)
                return .text(response.content)
            case .classification(let instructions, let prompt):
                let session = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: instructions
                )
                let response = try await session.respond(
                    to: prompt,
                    generating: AppleClassificationResult.self
                )
                return .classification(response.content.category.rawValue)
            }
        } catch is CancellationError {
            throw AppleFoundationModelFailure.cancelled
        } catch {
            throw mapRuntimeError(error)
        }
    }

    @available(iOS 26.0, *)
    private static func mapRuntimeError(_ error: any Error) -> AppleFoundationModelFailure {
        #if DEBUG
        let diagnosticError = error as NSError
        ModulaLog.intelligence.debug(
            "apple runtime error type=\(String(describing: type(of: error)), privacy: .public) domain=\(diagnosticError.domain, privacy: .public) code=\(diagnosticError.code, privacy: .public)"
        )
        #endif
        if isSimulatorUnsupported(error) {
            return .simulatorUnsupported
        }
        if #available(iOS 27.0, *) {
            if let error = error as? SystemLanguageModel.Error {
                switch error {
                case .assetsUnavailable:
                    return .unavailable
                @unknown default:
                    return opaqueRuntimeFailure()
                }
            }
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded:
                    return .contextLimitExceeded
                case .guardrailViolation, .refusal:
                    return .safetyRefusal
                case .unsupportedLanguageOrLocale:
                    return .unsupportedLanguage
                case .unsupportedGenerationGuide, .unsupportedCapability, .unsupportedTranscriptContent:
                    return .invalidStructuredOutput
                case .timeout:
                    return .timedOut
                case .rateLimited:
                    return .providerFailure
                @unknown default:
                    return opaqueRuntimeFailure()
                }
            }
        } else if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return .contextLimitExceeded
            case .assetsUnavailable:
                return .unavailable
            case .guardrailViolation, .refusal:
                return .safetyRefusal
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguage
            case .unsupportedGuide, .decodingFailure:
                return .invalidStructuredOutput
            case .rateLimited, .concurrentRequests:
                return .providerFailure
            @unknown default:
                return opaqueRuntimeFailure()
            }
        }
        return opaqueRuntimeFailure()
    }

    @available(iOS 26.0, *)
    private static func opaqueRuntimeFailure() -> AppleFoundationModelFailure {
        #if targetEnvironment(simulator)
        // Simulator can currently surface model-service environment failures as
        // opaque errors even when `availability == .available`. Keep this out of
        // the general provider-failure bucket so diagnostics do not blame prompts.
        return .simulatorUnsupported
        #else
        return .providerFailure
        #endif
    }

    @available(iOS 26.0, *)
    private static func isSimulatorUnsupported(_ error: any Error) -> Bool {
        let root = error as NSError
        let rootDescriptions = [
            String(describing: error),
            String(reflecting: error),
            root.localizedDescription,
            root.debugDescription,
            String(describing: root.userInfo),
        ]
        if rootDescriptions.contains(where: {
            $0.localizedCaseInsensitiveContains("Simulator is not supported")
        }) {
            return true
        }

        var current: NSError? = error as NSError
        while let candidate = current {
            let descriptions = [
                candidate.localizedDescription,
                candidate.debugDescription,
                String(describing: candidate.userInfo),
            ]
            if descriptions.contains(where: {
                $0.localizedCaseInsensitiveContains("Simulator is not supported")
            }) {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct AppleClassificationResult {
    var category: AppleClassificationCategory
}

@available(iOS 26.0, *)
@Generable
private enum AppleClassificationCategory: String {
    case productivity
    case social
    case finance
    case developer
}
#endif
