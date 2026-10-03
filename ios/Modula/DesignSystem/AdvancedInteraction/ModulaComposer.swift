import SwiftUI

struct ModulaComposerAttachment: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var systemImage: String
}

struct ModulaComposerState: Equatable, Sendable {
    var text: String
    var isEnabled: Bool
    var isSending: Bool
    var attachments: [ModulaComposerAttachment]

    init(text: String = "", isEnabled: Bool = true, isSending: Bool = false, attachments: [ModulaComposerAttachment] = []) {
        self.text = text
        self.isEnabled = isEnabled
        self.isSending = isSending
        self.attachments = attachments
    }

    var canSend: Bool {
        isEnabled && !isSending && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }
}

struct ModulaComposerTextField: View {
    let prompt: String
    @Binding var text: String
    var enabled = true
    var lineLimit: ClosedRange<Int> = 1...6
    @FocusState.Binding var focused: Bool

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .focused($focused)
            .lineLimit(lineLimit)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: ModulaLayout.minimumTouch)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
            .disabled(!enabled)
            .accessibilityLabel(prompt)
    }
}

struct ModulaComposerAccessoryButton: View {
    let title: String
    let systemImage: String
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

typealias ModulaComposerAttachmentButton = ModulaComposerAccessoryButton

struct ModulaComposerSendButton: View {
    var enabled: Bool
    var sending: Bool
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if sending {
                    ProgressView().controlSize(.small)
                        .transition(.opacity)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .transition(.opacity)
                }
            }
            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .background(enabled ? app.appearance.accent.color : Color.primary.opacity(0.06), in: Circle())
            // Subtle "wake up" when there is something to send.
            .scaleEffect(enabled || reduceMotion ? 1 : 0.92)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(ModulaMotion.animation(.morph, personality: app.appearance.motion, reduceMotion: reduceMotion), value: enabled)
        .animation(ModulaMotion.animation(.instantFeedback, personality: app.appearance.motion, reduceMotion: reduceMotion), value: sending)
        .accessibilityLabel(sending ? "Sending" : "Send")
    }
}

/// Trailing composer control that swaps between dictation (empty field)
/// and send (has content), like Messages. Only used when a caller
/// provides a dictation handler.
struct ModulaComposerTrailingButton: View {
    var canSend: Bool
    var sending: Bool
    var onDictate: (() -> Void)?
    var onSend: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsMic: Bool { onDictate != nil && !canSend && !sending }

    var body: some View {
        ZStack {
            if showsMic, let onDictate {
                ModulaComposerAccessoryButton(title: "Dictate", systemImage: "mic", action: onDictate)
                    .transition(swap)
            } else {
                ModulaComposerSendButton(enabled: canSend, sending: sending, action: onSend)
                    .transition(swap)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.18), value: showsMic)
    }

    private var swap: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }
}

struct ModulaComposer: View {
    @Binding var text: String
    var prompt = "Message"
    var enabled = true
    var sending = false
    var attachments: [ModulaComposerAttachment] = []
    var showsAttachmentButton = true
    var externalFocus: Binding<Bool>?
    var onAttachment: (() -> Void)?
    /// Optional: when set, the send button becomes a mic while the field is empty.
    var onDictate: (() -> Void)? = nil
    /// Return sends instead of inserting a new line (Settings → Chats → Composer).
    var returnSends = false
    var spellCheck = true
    var onSend: () -> Void

    @FocusState private var focused: Bool

    private var state: ModulaComposerState {
        ModulaComposerState(text: text, isEnabled: enabled, isSending: sending, attachments: attachments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ModulaSpacing.xs) {
                        ForEach(attachments) { attachment in
                            Label(attachment.title, systemImage: attachment.systemImage)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .modulaMaterial(.control, in: Capsule())
                        }
                    }
                }
                .accessibilityLabel("Attachments")
            }
            HStack(alignment: .bottom, spacing: ModulaSpacing.xs) {
                if showsAttachmentButton {
                    ModulaComposerAttachmentButton(title: "Add attachment", systemImage: "plus") {
                        onAttachment?()
                    }
                }
                ModulaComposerTextField(prompt: prompt, text: $text, enabled: enabled, focused: $focused)
                    .autocorrectionDisabled(!spellCheck)
                    // Settings → Keyboard → "Auto-capitalise sentences".
                    .textInputAutocapitalization(ModulaPreferences.composerAutoCapitalise ? .sentences : .never)
                    .submitLabel(returnSends ? .send : .return)
                ModulaComposerTrailingButton(canSend: state.canSend, sending: sending, onDictate: onDictate) {
                    onSend()
                    HapticEngine.shared.play(.actionConfirmed)
                }
            }
        }
        .onChange(of: text) { _, value in
            // A vertical TextField inserts "\n" for Return (software and
            // hardware keyboards); treat a trailing newline as Send.
            guard returnSends, value.hasSuffix("\n") else { return }
            text = String(value.dropLast())
            if state.canSend {
                onSend()
                HapticEngine.shared.play(.actionConfirmed)
            }
        }
        .onChange(of: focused) { _, value in externalFocus?.wrappedValue = value }
        .onChange(of: externalFocus?.wrappedValue) { _, value in
            if let value, value != focused { focused = value }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modula.composer")
    }
}
