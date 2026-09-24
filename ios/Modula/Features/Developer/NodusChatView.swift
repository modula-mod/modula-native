import SwiftUI

#if DEBUG
struct NodusChatView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var model = NodusChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            conversation
            Divider()
            composer
        }
        .navigationTitle("Nodus Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { model.clear() }
                    .disabled(model.messages.isEmpty)
                    .accessibilityIdentifier("nodus.chat.clear")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: app.nodusEvaluationStore.exportURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export Nodus evaluations")
                .accessibilityIdentifier("nodus.chat.export-evaluations")
            }
        }
        .task { await model.refresh(using: app.intelligence) }
        .onDisappear { model.cancel() }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.modelIdentity?.displayName ?? "Nodus R7")
                    .font(.headline)
                    .accessibilityIdentifier("nodus.chat.screen")
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Experimental")
                    .foregroundStyle(.orange)
                Text("Local · 4-bit")
            }
            .font(.caption.weight(.medium))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var conversation: some View {
        if model.availability == .modelNotInstalled && model.messages.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "Nodus model not installed",
                    systemImage: "brain.head.profile",
                    description: Text("A verified experimental developer bundle was not found.")
                )
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    detail("Provider", NodusIntelligenceProvider.providerID)
                    detail("Status", IntelligenceAvailability.modelNotInstalled.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("nodus.chat.model-not-installed")
        } else if model.availability != .available && model.messages.isEmpty {
            ContentUnavailableView(
                model.availability.displayName,
                systemImage: "exclamationmark.triangle",
                description: Text("Nodus cannot execute on this device. The experimental bundle remains local and no fallback provider will be used.")
            )
            .accessibilityIdentifier("nodus.chat.unavailable")
        } else if model.messages.isEmpty {
            VStack(spacing: 14) {
                Label("Experimental model", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Not approved for production")
                    .font(.subheadline.weight(.semibold))
                Text("Ask any general or Modula question. Conversation context is bounded to recent messages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                modelDetails
            }
            .padding()
            .accessibilityIdentifier("nodus.chat.experimental-warning")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                        if model.isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Nodus is thinking…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .accessibilityIdentifier("nodus.chat.generating")
                        }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: NodusChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .textSelection(.enabled)
                if let answer = message.answer {
                    HStack(spacing: 10) {
                        Label(answer.confidence.band.displayName, systemImage: "gauge.with.dots.needle.33percent")
                        Label(answer.freshness.displayName, systemImage: "clock")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if answer.verificationRecommended {
                        Button("Verify when online") {
                            Task { await model.queueVerification(for: message, store: app.nodusVerificationStore) }
                        }
                        .font(.caption)
                        .accessibilityIdentifier("nodus.chat.verify")
                    }
                    evaluationControls(for: message)
                    DisclosureGroup("Details") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                            detail("Task", answer.taskMode?.rawValue ?? NodusTaskMode.generalAnswer.rawValue)
                            detail("Model", answer.modelVersion)
                            detail("Base", model.modelIdentity?.baseModel ?? "Qwen/Qwen3-1.7B")
                            detail("Model", "R7")
                            detail("Stage", model.modelIdentity?.stage.displayName ?? "Experimental candidate")
                            detail("Quantization", model.modelIdentity?.quantization ?? "4-bit")
                            detail("Provider", NodusIntelligenceProvider.providerID)
                            detail("Execution", "Local")
                            detail("Shipping", "Not allowed")
                            detail("Generation", answer.latencySeconds.map { String(format: "%.2f s", $0) } ?? "—")
                            detail("Tokens/sec", answer.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "—")
                            detail("Request", message.requestID?.uuidString ?? "—")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if message.role == .nodus { Spacer(minLength: 44) }
        }
    }

    private func detail(_ name: String, _ value: String) -> some View {
        GridRow { Text(name); Text(value).textSelection(.enabled) }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.errorMessage ?? model.verificationStatus ?? model.evaluationStatus {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Nodus", text: $model.input, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(model.availability != .available || model.isGenerating)
                    .accessibilityIdentifier("nodus.chat.input")
                Button {
                    model.isGenerating ? model.cancel() : model.send(using: app.intelligence)
                } label: {
                    Image(systemName: model.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }
                .disabled(!model.isGenerating && !model.canSend)
                .accessibilityLabel(model.isGenerating ? "Stop" : "Send")
                .accessibilityIdentifier(model.isGenerating ? "nodus.chat.stop" : "nodus.chat.send")
            }
        }
        .padding()
    }

    private var statusText: String {
        switch model.availability {
        case .available:
            switch model.loadState {
            case .loading: "Loading Nodus…"
            case .generating: "Generating locally"
            case .failed: "Load failed"
            default: "Ready"
            }
        case .modelNotInstalled: "Model not installed"
        default: model.availability.displayName
        }
    }

    private var modelDetails: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            detail("Base", model.modelIdentity?.baseModel ?? "Qwen/Qwen3-1.7B")
            detail("Model", "R7")
            detail("Stage", model.modelIdentity?.stage.displayName ?? "Experimental candidate")
            detail("Quantization", model.modelIdentity?.quantization ?? "4-bit")
            detail("Provider", NodusIntelligenceProvider.providerID)
            detail("Execution", "Local")
            detail("Shipping", "Not allowed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func evaluationControls(for message: NodusChatMessage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NodusDeveloperRating.allCases, id: \.self) { rating in
                    Button(rating.displayName) {
                        Task {
                            await model.rate(
                                rating,
                                message: message,
                                store: app.nodusEvaluationStore
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(model.ratings[message.id] == rating ? Color.accentColor : nil)
                    .accessibilityIdentifier("nodus.chat.rating.\(rating.rawValue)")
                }
            }
        }
    }
}
#endif
