import Foundation
import Observation

@MainActor @Observable
final class AuthenticationStore {
    private let client: GreenfieldClient
    private(set) var account: GreenfieldAccount? { didSet { onAccountChange?(account) } }
    var onAccountChange: ((GreenfieldAccount?) -> Void)?
    private(set) var busy = false
    var error: String?
    init(client: GreenfieldClient) { self.client = client }
    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            account = try await client.restore()
            error = nil
        } catch {
            account = nil
            self.error = "Session could not be restored. Sign in again."
        }
    }
    func signIn(email: String, password: String) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { account = try await client.signIn(email: email, password: password) }
        catch { self.error = (error as? APIError)?.localizedDescription ?? "Unable to sign in. Check your connection and credentials." }
    }
    func signOut() async {
        guard !busy else { return }
        busy = true; account = nil
        defer { busy = false }
        do { try await client.signOut(); error = nil }
        catch { self.error = "Signed out locally. Server revocation could not be confirmed." }
    }
}
