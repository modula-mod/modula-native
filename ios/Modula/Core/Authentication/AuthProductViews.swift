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

    var body: some View {
        AuthChrome(title: "Create Account", subtitle: "Use a unique username and a password you don’t reuse.") {
            VStack(alignment: .leading, spacing: 14) {
                field("Email", text: $email, contentType: .emailAddress, identifier: "auth.register.email")
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                field("Username", text: $handle, contentType: .username, identifier: "auth.register.handle")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                field("Display name", text: $displayName, contentType: .name, identifier: "auth.register.display-name")
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("auth.register.password")
                Toggle("I agree to the Modula terms", isOn: $acceptedTerms)
                if let error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.register.error")
                    #if DEBUG
                    if let diagnostic {
                        Text(diagnostic).font(.caption2).foregroundStyle(.secondary)
                    }
                    #endif
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView() } else { Text("Create Account") }
                        Spacer()
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
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
                Button("Verify") {
                    Task { await verify() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty && token.isEmpty)
                Button("Resend code") {
                    Task { await resend() }
                }
                .disabled(email.isEmpty)
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

    var body: some View {
        AuthChrome(title: "Reset password", subtitle: "Use the token from your reset email. The new password is never stored on device.") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Reset token", text: $token)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                SecureField("Confirm password", text: $confirm)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let error { Text(error).foregroundStyle(.red) }
                if done {
                    Text("Password updated. Sign in with your new password.")
                        .foregroundStyle(.secondary)
                }
                Button("Update Password") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.isEmpty || password.count < 8 || password != confirm)
                Button("Back to Sign In") { app.navigation.open(.auth(.login)) }
            }
        }
        .accessibilityIdentifier("auth.reset")
    }

    private func submit() async {
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
