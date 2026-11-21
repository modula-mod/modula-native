import SwiftUI

/// Password re-entry for module data deletion. The signed-in email is shown and not
/// editable (the server identifies the account from the bearer, and the body may only
/// contain `password`). iOS 26 uses real Liquid Glass; earlier versions and Reduce
/// Transparency use a solid fill, never a fake blur.
struct ModuleUninstallStepUpSheet: View {
    let email: String
    let moduleName: String
    let submit: (String, Bool) async -> ModuleUninstallOutcome
    let onCancel: () -> Void
    let onFinished: (ModuleUninstallOutcome) -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var retryUntil: Date?
    @State private var now = Date()
    @State private var didFinish = false
    @State private var hasReprompted = false
    @FocusState private var focus: Field?
    private enum Field: Hashable { case password }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("To permanently delete \(moduleName)’s data, enter the password for this account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                emailRow

                AuthGlassField(
                    title: "Password",
                    symbol: "lock",
                    text: $password,
                    kind: .secure,
                    prompt: "Enter your password",
                    message: error,
                    focus: $focus,
                    focusValue: .password,
                    identifier: "module.uninstall.stepup.password"
                )
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { Task { await confirm() } }

                if let remaining = retryRemaining {
                    Text(retryMessage(remaining))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("module.uninstall.stepup.retryAfter")
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button("Cancel") { cancel() }
                        .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                        .accessibilityIdentifier("module.uninstall.stepup.cancel")

                    Button {
                        Task { await confirm() }
                    } label: {
                        HStack {
                            if working { ProgressView().controlSize(.small) }
                            Text("Confirm")
                        }
                        .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(app.appearance.liveAccent)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("module.uninstall.stepup.confirm")
                }
            }
            .padding(20)
            .navigationTitle("Confirm it’s you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground { sheetBackground }
        .onAppear { focus = .password }
        .onDisappear {
            password = ""
            if !didFinish {
                didFinish = true
                onCancel()
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private var canSubmit: Bool {
        !password.isEmpty && !working && (retryRemaining == nil || retryRemaining! <= 0)
    }

    private var retryRemaining: TimeInterval? {
        guard let retryUntil else { return nil }
        return retryUntil.timeIntervalSince(now)
    }

    private var emailRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Email")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(displayedEmail)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("module.uninstall.stepup.email")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(emailRowBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Email, \(displayedEmail)")
        .accessibilityHint("This is the signed-in email and can’t be changed.")
    }

    private var displayedEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "the email on this account" : trimmed
    }

    @ViewBuilder
    private var emailRowBackground: some View {
        if reduceTransparency || !isIOS26GlassAvailable {
            Color(uiColor: .secondarySystemBackground)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency || !isIOS26GlassAvailable {
            Color(uiColor: .systemBackground)
        } else if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    private var isIOS26GlassAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private func retryMessage(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return "You can try again now." }
        let seconds = Int(remaining.rounded(.up))
        if seconds >= 60 {
            let minutes = (seconds + 59) / 60
            return minutes == 1
                ? "Too many attempts. Try again in 1 minute."
                : "Too many attempts. Try again in \(minutes) minutes."
        }
        return seconds == 1
            ? "Too many attempts. Try again in 1 second."
            : "Too many attempts. Try again in \(seconds) seconds."
    }

    private func cancel() {
        guard !didFinish else { return }
        didFinish = true
        password = ""
        onCancel()
        dismiss()
    }

    private func confirm() async {
        guard canSubmit else { return }
        working = true
        defer { working = false }
        let submitted = password
        let outcome = await submit(submitted, hasReprompted)
        password = ""
        switch outcome {
        case .passwordRejected(let message), .unavailable(let message):
            HapticEngine.shared.play(.failure)
            error = message
            focus = .password
        case .rateLimited(let retryAfter, let message):
            HapticEngine.shared.play(.failure)
            error = message
            if let retryAfter, retryAfter > 0 {
                retryUntil = Date().addingTimeInterval(retryAfter)
                now = Date()
            } else {
                retryUntil = nil
            }
            focus = .password
        case .needsPasswordStepUp:
            // Re-prompt once in this sheet. maxAgeSeconds is never shown as a countdown.
            if hasReprompted {
                HapticEngine.shared.play(.failure)
                didFinish = true
                onFinished(.stillRequiresStepUp(ModuleUninstallFlow.stillRequiresStepUpMessage))
                dismiss()
            } else {
                hasReprompted = true
                HapticEngine.shared.play(.failure)
                error = ModuleUninstallFlow.repromptMessage
                focus = .password
            }
        case .cancelled:
            HapticEngine.shared.play(.failure)
            error = "Couldn’t confirm. Try again."
        case .succeeded, .stillRequiresStepUp, .failed:
            HapticEngine.shared.play(outcome == .succeeded ? .success : .failure)
            didFinish = true
            onFinished(outcome)
            dismiss()
        }
    }
}
