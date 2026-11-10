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
    /// Where this composer sits, for the mascot preference (Settings → Chats → Composer).
    var mascot: ModulaMascotPlacement = .other
    /// Keyboard down: the field, attach control and send button collapse into one floating glass pill.
    var collapsesWhenUnfocused = false
    /// Chats: the perched mascot steps away while you type, so it never sits over the field or the thread.
    var hidesMascotWhileComposing = false
    /// Tells the host when the "+" tray opens or closes (e.g. to expand a sheet).
    var onTrayChange: ((Bool) -> Void)? = nil
    var onSend: () -> Void

    @FocusState private var plainFocused: Bool
    @State private var richFocused = false
    @State private var rich = ModulaRichEditorController()
    @State private var linkSheet: ModulaLinkInsertSheet.Mode?
    /// Focus of whichever field is showing (rich WYSIWYG editor when formatting is enabled).
    private var focused: Bool {
        get { showsFormatting ? richFocused : plainFocused }
        nonmutating set { if showsFormatting { richFocused = newValue } else { plainFocused = newValue } }
    }
    @State private var attachMenuOpen = false
    @StateObject private var dictation = NodusDictation()
    @StateObject private var recorder = ModulaVoiceRecorder()
    @State private var micPressStart: Date?
    @State private var micHoldTask: Task<Void, Never>?
    @State private var cancelDrag: CGFloat = 0
    @State private var showTranslate = false
    @State private var handsFreeRecording = false
    /// Debounced formatting-bar visibility: a tool tap that briefly drops focus no longer
    /// collapses the card and snaps it back.
    @State private var formatBarShown = false
    /// Formatting tools are opt-in: the "Aa" button in the field toggles them.
    @State private var formatBarRequested = false
    @State private var formatBarHide: Task<Void, Never>?
    @State private var attachAppeared = false
    @State private var attachPage: Int? = 0
    /// Keeps the docked composer open for the moment between a pill tap and the keyboard appearing.
    @State private var holdExpanded = false
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(AppEnvironment.self) private var app

    private var state: ModulaComposerState {
        ModulaComposerState(text: text, isEnabled: enabled, isSending: sending, attachments: attachments, characterLimit: characterLimit)
    }

    private var showsMic: Bool {
        (onDictate != nil || dictationEnabled) && state.trimmed.isEmpty && attachments.isEmpty && !sending
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0)
    }

    /// Quick ease, no bounce, for the card growing/shrinking around the formatting bar.
    private var barMotion: Animation { .easeOut(duration: reduceMotion ? 0.12 : 0.2) }

    /// The formatting bar is for text editing only: hidden while the tray, media panel or a recording owns the dock.
    private var wantsFormatBar: Bool {
        showsFormatting && formatBarRequested && focused && !recorder.isRecording && !attachMenuOpen && mediaPanelActive?.wrappedValue != true
    }

    private func syncFormatBar(_ wants: Bool) {
        formatBarHide?.cancel()
        if wants {
            if !formatBarShown { withAnimation(barMotion) { formatBarShown = true } }
        } else if !formatBarRequested || attachMenuOpen || recorder.isRecording || mediaPanelActive?.wrappedValue == true {
            if formatBarShown { withAnimation(barMotion) { formatBarShown = false } }
        } else {
            // Focus loss only: wait a beat so a tool tap that refocuses keeps the bar steady.
            formatBarHide = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled, !wantsFormatBar else { return }
                withAnimation(barMotion) { formatBarShown = false }
            }
        }
    }

    /// Bouncier than the in-bar tweaks. Reduce Motion crossfades instead.
    private var collapseAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.58)
    }

    /// Keyboard dismissed, and nothing else (attach menu, media panel, recording) is using the dock.
    private var idleCollapsed: Bool {
        collapsesWhenUnfocused
            && !focused
            && !holdExpanded
            && !attachMenuOpen
            && !recorder.isRecording
            && !handsFreeRecording
            && mediaPanelActive?.wrappedValue != true
            && !sending
            && !dictation.isListening
    }

    var body: some View {
        ModulaGlassGroup(spacing: 10) {
            Group {
                if idleCollapsed {
                    collapsedPill.modifier(ComposerDockMorph(namespace: glass, enabled: !reduceMotion))
                } else {
                    dockedComposer.modifier(ComposerDockMorph(namespace: glass, enabled: !reduceMotion))
                }
            }
            .animation(collapseAnimation, value: idleCollapsed)
        }
        .animation(motion, value: attachMenuOpen)
        .animation(motion, value: showsMic)
        .animation(motion, value: attachments)
        .animation(motion, value: reply)
        .animation(motion, value: mentionSuggestions)
        .animation(motion, value: hashtagSuggestions)
        .animation(motion, value: recorder.isRecording)
        .onChange(of: wantsFormatBar, initial: true) { _, wants in syncFormatBar(wants) }
        .animation(motion, value: focused)
        .translationPresentation(isPresented: $showTranslate, text: text) { translated in
            text = translated
        }
        .sheet(item: Binding(get: { linkSheet.map { LinkSheetItem(mode: $0) } }, set: { linkSheet = $0?.mode })) { item in
            ModulaLinkInsertSheet(mode: item.mode, initialText: rich.selectedText) { label, value in
                switch item.mode {
                case .link: rich.insertLink(text: label, url: value)
                case .abbr: rich.insertAbbreviation(label, title: value)
            }
        }
        }
        .onChange(of: text) { _, value in
            onMentionQuery?(ModulaComposerState.mentionQuery(in: value))
            onHashtagQuery?(ModulaComposerState.hashtagQuery(in: value))
            // A vertical TextField inserts "\n" for Return; treat a trailing newline as Send.
            guard returnSends, value.hasSuffix("\n") else { return }
            text = String(value.dropLast())
            send()
        }
        .onChange(of: focused) { wasFocused, value in
            externalFocus?.wrappedValue = value
            if value {
                attachMenuOpen = false
                mediaPanelActive?.wrappedValue = false
            } else if wasFocused {
                // Keyboard went down after it was up. A failed focus before the field exists stays expanded.
                holdExpanded = false
            }
        }
        .onChange(of: externalFocus?.wrappedValue) { _, value in
            guard let value else { return }
            if value {
                holdExpanded = true
                if !focused { focused = true }
            } else {
                holdExpanded = false
                if focused { focused = false }
            }
        }
        .onDisappear { if dictation.isListening { dictation.stop() } }
        #if DEBUG
        .onAppear {
            if DebugSettingsHarness.composerState == "attach", !attachmentOptions.isEmpty { attachMenuOpen = true }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modula.composer")
        // Mascot perches on the composer's top edge (topmost bar), clear of the mic/send button.
        .modulaMascotPerch()
        .modulaComposerMascot(mascot, busy: sending, text: text, attachmentCount: attachments.count, trailingInset: 62,
                              // Stand fully above the card (clear of the formatting tools) while the bar shows.
                              lift: formatBarShown ? 10 : 4,
                              hidden: hidesMascotWhileComposing && (focused || !text.isEmpty || attachMenuOpen || mediaPanelActive?.wrappedValue == true || recorder.isRecording))
        .onChange(of: attachMenuOpen) { _, open in onTrayChange?(open) }
    }

    private var dockedComposer: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
                if !mentionSuggestions.isEmpty { mentionList }
                if !hashtagSuggestions.isEmpty { hashtagList }
                // The formatting bar lives inside the field card (see `fieldPill`), so the
                // composer is one compact stack with no separate glass strip.
                if let reply { replyPreview(reply) }
                if !attachments.isEmpty { attachmentStrip }
                if let status = dictation.status {
                    Text(status).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if showsAttachmentButton && !recorder.isRecording { attachButton }
                    if handsFreeRecording && recorder.isRecording {
                        ModulaGlassIconButton(title: "Discard voice note", systemImage: "trash", size: ModulaLayout.minimumTouch, tint: .red) {
                            recorder.cancel()
                            handsFreeRecording = false
                            HapticEngine.shared.play(.failure)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
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
                // The "+" tray opens under the field, in the keyboard's place (iMessage app drawer).
                if attachMenuOpen && !attachmentOptions.isEmpty { attachMenu.padding(.top, -4) }
        }
        .task(id: holdExpanded) {
            guard collapsesWhenUnfocused, holdExpanded, !focused else { return }
            focused = true
        }
    }

    /// Keyboard down: attach, field and send sit in one floating Liquid Glass pill.
    private var collapsedPill: some View {
        Button {
            withAnimation(collapseAnimation) { holdExpanded = true }
        } label: {
            HStack(spacing: 10) {
                if showsAttachmentButton {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                Text(state.trimmed.isEmpty ? prompt : state.trimmed)
                    .font(.body)
                    .foregroundStyle(state.trimmed.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: state.canSend ? "arrow.up" : "mic")
                    .font(.body.weight(.bold))
                    .foregroundStyle(state.canSend ? Color.white : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background {
                        if state.canSend {
                            Circle().fill(app.appearance.liveAccent)
                        }
                    }
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .modulaGlass(in: Capsule(), interactive: true, specular: true)
            .modulaGlassID("composer.field", in: glass)
            .overlay {
                Capsule()
                    .strokeBorder(
                        reduceTransparency ? Color.primary.opacity(0.35) : app.appearance.liveAccent.opacity(0.7),
                        lineWidth: 1.15
                    )
                    .shadow(
                        color: reduceTransparency ? .clear : app.appearance.liveAccent.opacity(0.5),
                        radius: reduceTransparency ? 0 : 7
                    )
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .accessibilityLabel(state.trimmed.isEmpty ? prompt : state.trimmed)
        .accessibilityHint("Opens the keyboard")
        .accessibilityIdentifier("composer.collapsed")
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
        VStack(alignment: .leading, spacing: 0) {
            if formatBarShown && !recorder.isRecording {
                ModulaRichFormattingBar(
                    controller: rich,
                    onLink: { linkSheet = .link },
                    onAbbr: { linkSheet = .abbr },
                    onTranslate: state.trimmed.isEmpty ? nil : { showTranslate = true },
                    embedded: true,
                    onToolUsed: { if !focused { focused = true } }
                )
                .padding(.top, 4)
                .transition(.opacity)
            }
            fieldRow
        }
        // Ideal height only: bar then field, no stretched blank strip between them.
        .fixedSize(horizontal: false, vertical: true)
        // A plain shape background sized to the content (not a morphing glass effect), so the
        // formatting row is always inside the card. Also cheaper than live glass over the keyboard.
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("composer.field")
    }

    private var fieldRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let avatar {
                ModulaAvatar(initials: avatar.initials, url: avatar.url, size: 30)
                    .padding(.bottom, 7)
                    .accessibilityHidden(true)
            }
            if showsFormatting {
                ModulaRichTextEditor(
                    text: $text,
                    isFocused: $richFocused,
                    controller: rich,
                    enabled: enabled,
                    spellCheck: spellCheck,
                    autocapitalize: ModulaPreferences.composerAutoCapitalise,
                    returnSends: returnSends,
                    onReturn: send
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(prompt).foregroundStyle(.tertiary).padding(.top, 11).allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(prompt)
            } else {
                ModulaComposerTextField(prompt: prompt, text: $text, enabled: enabled, focused: $plainFocused)
                    .autocorrectionDisabled(!spellCheck)
                    .textInputAutocapitalization(ModulaPreferences.composerAutoCapitalise ? .sentences : .never)
                    .submitLabel(returnSends ? .send : .return)
            }
            if let characterLimit, text.count > characterLimit / 2 {
                ModulaCharacterLimitRing(count: text.count, limit: characterLimit)
                    .padding(.bottom, 11)
                    .transition(.opacity)
            }
            if showsFormatting && !recorder.isRecording {
                Button {
                    formatBarRequested.toggle()
                    if !focused { focused = true }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: "textformat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(formatBarRequested ? AnyShapeStyle(app.appearance.liveAccent) : AnyShapeStyle(.secondary))
                        .frame(width: 32, height: ModulaLayout.minimumTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(formatBarRequested ? "Hide formatting" : "Show formatting")
                .accessibilityAddTraits(formatBarRequested ? .isSelected : [])
                .accessibilityIdentifier("composer.format.toggle")
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
    }

    /// Tap = dictation, hold = voice note (slide left to cancel).
    private var voiceMicButton: some View {
        Image(systemName: recorder.isRecording ? "mic.fill" : (dictation.isListening ? "stop.fill" : "mic"))
            .font(.body.weight(.semibold))
            .foregroundStyle(recorder.isRecording ? Color.white : (dictation.isListening ? Color.red : Color.primary))
            .symbolEffect(.bounce, value: recorder.isRecording)
            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
            .modulaGlass(in: Circle(), tint: recorder.isRecording ? .red : nil, prominent: recorder.isRecording, specular: true)
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
                                    // Finger already up while the recorder spun up: keep it as a hands-free note.
                                    if micPressStart == nil { handsFreeRecording = true }
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
                        let held = micPressStart.map { Date().timeIntervalSince($0) } ?? 0
                        if recorder.isRecording {
                            if cancelDrag >= 110 {
                                recorder.cancel()
                                HapticEngine.shared.play(.failure)
                            } else if held < 1.2 {
                                // Short hold: keep recording hands-free (trash / send) instead of
                                // flashing the recorder and aborting a too-short note.
                                handsFreeRecording = true
                            } else if let note = recorder.finish() {
                                onVoiceNote?(note)
                                HapticEngine.shared.play(.success)
                            }
                        } else if held < 0.32 {
                            // Tap: start a hands-free voice note (dictation stays on the keyboard's mic
                            // and the VoiceOver "Dictate" action).
                            if dictation.isListening { dictation.stop() }
                            Task { @MainActor in
                                if await recorder.start() {
                                    handsFreeRecording = true
                                    HapticEngine.shared.play(.actionConfirmed)
                                }
                            }
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Record voice note")
            .accessibilityHint("Tap to record, or touch and hold and release to send")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                Task { @MainActor in if await recorder.start() { handsFreeRecording = true } }
            }
            .accessibilityAction(named: "Dictate") {
                if let onDictate { onDictate() } else { dictation.toggle(current: { text }, apply: { text = $0 }) }
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
        if handsFreeRecording && recorder.isRecording {
            ModulaGlassSendButton(title: "Send voice note", systemImage: "arrow.up", ready: true, busy: false, size: ModulaLayout.minimumTouch, tint: app.appearance.liveAccent) {
                handsFreeRecording = false
                if let note = recorder.finish() {
                    onVoiceNote?(note)
                    HapticEngine.shared.play(.success)
                }
            }
            .modulaGlassID("composer.trailing", in: glass)
            .accessibilityIdentifier("composer.voice.send")
        } else if (showsMic || recorder.isRecording), onVoiceNote != nil {
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
            ModulaGlassSendButton(ready: state.canSend, busy: sending, size: ModulaLayout.minimumTouch, tint: app.appearance.liveAccent, action: send)
            .modulaGlassID("composer.trailing", in: glass)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
            .accessibilityLabel(sending ? "Sending" : "Send")
            .accessibilityIdentifier("composer.send")
        }
    }

    /// Options the composer handles itself (no host round-trip).
    private func handleOption(_ option: ModulaComposerAttachmentOption) {
        attachMenuOpen = false
        HapticEngine.shared.play(.selection)
        switch option.id {
        case "link" where showsFormatting:
            focused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { linkSheet = .link }
        case "code" where showsFormatting:
            focused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { rich.apply(.codeBlock) }
        case "voice" where onVoiceNote != nil:
            Task { @MainActor in
                if dictation.isListening { dictation.stop() }
                if await recorder.start() {
                    handsFreeRecording = true
                    HapticEngine.shared.play(.actionConfirmed)
                }
            }
        default:
            onAttachmentOption?(option)
        }
    }

    private var attachPages: [[ModulaComposerAttachmentOption]] {
        stride(from: 0, to: attachmentOptions.count, by: 8).map { Array(attachmentOptions[$0..<min($0 + 8, attachmentOptions.count)]) }
    }

    private var attachMenu: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(attachPages.enumerated()), id: \.offset) { pageIndex, page in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                            ForEach(Array(page.enumerated()), id: \.element.id) { index, option in
                                attachTile(option, order: pageIndex * 8 + index)
                            }
                        }
                        .padding(.horizontal, 14)
                        // Room above the first row so icons (and their shadow) are never clipped.
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                        .id(pageIndex)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $attachPage)
            .frame(height: attachPages.count > 1 || attachmentOptions.count > 4 ? 196 : 104)
            if attachPages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<attachPages.count, id: \.self) { index in
                        Capsule()
                            .fill(Color.primary.opacity((attachPage ?? 0) == index ? 0.7 : 0.2))
                            .frame(width: (attachPage ?? 0) == index ? 16 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: attachPage)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        // Solid enough that the list behind never shows through the tray.
        .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, specular: true)
        .modulaGlassID("composer.attach", in: glass)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            attachPage = 0
            attachAppeared = false
            DispatchQueue.main.async { attachAppeared = true }
        }
        .onDisappear { attachAppeared = false }
        .accessibilityIdentifier("composer.attach.menu")
    }

    private func attachTile(_ option: ModulaComposerAttachmentOption, order: Int) -> some View {
        Button { handleOption(option) } label: {
            VStack(spacing: 6) {
                Image(systemName: option.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(option.tint.gradient, in: Circle())
                    .overlay {
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .shadow(color: option.tint.opacity(0.35), radius: 8, y: 4)
                Text(option.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressScaleStyle())
        // Crisp, short stagger (no bouncy overshoot that pushed the top row out of the tray).
        .scaleEffect(attachAppeared || reduceMotion ? 1 : 0.85)
        .opacity(attachAppeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18).delay(Double(order % 8) * 0.018), value: attachAppeared)
        .accessibilityIdentifier("composer.attach.\(option.id)")
    }

    private func replyPreview(_ reply: ModulaComposerReply) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(app.appearance.liveAccent).frame(width: 3, height: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(reply.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .lineLimit(1)
                if !reply.excerpt.isEmpty {
                    Text(reply.excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let onCancelReply {
                Button(action: onCancelReply) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel reply")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
        .modulaGlassID("composer.reply", in: glass)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reply.title)
        .accessibilityValue(reply.excerpt)
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

/// Matched-geometry morph between the docked composer and the floating pill.
/// Reduce Motion leaves this off so the swap is a crossfade.
private struct ComposerDockMorph: ViewModifier {
    var namespace: Namespace.ID
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: "composer.dock", in: namespace)
        } else {
            content.transition(.opacity)
        }
    }
}

private struct LinkSheetItem: Identifiable {
    let mode: ModulaLinkInsertSheet.Mode
    var id: String { mode == .link ? "link" : "abbr" }
}

private struct ModulaPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
