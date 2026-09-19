import SwiftUI

#if DEBUG
/// Developer-only Local Intelligence diagnostic. Not a consumer AI surface.
struct IntelligenceDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var snapshot: IntelligenceServiceSnapshot?
    @State private var lastResult: String = "—"
    @State private var lastProvider: String = "—"
    @State private var lastExecution: String = "—"
    @State private var lastCapability: String = "—"
    @State private var lastStatus: String = "—"
    @State private var isRunning = false

    var body: some View {
        Form {
            Section("Local Intelligence") {
                LabeledContent("Native core", value: snapshot?.coreReady == true ? "Ready" : "—")
                LabeledContent("Providers", value: countText(snapshot?.providerCount))
                LabeledContent("Local providers", value: countText(snapshot?.localProviderCount))
                LabeledContent("Remote providers", value: countText(snapshot?.remoteProviderCount))
                LabeledContent("Real model", value: snapshot?.realModelConnected == true ? "Connected" : "Not connected")
                LabeledContent(
                    "Privacy enforcement",
                    value: snapshot.map { $0.privacyEnforcementPass ? "PASS" : "FAIL" } ?? "—"
                )
                LabeledContent("Network required", value: snapshot?.networkRequired == true ? "Yes" : "No")
            }

            Section("Last local test") {
                LabeledContent("Provider", value: lastProvider)
                LabeledContent("Execution", value: lastExecution)
                LabeledContent("Capability", value: lastCapability)
                LabeledContent("Status", value: lastStatus)
                Text(lastResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(isRunning ? "Running…" : "Run Local Test") {
                    Task { await runLocalTest() }
                }
                .disabled(isRunning)
            }
        }
        .navigationTitle("Local Intelligence")
        .task { await refresh() }
    }

    private func countText(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    private func refresh() async {
        snapshot = await app.intelligence.diagnosticsSnapshot()
    }

    private func runLocalTest() async {
        isRunning = true
        defer { isRunning = false }
        let request = IntelligenceRequest(
            capability: .summarize,
            input: .object([
                "text": .string("Modula is a modular social operating system."),
            ]),
            privacy: .localOnly,
            source: .developerDiagnostics
        )
        do {
            let response = try await app.intelligence.execute(request)
            lastProvider = response.providerID
            lastExecution = response.executionKind == .local ? "Local" : "Remote"
            lastCapability = response.capability.rawValue.capitalized
            lastStatus = "Success"
            if case let .object(object) = response.output,
               case let .string(summary)? = object["summary"] {
                lastResult = summary
            } else {
                lastResult = "Deterministic response received"
            }
        } catch let error as IntelligenceError {
            lastProvider = "—"
            lastExecution = "—"
            lastCapability = request.capability.rawValue.capitalized
            lastStatus = "Failed"
            lastResult = error.code
        } catch {
            lastStatus = "Failed"
            lastResult = "Unexpected error"
        }
        await refresh()
    }
}
#endif
