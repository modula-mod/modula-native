import Foundation

/// DEBUG launch argument that swaps the app's GreenField and module-artifact
/// session for a transport that fails every request. Other stacks, including
/// `URLSession.shared` and the simulator itself, stay available.
enum ModulaAppNetworkIsolation {
    static let argument = "--modula-isolate-app-network"

    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(argument)
        #else
        false
        #endif
    }

    static func isolatedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModulaBlockedAppNetworkProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

/// Fails every request on the session that lists it. It does not register
/// globally, so it is not a simulator-wide offline switch.
final class ModulaBlockedAppNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
