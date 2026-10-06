import NaturalLanguage
import SwiftUI
import Translation

/// On-device post translation (Apple Translation framework), driven by
/// Settings → Translate and Settings → Language:
/// - "Show Translate on posts" shows the control at all.
/// - "Auto-detect language" shows it only when the post looks like it's written in a
///   language other than yours; off shows it on every text post.
/// - "Target language" picks the output language (System = your iOS language).
/// - "Show translation hints" names the detected language ("Translate from French").
/// Nothing leaves the device; iOS may ask to download a language the first time.
struct PostTranslationControl: View {
    let text: String
    /// Start translating as soon as it appears (post menu → "Translate post").
    var autoStart = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var translated: String?
    @State private var failed = false
    @State private var showsOriginal = false
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let decision = PostTranslationPolicy.decision(for: text) {
            VStack(alignment: .leading, spacing: 6) {
                if let translated, !showsOriginal {
                    Text(translated)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(app.appearance.accent.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity)
                }
                Button {
                    if translated != nil {
                        showsOriginal.toggle()
                    } else if configuration == nil {
                        configuration = TranslationSession.Configuration(
                            source: decision.source,
                            target: ModulaPreferences.translateTargetLanguage
                        )
                    } else {
                        configuration?.invalidate()
                    }
                } label: {
                    Label(buttonTitle(decision), systemImage: "translate")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.appearance.accent.color)
                .accessibilityHint("Translates this post on your iPhone")
                if failed {
                    Text("Couldn’t translate this post.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .onAppear {
                guard autoStart, configuration == nil, translated == nil else { return }
                configuration = TranslationSession.Configuration(
                    source: decision.source,
                    target: ModulaPreferences.translateTargetLanguage
                )
            }
            .translationTask(configuration) { session in
                // The framework hands the session to this main-actor closure and keeps it
                // alive only for the closure's duration; it isn't shared elsewhere.
                nonisolated(unsafe) let session = session
                do {
                    let response = try await session.translate(text)
                    translated = response.targetText
                    showsOriginal = false
                    failed = false
                } catch {
                    failed = true
                }
            }
        }
    }

    private func buttonTitle(_ decision: PostTranslationPolicy.Decision) -> String {
        if translated != nil { return showsOriginal ? "Show translation" : "Show original" }
        if ModulaPreferences.translationHints, let name = decision.languageName {
            return "Translate from \(name)"
        }
        return "Translate"
    }
}

enum PostTranslationPolicy {
    struct Decision: Equatable {
        var source: Locale.Language?
        var languageName: String?
    }

    static func decision(
        for text: String,
        showButton: Bool = ModulaPreferences.translateButton,
        autoDetect: Bool = ModulaPreferences.translateAutoDetect,
        userLanguage: String? = Locale.current.language.languageCode?.identifier
    ) -> Decision? {
        guard showButton, text.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage
        let source = detected.map { Locale.Language(identifier: $0.rawValue) }
        let name = detected.flatMap { Locale.current.localizedString(forLanguageCode: $0.rawValue) }
        if autoDetect {
            guard let detected, detected != .undetermined else { return nil }
            if let userLanguage, detected.rawValue.hasPrefix(userLanguage) { return nil }
        }
        return Decision(source: autoDetect ? source : nil, languageName: name)
    }
}
