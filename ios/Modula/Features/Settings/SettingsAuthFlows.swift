import SwiftUI
import AuthenticationServices
import UIKit

// In-app flows for Greenfield auth routes that already exist.
// Every sensitive step goes through the server's step-up policy: a STEP_UP_REQUIRED rejection opens the
// shared PasswordStepUpSheet and the step retries once confirmed. Nothing is simulated.

enum SettingsAuthStepUp {
    static func isRequired(_ error: Error) -> Bool {
        if case APIError.rejected(_, let code) = error { return code == "STEP_UP_REQUIRED" || code == "FORBIDDEN_STEP_UP" }
        return false
    }
}

enum Base64URL {
    static func decode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
    static func encode(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - TOTP 2FA

/// Authenticator-app setup:
/// `POST /v1/auth/totp/enroll` (step-up) → QR / otpauth link / secret preview → `POST /v1/auth/totp/verify`.
/// Psychology: three numbered steps with one action each (chunking, progress), and a single bold CTA per step.
struct TOTPSetupSheet: View {
    var onFinished: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var enrollment: JSONValue?
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var needsStepUp = false
    @State private var done = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section {
                        Label("Two-factor authentication is on", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } footer: {
                        Text("Next time you sign in on a new device, Modula asks for a 6-digit code from your authenticator app. Keep your recovery codes somewhere safe in case you lose this phone.")
                    }
                } else if let enrollment {
                    Section {
                        if let qr = qrImage(enrollment) {
                            Image(uiImage: qr)
                                .interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 220).frame(maxWidth: .infinity)
                                .accessibilityLabel("QR code for your authenticator app")
                        }
                        if let uri = enrollment["provisioningUri"]?.string, let url = URL(string: uri) {
                            Button("Open in authenticator app") { openURL(url) }
                        }
                        if let preview = enrollment["secretPreview"]?.string {
                            LabeledContent("Setup key starts with", value: preview).font(.footnote)
                        }
                    } header: { Text("1 · Add Modula to your authenticator") } footer: {
                        Text("Scan the code with an app like Passwords, Google Authenticator or 1Password, or tap Open on this iPhone.")
                    }
                    Section {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .font(.title3.monospacedDigit()).focused($codeFocused)
                            .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(8)) }
                    } header: { Text("2 · Enter the code it shows") } footer: {
                        Text(error ?? "Codes change every 30 seconds.").foregroundStyle(error == nil ? Color.secondary : Color.red)
                    }
                    Section {
                        Button { Task { await verify() } } label: {
                            Text(busy ? "Checking…" : "3 · Turn on two-factor").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain).modulaAccentCTA(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(busy || code.count < 6)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } else {
                    Section {
                        Text("Two-factor authentication adds a 6-digit code from an authenticator app when you sign in somewhere new, so a stolen password alone isn't enough.")
                        Button { Task { await enroll() } } label: {
                            Text(busy ? "Preparing…" : "Set up authenticator app").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain).modulaAccentCTA(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(busy)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } footer: { if let error { Text(error).foregroundStyle(.red) } }
                }
            }
            .navigationTitle("Two-Factor Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done ? "Done" : "Cancel") { if done { onFinished() }; dismiss() } }
            }
            .sheet(isPresented: $needsStepUp) {
                PasswordStepUpSheet(reason: "Confirm your password to set up two-factor authentication.") { Task { await enroll() } }
            }
        }
        .accessibilityIdentifier("settings.totp.setup")
    }

    private func qrImage(_ value: JSONValue) -> UIImage? {
        guard let url = value["qrCodeDataUrl"]?.string, let comma = url.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(url[url.index(after: comma)...])).flatMap(UIImage.init(data:))
    }

    private func enroll() async {
        busy = true; error = nil; defer { busy = false }
        do {
            enrollment = try await app.client.authenticatedJSON("POST", path: "/v1/auth/totp/enroll", body: .object(["label": .string("Modula iOS")]))
            codeFocused = true
        } catch where SettingsAuthStepUp.isRequired(error) {
            needsStepUp = true
        } catch {
            self.error = SettingsRemoteError.message(error, fallback: "Couldn't start setup. Try again.")
        }
    }

    private func verify() async {
        guard let challengeId = enrollment?["challengeId"]?.string else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/auth/totp/verify",
                                                       body: .object(["challengeId": .string(challengeId), "code": .string(code)]))
            HapticEngine.shared.play(.success)
            done = true
        } catch {
            HapticEngine.shared.play(.failure)
            self.error = SettingsRemoteError.message(error, fallback: "That code didn't match. Check the time on your phone and try the newest code.")
        }
    }
}

// MARK: - Passkey registration

