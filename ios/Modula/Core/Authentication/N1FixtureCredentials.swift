#if DEBUG
import Foundation

/// Development-only loader for the isolated N1 Greenfield fixture.
/// Never ships secrets in the bundle; reads the ignored local file / env path.
enum N1FixtureCredentials {
    struct Payload: Decodable {
        let email: String
        let password: String
        let apiURL: String?
    }

    static func load() -> Payload? {
        var candidates: [URL] = []
        if let envPath = ProcessInfo.processInfo.environment["N1_SECRET_FILE"], !envPath.isEmpty {
            candidates.append(URL(fileURLWithPath: envPath))
        }
        // Simulator can read the Mac workspace path used by N1 tests/harness.
        candidates.append(URL(fileURLWithPath: "/Users/msjoy/Developer/modula-native/.env.n1.local"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env.n1.local"))

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  !payload.email.isEmpty,
                  !payload.password.isEmpty else { continue }
            return payload
        }
        return nil
    }
}
#endif

import Foundation

enum GreenfieldEnvironmentLabel {
    static func describe(host: String?) -> String {
        guard let host, !host.isEmpty else { return "API unconfigured" }
        if host == "api.modula.digital" { return "Production · \(host)" }
        if host.contains("native-n1") || host == "localhost" || host.hasPrefix("127.") {
            return "N1 fixture · \(host)"
        }
        return "Custom · \(host)"
    }

    static func isIsolatedFixture(host: String?) -> Bool {
        guard let host else { return false }
        return host.contains("native-n1") || host == "localhost" || host.hasPrefix("127.")
    }
}
