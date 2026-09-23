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
        }
        .task { await model.refresh(using: app.intelligence) }
        .onDisappear { model.cancel() }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nodus")
                    .font(.headline)
                    .accessibilityIdentifier("nodus.chat.screen")
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Local")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var conversation: some View {
        if model.availability != .available && model.messages.isEmpty {
            ContentUnavailableView(
                "No accepted Nodus model is installed.",
                systemImage: "brain.head.profile",
                description: Text("Install a hash-verified accepted model from Local Intelligence diagnostics.")
            )
            .accessibilityIdentifier("nodus.chat.model-not-installed")
        } else if model.messages.isEmpty {
            ContentUnavailableView(
                "Test Nodus locally",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Ask a general or Modula question. This history stays in memory for this session.")
            )
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
                    DisclosureGroup("Details") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                            detail("Task", answer.taskMode?.rawValue ?? NodusTaskMode.generalAnswer.rawValue)
                            detail("Model", answer.modelVersion)
                            detail("Base", "Qwen3-1.7B")
                            detail("Provider", NodusIntelligenceProvider.providerID)
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
            if let message = model.errorMessage ?? model.verificationStatus {
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
        case .modelNotInstalled: "No accepted model installed"
        default: model.availability.displayName
        }
    }
}
#endif
