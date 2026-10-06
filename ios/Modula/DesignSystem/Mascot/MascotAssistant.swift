import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - User context (local only, privacy-labeled)

struct MascotUserContext: Codable, Equatable, Sendable {
    var name: String = ""
    var birthday: DateComponents? = nil
    var bio: String = ""
    var pronouns: String = ""
    var notes: String = ""

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
            && bio.trimmingCharacters(in: .whitespaces).isEmpty
            && pronouns.trimmingCharacters(in: .whitespaces).isEmpty
            && notes.trimmingCharacters(in: .whitespaces).isEmpty
            && birthday == nil
    }

    var birthdaySummary: String? {
        guard let birthday, let month = birthday.month, let day = birthday.day else { return nil }
        var comps = DateComponents()
        comps.month = month
        comps.day = day
        comps.year = 2000
        guard let date = Calendar.current.date(from: comps) else { return nil }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }
}

struct MascotKeywordRule: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var keywords: [String]
    /// Always draft-only for v1; kept for forward-compat.
    var draftMode: Bool

    static func fresh(keywords: [String] = ["hello"]) -> MascotKeywordRule {
        MascotKeywordRule(id: UUID().uuidString, keywords: keywords, draftMode: true)
    }
}

enum MascotAssistantSettings {
    static let enabledKey = "composer.mascot.assistant.enabled"
    static let kindKey = "composer.mascot.assistant.kind"
    static let autoSendKey = "composer.mascot.assistant.autoSend" // default OFF
    static let rulesKey = "composer.mascot.assistant.rules"
    static let contextKey = "composer.mascot.assistant.context"
}

@MainActor @Observable
final class MascotAssistantStore {
    static let shared = MascotAssistantStore()

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: MascotAssistantSettings.enabledKey) }
    }
    var kindRaw: String {
        didSet { UserDefaults.standard.set(kindRaw, forKey: MascotAssistantSettings.kindKey) }
    }
    /// Dangerous; default false. Clear warning in UI.
    var autoSend: Bool {
        didSet { UserDefaults.standard.set(autoSend, forKey: MascotAssistantSettings.autoSendKey) }
    }
    var rules: [MascotKeywordRule]
    var context: MascotUserContext

    private init() {
        enabled = UserDefaults.standard.bool(forKey: MascotAssistantSettings.enabledKey)
        kindRaw = UserDefaults.standard.string(forKey: MascotAssistantSettings.kindKey) ?? ModulaMascotKind.pip.rawValue
        autoSend = UserDefaults.standard.bool(forKey: MascotAssistantSettings.autoSendKey)
        if let data = UserDefaults.standard.data(forKey: MascotAssistantSettings.rulesKey),
           let decoded = try? JSONDecoder().decode([MascotKeywordRule].self, from: data) {
            rules = decoded
        } else {
            rules = [
                .fresh(keywords: ["sugar"]),
                .fresh(keywords: ["hello", "hi", "hey"]),
            ]
        }
        if let data = UserDefaults.standard.data(forKey: MascotAssistantSettings.contextKey),
           let decoded = try? JSONDecoder().decode(MascotUserContext.self, from: data) {
            context = decoded
        } else {
            context = MascotUserContext()
        }
    }

    var selection: MascotSelection { MascotSelection.resolve(raw: kindRaw) }

    func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: MascotAssistantSettings.rulesKey)
        }
    }

    func persistContext() {
        if let data = try? JSONEncoder().encode(context) {
            UserDefaults.standard.set(data, forKey: MascotAssistantSettings.contextKey)
        }
        // Birthday outfit delight
        _ = MascotWardrobeStore.shared.applyBirthdayOutfitIfNeeded(birthday: context.birthday)
    }

    /// Returns the first matching rule + the matched keyword, if any.
    func match(in text: String) -> (rule: MascotKeywordRule, keyword: String)? {
        let lower = text.lowercased()
        for rule in rules {
            for kw in rule.keywords {
                let needle = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { continue }
                if lower.contains(needle) { return (rule, kw) }
            }
        }
        return nil
    }
}

