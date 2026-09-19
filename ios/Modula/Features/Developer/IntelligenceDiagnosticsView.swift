import SwiftUI

#if DEBUG
/// Developer-only Local Intelligence diagnostic. Not a consumer AI surface.
struct IntelligenceDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var snapshot: IntelligenceServiceSnapshot?
    @State private var lastResult = "—"
    @State private var lastProvider = "—"
    @State private var lastExecution = "—"
    @State private var lastCapability = "—"
    @State private var lastDuration = "—"
    @State private var lastStatus = "—"
    @State private var runningProviderID: String?
    @State private var appleTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Local Intelligence") {
                LabeledContent("Native core", value: snapshot?.coreReady == true ? "Ready" : "—")
                LabeledContent("Apple system provider", value: appleProviderStatusText)
                LabeledContent("Apple availability reason", value: appleAvailabilityText)
                LabeledContent("Execution", value: "Local")
                LabeledContent("Network required", value: "No")
                LabeledContent("Real model", value: snapshot?.realModelConnected == true ? "Connected" : "Unavailable")
                LabeledContent("Deterministic provider", value: deterministicAvailabilityText)
                LabeledContent(
                    "Privacy enforcement",
                    value: snapshot.map { $0.privacyEnforcementPass ? "PASS" : "FAIL" } ?? "—"
                )
            }

            Section("Last local test") {
                LabeledContent("Provider", value: lastProvider)
                LabeledContent("Execution", value: lastExecution)
                LabeledContent("Capability", value: lastCapability)
                LabeledContent("Duration", value: lastDuration)
                LabeledContent("Status", value: lastStatus)
                Text(lastResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Real Apple model") {
                Button(runningProviderID == AppleSystemIntelligenceProvider.providerID ? "Running…" : "Run Apple Summarize Test") {
                    appleTask = Task {
                        await runTest(using: AppleSystemIntelligenceProvider.providerID)
                    }
                }
                .accessibilityIdentifier("intelligence.apple.summarize")
                .disabled(runningProviderID != nil || snapshot?.appleProviderAvailability != .available)

                if runningProviderID == AppleSystemIntelligenceProvider.providerID {
                    Button("Cancel Apple Test", role: .cancel) {
                        appleTask?.cancel()
                    }
                }
            }

            Section("Deterministic fixture") {
                Button(runningProviderID == DeterministicLocalProvider.providerID ? "Running…" : "Run Deterministic Test") {
                    Task { await runTest(using: DeterministicLocalProvider.providerID) }
                }
                .accessibilityIdentifier("intelligence.deterministic.summarize")
                .disabled(runningProviderID != nil || snapshot?.deterministicProviderAvailability != .available)
            }
        }
        .navigationTitle("Local Intelligence")
        .accessibilityIdentifier("settings.developer.intelligence")
        .task { await refresh() }
        .onDisappear { appleTask?.cancel() }
    }

    private var appleAvailabilityText: String {
        guard let availability = snapshot?.appleProviderAvailability else { return "Not registered" }
        return switch availability {
        case .unsupportedDevice: "Device not eligible"
        case .disabled: "Apple Intelligence disabled"
        case .modelNotInstalled: "Model not ready"
        default: availability.displayName
        }
    }

    private var appleProviderStatusText: String {
        guard let availability = snapshot?.appleProviderAvailability else { return "Not registered" }
        return availability == .available ? "Available" : "Unavailable"
    }

    private var deterministicAvailabilityText: String {
        snapshot?.deterministicProviderAvailability?.displayName ?? "Not registered"
    }

    private func refresh() async {
        snapshot = await app.intelligence.diagnosticsSnapshot()
    }

    private func runTest(using providerID: String) async {
        runningProviderID = providerID
        defer {
            runningProviderID = nil
            appleTask = nil
        }

        let request = IntelligenceRequest(
            capability: .summarize,
            input: .object([
                "text": .string(
                    "Modula is a modular social operating system that combines native experiences, modules, local intelligence and optional cloud services."
                ),
            ]),
            privacy: .localOnly,
            source: .developerDiagnostics
        )

        do {
            let response = try await app.intelligence.executeDiagnostic(
                request,
                usingProviderID: providerID
            )
            lastProvider = response.providerID
            lastExecution = response.executionKind == .local ? "Local" : "Remote"
            lastCapability = response.capability.rawValue.capitalized
            lastDuration = response.duration.map(String.init(describing:)) ?? "—"
            lastStatus = "Success"
            switch response.output {
            case .string(let value):
                lastResult = value
            case .object(let object):
                lastResult = object["summary"]?.stringValue ?? "Structured response received"
            default:
                lastResult = "Response received"
            }
        } catch let error as IntelligenceError {
            lastProvider = providerID
            lastExecution = "Local"
            lastCapability = request.capability.rawValue.capitalized
            lastDuration = "—"
            lastStatus = error == .requestCancelled ? "Cancelled" : "Failed"
            if case .providerUnavailable = error,
               providerID == AppleSystemIntelligenceProvider.providerID {
                lastResult = snapshot?.appleProviderAvailability == .available
                    ? "Model service unavailable during execution"
                    : appleAvailabilityText
            } else {
                lastResult = error.code
            }
        } catch {
            lastStatus = "Failed"
            lastResult = "Unexpected error"
        }
        await refresh()
    }
}
#endif
