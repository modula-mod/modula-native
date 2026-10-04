import SwiftUI
import Translation

// MARK: - Shared Liquid Glass composer
//
// The single composer used by comments, chats, story replies and Nodus-style inputs.
// Telegram-style layout on iOS 26: a round glass attach button, a glass pill with the
// avatar, text and media toggle, and a round glass mic that morphs into Send. Every
// piece is real Liquid Glass inside one GlassEffectContainer so controls morph into
// each other (attach → menu, mic → send). Reduce Transparency / older iOS fall back
// to materials; Reduce Motion swaps springs for short fades.

struct ModulaComposerAttachment: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var systemImage: String
    var thumbnailURL: URL? = nil
    var progress: Double? = nil
    var failed = false
}

struct ModulaComposerAttachmentOption: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var systemImage: String
    var tint: Color = .accentColor
}

struct ModulaComposerMention: Identifiable, Hashable, Sendable {
    var id: String
    var handle: String
    var displayName: String
    var avatarURL: URL?
}

struct ModulaComposerReply: Equatable, Sendable {
    var title: String
    var excerpt: String
}

struct ModulaComposerAvatar: Equatable, Sendable {
    var initials: String
    var url: URL?
}

struct ModulaComposerState: Equatable, Sendable {
    var text: String
    var isEnabled: Bool
    var isSending: Bool
    var attachments: [ModulaComposerAttachment]
    var characterLimit: Int?

