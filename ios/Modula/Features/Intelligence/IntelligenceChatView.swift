import SwiftUI

enum IntelligenceChatIdentity {
    /// Nodus names the entry point once it can actually answer (or always in developer
    /// builds, which show Nodus' own unavailable states); otherwise it is plain AI Chat.
    static var presentsNodus: Bool {
        guard NodusChatFeature.isEnabled() else { return false }
        return NodusChatFeature.showsUnavailableNodus
            || (NodusDeviceCapability.evaluate() == .supported && NodusModelStorage.hasInstalledModel())
    }

    static var title: String { presentsNodus ? "Nodus" : "AI Chat" }

    static var subtitle: String {
        presentsNodus ? "On-device personal intelligence" : "On-device intelligence"
    }

    static var aliases: [String] {
        var aliases = ["ai", "assistant", "intelligence"]
        aliases += presentsNodus ? ["nodus", "local intelligence"] : ["apple intelligence"]
        return aliases
    }
}

@MainActor
struct IntelligenceChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable {
        case user
        case assistant
        case status
    }

    let id: UUID
    var role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct IntelligenceChatView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var composerFocused: Bool

    @State private var messages: [IntelligenceChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var availability: IntelligenceAvailability?

    @State private var surface: NodusChatSurface?

    static var activeProviderID: String {
        IntelligenceChatIdentity.presentsNodus
            ? NodusIntelligenceProvider.providerID
            : AppleSystemIntelligenceProvider.providerID
    }

    @ViewBuilder
    var body: some View {
        switch surface ?? Self.immediateSurface {
        case .some(.nodus):
            NavigationStack {
                NodusChatView(presentation: .accessorySheet)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("intelligence.chat")
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .some(.appleFallback):
            legacyAppleIntelligenceChat
        case .none:
            NavigationStack {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modulaCanvas()
                    .accessibilityIdentifier("intelligence.chat.resolving")
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .task { await resolveSurface() }
        }
    }

    /// Surfaces that need no async availability probe: feature off, or developer builds.
    private static var immediateSurface: NodusChatSurface? {
        guard NodusChatFeature.isEnabled() else { return .appleFallback }
        if NodusChatFeature.showsUnavailableNodus { return .nodus }
        guard NodusDeviceCapability.evaluate() == .supported, NodusModelStorage.hasInstalledModel() else {
            return .appleFallback
        }
        return nil
    }

    private func resolveSurface() async {
        let snapshot = await app.intelligence.diagnosticsSnapshot()
        surface = NodusChatRouting.surface(
            featureEnabled: NodusChatFeature.isEnabled(),
            nodusAvailability: snapshot.nodusProviderAvailability
        )
    }

    private var legacyAppleIntelligenceChat: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                composer
            }
            .modulaCanvas()
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("intelligence.chat.close")
                }
            }
            .task { await refreshAvailability() }
            .onAppear {
                if messages.isEmpty {
                    messages.append(.init(role: .status, text: availabilityCopy))
                }
            }
            .onChange(of: availability) { _, _ in
                if messages.count == 1, messages.first?.role == .status {
                    messages = [.init(role: .status, text: availabilityCopy)]
                }
            }
            .accessibilityIdentifier("intelligence.chat")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                            .id("intelligence.chat.pending")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .modulaSoftScrollEdge()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onChange(of: isSending) { _, sending in
                if sending {
                    proxy.scrollTo("intelligence.chat.pending", anchor: .bottom)
                }
            }
        }
    }

    private func bubble(_ message: IntelligenceChatMessage) -> some View {
        let isUser = message.role == .user
        return Text(message.text)
            .font(message.role == .status ? .subheadline : .body)
            .foregroundStyle(message.role == .status ? .secondary : (isUser ? Color.white : Color.primary))
            .padding(.horizontal, message.role == .status ? 4 : 14)
            .padding(.vertical, message.role == .status ? 2 : 10)
            .background {
                if message.role != .status {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isUser ? app.appearance.liveAccent : Color(uiColor: .secondarySystemBackground))
                }
            }
            .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .accessibilityIdentifier(isUser ? "intelligence.chat.user" : "intelligence.chat.assistant")
    }

    private var composer: some View {
        // Shared Liquid Glass composer (design system); dictation stays on device.
        ModulaComposer(
            text: $draft,
            prompt: "Ask Modula…",
            enabled: canSend && !isSending,
            sending: isSending,
            showsAttachmentButton: false,
            externalFocus: Binding(get: { composerFocused }, set: { composerFocused = $0 }),
            onSend: { Task { await send() } }
        )
        .accessibilityIdentifier("intelligence.chat.field")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        availability == .available
    }

    private var canSubmit: Bool {
        canSend && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availabilityCopy: String {
        switch availability {
        case .available:
            "On-device intelligence is ready. Nothing leaves this iPhone."
        case .disabled:
            "Turn on Apple Intelligence in Settings to chat on-device."
        case .modelNotInstalled, .modelDownloading:
            "The on-device model isn’t ready yet."
        case .unsupportedDevice:
            "This device can’t run on-device intelligence."
        case .unsupportedOS:
            "This iOS version can’t run on-device intelligence."
        case .none:
            "Checking on-device intelligence…"
        default:
            "On-device intelligence isn’t available right now."
        }
    }

    private func refreshAvailability() async {
        let snapshot = await app.intelligence.diagnosticsSnapshot()
        availability = snapshot.appleProviderAvailability
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }
        draft = ""
        messages.append(.init(role: .user, text: text))
        isSending = true
        defer { isSending = false }

        let prompt = conversationPrompt(adding: text)
        let request = IntelligenceRequest(
            capability: .generate,
            input: .object(["text": .string(prompt)]),
            privacy: .localOnly,
            source: .nativeFeature
        )
        do {
            let response = try await app.intelligence.execute(request)
            guard response.providerID != DeterministicLocalProvider.providerID else {
                messages.append(.init(role: .status, text: "On-device intelligence isn’t available right now."))
                return
            }
            let reply = Self.replyText(from: response.output)
                ?? "I couldn’t form a reply from that result."
            messages.append(.init(role: .assistant, text: reply))
        } catch let error as IntelligenceError {
            messages.append(.init(role: .status, text: Self.userMessage(for: error)))
        } catch {
            messages.append(.init(role: .status, text: "Couldn’t complete that on-device."))
        }
    }

    private func conversationPrompt(adding latest: String) -> String {
        var lines: [String] = [
            "You are Modula’s on-device assistant. Answer helpfully and concisely. Do not invent account data, ratings, or permissions."
        ]
        for message in messages.suffix(9) {
            switch message.role {
            case .user: lines.append("User: \(message.text)")
            case .assistant: lines.append("Assistant: \(message.text)")
            case .status: break
            }
        }
        if messages.last?.text != latest {
            lines.append("User: \(latest)")
        }
        return lines.joined(separator: "\n")
    }

    static func replyText(from output: IntelligenceValue) -> String? {
        if let text = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if let object = output.objectValue {
            for key in ["text", "summary", "content"] {
                if let text = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    static func userMessage(for error: IntelligenceError) -> String {
        switch error {
        case .localProviderUnavailable, .noEligibleProvider, .providerUnavailable:
            "On-device intelligence isn’t available right now."
        case .safetyRefusal:
            "That request was declined."
        case .contextLimitExceeded:
            "This conversation is too long. Start a new chat."
        case .unsupportedLanguage:
            "That language isn’t supported on-device."
        case .requestCancelled:
            "Cancelled."
        default:
            "Couldn’t complete that on-device."
        }
    }
}
