import SwiftUI

#if DEBUG
struct RuntimeDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Form {
            LabeledContent("React Native", value: "0.87.1")
            LabeledContent("Bridge", value: ModuleRuntimeController.bridgeVersion)
            LabeledContent("Runtime", value: app.runtime.state)
            LabeledContent("Initializations", value: "\(app.runtime.initializationCount)")
            LabeledContent("Active surfaces", value: "\(app.runtime.sessions.count)")
            LabeledContent("Memory warnings", value: "\(app.runtime.memoryWarnings)")
            if let session = app.runtime.lastSession {
                LabeledContent("Module", value: session.manifest.name)
                LabeledContent("Version", value: session.manifest.version)
                LabeledContent("State", value: session.state.rawValue)
                LabeledContent("Load ms", value: session.loadMilliseconds.map { String(format: "%.1f", $0) } ?? "pending")
                LabeledContent("Session", value: session.isValid ? "valid" : "revoked")
                LabeledContent("Appearance", value: session.environment.colorScheme)
                LabeledContent("OLED", value: String(session.environment.oled))
                LabeledContent("Accent", value: session.environment.accent)
                if let error = session.error { Text(error) }
            }
        }.navigationTitle("Runtime diagnostics")
    }
}
#endif
