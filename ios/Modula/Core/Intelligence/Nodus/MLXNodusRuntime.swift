import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(Tokenizers)
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor MLXNodusRuntime: NodusRuntime {
    private let modelDirectory: URL
    private let modelVersion: String
    private let identity: NodusModelIdentity?
    private let enabled: Bool
    private let minimumMemoryBytes: UInt64
    private var state: NodusLoadState = .unloaded
    private var container: ModelContainer?

    init(
        modelDirectory: URL,
        modelVersion: String = "Nodus R7 Experimental",
        identity: NodusModelIdentity? = nil,
        enabled: Bool = true,
        minimumMemoryBytes: UInt64 = 6 * 1_024 * 1_024 * 1_024
    ) {
        self.modelDirectory = modelDirectory
        self.modelVersion = modelVersion
        self.identity = identity
        self.enabled = enabled
        self.minimumMemoryBytes = minimumMemoryBytes
    }

    func availability() -> IntelligenceAvailability {
        if !enabled { return .disabled }
        if ProcessInfo.processInfo.physicalMemory < minimumMemoryBytes { return .insufficientMemory }
        let downloadingMarker = modelDirectory.deletingLastPathComponent().appending(path: "download.in-progress")
        if FileManager.default.fileExists(atPath: downloadingMarker.path) { return .modelDownloading }
        let acceptedManifest = modelDirectory.appending(path: "nodus-manifest.json")
        let experimentalManifest = modelDirectory.appending(path: NodusExperimentalManifest.fileName)
        guard FileManager.default.fileExists(atPath: acceptedManifest.path)
                || FileManager.default.fileExists(atPath: experimentalManifest.path) else {
            return .modelNotInstalled
        }
        // MLX does not support iOS Simulator execution and aborts while
        // constructing its Metal scheduler, including on the CPU stream.
        // Report the limitation before touching MLX so Developer Chat fails
        // safely instead of terminating the app. Physical devices are
        // unaffected and continue through the real local MLX path.
        #if targetEnvironment(simulator)
        return .unsupportedDevice
        #endif
        return state == .failed ? .temporarilyUnavailable : .available
    }

    func loadState() -> NodusLoadState { state }

    func load() async throws {
        if container != nil { return }
        guard availability() == .available else {
            throw IntelligenceError.providerUnavailable(providerID: NodusIntelligenceProvider.providerID)
        }
        state = .loading
        do {
            if FileManager.default.fileExists(
                atPath: modelDirectory.appending(path: NodusExperimentalManifest.fileName).path
            ) {
                let manifest = try NodusExperimentalManifest.load(from: modelDirectory)
                try manifest.verify(in: modelDirectory)
            } else {
                let installer = NodusArtifactInstaller(root: modelDirectory.deletingLastPathComponent())
                guard let manifest = try await installer.installedManifest() else {
                    throw NodusArtifactError.invalidManifest
                }
                try NodusArtifactInstaller.verify(manifest: manifest, in: modelDirectory)
            }
            container = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: #huggingFaceTokenizerLoader()
            )
            state = .loaded
        } catch let artifactError as NodusArtifactError {
            state = .failed
            throw IntelligenceError.providerFailure(
                providerID: NodusIntelligenceProvider.providerID,
                detail: "MODEL_MANIFEST_\(artifactError)"
            )
        } catch {
            state = .failed
            throw IntelligenceError.providerFailure(
                providerID: NodusIntelligenceProvider.providerID,
                detail: "MLX_MODEL_LOAD_FAILED_\(String(describing: error))"
            )
        }
    }

    func generate(prompt: String, capability: IntelligenceCapability) async throws -> NodusRuntimeGeneration {
        try await generate(prompt: prompt, capability: capability, budget: .standard)
    }

    func generate(
        prompt: String,
        capability: IntelligenceCapability,
        budget: NodusGenerationBudget
    ) async throws -> NodusRuntimeGeneration {
        try Task.checkCancellation()
        if container == nil { try await load() }
        guard let container else {
            throw IntelligenceError.providerUnavailable(providerID: NodusIntelligenceProvider.providerID)
        }
        state = .generating
        defer { state = .loaded }
        let input = UserInput(chat: [
            .system(NodusPromptContract.system),
            .user(prompt),
        ], additionalContext: ["enable_thinking": false])
        let prepared = try await container.prepare(input: input)
        let stream = try await container.generate(
            input: prepared,
            parameters: GenerateParameters(
                maxTokens: min(max(budget.maximumOutputTokens, 64), 768),
                temperature: budget.reasoningMode == .deep ? 0.15 : 0.2,
                topP: 0.9
            )
        )
        var text = ""
        var tokensPerSecond: Double?
        for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let chunk): text += chunk
            case .info(let info): tokensPerSecond = info.tokensPerSecond
            case .toolCall: break // Tool output is never execution or authorization.
            }
        }
        return NodusRuntimeGeneration(
            text: NodusPromptContract.normalize(text), modelVersion: modelVersion,
            completed: true, tokensPerSecond: tokensPerSecond, modelConsistency: nil
        )
    }

    func unload() { container = nil; state = .unloaded }

    func modelIdentity() -> NodusModelIdentity? { identity }

}
#endif

enum NodusRuntimeFactory {
    static func makeDefault() -> any NodusRuntime {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(Tokenizers)
        let preference = UserDefaults.standard.object(forKey: "modula.nodus.enabled") as? Bool
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appending(path: "Nodus/R7")
            if let manifest = try? NodusExperimentalManifest.load(from: bundled) {
                return MLXNodusRuntime(
                    modelDirectory: bundled,
                    modelVersion: manifest.displayName,
                    identity: manifest.identity,
                    enabled: preference ?? true
                )
            }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return MLXNodusRuntime(
            modelDirectory: support.appending(path: "Modula/Nodus/models/accepted"),
            enabled: preference ?? true
        )
        #else
        return UnavailableNodusRuntime(availability: .unsupportedDevice)
        #endif
    }
}
