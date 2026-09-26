import SwiftUI
import UniformTypeIdentifiers

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
    @State private var nodusTask: Task<Void, Never>?
    @State private var nodusPrompt = "Explain photosynthesis simply."
    @State private var lastNodusAnswer: NodusAnswer?
    @State private var lastNodusQuestion = ""
    @State private var missionCount = 0
    @State private var candidateCount = 0
    @State private var installedManifest: NodusModelManifest?
    @State private var installedSize = "—"
    @State private var showingArtifactImporter = false
    @State private var artifactStatus = "No installation action"
    @State private var expectedArtifactHash = ""

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

            Section("Nodus") {
                LabeledContent("Version", value: installedManifest?.nodusVersion ?? "Not installed")
                LabeledContent("Base model", value: installedManifest?.baseModel ?? "Not installed")
                LabeledContent("Quantization", value: installedManifest?.quantization ?? "4-bit expected")
                LabeledContent("Storage", value: installedSize)
                LabeledContent("Status", value: snapshot?.nodusProviderAvailability?.displayName ?? "Not registered")
                LabeledContent("Provider", value: NodusIntelligenceProvider.providerID)
                LabeledContent("Execution", value: "Local")
                LabeledContent("Load state", value: snapshot?.nodusLoadState?.rawValue.capitalized ?? "Unavailable")
                LabeledContent("Confidence engine", value: "External / calibrated")
                TextField("Expected sha256: artifact hash", text: $expectedArtifactHash)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Install verified artifact…") { showingArtifactImporter = true }
                    .disabled(expectedArtifactHash.count != 71 || !expectedArtifactHash.hasPrefix("sha256:"))
                Button("Delete installed Nodus", role: .destructive) {
                    Task { await deleteArtifact() }
                }
                .disabled(installedManifest == nil)
                Button("Rollback to previous Nodus") {
                    Task { await rollbackArtifact() }
                }
                Text(artifactStatus).font(.caption).foregroundStyle(.secondary)
                Button("Open Nodus Chat") {
                    app.navigation.open(.settings(.developer(.nodusChat)))
                }
                .accessibilityIdentifier("intelligence.nodus.open-chat")
                Button("Open Nodus Workspace") {
                    app.navigation.open(.settings(.developer(.nodus)))
                }
                .accessibilityIdentifier("intelligence.nodus.open-workspace")
                Button("Configure Online Search") {
                    app.navigation.open(.settings(.developer(.nodusSearch)))
                }
                .accessibilityIdentifier("intelligence.nodus.open-search")
            }

            Section("Nodus playground") {
                TextField("Prompt", text: $nodusPrompt, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .accessibilityIdentifier("intelligence.nodus.prompt")
                Button(runningProviderID == NodusIntelligenceProvider.providerID ? "Generating…" : "Run Nodus") {
                    nodusTask = Task { await runNodus() }
                }
                .accessibilityIdentifier("intelligence.nodus.generate")
                .disabled(runningProviderID != nil || snapshot?.nodusProviderAvailability != .available)
                if runningProviderID == NodusIntelligenceProvider.providerID {
                    Button("Cancel generation", role: .cancel) { nodusTask?.cancel() }
                        .accessibilityIdentifier("intelligence.nodus.cancel")
                }
                if let answer = lastNodusAnswer {
                    Text(answer.answer).textSelection(.enabled)
                    LabeledContent("Confidence", value: answer.confidence.band.displayName)
                    LabeledContent("Freshness", value: answer.freshness.displayName)
                    LabeledContent("Verification", value: answer.verificationRecommended ? "Recommended" : "Not needed")
                    LabeledContent("Provider", value: NodusIntelligenceProvider.providerID)
                    LabeledContent("Execution", value: "Local")
                    LabeledContent("Latency", value: answer.latencySeconds.map { String(format: "%.2f s", $0) } ?? "—")
                    LabeledContent("Tokens/sec", value: answer.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "—")
                    if answer.verificationRecommended {
                        Button("Verify when online") { Task { await createVerificationMission() } }
                            .accessibilityIdentifier("intelligence.nodus.verify")
                    }
                }
            }

            Section("Governed learning diagnostics") {
                LabeledContent("Verification Missions", value: "\(missionCount)")
                    .accessibilityIdentifier("intelligence.nodus.mission-count")
                LabeledContent("Learning Candidates", value: "\(candidateCount)")
                    .accessibilityIdentifier("intelligence.nodus.candidate-count")
                LabeledContent("Training Dataset Revision", value: "nodus-training-v0.1")
                Text("Verification does not grant training consent. Candidates remain pending or ineligible until separately approved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .modulaSoftScrollEdge()
        .navigationTitle("Local Intelligence")
        .accessibilityIdentifier("settings.developer.intelligence")
        .task { await refresh() }
        .onDisappear { appleTask?.cancel(); nodusTask?.cancel() }
        .fileImporter(
            isPresented: $showingArtifactImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task { await installArtifact(result) }
        }
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
        installedManifest = try? await app.nodusArtifactInstaller.installedManifest()
        let bytes = (try? await app.nodusArtifactInstaller.installedSizeBytes()) ?? 0
        installedSize = bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "—"
        let state = await app.nodusVerificationStore.snapshot()
        missionCount = state.missions.count
        candidateCount = state.learningCandidates.count
    }

    private func runNodus() async {
        runningProviderID = NodusIntelligenceProvider.providerID
        defer { runningProviderID = nil; nodusTask = nil }
        let request = IntelligenceRequest(
            capability: .generate, input: .string(nodusPrompt), privacy: .localOnly,
            source: .developerDiagnostics
        )
        do {
            let response = try await app.intelligence.executeDiagnostic(
                request, usingProviderID: NodusIntelligenceProvider.providerID
            )
            lastNodusAnswer = NodusAnswer.parse(response.output)
            lastNodusQuestion = nodusPrompt
            lastStatus = "Success"
        } catch let error as IntelligenceError {
            lastStatus = error == .requestCancelled ? "Cancelled" : "Failed"
            lastResult = error.code
        } catch {
            lastStatus = "Failed"
            lastResult = "Unexpected error"
        }
        await refresh()
    }

    private func createVerificationMission() async {
        guard let answer = lastNodusAnswer else { return }
        let reason: NodusVerificationReason = answer.freshness == .currentDataRequired
            ? .freshnessRequired : .lowConfidence
        do {
            _ = try await app.nodusVerificationStore.createMission(
                question: lastNodusQuestion, answer: answer, reason: reason,
                connectivityAvailable: false
            )
            artifactStatus = "Verification Mission queued locally"
        } catch {
            artifactStatus = "Could not persist Verification Mission"
        }
        await refresh()
    }

    private func installArtifact(_ result: Result<[URL], any Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            await app.intelligence.unloadNodus()
            let manifest = try await app.nodusArtifactInstaller.installVerifiedArtifact(
                from: url,
                expectedArtifactHash: expectedArtifactHash
            )
            artifactStatus = "Installed \(manifest.nodusVersion); restart diagnostics before loading"
        } catch {
            artifactStatus = "Artifact rejected: manifest or hash validation failed"
        }
        await refresh()
    }

    private func rollbackArtifact() async {
        do {
            await app.intelligence.unloadNodus()
            let rolledBack = try await app.nodusArtifactInstaller.rollbackToPreviousArtifact()
            artifactStatus = rolledBack ? "Rolled back to the previous accepted Nodus" : "No previous artifact is available"
        } catch {
            artifactStatus = "Could not roll back Nodus"
        }
        await refresh()
    }

    private func deleteArtifact() async {
        do {
            await app.intelligence.unloadNodus()
            try await app.nodusArtifactInstaller.deleteAcceptedArtifact()
            artifactStatus = "Installed artifact deleted; previous accepted artifact retained for rollback"
        } catch {
            artifactStatus = "Could not delete installed artifact"
        }
        await refresh()
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
