import SwiftUI

struct IntelligenceSettingsHost: View {
    let route: IntelligenceSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            IntelligenceSettingsRootView()
        case .models:
            IntelligenceModelsSettingsView()
        case .knowledge:
            IntelligenceKnowledgeSettingsView()
        case .privacy:
            IntelligencePrivacySettingsView()
        case .tools:
            IntelligenceToolsSettingsView()
        }
    }
}

struct IntelligenceSettingsRootView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var library = NodusLibrarySnapshot()
    @State private var memory = NodusMemorySnapshot()
    @State private var knowledge = NodusKnowledgeSnapshot()
    @State private var providerLine = "Checking on-device providers"
    @State private var promptTitle = ""
    @State private var promptBody = ""

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(
                title: "Intelligence",
                subtitle: providerLine,
                symbol: "brain"
            )
            SettingsSceneGraphic(style: .orbit)
            SettingsGroup(title: "Chat") {
                VStack(spacing: 0) {
                    SettingsNavigationRow(title: "Open Nodus", subtitle: "Local chat, projects, and prompts", symbol: "bubble.left.and.bubble.right") {
                        PresentationCoordinator.present(.intelligenceChat, in: app.navigation)
                    }
                    SettingsDivider()
                    labeled("Projects", value: "\(library.projects.filter { !$0.archived }.count)")
                    SettingsDivider()
                    labeled("Folders", value: "\(library.folders.count)")
                    SettingsDivider()
                    labeled("Saved prompts", value: "\(library.prompts.count)")
                    SettingsDivider()
                    labeled("Important chats", value: "\(library.placements.filter(\.important).count)")
                }
            }
            SettingsGroup(title: "Saved prompts", subtitle: "Inserted into the composer. Stored on this iPhone.") {
                VStack(alignment: .leading, spacing: 10) {
                    if library.prompts.isEmpty {
                        Text("No saved prompts yet.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(library.prompts) { prompt in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.title).font(.body.weight(.medium))
                            Text(prompt.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                Task { library = (try? await app.nodusConversationStore.deletePrompt(id: prompt.id)) ?? library }
                            }
                        }
                    }
                    TextField("Title", text: $promptTitle)
                    TextField("Prompt", text: $promptBody, axis: .vertical).lineLimit(2 ... 5)
                    Button("Save prompt") {
                        Task {
                            library = (try? await app.nodusConversationStore.savePrompt(title: promptTitle, body: promptBody, projectID: nil)) ?? library
                            promptTitle = ""
                            promptBody = ""
                        }
                    }
                    .disabled(promptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
            }
            SettingsGroup(title: "Memory", subtitle: "Confirmed local memory. Not model training.") {
                VStack(spacing: 0) {
                    labeled("Active", value: "\(memory.items.filter(\.active).count)")
                    SettingsDivider()
                    labeled("Archived", value: "\(memory.items.filter { !$0.active }.count)")
                    if memory.items.isEmpty {
                        Text("No stored memory.").font(.subheadline).foregroundStyle(.secondary).padding(12)
                    } else {
                        ForEach(memory.items.prefix(6)) { item in
                            SettingsDivider()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(.subheadline).lineLimit(2)
                                Text(item.active ? item.kind.displayName : "Archived").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            SettingsGroup(title: "Open") {
                VStack(spacing: 0) {
                    SettingsNavigationRow(title: "Models", subtitle: "Registered providers on this device", symbol: "cpu") {
                        app.navigation.open(.settings(.intelligence(.models)))
                    }
                    SettingsDivider()
                    SettingsNavigationRow(title: "Knowledge", subtitle: "\(knowledge.collections.count) collections on this iPhone", symbol: "books.vertical") {
                        app.navigation.open(.settings(.intelligence(.knowledge)))
                    }
                    SettingsDivider()
                    SettingsNavigationRow(title: "Privacy", subtitle: "Local-only policy", symbol: "hand.raised.fill") {
                        app.navigation.open(.settings(.intelligence(.privacy)))
                    }
                    SettingsDivider()
                    SettingsNavigationRow(title: "Tools", subtitle: "Registered tool descriptors", symbol: "wrench.and.screwdriver") {
                        app.navigation.open(.settings(.intelligence(.tools)))
                    }
                }
            }
        }
        .navigationTitle("Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .accessibilityIdentifier("settings.intelligence")
    }

    private func labeled(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.body)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }

    private func refresh() async {
        library = await app.nodusConversationStore.librarySnapshot()
        memory = await app.nodusMemoryStore.snapshot()
        knowledge = await app.nodusKnowledgeStore.snapshot()
        let providers = await app.intelligence.providers.allProviders()
        var nodusLabel = "Nodus not registered"
        for provider in providers where provider.id == NodusIntelligenceProvider.providerID {
            let availability = await provider.availability()
            nodusLabel = availability == .available ? "Nodus available" : availability.displayName
        }
        providerLine = "On-device · \(nodusLabel). Fail-closed."
    }
}

private struct IntelligenceProviderRow: Identifiable {
    let id: String
    let executionKind: IntelligenceExecutionKind
    let capabilityCount: Int
    let availabilityLabel: String
}

struct IntelligenceModelsSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var rows: [IntelligenceProviderRow] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(
                    title: "Providers",
                    subtitle: "Product list excludes the deterministic test fixture. Diagnostics stay under Developer."
                ) {
                    if !loaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if rows.isEmpty {
                        ContentUnavailableView(
                            "No models available",
                            systemImage: "cpu",
                            description: Text("No product intelligence providers are registered on this build.")
                        )
                        .frame(minHeight: 180)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: 13) {
                                    Image(systemName: row.executionKind == .local ? "iphone" : "cloud")
                                        .frame(width: 28)
                                        .foregroundStyle(app.appearance.accent.color)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName(for: row.id))
                                            .font(.body.weight(.medium))
                                        Text(subtitle(for: row))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 52)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(displayName(for: row.id)), \(subtitle(for: row))")
                                if index < rows.count - 1 { SettingsDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .accessibilityIdentifier("settings.intelligence.models")
    }

    private func refresh() async {
        let providers = await app.intelligence.providers.allProviders()
        var built: [IntelligenceProviderRow] = []
        for provider in providers {
            guard provider.id != DeterministicLocalProvider.providerID else { continue }
            let availability = await provider.availability()
            built.append(
                IntelligenceProviderRow(
                    id: provider.id,
                    executionKind: provider.executionKind,
                    capabilityCount: provider.capabilities.count,
                    availabilityLabel: availabilityLabel(availability)
                )
            )
        }
        rows = built
        loaded = true
    }

    private func displayName(for id: String) -> String {
        switch id {
        case NodusIntelligenceProvider.providerID: "Nodus"
        case AppleSystemIntelligenceProvider.providerID: "Apple System"
        default: intelligenceReadableName(id)
        }
    }

    private func subtitle(for row: IntelligenceProviderRow) -> String {
        let kind = row.executionKind == .local ? "On-device" : "Remote"
        return "\(kind) · \(row.availabilityLabel) · \(row.capabilityCount) capabilities"
    }

    private func availabilityLabel(_ availability: IntelligenceAvailability) -> String {
        availability.displayName
    }
}

struct IntelligenceKnowledgeSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var snapshot = NodusKnowledgeSnapshot()

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(
                title: "Knowledge",
                subtitle: "Collections stored on this iPhone. System collections are read-only.",
                symbol: "books.vertical"
            )
            if snapshot.collections.isEmpty {
                ContentUnavailableView(
                    "No local knowledge",
                    systemImage: "books.vertical",
                    description: Text("Nothing has been saved into Knowledge yet.")
                )
            } else {
                ForEach(snapshot.collections) { collection in
                    let items = snapshot.items.filter { $0.collectionID == collection.id }
                    SettingsGroup(title: collection.name, subtitle: collection.isReadOnly ? "System · read-only" : "On this iPhone") {
                        VStack(alignment: .leading, spacing: 0) {
                            if items.isEmpty {
                                Text("No documents in this collection.").font(.subheadline).foregroundStyle(.secondary).padding(12)
                            }
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.body.weight(.medium))
                                    Text(item.sourceName).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Knowledge")
        .navigationBarTitleDisplayMode(.inline)
        .task { snapshot = await app.nodusKnowledgeStore.snapshot() }
        .accessibilityIdentifier("settings.intelligence.knowledge")
    }
}

struct IntelligencePrivacySettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var remotePermitted = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Default policy", value: "Local only")
                Text("Requests stay on this device. If on-device processing isn’t available, Modula won’t quietly send them elsewhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Off-device processing") {
                LabeledContent("Allowed", value: remotePermitted ? "Yes" : "No")
                Text("This is set by Modula’s intelligence service. There’s no option here to choose a remote model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy levels") {
                ForEach(IntelligencePrivacy.allCases, id: \.self) { policy in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(policyTitle(policy))
                        Text(policyDetail(policy))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .modulaCanvas()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            remotePermitted = await app.intelligence.isRemoteIntelligencePermitted()
        }
        .accessibilityIdentifier("settings.intelligence.privacy")
    }

    private func policyTitle(_ policy: IntelligencePrivacy) -> String {
        switch policy {
        case .localOnly: "Local only"
        case .preferLocal: "Prefer local"
        case .allowRemote: "Allow remote"
        }
    }

    private func policyDetail(_ policy: IntelligencePrivacy) -> String {
        switch policy {
        case .localOnly: "Only ever runs on this device."
        case .preferLocal: "Runs on this device when it can."
        case .allowRemote: "May use a remote service when allowed."
        }
    }
}

/// Turns ids like "nodus.knowledge_search" into "Knowledge Search".
func intelligenceReadableName(_ id: String) -> String {
    let last = id.split(separator: ".").last.map(String.init) ?? id
    return settingsDisplayTitle(last)
}

private struct IntelligenceToolRow: Identifiable {
    let id: String
    let title: String
    let detail: String
}

struct IntelligenceToolsSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var rows: [IntelligenceToolRow] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Registered tools", subtitle: "Descriptors only — tools are not executed from Settings.") {
                    if !loaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if rows.isEmpty {
                        ContentUnavailableView(
                            "No tools registered",
                            systemImage: "wrench.and.screwdriver",
                            description: Text("The tool registry is empty on this build.")
                        )
                        .frame(minHeight: 180)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: 13) {
                                    Image(systemName: "wrench.and.screwdriver")
                                        .frame(width: 28)
                                        .foregroundStyle(app.appearance.accent.color)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.title)
                                            .font(.body.weight(.medium))
                                        Text(row.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 52)
                                if index < rows.count - 1 { SettingsDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let tools = await app.intelligence.tools.allTools()
            rows = tools.map {
                IntelligenceToolRow(
                    id: $0.id,
                    title: intelligenceReadableName($0.id),
                    detail: $0.requiredPermission.map { "Needs \(intelligenceReadableName($0)) permission" } ?? "No extra permission"
                )
            }
            loaded = true
        }
        .accessibilityIdentifier("settings.intelligence.tools")
    }
}
