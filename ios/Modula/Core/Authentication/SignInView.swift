import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        Form {
            if let account = app.auth.account {
                LabeledContent("Account", value: account.primaryHandle)
                Button("Sign out", role: .destructive) {
                    app.runtime.revokeAll()
                    Task { await app.auth.signOut() }
                }.disabled(app.auth.busy)
            } else {
                TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                Button("Sign in") {
                    let credential = password
                    password = ""
                    Task { await app.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: credential) }
                }.disabled(email.isEmpty || password.isEmpty || app.auth.busy)
            }
            if app.auth.busy { ProgressView() }
            if let error = app.auth.error { Text(error).foregroundStyle(.red).accessibilityLabel(error) }
            Text("Your session is stored securely on this iPhone. Modules never receive your account credentials.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Account")
    }
}
