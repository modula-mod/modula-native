import SwiftUI

/// "Versions" on the module page: every registry release the account may see, with its
/// publish date, release notes and trust/signature state. The newest release ahead of the
/// installation offers Update; other switchable releases offer "Install this version",
/// labelled Upgrade or Downgrade. Data comes from the registry only.
struct ModuleVersionsSection: View {
    let list: ModuleVersionList?
    let failed: Bool
    let installedVersion: String?
    let bundledVersion: String?
    let busy: Bool
    let onSelect: (ModuleVersionOption) -> Void
    let onRetry: () -> Void

    @State private var showAll = false
    private let collapsedCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Versions").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if let installedVersion {
                    Text("Installed \(installedVersion)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("module.versions.installed")
                }
            }
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("module.versions")
    }

    @ViewBuilder
    private var content: some View {
        if let list, !list.versions.isEmpty {
            ModulaCard {
                VStack(alignment: .leading, spacing: 0) {
                    let rows = showAll ? list.versions : Array(list.versions.prefix(collapsedCount))
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider().padding(.vertical, 12) }
                        ModuleVersionRow(
                            option: option,
                            action: ModuleVersionAction.resolve(option, installed: installedVersion != nil, bundledVersion: bundledVersion, busy: busy),
                            onSelect: { onSelect(option) }
                        )
                    }
                    if list.versions.count > collapsedCount {
                        Divider().padding(.vertical, 12)
                        Button(showAll ? "Show fewer versions" : "Show all \(list.versions.count) versions") {
                            withAnimation(.snappy) { showAll.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("module.versions.toggle")
                    }
                }
            }
        } else if failed {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("Versions couldn’t be loaded.").foregroundStyle(.secondary)
                Spacer()
                Button("Retry", action: onRetry).font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        } else if list != nil {
            Text("The registry has no other versions of this module.").foregroundStyle(.secondary)
        } else if installedVersion == nil {
            Text("Install the module to switch between its versions.").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading versions…").foregroundStyle(.secondary)
            }
        }
    }
}

