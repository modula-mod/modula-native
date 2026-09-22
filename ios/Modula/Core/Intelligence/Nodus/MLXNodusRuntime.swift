import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(Tokenizers)
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor MLXNodusRuntime: NodusRuntime {
    private let modelDirectory: URL
    private let modelVersion: String
    private let enabled: Bool
    private let minimumMemoryBytes: UInt64
    private var state: NodusLoadState = .unloaded
    private var container: ModelContainer?

    init(
        modelDirectory: URL,
        modelVersion: String = "Nodus v0.1",
        enabled: Bool = true,
        minimumMemoryBytes: UInt64 = 6 * 1_024 * 1_024 * 1_024
    ) {
        self.modelDirectory = modelDirectory
        self.modelVersion = modelVersion
        self.enabled = enabled
        self.minimumMemoryBytes = minimumMemoryBytes
    }

    func availability() -> IntelligenceAvailability {
        if !enabled { return .disabled }
        if ProcessInfo.processInfo.physicalMemory < minimumMemoryBytes { return .insufficientMemory }
        let downloadingMarker = modelDirectory.deletingLastPathComponent().appending(path: "download.in-progress")
        if FileManager.default.fileExists(atPath: downloadingMarker.path) { return .modelDownloading }
        guard FileManager.default.fileExists(atPath: modelDirectory.appending(path: "nodus-manifest.json").path) else {
            return .modelNotInstalled
        }
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
            let installer = NodusArtifactInstaller(root: modelDirectory.deletingLastPathComponent())
            guard let manifest = try await installer.installedManifest() else {
                throw NodusArtifactError.invalidManifest
            }
            try NodusArtifactInstaller.verify(manifest: manifest, in: modelDirectory)
            container = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: #huggingFaceTokenizerLoader()
            )
            state = .loaded
        } catch {
            state = .failed
            throw IntelligenceError.providerFailure(
                providerID: NodusIntelligenceProvider.providerID,
                detail: "MODEL_LOAD_FAILED"
            )
        }
    }

    func generate(prompt: String, capability: IntelligenceCapability) async throws -> NodusRuntimeGeneration {
        try Task.checkCancellation()
        if container == nil { try await load() }
        guard let container else {
            throw IntelligenceError.providerUnavailable(providerID: NodusIntelligenceProvider.providerID)
        }
        state = .generating
        defer { state = .loaded }
        let instruction = Self.instruction(for: capability)
        let input = UserInput(chat: [
            .system("You are Nodus, Modula's concise general-purpose offline assistant. Never claim live information without current evidence. Actions are proposals only."),
            .user("\(instruction)\n\n\(prompt)"),
        ])
        let prepared = try await container.prepare(input: input)
        let stream = try await container.generate(
            input: prepared,
            parameters: GenerateParameters(maxTokens: 384, temperature: 0.2, topP: 0.9)
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
            text: text.trimmingCharacters(in: .whitespacesAndNewlines), modelVersion: modelVersion,
            completed: true, tokensPerSecond: tokensPerSecond, modelConsistency: nil
        )
    }

    func unload() { container = nil; state = .unloaded }

    private static func instruction(for capability: IntelligenceCapability) -> String {
        switch capability {
        case .generate: "Answer the request directly."
        case .rewrite: "Rewrite while preserving meaning."
        case .summarize: "Summarize accurately and concisely."
        case .classify: "Return only the requested classification."
        case .extract: "Extract only the requested facts."
        case .intent: "Identify the primary intent."
        case .toolCall: "Return a proposal only."
        }
    }
}
#endif

enum NodusRuntimeFactory {
    static func makeDefault() -> any NodusRuntime {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(Tokenizers)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let preference = UserDefaults.standard.object(forKey: "modula.nodus.enabled") as? Bool
        return MLXNodusRuntime(
            modelDirectory: support.appending(path: "Modula/Nodus/models/accepted"),
            enabled: preference ?? true
        )
        #else
        return UnavailableNodusRuntime(availability: .unsupportedDevice)
        #endif
    }
}
