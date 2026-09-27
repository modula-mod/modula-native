import Foundation

struct NodusConversationEngineResult: Sendable, Equatable {
    let conversation: NodusConversation
    let message: NodusMessage
}

actor NodusConversationEngine {
    private let conversations: NodusConversationStore
    private let knowledge: NodusKnowledgeStore
    private let memory: NodusMemoryStore
    private let intelligence: ModulaIntelligence
    private let searchProvider: (any NodusSearchProvider)?
    private let freshness = NodusFreshnessClassifier()
    private let deepCoordinator = NodusDeepReasoningCoordinator()

    init(
        conversations: NodusConversationStore,
        knowledge: NodusKnowledgeStore,
        memory: NodusMemoryStore,
        intelligence: ModulaIntelligence,
        searchProvider: (any NodusSearchProvider)?
    ) {
        self.conversations = conversations
        self.knowledge = knowledge
        self.memory = memory
        self.intelligence = intelligence
        self.searchProvider = searchProvider
    }

    func send(
        question: String,
        conversationID: UUID,
        progress: @escaping @Sendable (NodusReasoningStage) async -> Void = { _ in }
    ) async throws -> NodusConversationEngineResult {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var conversation = await conversations.conversation(id: conversationID) else {
            throw IntelligenceError.invalidRequest(detail: "Nodus conversation or message is missing")
        }
        try Task.checkCancellation()
        await progress(.classifying)
        let requestFreshness = freshness.classify(clean)
        let taskMode: NodusTaskMode = Self.isModulaRelated(clean) ? .modulaAnswer : .generalAnswer
        let userMessage = NodusMessage(role: .user, text: clean)
        _ = try await conversations.append(userMessage, to: conversationID)

        if requestFreshness == .currentDataRequired, !conversation.searchEnabled {
            let answer = NodusAnswer(
                answer: "Current information is required. Turn on Search to check.",
                confidence: NodusConfidence(answer: 1, evidence: 0, freshness: 0, band: .needsVerification),
                freshness: .currentDataRequired, evidenceState: .noReliableEvidence,
                verificationRecommended: true, abstained: true,
                reasons: ["Current evidence is required"], modelVersion: "Nodus routing policy",
                latencySeconds: 0, tokensPerSecond: nil, taskMode: taskMode
            )
            let details = NodusResponseDetails(
                reasoningMode: conversation.reasoningMode, searchEnabled: false, searchedWeb: false,
                knowledgeChunkCount: 0, memoryItemIDs: [], searchResultCount: 0,
                generationDuration: 0, retrievalDuration: 0, searchDuration: nil, inferencePasses: 0
            )
            let message = NodusMessage(role: .nodus, text: answer.answer, answer: answer, details: details)
            guard let updated = try await conversations.append(message, to: conversationID) else {
                throw IntelligenceError.providerFailure(providerID: NodusIntelligenceProvider.providerID, detail: "CONVERSATION_PERSIST_FAILED")
            }
            return NodusConversationEngineResult(conversation: updated, message: message)
        }

        let retrievalStart = ContinuousClock.now
        await progress(.checkingMemory)
        let memories = conversation.memoryEnabled
            ? await memory.retrieve(query: clean, conversationID: conversation.id, topK: 5) : []
        try Task.checkCancellation()

        await progress(.searchingKnowledge)
        var eligibleCollections = conversation.attachedKnowledgeCollectionIDs
        if Self.isModulaRelated(clean) { eligibleCollections.insert(NodusKnowledgeStore.modulaCoreCollectionID) }
        let knowledgeMatches = eligibleCollections.isEmpty
            ? [] : await knowledge.search(clean, collectionIDs: eligibleCollections, topK: 6)
        let retrievalDuration = Self.seconds(since: retrievalStart)
        try Task.checkCancellation()

        var web: NodusSearchResponse?
        var searchDuration: Double?
        if conversation.searchEnabled {
            guard let searchProvider else { throw NodusSearchError.notConfigured }
            await progress(.searchingWeb)
            let started = ContinuousClock.now
            web = try await searchProvider.search(query: clean, limit: 6)
            searchDuration = Self.seconds(since: started)
            try Task.checkCancellation()
        }

        let budget = conversation.reasoningMode == .deep ? NodusContextBudget.deep : .standard
        let reasoningMode = conversation.reasoningMode
        let prompt = NodusContextBuilder.build(
            question: clean, conversation: conversation, memory: memories,
            knowledge: knowledgeMatches, search: web, budget: budget
        )
        let generationStart = ContinuousClock.now
        let generated = try await deepCoordinator.run(
            prompt: prompt, taskMode: taskMode, budget: budget,
            generate: { [intelligence] generationPrompt, maxTokens in
                let request = IntelligenceRequest(
                    capability: .generate,
                    input: .object([
                        "text": .string(generationPrompt),
                        "taskMode": .string(taskMode.rawValue),
                        "maxOutputTokens": .integer(maxTokens),
                        "reasoningMode": .string(reasoningMode.rawValue),
                        "freshness": .string(requestFreshness.rawValue),
                    ]),
                    privacy: .localOnly,
                    source: .developerDiagnostics
                )
                let response = try await intelligence.executeDiagnostic(
                    request, usingProviderID: NodusIntelligenceProvider.providerID
                )
                guard let answer = NodusAnswer.parse(response.output) else {
                    throw IntelligenceError.providerFailure(
                        providerID: NodusIntelligenceProvider.providerID,
                        detail: "INVALID_NODUS_ENVELOPE"
                    )
                }
                return (answer, response.requestID)
            },
            progress: progress
        )
        let generationDuration = Self.seconds(since: generationStart)
        let citations = Self.citations(knowledge: knowledgeMatches, search: web)
        let details = NodusResponseDetails(
            reasoningMode: conversation.reasoningMode,
            searchEnabled: conversation.searchEnabled,
            searchedWeb: web != nil,
            knowledgeChunkCount: knowledgeMatches.count,
            memoryItemIDs: memories.map(\.item.id),
            searchResultCount: web?.results.count ?? 0,
            generationDuration: generationDuration,
            retrievalDuration: retrievalDuration,
            searchDuration: searchDuration,
            inferencePasses: generated.passes
        )
        let message = NodusMessage(
            role: .nodus, text: generated.answer.answer, answer: generated.answer,
            requestID: generated.requestID, citations: citations, details: details
        )
        guard let updated = try await conversations.append(message, to: conversationID) else {
            throw IntelligenceError.providerFailure(providerID: NodusIntelligenceProvider.providerID, detail: "CONVERSATION_PERSIST_FAILED")
        }
        conversation = updated
        return NodusConversationEngineResult(conversation: conversation, message: message)
    }

    private static func isModulaRelated(_ value: String) -> Bool {
        let text = value.lowercased()
        return ["modula", "nodus", "gaia", "aki", "governor", "vault notes", "module runtime"]
            .contains(where: text.contains)
    }

    private static func citations(
        knowledge: [NodusKnowledgeMatch],
        search: NodusSearchResponse?
    ) -> [NodusCitation] {
        let knowledgeCitations = knowledge.map {
            NodusCitation(
                kind: .knowledge, title: $0.item.title, sourceName: $0.item.sourceName,
                collectionName: $0.collection.name, location: $0.chunk.location,
                url: $0.item.sourceURL, excerpt: $0.chunk.text
            )
        }
        let searchCitations = search?.results.map {
            NodusCitation(
                kind: .web, title: $0.title, sourceName: $0.domain,
                url: $0.url, retrievedAt: $0.retrievedAt, excerpt: $0.snippet
            )
        } ?? []
        return knowledgeCitations + searchCitations
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let components = (ContinuousClock.now - start).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
