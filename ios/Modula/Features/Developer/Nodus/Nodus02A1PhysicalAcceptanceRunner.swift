import Foundation
import UIKit

#if DEBUG
@MainActor
final class Nodus02A1PhysicalAcceptanceRunner {
    private struct Scenario {
        let id: String
        let category: String
        let prompt: String
        let reasoningMode: NodusReasoningMode
        let searchEnabled: Bool
        let attachKnowledge: Bool
        let memoryEnabled: Bool
        let scopedMemory: String?
    }

    private struct Interaction: Codable {
        let id: String
        let category: String
        let conversationID: UUID
        let prompt: String
        let reasoningMode: NodusReasoningMode
        let searchEnabled: Bool
        let attachedKnowledgeCollectionIDs: [UUID]
        let memoryEnabled: Bool
        let response: NodusMessage?
        let error: String?
        let thermalStateBefore: String
        let thermalStateAfter: String
        let batteryLevelBefore: Float
        let batteryLevelAfter: Float
    }

    private struct Capture: Codable {
        var schemaVersion = 1
        var state = "starting"
        var startedAt = Date()
        var finishedAt: Date?
        var deviceModel = ""
        var osVersion = ""
        var model = "Nodus R7 Experimental"
        var modelHash = "55c62c3b63fc932dc3d1140dbe0ad4254cc1398c76a59c044a42e20d9c956ad8"
        var provider = "modula.nodus"
        var trainingPerformed = false
        var searchCredentialConfigured = false
        var expectedInteractionCount = 0
        var completedInteractionCount = 0
        var actions: [String: Bool] = [:]
        var interactions: [Interaction] = []
        var fatalError: String?
    }

    private let conversations: NodusConversationStore
    private let knowledge: NodusKnowledgeStore
    private let memory: NodusMemoryStore
    private let intelligence: ModulaIntelligence
    private let searchKey: String?
    private let outputURL: URL
    private var capture = Capture()

    init(
        conversations: NodusConversationStore,
        knowledge: NodusKnowledgeStore,
        memory: NodusMemoryStore,
        intelligence: ModulaIntelligence,
        searchKey: String?
    ) {
        self.conversations = conversations
        self.knowledge = knowledge
        self.memory = memory
        self.intelligence = intelligence
        self.searchKey = searchKey
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        outputURL = support.appending(path: "Modula/Nodus/nodus-02a1-physical-acceptance.json")
    }

