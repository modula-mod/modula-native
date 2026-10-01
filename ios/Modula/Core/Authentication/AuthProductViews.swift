import SwiftUI
import UIKit

struct AuthChrome<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modula")
                        .font(.title.bold())
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RegisterView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var email = ""
    @State private var handle = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var error: String?
    @State private var diagnostic: String?
    @State private var busy = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, handle, displayName, password }

    var body: some View {
        AuthChrome(title: "Create Account", subtitle: "Use a unique username and a password you don’t reuse.") {
            VStack(alignment: .leading, spacing: 14) {
                field("Email", text: $email, contentType: .emailAddress, identifier: "auth.register.email")
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .handle }
                field("Username", text: $handle, contentType: .username, identifier: "auth.register.handle")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .handle)
                    .submitLabel(.next)
                    .onSubmit { focus = .displayName }
                field("Display name", text: $displayName, contentType: .name, identifier: "auth.register.display-name")
                    .focused($focus, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ModulaRadius.small + 4, style: .continuous))
                    .accessibilityIdentifier("auth.register.password")
                    .accessibilityHint("At least 8 characters.")
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await submit() } } }
                AuthPasswordRequirement(password: password)
                Toggle("I agree to the Modula terms", isOn: $acceptedTerms)
                if let error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.register.error")
                    #if DEBUG
                    if let diagnostic {
                        Text(diagnostic).font(.caption2).foregroundStyle(.secondary)
                    }
                    #endif
                }
                AuthPrimaryButton(title: "Create Account", busy: busy, enabled: canSubmit) {
                    Task { await submit() }
                }
                Button("Already have an account? Sign In") {
                    app.navigation.open(.auth(.login))
                }
            }
        }
        .accessibilityIdentifier("auth.register")
        .disabled(busy)
    }

    private var canSubmit: Bool {
        !email.isEmpty && !handle.isEmpty && password.count >= 8 && acceptedTerms && !busy
    }

    private func field(_ title: String, text: Binding<String>, contentType: UITextContentType, identifier: String) -> some View {
        TextField(title, text: text)
            .textContentType(contentType)
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier(identifier)
    }

    private func submit() async {
        guard !busy else { return }
        focus = nil
        busy = true
        error = nil
        diagnostic = nil
        defer { busy = false }
        do {
            let result = try await app.client.register(payload: RegistrationPayload(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: displayName.isEmpty ? nil : displayName,
                inviteCode: nil,
                acceptedTerms: acceptedTerms
            ))
            password = ""
            HapticEngine.shared.play(.success)
            if result.verificationRequired {
                app.navigation.open(.auth(.verify))
            } else {
                app.navigation.open(.auth(.login))
            }
        } catch let api as APIError {
            error = api.userFacingMessage
            #if DEBUG
            diagnostic = api.diagnosticDescription
            #endif
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = "Unable to create an account right now."
            HapticEngine.shared.play(.failure)
        }
    }
}

struct VerifyEmailView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var code = ""
    @State private var token = ""
    @State private var email = ""
    @State private var error: String?
    @State private var busy = false
    @State private var sent = false
    @State private var resending = false

    var body: some View {
        AuthChrome(title: "Verify email", subtitle: "Enter the code or token Greenfield sent you.") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Verification code", text: $code)
                    .keyboardType(.numberPad)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("auth.verify.code")
                TextField("Token (optional)", text: $token)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                TextField("Email for resend", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                AuthPrimaryButton(title: "Verify", busy: busy, enabled: !(code.isEmpty && token.isEmpty) && !busy) {
                    Task { await verify() }
                }
                Button {
                    Task { await resend() }
                } label: {
                    HStack(spacing: 8) {
                        if resending { ProgressView().controlSize(.small) }
                        Text("Resend code")
                    }
                    .frame(minHeight: ModulaLayout.minimumTouch)
                }
                .disabled(email.isEmpty || resending)
                if sent {
                    Text("If that email is registered, a new code is on its way.")
                        .foregroundStyle(.secondary)
                }
                Button("Sign In") { app.navigation.open(.auth(.login)) }
            }
        }
        .accessibilityIdentifier("auth.verify")
    }

    private func verify() async {
        guard !busy else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await app.client.verifyEmail(challengeID: nil, code: code.isEmpty ? nil : code, token: token.isEmpty ? nil : token)
            HapticEngine.shared.play(.success)
            app.navigation.open(.auth(.login))
        } catch let api as APIError {
            error = api.userFacingMessage
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = "Verification didn’t succeed."
            HapticEngine.shared.play(.failure)
        }
    }

    private func resend() async {
        guard !resending else { return }
        resending = true
        defer { resending = false }
        error = nil
        do {
            try await app.client.resendVerification(email: email)
            sent = true
            HapticEngine.shared.play(.confirmation)
        } catch let api as APIError {
            error = api.userFacingMessage
        } catch {
            self.error = "Unable to resend verification."
        }
    }
}

struct ResetPasswordView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var token = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var done = false
    @State private var busy = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case token, password, confirm }

    var body: some View {
        AuthChrome(title: "Reset password", subtitle: "Use the token from your reset email. The new password is never stored on device.") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Reset token", text: $token)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focus, equals: .token)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirm }
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focus, equals: .confirm)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await submit() } } }
                AuthPasswordRequirement(password: password)
                if !confirm.isEmpty, password != confirm {
                    Label("Passwords don’t match.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("auth.reset.mismatch")
                }
                if let error { Text(error).foregroundStyle(.red) }
                if done {
                    Text("Password updated. Sign in with your new password.")
                        .foregroundStyle(.secondary)
                }
                AuthPrimaryButton(title: "Update Password", busy: busy, enabled: canSubmit) {
                    Task { await submit() }
                }
                Button("Back to Sign In") { app.navigation.open(.auth(.login)) }
            }
        }
        .accessibilityIdentifier("auth.reset")
    }

    private var canSubmit: Bool {
        !token.isEmpty && password.count >= 8 && password == confirm && !busy
    }

    private func submit() async {
        guard !busy else { return }
        focus = nil
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await app.client.resetPassword(token: token, newPassword: password)
            password = ""
            confirm = ""
            done = true
            HapticEngine.shared.play(.success)
        } catch let api as APIError {
            error = api.userFacingMessage
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = "Unable to reset the password."
            HapticEngine.shared.play(.failure)
        }
    }
}

/// Live 8+ character requirement shown under new-password fields.
struct AuthPasswordRequirement: View {
    let password: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let met = password.count >= 8
        Label("At least 8 characters", systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.footnote)
            .foregroundStyle(met ? app.appearance.accent.color : Color.secondary)
            .accessibilityLabel(met ? "Password meets the 8 character minimum" : "Password needs at least 8 characters")
    }
}

/// Primary auth action with an inline busy state and repeat-tap protection.
struct AuthPrimaryButton: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            guard !busy else { return }
            action()
        } label: {
            HStack {
                Spacer()
                if busy { ProgressView() } else { Text(title) }
                Spacer()
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(app.appearance.accent.color)
        .disabled(!enabled || busy)
        .accessibilityLabel(title)
        .accessibilityValue(busy ? "In progress" : "")
    }
}