private struct ModuleVersionRow: View {
    let option: ModuleVersionOption
    let action: ModuleVersionAction
    let onSelect: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Version \(option.version)").font(.headline)
                        if option.isLatest { tag("Latest", tint: app.appearance.accent.color) }
                        if option.isCurrent { tag("Installed", tint: .green) }
                        if option.releaseState == "superseded" { tag("Superseded", tint: .secondary) }
                    }
                    HStack(spacing: 6) {
                        if let date = option.publishedAt {
                            Text(date, format: .dateTime.day().month(.abbreviated).year())
                        } else {
                            Text("Publish date not recorded")
                        }
                        Text("·")
                        Label(option.trustLabel, systemImage: option.trustSymbol)
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                actionButton
            }
            .accessibilityElement(children: .contain)
            if let notes = option.releaseNotes {
                Text(notes)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if notes.count > 160 {
                    Button(expanded ? "less" : "more") { withAnimation(.snappy) { expanded.toggle() } }
                        .font(.caption.weight(.semibold))
                        .accessibilityLabel(expanded ? "Show less release notes" : "Show more release notes")
                }
            } else {
                Text("No release notes were published for this version.").font(.subheadline).foregroundStyle(.secondary)
            }
            if case .unavailable(let reason) = action, !option.isCurrent {
                Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            } else if action == .needsNewerApp {
                Label("This version needs a newer Modula app.", systemImage: "arrow.down.app").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("module.version.\(option.version)")
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private var actionButton: some View {
        if action.isEnabled {
            Button(action: onSelect) {
                VStack(spacing: 2) {
                    Text(action == .update ? "UPDATE" : action.title)
                        .font(.caption.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let badge = action.badge {
                        Text(badge).font(.caption2.weight(.semibold)).opacity(0.85)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 84, minHeight: 34)
                .foregroundStyle(action == .update ? Color.white : app.appearance.accent.color)
                .background(action == .update ? app.appearance.accent.color : app.appearance.accent.color.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityHint("Shows the changes before anything is installed")
            .accessibilityIdentifier("module.version.\(option.version).action")
        } else if option.isCurrent {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityLabel("Installed version")
        }
    }

    private var accessibilityTitle: String {
        switch action {
        case .update: "Update to version \(option.version)"
        case .installThisVersion(.downgrade): "Install version \(option.version), downgrade"
        case .installThisVersion: "Install version \(option.version), upgrade"
        default: action.title
        }
    }
}

/// Confirmation for a version switch: what changes (permissions that need consent, ones no
/// longer requested), the trust state of the target and, for downgrades, the data warning.
struct ModuleVersionSwitchSheet: View {
    enum Phase: Equatable {
        case loading
        case ready(ModuleVersionPreview)
        case failed(String)
    }

    let moduleName: String
    let option: ModuleVersionOption
    let phase: Phase
    let onConfirm: (ModuleVersionPreview) -> Void
    let onCancel: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var detent: ModulaSheetDetent = .large

    var body: some View {
        ModulaSheet(detents: [.medium, .large], selectedDetent: $detent) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch phase {
                        case .loading:
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking version \(option.version) with the registry…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160)
                        case .failed(let message):
                            Label(message, systemImage: "xmark.shield.fill")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("module.version-switch.error")
                        case .ready(let preview):
                            details(preview)
                        }
                    }
                    .padding(.horizontal, ModulaLayout.contentInset)
                    .padding(.vertical, 16)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel).accessibilityIdentifier("module.version-switch.cancel")
                    }
                }
                .safeAreaInset(edge: .bottom) { confirmBar }
            }
        }
    }

    private var direction: ModuleVersionDirection {
        if case .ready(let preview) = phase { return preview.direction }
        return option.direction
    }

    private var verb: String {
        switch direction {
        case .downgrade: "Downgrade"
        case .upgrade: option.isLatest ? "Update" : "Upgrade"
        default: "Install"
        }
    }

    private var title: String { "\(verb) \(moduleName)" }

    @ViewBuilder
    private func details(_ preview: ModuleVersionPreview) -> some View {
        HStack(spacing: 12) {
            versionPill(preview.fromVersion, caption: "Installed")
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            versionPill(preview.toVersion, caption: preview.isDowngrade ? "Older" : "Newer")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From version \(preview.fromVersion) to version \(preview.toVersion)")

        if let warning = preview.downgradeWarning {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downgrade").font(.subheadline.weight(.semibold))
                    Text(warning).font(.subheadline)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("module.version-switch.downgrade-warning")
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("Permission changes").font(.headline).accessibilityAddTraits(.isHeader)
            ModulaCard {
                VStack(alignment: .leading, spacing: 12) {
                    if preview.addedPermissions.isEmpty && preview.removedPermissions.isEmpty {
                        Label("No permission changes", systemImage: "checkmark.shield").font(.subheadline)
                    }
                    if !preview.addedPermissions.isEmpty {
                        Text(preview.requiresConsent.isEmpty ? "New permissions" : "New permissions need your consent")
                            .font(.subheadline.weight(.semibold))
                        ForEach(preview.addedPermissions) { permission in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: Self.riskSymbol(permission.risk)).foregroundStyle(Self.riskColor(permission.risk)).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(permission.reason ?? permission.permission).font(.subheadline)
                                    Text("\(permission.permission) · \(permission.risk.capitalized) risk").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if !preview.removedPermissions.isEmpty {
                        if !preview.addedPermissions.isEmpty { Divider() }
                        Text("No longer requested").font(.subheadline.weight(.semibold))
                        ForEach(preview.removedPermissions, id: \.self) { permission in
                            Label(permission, systemImage: "minus.circle").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("module.version-switch.permissions")

        VStack(alignment: .leading, spacing: 6) {
            Text("Release").font(.headline).accessibilityAddTraits(.isHeader)
            Label(option.trustLabel, systemImage: option.trustSymbol).font(.subheadline)
            Text("Verified against the Modula registry · descriptor \(String(preview.descriptor.descriptorSha256.prefix(12)))…")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Install descriptor verified against the Modula registry")
            ForEach(preview.warnings.filter { !["DATA_SCHEMA_OLDER", "DOWNGRADE"].contains($0.code) }) { warning in
                Label(warning.message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            Text("Your module data stays on your account.").font(.caption).foregroundStyle(.secondary)
        }

        if let blocker = preview.blockers.first {
            Label(blocker.message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.subheadline)
        }
    }

    private func versionPill(_ version: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(version).font(.title3.weight(.bold).monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var confirmBar: some View {
        if case .ready(let preview) = phase {
            VStack(spacing: 8) {
                Button {
                    onConfirm(preview)
                } label: {
                    Text(confirmTitle(preview))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(preview.isDowngrade ? .orange : app.appearance.accent.color)
                .disabled(!preview.allowed)
                .accessibilityIdentifier("module.version-switch.confirm")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func confirmTitle(_ preview: ModuleVersionPreview) -> String {
        let action = "\(verb) to \(preview.toVersion)"
        return preview.requiresConsent.isEmpty ? action : "Allow & \(action)"
    }

    static func riskSymbol(_ risk: String) -> String {
        switch risk { case "high", "restricted": "exclamationmark.shield.fill"; case "medium": "shield.lefthalf.filled"; default: "checkmark.shield" }
    }

    static func riskColor(_ risk: String) -> Color {
        switch risk { case "high", "restricted": .red; case "medium": .orange; default: .green }
    }
}
