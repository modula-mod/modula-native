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

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(
                title: "Intelligence",
                subtitle: "On-device Swift. Fail-closed. No remote fallback from these screens.",
                symbol: "brain"
            )
            SettingsSceneGraphic(style: .orbit)
            SettingsGroup(title: "Open") {
                VStack(spacing: 0) {
                    SettingsNavigationRow(
                        title: "Models",
                        subtitle: "Registered providers on this device",
                        symbol: "cpu"
                    ) { app.navigation.open(.settings(.intelligence(.models))) }
                    SettingsDivider()
                    SettingsNavigationRow(
                        title: "Knowledge",
                        subtitle: "Local knowledge surfaces",
                        symbol: "books.vertical"
                    ) { app.navigation.open(.settings(.intelligence(.knowledge))) }
                    SettingsDivider()
                    SettingsNavigationRow(
                        title: "Privacy",
                        subtitle: "Local-only policy",
                        symbol: "hand.raised.fill"
                    ) { app.navigation.open(.settings(.intelligence(.privacy))) }
                    SettingsDivider()
                    SettingsNavigationRow(
                        title: "Tools",
                        subtitle: "Registered tool descriptors",
                        symbol: "wrench.and.screwdriver"
                    ) { app.navigation.open(.settings(.intelligence(.tools))) }
                }
            }
        }
        .navigationTitle("Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.intelligence")
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
                                        .foregroundStyle(.tint)
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
        default: id
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
    var body: some View {
        ContentUnavailableView {
            Label("No local knowledge index", systemImage: "books.vertical")
        } description: {
            Text("Knowledge corpora are not exposed as a product surface yet. Native will not invent catalogue entries.")
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Knowledge")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Requests use fail-closed local-only privacy. Remote providers are never selected as a silent fallback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Remote gate") {
                LabeledContent("Remote intelligence permitted", value: remotePermitted ? "Yes" : "No")
                Text("This gate is owned by the native intelligence service. Product settings do not invent a remote model picker.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Policies") {
                ForEach(IntelligencePrivacy.allCases, id: \.self) { policy in
                    LabeledContent(policyTitle(policy), value: policy.rawValue)
                }
            }
        }
        .modulaSoftScrollEdge()
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
                                        .foregroundStyle(.tint)
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
                    title: $0.id,
                    detail: $0.requiredPermission.map { "Requires \($0)" } ?? "No extra permission"
                )
            }
            loaded = true
        }
        .accessibilityIdentifier("settings.intelligence.tools")
    }
}