    init(text: String = "", isEnabled: Bool = true, isSending: Bool = false, attachments: [ModulaComposerAttachment] = [], characterLimit: Int? = nil) {
        self.text = text
        self.isEnabled = isEnabled
        self.isSending = isSending
        self.attachments = attachments
        self.characterLimit = characterLimit
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isOverLimit: Bool { characterLimit.map { text.count > $0 } ?? false }
    var attachmentsReady: Bool { attachments.allSatisfy { $0.progress == nil && !$0.failed } }

    var canSend: Bool {
        isEnabled && !isSending && !isOverLimit && attachmentsReady && (!trimmed.isEmpty || !attachments.isEmpty)
    }

    /// The "@query" being typed at the end of the text, if any.
    static func mentionQuery(in text: String) -> String? {
        guard let range = text.range(of: #"(?:^|\s)@([A-Za-z0-9_.]{0,30})$"#, options: .regularExpression) else { return nil }
        let token = text[range].trimmingCharacters(in: .whitespaces)
        return String(token.dropFirst())
    }

    static func hashtagQuery(in text: String) -> String? {
        guard let range = text.range(of: #"(?:^|\s)#([A-Za-z0-9_]{1,40})$"#, options: .regularExpression) else { return nil }
        return String(text[range].trimmingCharacters(in: .whitespaces).dropFirst())
    }

    static func applying(hashtag tag: String, to text: String) -> String {
        guard let range = text.range(of: #"#([A-Za-z0-9_]{1,40})$"#, options: .regularExpression) else { return text }
        return text.replacingCharacters(in: range, with: "#\(tag) ")
    }

    static func applying(mention handle: String, to text: String) -> String {
        guard let range = text.range(of: #"@([A-Za-z0-9_.]{0,30})$"#, options: .regularExpression) else { return text }
        return text.replacingCharacters(in: range, with: "@\(handle) ")
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
            .padding(.vertical, 11)
            .frame(minHeight: ModulaLayout.minimumTouch)
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
                .foregroundStyle(.secondary)
                .frame(width: 36, height: ModulaLayout.minimumTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

typealias ModulaComposerAttachmentButton = ModulaComposerAccessoryButton

/// Progress ring for the character limit; shows the remaining count near the end.
struct ModulaCharacterLimitRing: View {
    let count: Int
    let limit: Int

    private var fraction: Double { min(Double(count) / Double(max(limit, 1)), 1) }
    private var remaining: Int { limit - count }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(remaining < 0 ? Color.red : (remaining <= 20 ? Color.orange : Color.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if remaining <= 20 {
                Text("\(remaining)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(remaining < 0 ? .red : .secondary)
            }
        }
        .frame(width: 22, height: 22)
        .animation(.snappy(duration: 0.15), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(remaining < 0 ? "\(-remaining) characters over the limit" : "\(remaining) characters left")
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
    /// Optional custom mic action; by default the mic dictates on device into the field.
    var onDictate: (() -> Void)? = nil
    /// Return sends instead of inserting a new line (Settings → Chats → Composer).
    var returnSends = false
    var spellCheck = true
    var avatar: ModulaComposerAvatar? = nil
    var reply: ModulaComposerReply? = nil
    var onCancelReply: (() -> Void)? = nil
    /// When non-empty the attach button opens a glass menu with these (backend-supported) options.
    var attachmentOptions: [ModulaComposerAttachmentOption] = []
    var onAttachmentOption: ((ModulaComposerAttachmentOption) -> Void)? = nil
    var onRemoveAttachment: ((ModulaComposerAttachment) -> Void)? = nil
    var characterLimit: Int? = nil
    var mentionSuggestions: [ModulaComposerMention] = []
    var onMentionQuery: ((String?) -> Void)? = nil
    /// Emoji/GIF panel toggle (shown in place of the keyboard by the host).
    var mediaPanelActive: Binding<Bool>? = nil
    var dictationEnabled = true
    var hashtagSuggestions: [String] = []
    var onHashtagQuery: ((String?) -> Void)? = nil
    var showsFormatting = false
    /// Hold the mic to record a voice note (tap still dictates).
    var onVoiceNote: ((ModulaVoiceNote) -> Void)? = nil
    var onSend: () -> Void

    @FocusState private var focused: Bool
    @State private var attachMenuOpen = false
    @StateObject private var dictation = NodusDictation()
    @StateObject private var recorder = ModulaVoiceRecorder()
    @State private var micPressStart: Date?
    @State private var micHoldTask: Task<Void, Never>?
    @State private var cancelDrag: CGFloat = 0
    @State private var showTranslate = false
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app

    private var state: ModulaComposerState {
        ModulaComposerState(text: text, isEnabled: enabled, isSending: sending, attachments: attachments, characterLimit: characterLimit)
    }

    private var showsMic: Bool {
        (onDictate != nil || dictationEnabled) && state.trimmed.isEmpty && attachments.isEmpty && !sending
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.8)
    }

    var body: some View {
        ModulaGlassGroup(spacing: 10) {
            VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
                if !mentionSuggestions.isEmpty { mentionList }
                if !hashtagSuggestions.isEmpty { hashtagList }
                if showsFormatting && focused && !recorder.isRecording {
                    ModulaFormattingBar(
                        onFormat: { text = ModulaTextFormat.apply($0, to: text) },
                        onTranslate: state.trimmed.isEmpty ? nil : { showTranslate = true }
                    )
                    .modulaGlassID("composer.formatting", in: glass)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                if let reply { replyPreview(reply) }
                if !attachments.isEmpty { attachmentStrip }
                if attachMenuOpen && !attachmentOptions.isEmpty { attachMenu }
                if let status = dictation.status {
                    Text(status).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if showsAttachmentButton && !recorder.isRecording { attachButton }
                    if recorder.isRecording {
                        ModulaRecordingPill(recorder: recorder, cancelProgress: min(cancelDrag / 110, 1))
                            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
                            .modulaGlassID("composer.field", in: glass)
                            .transition(.opacity)
                    } else {
                        fieldPill
                    }
                    trailingButton
                }
            }
        }
        .animation(motion, value: attachMenuOpen)
        .animation(motion, value: showsMic)
        .animation(motion, value: attachments)
        .animation(motion, value: reply)
        .animation(motion, value: mentionSuggestions)
        .animation(motion, value: hashtagSuggestions)
        .animation(motion, value: recorder.isRecording)
        .animation(motion, value: focused)
        .translationPresentation(isPresented: $showTranslate, text: text) { translated in
            text = translated
        }
        .onChange(of: text) { _, value in
            onMentionQuery?(ModulaComposerState.mentionQuery(in: value))
            onHashtagQuery?(ModulaComposerState.hashtagQuery(in: value))
            // A vertical TextField inserts "\n" for Return; treat a trailing newline as Send.
            guard returnSends, value.hasSuffix("\n") else { return }
            text = String(value.dropLast())
            send()
        }
        .onChange(of: focused) { _, value in
            externalFocus?.wrappedValue = value
            if value {
                attachMenuOpen = false
                mediaPanelActive?.wrappedValue = false
            }
        }
        .onChange(of: externalFocus?.wrappedValue) { _, value in
            if let value, value != focused { focused = value }
        }
        .onDisappear { if dictation.isListening { dictation.stop() } }
        #if DEBUG
        .onAppear {
            if DebugSettingsHarness.composerState == "attach", !attachmentOptions.isEmpty { attachMenuOpen = true }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modula.composer")
    }

    // MARK: Pieces

    private var attachButton: some View {
        ModulaGlassIconButton(
            title: attachMenuOpen ? "Close attachments" : "Add attachment",
            systemImage: attachMenuOpen ? "xmark" : "plus",
            size: ModulaLayout.minimumTouch,
            enabled: enabled
        ) {
            if attachmentOptions.isEmpty {
                onAttachment?()
            } else {
                attachMenuOpen.toggle()
                if attachMenuOpen { focused = false; mediaPanelActive?.wrappedValue = false }
            }
            HapticEngine.shared.play(.lightImpact)
        }
        .modulaGlassID("composer.attach", in: glass)
        .accessibilityIdentifier("composer.attach")
    }

    private var fieldPill: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let avatar {
                ModulaAvatar(initials: avatar.initials, url: avatar.url, size: 30)
                    .padding(.bottom, 7)
                    .accessibilityHidden(true)
            }
            ModulaComposerTextField(prompt: prompt, text: $text, enabled: enabled, focused: $focused)
                .autocorrectionDisabled(!spellCheck)
                .textInputAutocapitalization(ModulaPreferences.composerAutoCapitalise ? .sentences : .never)
                .submitLabel(returnSends ? .send : .return)
            if let characterLimit, text.count > characterLimit / 2 {
                ModulaCharacterLimitRing(count: text.count, limit: characterLimit)
                    .padding(.bottom, 11)
                    .transition(.opacity)
            }
            if let mediaPanelActive {
                ModulaComposerAccessoryButton(
                    title: mediaPanelActive.wrappedValue ? "Show keyboard" : "Emoji and GIFs",
                    systemImage: mediaPanelActive.wrappedValue ? "keyboard" : "face.smiling"
                ) {
                    let opening = !mediaPanelActive.wrappedValue
                    attachMenuOpen = false
                    if opening { focused = false }
                    mediaPanelActive.wrappedValue = opening
                    if !opening { focused = true }
                    HapticEngine.shared.play(.selection)
                }
                .accessibilityIdentifier("composer.media")
            }
        }
        .padding(.leading, avatar == nil ? 14 : 6)
        .padding(.trailing, mediaPanelActive == nil ? 14 : 4)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .modulaGlassID("composer.field", in: glass)
        .accessibilityIdentifier("composer.field")
    }

    /// Tap = dictation, hold = voice note (slide left to cancel).
    private var voiceMicButton: some View {
        Image(systemName: recorder.isRecording ? "mic.fill" : (dictation.isListening ? "stop.fill" : "mic"))
            .font(.body.weight(.semibold))
            .foregroundStyle(recorder.isRecording ? Color.white : (dictation.isListening ? Color.red : Color.primary))
            .symbolEffect(.bounce, value: recorder.isRecording)
            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
            .modulaGlass(in: Circle(), tint: recorder.isRecording ? .red : nil)
            .scaleEffect(recorder.isRecording && !reduceMotion ? 1.25 : 1)
            .offset(x: recorder.isRecording ? -min(cancelDrag, 120) * 0.4 : 0)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if micPressStart == nil {
                            micPressStart = Date()
                            micHoldTask = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(320))
                                guard !Task.isCancelled, micPressStart != nil else { return }
                                if dictation.isListening { dictation.stop() }
                                if await recorder.start() {
                                    HapticEngine.shared.play(.actionConfirmed)
                                }
                            }
                        }
                        guard recorder.isRecording else { return }
                        let dragged = max(0, -value.translation.width)
                        if dragged >= 110 && cancelDrag < 110 { HapticEngine.shared.play(.dragThreshold) }
                        cancelDrag = dragged
                    }
                    .onEnded { _ in
                        micHoldTask?.cancel()
                        defer { micPressStart = nil; cancelDrag = 0 }
                        if recorder.isRecording {
                            if cancelDrag >= 110 {
                                recorder.cancel()
                                HapticEngine.shared.play(.failure)
                            } else if let note = recorder.finish() {
                                onVoiceNote?(note)
                                HapticEngine.shared.play(.success)
                            }
                        } else if let start = micPressStart, Date().timeIntervalSince(start) < 0.32 {
                            if let onDictate { onDictate() } else {
                                dictation.toggle(current: { text }, apply: { text = $0 })
                            }
                            HapticEngine.shared.play(.lightImpact)
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate")
            .accessibilityHint("Touch and hold to record a voice note")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dictation.toggle(current: { text }, apply: { text = $0 }) }
            .accessibilityAction(named: "Record voice note") {
                Task { _ = await recorder.start() }
            }
            .accessibilityIdentifier("composer.mic")
    }

    private var hashtagList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hashtagSuggestions.prefix(8), id: \.self) { tag in
                    Button {
                        text = ModulaComposerState.applying(hashtag: tag, to: text)
                        onHashtagQuery?(nil)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Text("#\(tag)").font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule())
                }
            }
            .padding(.horizontal, 4)
        }
        .modulaGlassID("composer.hashtags", in: glass)
        .accessibilityIdentifier("composer.hashtags")
    }

    @ViewBuilder
    private var trailingButton: some View {
        if (showsMic || recorder.isRecording), onVoiceNote != nil {
            voiceMicButton
                .modulaGlassID("composer.trailing", in: glass)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
        } else if showsMic {
            ModulaGlassIconButton(
                title: dictation.isListening ? "Stop dictation" : "Dictate",
                systemImage: dictation.isListening ? "stop.fill" : "mic",
                size: ModulaLayout.minimumTouch,
                tint: dictation.isListening ? .red : nil,
                enabled: enabled
            ) {
                if let onDictate { onDictate() } else {
                    dictation.toggle(current: { text }, apply: { text = $0 })
                }
                HapticEngine.shared.play(.lightImpact)
            }
            .modulaGlassID("composer.trailing", in: glass)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
        } else {
            Button(action: send) {
                Group {
                    if sending { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "arrow.up").font(.body.weight(.bold)) }
                }
                .foregroundStyle(state.canSend ? Color.white : Color.secondary)
                .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Circle(), tint: state.canSend ? app.appearance.accent.color : nil)
            .disabled(!state.canSend)
            .modulaGlassID("composer.trailing", in: glass)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
            .accessibilityLabel(sending ? "Sending" : "Send")
            .accessibilityIdentifier("composer.send")
        }
    }

    private var attachMenu: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
            ForEach(attachmentOptions) { option in
                Button {
                    attachMenuOpen = false
                    HapticEngine.shared.play(.selection)
                    onAttachmentOption?(option)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.systemImage)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(option.tint.gradient, in: Circle())
                        Text(option.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer.attach.\(option.id)")
            }
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false)
        .modulaGlassID("composer.attach", in: glass)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.3, anchor: .bottomLeading).combined(with: .opacity))
        .accessibilityIdentifier("composer.attach.menu")
    }

    private func replyPreview(_ reply: ModulaComposerReply) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(app.appearance.accent.color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(reply.title).font(.caption.weight(.semibold)).foregroundStyle(app.appearance.accent.color)
                Text(reply.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onCancelReply {
                Button(action: onCancelReply) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel reply")
            }
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 6)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
        .modulaGlassID("composer.reply", in: glass)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityIdentifier("composer.reply")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ModulaSpacing.xs) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let url = attachment.thumbnailURL {
                                ModulaAnimatedRemoteImage(url: url)
                            } else {
                                Image(systemName: attachment.systemImage).font(.title3).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            if let progress = attachment.progress {
                                ZStack {
                                    Color.black.opacity(0.35)
                                    ProgressView(value: progress).progressViewStyle(.circular).tint(.white)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            } else if attachment.failed {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            }
                        }
                        if let onRemoveAttachment {
                            Button { onRemoveAttachment(attachment) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(3)
                            .accessibilityLabel("Remove \(attachment.title)")
                        }
                    }
                    .accessibilityLabel(attachment.title)
                }
            }
            .padding(6)
        }
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .accessibilityLabel("Attachments")
    }

    private var mentionList: some View {
        VStack(spacing: 0) {
            ForEach(mentionSuggestions.prefix(5)) { mention in
                Button {
                    text = ModulaComposerState.applying(mention: mention.handle, to: text)
                    onMentionQuery?(nil)
                    HapticEngine.shared.play(.selection)
                } label: {
                    HStack(spacing: 10) {
                        ModulaAvatar(initials: String(mention.displayName.prefix(2)).uppercased(), url: mention.avatarURL, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(mention.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("@\(mention.handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .modulaGlassID("composer.mentions", in: glass)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityIdentifier("composer.mentions")
    }

    private func send() {
        guard state.canSend else { return }
        if dictation.isListening { dictation.stop() }
        onSend()
        HapticEngine.shared.play(.actionConfirmed)
    }
}
