import Foundation

/// Platform-level privacy contract for intelligence execution.
///
/// ## P1 — `localOnly`
/// Only local providers are eligible. If none are compatible and available, fail closed.
/// Never select a remote provider, never call remote `execute`, never upload input,
/// never queue cloud execution, and never silently downgrade privacy.
enum IntelligencePrivacy: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case localOnly = "local-only"
    case preferLocal = "prefer-local"
    case allowRemote = "allow-remote"
}
