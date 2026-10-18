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
            metric("Native usable", app.runtime.nativeUsableMilliseconds, unit: "ms", id: "metric.nativeUsable")
            metric("Factory setup", app.runtime.initializationMilliseconds, unit: "ms", id: "metric.factory")
            metric("First runtime ready", app.runtime.firstRuntimeReadyMilliseconds, unit: "ms", id: "metric.runtimeReady")
            metric("First module mount", app.runtime.moduleMountMilliseconds.first, unit: "ms", id: "metric.moduleFirst")
            metric("Second module mount", app.runtime.moduleMountMilliseconds.dropFirst().first, unit: "ms", id: "metric.moduleSecond")
            metric("First module data", app.runtime.firstModuleDataReadyMilliseconds, unit: "ms", id: "metric.moduleData")
            metric("Memory before RN", app.runtime.memoryBeforeRuntimeMB, unit: "MB", id: "metric.memoryBefore")
            metric("Memory with module", app.runtime.memoryWithModuleMB, unit: "MB", id: "metric.memoryWith")
            metric("Memory after close", app.runtime.memoryAfterCloseMB, unit: "MB", id: "metric.memoryAfter")
            if let rejected = app.runtime.lastRejectedAction { LabeledContent("Last rejection", value: rejected) }
            Section("Activity") {
                activityDiagnostics
            }
            if let session = app.runtime.lastSession {
                LabeledContent("Module", value: session.manifest.name)
                LabeledContent("Version", value: session.manifest.version)
                LabeledContent("State", value: session.state.rawValue)
                LabeledContent("Load ms", value: session.loadMilliseconds.map { String(format: "%.1f", $0) } ?? "pending")
                LabeledContent("Data ready ms", value: session.dataReadyMilliseconds.map { String(format: "%.1f", $0) } ?? "pending")
                LabeledContent("Session", value: session.isValid ? "valid" : "revoked")
                LabeledContent("Appearance", value: session.environment.colorScheme)
                LabeledContent("OLED", value: String(session.environment.oled))
                LabeledContent("Accent", value: session.environment.accent)
                if let error = session.error { Text(error) }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Runtime diagnostics")
    }
    private func metric(_ label: String, _ value: Double?, unit: String, id: String) -> some View {
        LabeledContent(label, value: value.map { String(format: "%.1f %@", $0, unit) } ?? "pending")
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var activityDiagnostics: some View {
        let mode: ActivityMode = {
            if case .activity(let mode) = app.navigation.currentRoute { return mode }
            return .all
        }()
        let state = app.activity.state(for: mode)
        LabeledContent("Mode", value: mode.rawValue)
        LabeledContent("Events", value: "\(state.events.count)")
        LabeledContent("Next cursor", value: state.nextCursor ?? "none")
        LabeledContent("Unread", value: state.unreadCount.map(String.init) ?? "—")
        LabeledContent("Last refresh", value: state.lastRefresh.map { ActivityRelativeTime.string(from: $0) } ?? "never")
        if let error = state.lastError { LabeledContent("Last error", value: error) }
        LabeledContent("API host", value: Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String ?? "unset")
        LabeledContent("Signed in", value: app.auth.isSignedIn ? "yes" : "no")
    }
}
#endif
