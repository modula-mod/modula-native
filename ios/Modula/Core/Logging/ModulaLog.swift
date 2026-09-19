import OSLog

enum ModulaLog {
    static let app = Logger(subsystem: "digital.modula.app.native", category: "app")
    static let network = Logger(subsystem: "digital.modula.app.native", category: "network")
    static let auth = Logger(subsystem: "digital.modula.app.native", category: "auth")
    static let runtime = Logger(subsystem: "digital.modula.app.native", category: "runtime")
    static let bridge = Logger(subsystem: "digital.modula.app.native", category: "bridge")
    static let intelligence = Logger(subsystem: "digital.modula.app.native", category: "intelligence")
}