/// `POST /v1/auth/passkeys/registration/options` (step-up) → ASAuthorization platform passkey → `.../registration/verify`.
@MainActor
fileprivate final class PasskeyRegistrar: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialRegistration, Error>?

    func register(rpID: String, challenge: Data, userID: Data, name: String) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userID)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { c in
            continuation = c
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let reg = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                continuation?.resume(returning: reg)
            } else {
                continuation?.resume(throwing: APIError.invalidResponse)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { continuation?.resume(throwing: error); continuation = nil }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

enum PasskeyRegistrationFlow {
    /// Returns nil on success, or a user-facing failure. Throws only STEP_UP_REQUIRED so callers can confirm and retry.
    @MainActor
    static func run(app: AppEnvironment, label: String) async throws -> String? {
        let start: JSONValue
        do {
            start = try await app.client.authenticatedJSON("POST", path: "/v1/auth/passkeys/registration/options", body: .object(["label": .string(label)]))
        } catch where SettingsAuthStepUp.isRequired(error) {
            throw error
        } catch {
            return SettingsRemoteError.message(error, fallback: "Couldn't start adding a passkey.")
        }
        guard let challengeId = start["challengeId"]?.string,
              let options = start["options"],
              let challenge = options["challenge"]?.string.flatMap(Base64URL.decode),
              let userID = options["user"]?["id"]?.string.flatMap(Base64URL.decode),
              let rpID = options["rp"]?["id"]?.string ?? start["rp"]?["id"]?.string else {
            return "The server sent passkey options this version can't read."
        }
        let name = options["user"]?["name"]?.string ?? app.auth.account?.primaryHandle ?? "Modula"
        let registration: ASAuthorizationPlatformPublicKeyCredentialRegistration
        do {
            registration = try await PasskeyRegistrar().register(rpID: rpID, challenge: challenge, userID: userID, name: name)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return nil
        } catch {
            // Typical cause in dev builds: the app's associated domain (webcredentials:modula.digital) is not provisioned.
            return "This iPhone couldn't create the passkey (\((error as NSError).localizedDescription))."
        }
        guard let attestation = registration.rawAttestationObject else { return "The passkey didn't include an attestation." }
        let id = Base64URL.encode(registration.credentialID)
        let response: JSONValue = .object([
            "id": .string(id), "rawId": .string(id), "type": .string("public-key"),
            "authenticatorAttachment": .string("platform"),
            "clientExtensionResults": .object([:]),
            "response": .object([
                "clientDataJSON": .string(Base64URL.encode(registration.rawClientDataJSON)),
                "attestationObject": .string(Base64URL.encode(attestation)),
                "transports": .array([.string("internal"), .string("hybrid")]),
            ]),
        ])
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/auth/passkeys/registration/verify",
                                                       body: .object(["challengeId": .string(challengeId), "response": response, "label": .string(label)]))
            HapticEngine.shared.play(.success)
            return nil
        } catch {
            return SettingsRemoteError.message(error, fallback: "The server couldn't verify the new passkey.")
        }
    }
}

// MARK: - Sign in with Apple linking

/// `GET /v1/auth/apple/status` (server capability) → `POST /v1/auth/apple/link/options` (step-up, nonce)
/// → Sign in with Apple with that nonce → `POST /v1/auth/apple/link` with the identity token.
@MainActor
fileprivate final class AppleLinker: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func authorize(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = nonce
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { c in continuation = c; controller.performRequests() }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let cred = authorization.credential as? ASAuthorizationAppleIDCredential { continuation?.resume(returning: cred) }
            else { continuation?.resume(throwing: APIError.invalidResponse) }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { continuation?.resume(throwing: error); continuation = nil }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

enum AppleLinkFlow {
    @MainActor
    static func run(app: AppEnvironment) async throws -> String? {
        let start: JSONValue
        do {
            start = try await app.client.authenticatedJSON("POST", path: "/v1/auth/apple/link/options", body: .object([:]))
        } catch where SettingsAuthStepUp.isRequired(error) {
            throw error
        } catch {
            return SettingsRemoteError.message(error, fallback: "Couldn't start linking Apple.")
        }
        guard let challengeId = start["challengeId"]?.string, let nonce = start["nonce"]?.string else {
            return "The server sent linking options this version can't read."
        }
        let credential: ASAuthorizationAppleIDCredential
        do {
            credential = try await AppleLinker().authorize(nonce: nonce)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return nil
        } catch {
            return "Sign in with Apple didn't finish (\((error as NSError).localizedDescription))."
        }
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
            return "Apple didn't return an identity token."
        }
        do {
            _ = try await app.client.authenticatedJSON("POST", path: "/v1/auth/apple/link",
                                                       body: .object(["challengeId": .string(challengeId), "nonce": .string(nonce), "idToken": .string(idToken)]))
            HapticEngine.shared.play(.success)
            return nil
        } catch {
            return SettingsRemoteError.message(error, fallback: "The server couldn't link this Apple ID.")
        }
    }
}