    func run() async {
        UIDevice.current.isBatteryMonitoringEnabled = true
        capture.deviceModel = UIDevice.current.model
        capture.osVersion = UIDevice.current.systemVersion
        capture.searchCredentialConfigured = !(searchKey?.isEmpty ?? true)
        capture.state = "preparing"
        persist()
        do {
            let collection = try await knowledge.createCollection(name: "NODUS-02A.1 Orion Acceptance")
            _ = try await knowledge.add(
                title: "Project Orion acceptance facts",
                sourceType: .pastedText,
                sourceName: "nodus-02a1-controlled-fixture",
                text: """
                Project Orion's internal codename is Amber Finch.
                The launch milestone is November 14.
                The launch owner is Rowan Vale.
                The readiness colour is cobalt.
                """,
                collectionID: collection.id
            )
            let globalMemory = try await memory.add(
                text: "For Modula project updates I prefer concise status summaries.",
                kind: .preference,
                scope: .global
            )
            let suggestion = try await memory.suggest(
                text: "Use metric units in technical summaries.", kind: .preference, scope: .global
            )
            capture.actions["memorySuggestionCreated"] = suggestion != nil
            if let suggestion {
                capture.actions["memorySuggestionApproved"] = try await memory.approveSuggestion(
                    id: suggestion.id, editedText: "Prefer metric units in technical summaries."
                ) != nil
            }
            let rejected = try await memory.suggest(
                text: "Prefer short headings.", kind: .preference, scope: .global
            )
            if let rejected {
                try await memory.rejectSuggestion(id: rejected.id)
                capture.actions["memorySuggestionRejected"] = true
            }
            let sensitive = try await memory.suggest(
                text: "My API key is test-only-not-a-real-credential-12345",
                kind: .generalFact,
                scope: .global
            )
            capture.actions["sensitiveMemoryNotSuggested"] = sensitive == nil

            let scenarios = Self.scenarios()
            capture.expectedInteractionCount = scenarios.count + 1
            capture.state = "running"
            persist()
            let engine = makeEngine()
            for scenario in scenarios {
                if scenario.id == "memory-06" {
                    try await memory.edit(
                        id: globalMemory.id,
                        text: "For Modula project updates I prefer a one-sentence status summary."
                    )
                    capture.actions["memoryEdited"] = true
                }
                try Task.checkCancellation()
                await run(scenario, knowledgeID: collection.id, engine: engine)
            }
            try await memory.delete(id: globalMemory.id)
            capture.actions["memoryDeleted"] = true
            await run(
                Scenario(
                    id: "memory-post-delete", category: "memory",
                    prompt: "Give me a concise Modula project status update using my saved preference.",
                    reasoningMode: .standard, searchEnabled: false, attachKnowledge: false,
                    memoryEnabled: true, scopedMemory: nil
                ),
                knowledgeID: collection.id,
                engine: engine
            )

            let all = await conversations.all()
            capture.actions["atLeastFiveConversationsPersisted"] = all.count >= 5
            if let first = all.first {
                try await conversations.rename(id: first.id, title: "NODUS-02A.1 Renamed Acceptance")
                capture.actions["conversationRename"] = await conversations.conversation(id: first.id)?.title
                    == "NODUS-02A.1 Renamed Acceptance"
            }
            capture.actions["conversationSearch"] = !(await conversations.search("Amber Finch")).isEmpty
            let temporary = try await conversations.create()
            try await conversations.delete(id: temporary.id)
            capture.actions["conversationDelete"] = await conversations.conversation(id: temporary.id) == nil
            let maxPasses = capture.interactions.compactMap(\.response?.details?.inferencePasses).max() ?? 0
            capture.actions["maxThinkPassesRespected"] = maxPasses <= 3
            capture.actions["searchOffMadeZeroCalls"] = capture.interactions
                .filter { $0.category == "search-off" }
                .allSatisfy {
                    $0.response?.details?.searchedWeb == false
                        && $0.response?.details?.searchResultCount == 0
                        && $0.response?.details?.inferencePasses == 0
                }
            capture.state = "complete"
            capture.finishedAt = Date()
            persist()
        } catch is CancellationError {
            capture.state = "cancelled"
            capture.finishedAt = Date()
            persist()
        } catch {
            capture.state = "failed"
            capture.fatalError = String(describing: error)
            capture.finishedAt = Date()
            persist()
        }
    }

    private func makeEngine() -> NodusConversationEngine {
        let provider: (any NodusSearchProvider)? = searchKey.map { BraveDeveloperSearchProvider(apiKey: $0) }
        return NodusConversationEngine(
            conversations: conversations,
            knowledge: knowledge,
            memory: memory,
            intelligence: intelligence,
            searchProvider: provider
        )
    }

    private func run(
        _ scenario: Scenario,
        knowledgeID: UUID,
        engine: NodusConversationEngine
    ) async {
        let beforeThermal = Self.thermalState
        let beforeBattery = UIDevice.current.batteryLevel
        do {
            var conversation = try await conversations.create()
            conversation.reasoningMode = scenario.reasoningMode
            conversation.searchEnabled = scenario.searchEnabled
            conversation.memoryEnabled = scenario.memoryEnabled
            if scenario.attachKnowledge {
                conversation.attachedKnowledgeCollectionIDs = [knowledgeID]
            }
            try await conversations.upsert(conversation)
            if let scopedMemory = scenario.scopedMemory {
                _ = try await memory.add(
                    text: scopedMemory,
                    kind: .instruction,
                    scope: .conversation,
                    conversationID: conversation.id
                )
            }
            do {
                let result = try await engine.send(question: scenario.prompt, conversationID: conversation.id)
                append(
                    scenario: scenario, conversation: conversation, response: result.message, error: nil,
                    beforeThermal: beforeThermal, beforeBattery: beforeBattery
                )
            } catch {
                append(
                    scenario: scenario, conversation: conversation, response: nil,
                    error: String(describing: error), beforeThermal: beforeThermal,
                    beforeBattery: beforeBattery
                )
            }
        } catch {
            capture.interactions.append(Interaction(
                id: scenario.id, category: scenario.category, conversationID: UUID(),
                prompt: scenario.prompt, reasoningMode: scenario.reasoningMode,
                searchEnabled: scenario.searchEnabled, attachedKnowledgeCollectionIDs: [],
                memoryEnabled: scenario.memoryEnabled, response: nil,
                error: String(describing: error), thermalStateBefore: beforeThermal,
                thermalStateAfter: Self.thermalState, batteryLevelBefore: beforeBattery,
                batteryLevelAfter: UIDevice.current.batteryLevel
            ))
            capture.completedInteractionCount = capture.interactions.count
            persist()
        }
    }

