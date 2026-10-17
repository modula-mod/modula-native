import SwiftUI

#if DEBUG
/// Development-only controls for digest rejection and activation-health rollback.
/// The type is absent from Release builds.
struct ModuleLifecycleLab: View {
    let moduleID: String
    var onChanged: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Active release") {
                    LabeledContent("Version", value: snapshot.version)
                        .accessibilityIdentifier("module.lifecycle.active-version")
                    LabeledContent("Digest", value: snapshot.digest)
                        .accessibilityIdentifier("module.lifecycle.digest")
                    LabeledContent("Audit", value: snapshot.audit)
                        .accessibilityIdentifier("module.lifecycle.audit")
                }
                Section("Controlled failures") {
                    Button("Stage incorrect digest") { perform { try app.catalogue.debugStageBadDigest(moduleID) } }
                        .accessibilityIdentifier("module.lifecycle.stage-bad-digest")
                    Button("Verify staged release") { perform { try app.catalogue.debugActivateStaged(moduleID) } }
                        .accessibilityIdentifier("module.lifecycle.activate")
                    Button("Fail activation health") { perform { try app.catalogue.debugFailActivationHealth(moduleID) } }
                        .accessibilityIdentifier("module.lifecycle.fail-health")
                }
                if !status.isEmpty {
                    Section("Result") {
                        Text(status).accessibilityIdentifier("module.lifecycle.status")
                    }
                }
            }
            .navigationTitle("Lifecycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("module.lifecycle.lab")
    }

    private var snapshot: (version: String, digest: String, audit: String) {
        let activation = app.moduleActivation
        guard let account = app.catalogue.accountID,
              let active = activation.active(accountID: account, moduleId: moduleID) else {
            return ("none", "none", activation.lastRollbackReason ?? "none")
        }
        let audit = activation.store.index(accountID: account, moduleId: moduleID).lastAuditReason
            ?? activation.lastRollbackReason
            ?? "none"
        return (active.version, String(active.frontendSha256.prefix(12)), audit)
    }

    private func perform(_ work: () throws -> String) {
        do {
            status = try work()
        } catch {
            status = error.localizedDescription
        }
        onChanged()
    }
}
#endif
