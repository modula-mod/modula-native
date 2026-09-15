import Foundation
import Observation

@MainActor @Observable
final class AuthenticationStore {
    private let client: GreenfieldClient
    private(set) var account: GreenfieldAccount? { didSet { onAccountChange?(account) } }
    var onAccountChange: ((GreenfieldAccount?) -> Void)?
    private(set) var busy = false
    var error: String?
    #if DEBUG
    var lastDiagnostic: String?
    #endif

    init(client: GreenfieldClient) { self.client = client }

    var isSignedIn: Bool { account != nil }

    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            account = try await client.restore()
            error = nil
            #if DEBUG
            lastDiagnostic = nil
            #endif
        } catch {
            account = nil
            self.error = "Session could not be restored. Sign in again."
            #if DEBUG
            lastDiagnostic = (error as? APIError)?.diagnosticDescription ?? String(describing: error)
            #endif
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        let host = await client.apiOriginHost
        do {
            account = try await client.signIn(email: email, password: password)
            #if DEBUG
            lastDiagnostic = nil
            #endif
            return true
        } catch let api as APIError {
            self.error = Self.userFacing(api, host: host)
            #if DEBUG
            lastDiagnostic = api.diagnosticDescription + (host.map { " · \($0)" } ?? "")
            #endif
            return false
        } catch {
            self.error = "Unable to sign in. Check your connection and try again."
            #if DEBUG
            lastDiagnostic = String(describing: error)
            #endif
            return false
        }
    }

    private static func userFacing(_ api: APIError, host: String?) -> String {
        if case .rejected(_, "INVALID_CREDENTIALS") = api, GreenfieldEnvironmentLabel.isIsolatedFixture(host: host) {
            return "Incorrect email or password for this environment (\(host ?? "fixture")). Production accounts do not exist here — use the N1 fixture in Debug."
        }
        return api.userFacingMessage
    }

    func signOut() async {
        guard !busy else { return }
        busy = true; account = nil
        defer { busy = false }
        do {
            try await client.signOut()
            error = nil
        } catch {
            self.error = "Signed out locally. Server revocation could not be confirmed."
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await client.requestPasswordReset(email: email)
            return true
        } catch let api as APIError {
            self.error = api.userFacingMessage
            return false
        } catch {
            self.error = "Unable to request a password reset right now."
            return false
        }
    }
}