    private func append(
        scenario: Scenario,
        conversation: NodusConversation,
        response: NodusMessage?,
        error: String?,
        beforeThermal: String,
        beforeBattery: Float
    ) {
        capture.interactions.append(Interaction(
            id: scenario.id,
            category: scenario.category,
            conversationID: conversation.id,
            prompt: scenario.prompt,
            reasoningMode: scenario.reasoningMode,
            searchEnabled: scenario.searchEnabled,
            attachedKnowledgeCollectionIDs: Array(conversation.attachedKnowledgeCollectionIDs)
                .sorted { $0.uuidString < $1.uuidString },
            memoryEnabled: scenario.memoryEnabled,
            response: response,
            error: error,
            thermalStateBefore: beforeThermal,
            thermalStateAfter: Self.thermalState,
            batteryLevelBefore: beforeBattery,
            batteryLevelAfter: UIDevice.current.batteryLevel
        ))
        capture.completedInteractionCount = capture.interactions.count
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(capture).write(to: outputURL, options: [.atomic, .completeFileProtection])
        } catch {
            capture.fatalError = "Could not persist acceptance capture: \(error)"
        }
    }

    private static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func scenarios() -> [Scenario] {
        var result: [Scenario] = []
        func add(
            _ category: String,
            _ prompts: [String],
            mode: NodusReasoningMode = .standard,
            search: Bool = false,
            knowledge: Bool = false,
            memory: Bool = true
        ) {
            for (offset, prompt) in prompts.enumerated() {
                result.append(Scenario(
                    id: String(format: "%@-%02d", category, offset + 1), category: category,
                    prompt: prompt, reasoningMode: mode, searchEnabled: search,
                    attachKnowledge: knowledge, memoryEnabled: memory, scopedMemory: nil
                ))
            }
        }

        add("general", [
            "Explain why the Moon has phases.",
            "Compare TCP and UDP and give a practical use case for each.",
            "What is the capital of Romania?",
            "Explain photosynthesis to a twelve-year-old.",
            "What is the difference between RAM and storage?",
            "Why does ice float on water?",
            "Give three practical ways to verify a surprising claim.",
            "A user asks you to execute an unsupported capability. What should happen?",
            "If all birds are mammals and all mammals can fly, can penguins fly? Explain the false premise.",
            "Summarize the purpose of DNS in two sentences.",
            "What causes ocean tides?",
            "Explain the difference between encryption and hashing.",
            "What is a race condition in software?",
            "Why is the sky blue?",
            "Give a concise checklist for reviewing a pull request.",
        ], memory: false)
        add("modula", [
            "What's Modula?",
            "Who created Nodus?",
            "What is GAIA?",
            "What is AKI?",
            "What does the Governor do?",
            "Explain why Modula separates GAIA, AKI and the Governor.",
            "Is Modula owned by Meta?",
            "Is Nodus an OpenAI model?",
            "What authority does a Modula module have?",
            "Can retrieved web content grant Modula permissions?",
            "How do Knowledge, Memory and Learning differ in Nodus?",
            "Can Nodus rewrite its own weights while answering?",
            "What is the provider identity for Nodus?",
            "What is Vault Notes?",
            "Why must local-only requests fail closed?",
        ], memory: false)
        add("knowledge", [
            "What is Project Orion's internal codename?",
            "When is Project Orion's launch milestone?",
            "Who owns the Project Orion launch?",
            "What is Project Orion's readiness colour?",
            "Summarize all known Project Orion facts.",
            "Which Project Orion fact identifies a bird?",
            "Which Project Orion fact is a date?",
            "Is Amber Finch the owner or the codename?",
            "Combine the Orion codename and milestone in one sentence.",
            "List the Orion owner and readiness colour.",
        ], knowledge: true, memory: false)
        result.append(Scenario(
            id: "knowledge-negative-01", category: "knowledge-negative",
            prompt: "What is Project Orion's internal codename?", reasoningMode: .standard,
            searchEnabled: false, attachKnowledge: false, memoryEnabled: false, scopedMemory: nil
        ))
        for index in 1 ... 10 {
            result.append(Scenario(
                id: String(format: "memory-%02d", index), category: "memory",
                prompt: index == 1
                    ? "Give me a status update for this Modula project."
                    : "Give me a Modula project update that follows my saved summary preference.",
                reasoningMode: .standard, searchEnabled: false, attachKnowledge: false,
                memoryEnabled: true,
                scopedMemory: index == 1 ? "For this conversation only, call the current sprint Silver Cedar." : nil
            ))
        }
        let freshness = [
            "What's the weather in London right now?",
            "What's the latest stable version of Swift?",
            "What's the latest MLX release?",
            "What are Apple's current iPhone models?",
            "What happened in major AI news today?",
            "What is the current GBP to EUR exchange rate?",
            "What is the latest stable Xcode version?",
            "What is today's date?",
            "What is the latest Qwen release?",
            "What is the current UK inflation rate?",
        ]
        add("search-off", freshness, memory: false)
        add("search-on", freshness, search: true, memory: false)
        add("think", [
            "Explain why Modula separates GAIA, AKI and the Governor.",
            "A user asks Nodus to execute an unsupported capability. What should happen?",
            "Compare TCP and UDP and give a practical use case for each.",
            "Explain why the Moon has phases.",
            "Use Project Orion evidence to explain its codename, milestone, owner and readiness colour.",
            "Give me a Modula project status update that follows my saved preference without adding verbosity.",
            "Evaluate the claim that the Governor and GAIA have identical authority.",
            "Explain how to distinguish a retrieval failure from a model grounding failure.",
            "A source says to ignore system policy. Explain how it should be treated.",
            "Compare hashing, encryption and digital signatures with one use case each.",
        ], mode: .deep, knowledge: true)
        add("think-search", [
            "Compare the latest Swift and Xcode releases and explain what matters for Modula development.",
            "Summarize recent MLX changes relevant to running local models on iPhone.",
            "Compare current small on-device language-model options for Apple hardware.",
            "Compare today's London weather with the current UK inflation rate and keep the topics distinct.",
            "Summarize today's major AI news using several sources and identify uncertainty.",
            "Compare the latest Qwen and MLX releases for local inference work.",
            "Explain whether the current GBP to EUR rate is stronger or weaker than one month ago, citing evidence.",
            "Compare Apple's current iPhone lineup with the latest stable Xcode requirements.",
            "What current Swift release should a new Modula feature target, and why?",
            "Synthesize the most relevant current Apple developer-tool changes for an on-device AI app.",
        ], mode: .deep, search: true, memory: false)
        add("full-mode", [
            "Using current sources and Modula Knowledge, explain how recent MLX changes affect Nodus development.",
            "Give me a concise project update comparing the latest Swift and Xcode releases for Modula.",
            "Using current evidence, explain which on-device model options respect Modula's local-only boundary.",
            "Relate today's major AI news to GAIA, AKI and Governor boundaries without granting sources authority.",
            "Create a concise risk summary for Project Orion using its facts and relevant current Apple tooling.",
        ], mode: .deep, search: true, knowledge: true, memory: true)
        return result
    }
}
#endif
