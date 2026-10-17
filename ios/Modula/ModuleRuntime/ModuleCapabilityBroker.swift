import Foundation

/// Host-owned capability broker. Downloaded modules never import native modules directly.
enum ModuleCapabilityBroker {
    static let supported: Set<String> = [
        "ui.richText@1",
        "ui.richText.commands@1",
        "ui.graph@1",
        "ui.revisions@1",
        "ui.attachments@1",
        "ui.propertyEditor@1",
        "ui.referencePicker@1",
        "ui.recordTable@1",
        "ui.recordBoard@1",
        "ui.commandMenu@1",
        "mediaPicker",
        "share",
        "biometrics",
        "secureStorage",
        "localIntelligence",
        "backgroundTask",
        "navigation.open",
        "haptics.selection",
        "diagnostics.ready",
        "diagnostics.dataReady",
        "diagnostics.fail",
        "backend.records.list",
        "backend.records.get",
        "backend.records.create",
        "backend.records.update",
        "backend.records.delete",
        ModulePolicy.identityUserID,
    ]

    /// Frontend files use dotted capability ids. The host implements the same
    /// abilities under the names it already grants.
    static func canonical(_ capability: String) -> String {
        switch capability {
        case "media.picker@1": "mediaPicker"
        case "ui.property-editor@1": "ui.propertyEditor@1"
        case "ui.reference-picker@1": "ui.referencePicker@1"
        case "ui.attachment-gallery@1": "ui.attachments@1"
        case "ui.revision-browser@1": "ui.revisions@1"
        case "ui.table@1": "ui.recordTable@1"
        case "ui.board@1": "ui.recordBoard@1"
        case "ui.local-intelligence@1": "localIntelligence"
        case "share.native@1": "share"
        default: capability
        }
    }

    static func hostSupports(_ capability: String) -> Bool {
        supported.contains(capability) || supported.contains(canonical(capability))
    }

    /// `localOnly` never leaves the device. Missing local providers return CAPABILITY_UNAVAILABLE.
    @MainActor
    static func invoke(_ capability: String, session: ModuleSession, localOnly: Bool) -> String {
        let capability = canonical(capability)
        guard session.isValid else { return "REQUEST_DENIED" }
        guard session.grantedCapabilities.contains(capability) || hostSupports(capability) else {
            return "PERMISSION_DENIED"
        }
        if localOnly && (capability == "localIntelligence" || capability.hasPrefix("ai.") || capability.hasPrefix("intelligence.")) {
            return "CAPABILITY_UNAVAILABLE"
        }
        switch capability {
        case "share":
            return "ok"
        case "mediaPicker", "biometrics", "secureStorage", "backgroundTask":
            return "ok"
        case "localIntelligence":
            return localOnly ? "CAPABILITY_UNAVAILABLE" : "CAPABILITY_UNAVAILABLE"
        default:
            return hostSupports(capability) ? "ok" : "CAPABILITY_UNAVAILABLE"
        }
    }
}
