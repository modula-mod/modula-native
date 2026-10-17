import Foundation
import CryptoKit

struct ModulePermissionReview: Equatable, Sendable {
    var moduleId: String
    var releaseId: String
    var descriptorRevision: String
    var granted: [String]
    var denied: [String]
    var reviewedAt: Date
}

/// Exact-release permission reviews. Grants never carry across an added permission.
@MainActor
final class ModulePermissionReviewStore {
    private var reviews: [String: ModulePermissionReview] = [:]

    func key(moduleId: String, releaseId: String) -> String { "\(moduleId)::\(releaseId)" }

    func review(moduleId: String, releaseId: String) -> ModulePermissionReview? {
        reviews[key(moduleId: moduleId, releaseId: releaseId)]
    }

    func record(_ review: ModulePermissionReview) {
        reviews[key(moduleId: review.moduleId, releaseId: review.releaseId)] = review
    }

    func allows(moduleId: String, releaseId: String, requested: [String]) -> Bool {
        guard let review = review(moduleId: moduleId, releaseId: releaseId) else { return requested.isEmpty }
        let granted = Set(review.granted)
        return requested.allSatisfy { granted.contains($0) }
    }
}

/// Cache-first activation: STAGED → health gate → ACTIVE, retaining PREVIOUS_GOOD.
@MainActor
final class ModuleActivationController {
    let store: ModuleArtifactStore
    let reviews = ModulePermissionReviewStore()
    /// Test hook: force the next activation health check to fail without weakening digests.
    var failNextActivationHealth = false
    var lastRollbackReason: String?

    init(store: ModuleArtifactStore = ModuleArtifactStore()) {
        self.store = store
    }

    func active(accountID: String?, moduleId: String) -> ModuleCachedRelease? {
        guard let accountID else { return nil }
        return store.release(in: .active, accountID: accountID, moduleId: moduleId)
    }

    func stageVerified(
        accountID: String,
        moduleId: String,
        version: String,
        releaseId: String,
        frontend: Data,
        frontendSha256: String,
        mediaType: String,
        hostManifest: ModuleManifest,
        descriptor: ModuleInstallDescriptor?
    ) throws {
        if let descriptor {
            if descriptor.revoked || descriptor.quarantined { throw ModuleActivationError.revoked }
            if descriptor.moduleId != moduleId { throw ModuleActivationError.untrusted }
            if let expected = descriptor.frontendSha256, expected != frontendSha256 {
                throw ModuleActivationError.digestMismatch("frontend")
            }
        }
        let digest = SHA256.hash(data: frontend).map { String(format: "%02x", $0) }.joined()
        guard digest == frontendSha256 else { throw ModuleActivationError.digestMismatch("frontend") }
        _ = try ProductUIDocument.parse(data: frontend, productId: moduleId, version: version)
        try store.stage(
            accountID: accountID, moduleId: moduleId, version: version, releaseId: releaseId,
            frontend: frontend, frontendSha256: frontendSha256, mediaType: mediaType,
            hostManifest: hostManifest, descriptor: descriptor
        )
    }

    func activate(accountID: String, moduleId: String) throws -> ModuleCachedRelease {
        let staged = store.release(in: .staged, accountID: accountID, moduleId: moduleId)
        if failNextActivationHealth {
            failNextActivationHealth = false
            lastRollbackReason = "activation-health"
            throw ModuleActivationError.activationHealth
        }
        if let staged {
            let data = try store.frontendData(for: staged)
            _ = try ProductUIDocument.parse(data: data, productId: staged.moduleId, version: staged.version)
        }
        do {
            return try store.activateStaged(accountID: accountID, moduleId: moduleId)
        } catch {
            lastRollbackReason = error.localizedDescription
            _ = try? store.rollbackToPreviousGood(accountID: accountID, moduleId: moduleId)
            throw error
        }
    }

    func rollback(accountID: String, moduleId: String, reason: String) throws -> ModuleCachedRelease? {
        lastRollbackReason = reason
        return try store.rollbackToPreviousGood(accountID: accountID, moduleId: moduleId)
    }

    /// Local verified package used by tests and the generator dogfood path.
    func installLocalPackage(
        accountID: String,
        moduleId: String,
        version: String,
        releaseId: String,
        frontend: Data,
        hostManifest: ModuleManifest,
        descriptor: ModuleInstallDescriptor? = nil,
        activate: Bool = true
    ) throws -> ModuleCachedRelease {
        let digest = SHA256.hash(data: frontend).map { String(format: "%02x", $0) }.joined()
        try stageVerified(
            accountID: accountID, moduleId: moduleId, version: version, releaseId: releaseId,
            frontend: frontend, frontendSha256: digest, mediaType: ProductUIDocument.mediaType,
            hostManifest: hostManifest, descriptor: descriptor
        )
        if activate { return try self.activate(accountID: accountID, moduleId: moduleId) }
        guard let staged = store.release(in: .staged, accountID: accountID, moduleId: moduleId) else {
            throw ModuleActivationError.missingStaged
        }
        return staged
    }
}
