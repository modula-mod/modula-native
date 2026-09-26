import SwiftUI

#if DEBUG
struct NodusWorkspaceView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var conversationCount = 0
    @State private var collectionCount = 0
    @State private var memoryCount = 0
    @State private var candidateCount = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Nodus R7 Experimental", systemImage: "brain")
                        .font(.headline)
                    Text("Developer-only · Local · Not approved for shipping")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section("Workspace") {
                row("Chats", "\(conversationCount) conversations", "bubble.left.and.bubble.right", id: "nodus.workspace.chats") {
                    app.navigation.open(.settings(.developer(.nodusChat)))
                }
                row("Knowledge", "\(collectionCount) collections", "books.vertical", id: "nodus.workspace.knowledge") {
                    app.navigation.open(.settings(.developer(.nodusKnowledge)))
                }
                row("Memory", "\(memoryCount) confirmed items", "memorychip", id: "nodus.workspace.memory") {
                    app.navigation.open(.settings(.developer(.nodusMemory)))
                }
                row("Learning", "\(candidateCount) candidates", "checkmark.seal", id: "nodus.workspace.learning") {
                    app.navigation.open(.settings(.developer(.nodusLearning)))
                }
                row("Model / Diagnostics", "R7 · experimentalCandidate", "stethoscope", id: "nodus.workspace.diagnostics") {
                    app.navigation.open(.settings(.developer(.nodusModel)))
                }
            }
            Section("Boundaries") {
                LabeledContent("Generation", value: "On-device")
                LabeledContent("Provider", value: NodusIntelligenceProvider.providerID)
                LabeledContent("Training", value: "Never automatic")
                LabeledContent("Shipping", value: "Not allowed")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Nodus")
        .task { await refresh() }
        .accessibilityIdentifier("nodus.workspace")
    }

    private func row(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: symbol) }
        }
        .accessibilityIdentifier(id)
    }

    private func refresh() async {
        conversationCount = await app.nodusConversationStore.all().count
        collectionCount = await app.nodusKnowledgeStore.collections().count
        memoryCount = await app.nodusMemoryStore.snapshot().items.count
        candidateCount = await app.nodusVerificationStore.snapshot().learningCandidates.count
    }
}

struct NodusModelDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var intelligence: IntelligenceServiceSnapshot?
    @State private var conversationCount = 0
    @State private var collectionCount = 0
    @State private var itemCount = 0
    @State private var chunkCount = 0
    @State private var memoryCount = 0
    @State private var suggestionCount = 0
    @State private var candidateCount = 0

    var body: some View {
        List {
            Section("Model") {
                LabeledContent("Provider", value: NodusIntelligenceProvider.providerID)
                LabeledContent("Model", value: intelligence?.nodusModelIdentity?.displayName ?? "Nodus R7 Experimental")
                LabeledContent("Stage", value: intelligence?.nodusModelIdentity?.stage.displayName ?? "Experimental candidate")
                LabeledContent("Shipping", value: "Not allowed")
                LabeledContent("Availability", value: intelligence?.nodusProviderAvailability?.displayName ?? "—")
                LabeledContent("Load state", value: intelligence?.nodusLoadState?.rawValue.capitalized ?? "—")
            }
            Section("Workspace") {
                LabeledContent("Conversations", value: "\(conversationCount)")
                LabeledContent("Knowledge collections", value: "\(collectionCount)")
                LabeledContent("Knowledge items", value: "\(itemCount)")
                LabeledContent("Knowledge chunks", value: "\(chunkCount)")
                LabeledContent("Memory", value: "\(memoryCount)")
                LabeledContent("Memory suggestions", value: "\(suggestionCount)")
                LabeledContent("Learning Candidates", value: "\(candidateCount)")
                LabeledContent("Search provider", value: app.nodusSearchCredentials.isConfigured() ? "Configured" : "Not configured")
            }
            Section {
                NavigationLink("Runtime and Artifact Diagnostics") {
                    IntelligenceDiagnosticsView()
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Nodus Diagnostics")
        .task { await refresh() }
        .accessibilityIdentifier("nodus.diagnostics")
    }

    private func refresh() async {
        intelligence = await app.intelligence.diagnosticsSnapshot()
        conversationCount = await app.nodusConversationStore.all().count
        let knowledge = await app.nodusKnowledgeStore.snapshot()
        collectionCount = knowledge.collections.count
        itemCount = knowledge.items.count
        chunkCount = knowledge.chunks.count
        let memory = await app.nodusMemoryStore.snapshot()
        memoryCount = memory.items.count
        suggestionCount = memory.suggestions.count
        candidateCount = await app.nodusVerificationStore.snapshot().learningCandidates.count
    }
}
#endif