struct MascotAssistantDraft: Identifiable, Equatable {
    let id = UUID()
    let commentID: String
    let keyword: String
    let originalText: String
    var draftText: String
    let mascotRaw: String
}

enum MascotAssistantVoice {
    static func draftReply(
        selection: MascotSelection,
        keyword: String,
        commentText: String,
        context: MascotUserContext
    ) async -> String {
        let name = selection.displayName
        let personality = selection.personality
        let tic = selection.tic
        let contextBlock: String = {
            var parts: [String] = []
            if !context.name.isEmpty { parts.append("User's name: \(context.name)") }
            if let b = context.birthdaySummary { parts.append("Birthday: \(b)") }
            if !context.pronouns.isEmpty { parts.append("Pronouns: \(context.pronouns)") }
            if !context.bio.isEmpty { parts.append("Bio: \(context.bio)") }
            if !context.notes.isEmpty { parts.append("Notes: \(context.notes)") }
            return parts.isEmpty ? "" : "Context (private, on-device only): " + parts.joined(separator: "; ") + "."
        }()

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let instructions = """
            You are \(name), a tiny mascot assistant on Modula. Personality: \(personality). \
            A comment on the user's post matched the keyword "\(keyword)". Draft a short, warm, in-character reply \
            (under 40 words), sometimes ending with "\(tic)". Do not claim to take actions. \
            \(contextBlock)
            """
            let session = LanguageModelSession(instructions: instructions)
            if let response = try? await session.respond(to: "Comment: \(commentText)") {
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        #endif
        try? await Task.sleep(for: .milliseconds(400))
        return canned(name: name, tic: tic, keyword: keyword, commentText: commentText, context: context)
    }

    private static func canned(name: String, tic: String, keyword: String, commentText: String, context: MascotUserContext) -> String {
        let who = context.name.isEmpty ? "" : " \(context.name)!"
        let lines = [
            "Ooh, someone said \"\(keyword)\"!\(who) Thanks for stopping by. \(tic)",
            "I spotted \"\(keyword)\" and had to say hi.\(who) \(tic)",
            "\"\(keyword)\" caught my eye — welcome! \(tic)",
            "Hey hey! \"\(keyword)\" is one of my favourite words. \(tic)",
        ]
        return lines.randomElement() ?? "Hi! \(tic)"
    }
}

// MARK: - Draft sheet (glass)

struct MascotAssistantDraftSheet: View {
    let draft: MascotAssistantDraft
    var onSend: (String) -> Void
    var onDiscard: () -> Void

    @State private var text: String = ""
    @State private var brain = MascotBrain()
    @Environment(\.dismiss) private var dismiss

    private var selection: MascotSelection { MascotSelection.resolve(raw: draft.mascotRaw) }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 8)
            HStack(spacing: 10) {
                mascotFace
                    .frame(width: 64, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draft reply").font(.headline)
                    Text("Matched “\(draft.keyword)” · \(selection.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            Text("Original: \(draft.originalText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))

            TextEditor(text: $text)
                .frame(minHeight: 90, maxHeight: 140)
                .padding(10)
                .scrollContentBackground(.hidden)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false, specular: true)

            Text("Nothing posts until you tap Send. Auto-send stays off unless you turn it on in Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Discard") {
                    onDiscard()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Spacer()

                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSend(trimmed)
                    dismiss()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .onAppear {
            text = draft.draftText
            brain.react(.curious)
            brain.burst(.sparkle)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }

    @ViewBuilder private var mascotFace: some View {
        switch selection {
        case .stock(let kind):
            ModulaLiveMascot(kind: kind, size: 36, brain: brain, showsShadow: false, bubble: false, outfit: MascotWardrobeStore.shared.outfit)
        case .custom(let custom):
            CustomLiveMascot(mascot: custom, size: 36, brain: brain, showsShadow: false, outfit: MascotWardrobeStore.shared.outfit)
        case .off:
            Image(systemName: "pawprint.fill").font(.title2)
        }
    }
}
